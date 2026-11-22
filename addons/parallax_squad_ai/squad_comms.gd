class_name SquadComms
extends Node
## Hub between the player's words and the ally squad. Chat bar and push-to-talk BOTH end in
## `submit_utterance()`, so typed and spoken orders have identical outcomes.
##   online  (API key): per-ally conversation (own history + system prompt with the LIVE roster, rebuilt on
##            every request so deaths / revives show up immediately) -> streaming chat with parallel tool calls
##            -> tool calls become squad commands; streamed text becomes subtitles + sentence-chunked TTS.
##   offline (no key / API error): SquadCommandParser keyword fallback -> same commands, canned voice lines.
## API errors surface as in-game notifications; nothing here may crash the game.

signal notify(text: String, level: String)                 # level: info | warn | error
signal subtitle(speaker: String, text: String, color: Color, final: bool)
signal log_entry(entry: Dictionary)
signal mic_state_changed(state: String)                    # idle | recording | transcribing | unavailable
signal mic_level(rms: float)
signal tool_called(ally_name: String, tool_name: String, args: Dictionary, result: String)
signal text_response(ally_name: String, text: String)
signal roster_prompt_updated(roster_text: String)

const ParserScript := preload("res://scripts/allies/squad_command_parser.gd")
const HISTORY_MAX: int = 24

var client: OpenAIClient = null
var mic: SquadMicCapture = null
var tts: SquadTTSPlayer = null
var mic_state: String = "idle"

var _histories: Dictionary = {}     # ally name -> Array of memory lines (what they said / were told)
var _director_history: Array = []  # one shared Director conversation (user / assistant / tool messages)
var _recent_events: Array = []     # rolling squad event log injected as RECENT EVENTS
var _pending: Dictionary = {}       # request id -> {ally, user_text, via, spoken_upto, text}
var _stt_req: int = -1
var _manager: AllySquadManager = null
var _last_roster_text: String = ""
var _last_tts_warn: int = -100000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("squad_comms")
	SquadAIConfig.ensure_loaded()
	client = OpenAIClient.new()
	client.name = "OpenAIClient"
	add_child(client)
	mic = SquadMicCapture.new()
	mic.name = "Mic"
	add_child(mic)
	tts = SquadTTSPlayer.new()
	tts.name = "TTS"
	add_child(tts)
	tts.bind_client(client)
	# Subtitles follow the voice: shown when a line is actually heard, or right away if it won't be voiced.
	tts.line_started.connect(_on_voice_line)
	tts.line_dropped.connect(_on_voice_line)
	client.text_delta.connect(_on_text_delta)
	client.chat_completed.connect(_on_chat_completed)
	client.transcribed.connect(_on_transcribed)
	client.request_failed.connect(_on_request_failed)
	mic.level_changed.connect(func(r: float) -> void: mic_level.emit(r))
	call_deferred("_bind_manager")


func _bind_manager() -> void:
	_manager = AllySquadManager.instance
	if _manager == null:
		await get_tree().create_timer(0.5).timeout
		_manager = AllySquadManager.instance
	if _manager == null:
		return
	if not _manager.ally_spoke.is_connected(_on_ally_spoke):
		_manager.ally_spoke.connect(_on_ally_spoke)
		_manager.command_logged.connect(_on_command_logged)
		_manager.roster_changed.connect(_on_roster_changed)
		_manager.combo_progress.connect(func(_k: String, t: String) -> void: log_entry.emit({"source": "combo", "who": "squad", "what": t, "result": ""}))
	notify.emit("Squad comms %s. Enter: chat   V: push-to-talk" % SquadAIConfig.describe(), "info")


func is_online() -> bool:
	return SquadAIConfig.is_online()


# ------------------------------------------------------------------ input entry points

## Typed chat and transcribed voice both arrive here.
func submit_utterance(text: String, via: String = "chat") -> void:
	var t: String = text.strip_edges()
	if t.is_empty():
		return
	if via == "chat" and not SquadAIConfig.chat_allowed():
		notify.emit("Chat is disabled (Squad Comms mode: voice only).", "warn")
		return
	log_entry.emit({"source": via, "who": "YOU", "what": t, "result": ""})
	subtitle.emit("YOU", t, UITheme.GOLD_BRIGHT, true)
	if _manager == null:
		_manager = AllySquadManager.instance
	if _manager == null:
		notify.emit("No squad present.", "warn")
		return
	if is_online():
		_ask_llm(t, via)
	else:
		_offline(t, via)


func _offline(t: String, via: String) -> void:
	var cmds: Array = ParserScript.parse(t, _manager.get_ally_names(), _manager.get_parser_context())
	var results: Array[String] = _manager.issue_commands(cmds, via)
	for i in range(cmds.size()):
		var cd: Dictionary = cmds[i]
		tool_called.emit(_addressed_name(cd), "parser:" + String(cd.get("verb", "")), cd, results[i] if i < results.size() else "")


func _addressed_name(cd: Dictionary) -> String:
	var a: Variant = cd.get("allies", [])
	if a is Array and not (a as Array).is_empty():
		return String((a as Array)[0])
	return "squad"


## Push-to-talk (key held or on-screen button held).
func begin_voice() -> void:
	if not SquadAIConfig.voice_allowed():
		notify.emit("Voice is disabled (Squad Comms mode: chat only).", "warn")
		return
	if not is_online():
		_set_mic("unavailable")
		notify.emit("Voice orders need an API key (GEMINI_API_KEY or OPENAI_API_KEY). Type orders with Enter instead.", "warn")
		return
	if mic_state == "transcribing":
		return
	if not mic.start():
		_set_mic("unavailable")
		notify.emit("Microphone unavailable (enable audio input / check permissions).", "error")
		return
	tts.interrupt()   # the player talking over the squad cuts the current line
	_set_mic("recording")


func end_voice() -> void:
	if mic_state != "recording":
		if mic_state == "unavailable":
			_set_mic("idle")
		return
	var wav: PackedByteArray = mic.stop_and_encode()
	if wav.is_empty():
		_set_mic("idle")
		notify.emit("Didn't catch that — hold V while speaking.", "info")
		return
	_set_mic("transcribing")
	var hint: String = "Allies: %s." % ", ".join(_manager.get_ally_names() if _manager != null else [])
	_stt_req = client.transcribe(wav, hint)


func _set_mic(s: String) -> void:
	mic_state = s
	mic_state_changed.emit(s)


func _is_english_or_hindi(text: String) -> bool:
	var has_letter: bool = false
	for i in range(text.length()):
		var cp: int = text.unicode_at(i)
		# Allow ASCII / Latin Extended (English & Hinglish), Devanagari (Hindi), and general punctuation/quotes.
		if (cp >= 0x0020 and cp <= 0x024F) or (cp >= 0x0900 and cp <= 0x097F) or (cp >= 0x2000 and cp <= 0x206F):
			if (cp >= 0x0041 and cp <= 0x005A) or (cp >= 0x0061 and cp <= 0x007A) or (cp >= 0x0900 and cp <= 0x097F):
				has_letter = true
		else:
			return false
	return has_letter


func _on_transcribed(id: int, text: String) -> void:
	if id != _stt_req:
		return
	_stt_req = -1
	_set_mic("idle")
	var t: String = text.strip_edges()
	var low: String = t.to_lower()
	if t.is_empty() or not _is_english_or_hindi(t) or low.begins_with("parallax squad") or low.begins_with("english or hindi") or low.contains("kite, nuke") or low.contains("bodyguard, massacre") or low.contains("ceasefire, scatter"):
		notify.emit("Didn't catch that.", "info")
		return
	submit_utterance(t, "voice")


# ------------------------------------------------------------------ LLM path

## The LLM acts as ONE Squad Director: it reads every natural-language message (any phrasing, slang, typos,
## no trigger words), sees the live roster + skills, the strategy library and the battlefield table (enemy IDs
## with looks / colours / weapons / positions from WorldIntel), then issues tool calls and has allies answer
## in character through `say`. Allies themselves query WorldIntel to act on the IDs.
static func tools() -> Array:
	return [
		{"type": "function", "function": {
			"name": "command_allies",
			"description": "Give an order to one or more allies. Call once per distinct order. CHAINS: several calls for the SAME ally in one response run in sequence, in the order you list them (e.g. jump x2 -> position behind -> ranged E3). Different allies can get different chains in the same response.",
			"parameters": {"type": "object", "properties": {
				"allies": {"type": "array", "items": {"type": "string"}, "description": "Ally names from the roster, or [\"all\"]."},
				"action": {"type": "string", "enum": ["follow", "hold", "advance", "wait", "position", "rearguard", "ranged", "sneak_attack", "attack", "retreat", "taunt", "take_aggro", "peel", "hit_and_run", "bodyguard", "kite", "nuke", "revive", "split", "hunt", "destroy", "interact", "overwatch", "jump", "dance", "emote", "circle", "face", "status", "stop", "auto_engage_on", "auto_engage_off"]},
				"target": {"type": "string", "description": "Enemy: a player mark ('M1'..'M4', 'marked', or 'marked group' for enemies inside a mark's 18 m radius — leave blank to default to M1 when marked), OR a BATTLEFIELD ID ('E3'), nearest/strongest/weakest, or 'ally:<Name>'. advance/hold at ping: 'marked_location' (allies march to the marked spot/ahead and engage & hold any enemies encountered on the way). bodyguard: ally name/'player'/'objective'. revive: ally name. interact: 'chest'/blank. ranged: optional enemy (blank = keep shooting marked/nearest until clear)."},
				"spot": {"type": "string", "enum": ["behind", "front", "left", "right", "close", "far"], "description": "position: where to stand relative to the player (far = keep your distance / get away)."},
				"seconds": {"type": "integer", "description": "wait/hold: how long (1-30 s) before the next step of a chain."},
				"lure_to_player": {"type": "boolean", "description": "kite only: bait the enemy back to the player/squad and circle there so the others can hit it."},
				"count": {"type": "integer", "description": "Repetitions for jump (1-12)."},
				"emote": {"type": "string", "enum": ["wave", "cheer", "sit", "bow", "salute", "spin", "flex", "laugh", "clap", "point", "kneel", "nod", "shrug", "backflip", "lie"]}
			}, "required": ["allies", "action"]}}},
		{"type": "function", "function": {
			"name": "use_skill",
			"description": "Make an ally use one of THEIR OWN signature skills (see SKILLS). Enemy-target skills take an enemy ID; heals/wards take an ally name or 'player'.",
			"parameters": {"type": "object", "properties": {
				"ally": {"type": "string"},
				"skill": {"type": "string", "description": "Skill id from SKILLS, e.g. war_cry, shadowstep, mending_light."},
				"target": {"type": "string"}
			}, "required": ["ally", "skill"]}}},
		{"type": "function", "function": {
			"name": "execute_strategy",
			"description": "Run a squad strategy from STRATEGIES. The game assigns every living ally a part by role.",
			"parameters": {"type": "object", "properties": {
				"strategy": {"type": "string", "enum": SquadStrategies.ids()},
				"target": {"type": "string", "description": "Primary mark/enemy ID such as 'M1', 'marked', or 'E3' (optional; defaults to M1 if marked)."},
				"allies": {"type": "array", "items": {"type": "string"}, "description": "Optional subset of allies."}
			}, "required": ["strategy"]}}},
		{"type": "function", "function": {
			"name": "start_combo",
			"description": "Two-ally handshake combo. kite_nuke: skirmisher kites into a cluster, artillery nukes. charge_finish: vanguard charges + knocks down, skirmisher finishes. lure_detonate: artillery plants a sigil, skirmisher lures enemies onto it, it detonates.",
			"parameters": {"type": "object", "properties": {
				"combo": {"type": "string", "enum": ["kite_nuke", "charge_finish", "lure_detonate"]},
				"target": {"type": "string"},
				"allies": {"type": "array", "items": {"type": "string"}}
			}, "required": ["combo"]}}},
		{"type": "function", "function": {
			"name": "panic_order",
			"description": "Overrides everything. massacre: all-out attack, no retreat. ceasefire: stop attacking and regroup. scatter: spread away from danger.",
			"parameters": {"type": "object", "properties": {
				"order": {"type": "string", "enum": ["massacre", "ceasefire", "scatter"]},
				"allies": {"type": "array", "items": {"type": "string"}}
			}, "required": ["order"]}}},
		{"type": "function", "function": {
			"name": "say",
			"description": "An ally speaks out loud, in character (one short line, max ~20 words). Use it for every reply; usually only the ally/allies addressed or acting speak (max 2 per turn).",
			"parameters": {"type": "object", "properties": {
				"ally": {"type": "string"},
				"text": {"type": "string"}
			}, "required": ["ally", "text"]}}},
	]


func build_system_prompt(focus_ally: SquadAlly = null) -> String:
	var roster: String = _manager.get_roster_text() if _manager != null else ""
	var skills: String = _manager.get_skills_text() if _manager != null else ""
	var marks: String = _manager.intel.describe_marks_text() if _manager != null and _manager.intel != null else "- none"
	var field: String = _manager.intel.describe_text() if _manager != null and _manager.intel != null else "unknown"
	var personas: PackedStringArray = []
	if _manager != null:
		for a in _manager.allies:
			personas.append("- %s (%s): %s" % [a.get_display_name(), a.get_role(), a.profile.personality])
	var player_s: String = ""
	var p: PlayerController = get_tree().get_first_node_in_group("player") as PlayerController
	if p != null:
		player_s = "Player HP %d/%d%s." % [p.health, p.max_health, (", Mirror Ward %d" % p.get_ally_ward()) if p.get_ally_ward() > 0 else ""]
		if RealmManager.instance != null:
			player_s += " Realm: %s." % ("MERGED" if RealmManager.instance.is_merged else ("MIRROR" if RealmManager.instance.current_realm == RealmManager.Realm.MIRROR else "REALITY"))
	var memory: PackedStringArray = []
	for line in _recent_events.slice(maxi(0, _recent_events.size() - 8)):
		memory.append("- " + String(line))
	var focus: String = ("The player is mainly talking to %s.\n" % focus_ally.get_display_name()) if focus_ally != null else ""
	return "You are the SQUAD DIRECTOR of PARALLAX, a dark-fantasy mirror-realm arena game. You command the player's squad of mirror-bound 'Echoes' and voice them.\n" \
		+ "The player talks to you in completely natural language — any phrasing, slang, typos, half-sentences, voice transcripts. Work out what they mean; never require keywords. Ambiguous orders: choose the most sensible tactical reading.\n" \
		+ "RULES: (1) Turn every order into tool calls in THIS response (parallel calls allowed). (2) Refer to enemies by their BATTLEFIELD ID (E#) or player mark (M1..M4): when the player describes one by look, colour, weapon, size, position (left/right/behind, near an ally, around/near M#) or behaviour (who it is hitting, stunned, fleeing), pick the matching ID. (3) Use allies' OWN skills when they fit; a skill belongs to exactly one ally. (4) Prefer a STRATEGY when the player describes a plan for the whole squad. (5) Reply only through `say`, in character, 1-2 short punchy lines per speaker, max 2 speakers; no narration. Questions about the fight: answer from BATTLEFIELD/ROSTER via `say`. (6) massacre / ceasefire / scatter are panic orders. Silly orders are fine — jump, dance, emotes, circle, face, backflips; play along in character. (7) A DOWN ally can't act: say so and suggest a revive. Never invent allies, enemies, skills or strategies. (8) One message often mixes everything: simple orders, chains (\"then\", \"after that\"), several allies each with their OWN different chain, plus chat. Decompose it fully: for each ally, emit its steps as separate tool calls IN ORDER (they run as a chain); 'everyone else' = the allies not named elsewhere. Movement words: get behind me/in front/left/right/close/keep distance = position; hold/watch the rear = rearguard; long-distance / shoot / throw = ranged; wait N seconds = wait; bait / run circles / keep it busy = kite (lure_to_player when they want it brought back); sneak attack / backstab / get behind IT = sneak_attack. A taunted or baited enemy chases its taunter until that ally is down, so pair a bait with a sneak_attack or attacks from the others. (9) Plain conversation (greetings, jokes, questions, banter) = only `say`, no orders. (10) The squad auto-rallies to protect anyone at low HP; don't fight that unless told. (11) Every `say` line must describe ONLY what that ally was ordered to do in THIS response (or answer the player's question) — never announce a plan, target or skill you did not issue as a tool call, never narrate other allies, no lore or filler. Default to ONE speaker; use two only when the player addressed several allies. (12) Enemy Marks & Marked Locations: [MARKED M#] targets can be far away; all enemies within 18m of a mark appear tagged [NEAR M#]. The player can also ping any ground location (MARKED LOCATION). Allies under any active order have a free leash and run across the arena without teleporting back. When the player asks allies to go to the marked location/spot/ping, or to go/push/scout ahead and engage anything they encounter (in English or Hindi/Hinglish), use action='advance' with target='marked_location' — allies march there, engage and hold any enemies encountered along the way, and hold the spot until the player arrives. When a player mentions 'the marked one'/'M#'/'that one' for an enemy, pass 'M#' or leave target blank (automatically prefers M1). (13) STRICT ADDRESSEE RULE: If the player names specific allies (e.g. 'Sam go attack em', 'Sam attack, Mark protect him'), issue tool calls ONLY for those specific allies named! DO NOT issue orders or tool calls for unmentioned allies (they must stay quietly in formation following the player). Only assign orders to all allies if the player explicitly says 'all', 'squad', 'everyone', or calls a full squad strategy. (14) DIALOGUE QUALITY & AWARENESS: Write sharp, fresh, genuinely human squad dialogue that shows real awareness of the current fight (name the exact enemy/count/distance, notice low HP, realm shifts, who's outnumbered, or recent events). NEVER repeat generic canned acknowledgements ('On it', 'Understood', 'Certainly', 'As you wish', 'Conducting', 'Commencing demonstration', 'Q.E.D.'). Let Sam's dry veteran grit, Sera's cocky banter, and Mark's cool sarcastic wit shine through naturally. If the player speaks Hindi/Hinglish, understand it seamlessly and reply naturally.\n" \
		+ focus \
		+ "PERSONALITIES:\n%s\n" % "\n".join(personas) \
		+ "ROSTER (live):\n%s\n" % roster \
		+ "SKILLS:\n%s\n" % skills \
		+ "STRATEGIES:\n%s\n" % SquadStrategies.describe_all() \
		+ "MARKED TARGETS:\n%s\n" % marks \
		+ "BATTLEFIELD (live, marked & mark-region first, then nearest; bearing is relative to the player's facing):\n%s\n" % field \
		+ "PLAYER: %s\n" % player_s \
		+ "RECENT EVENTS:\n%s" % ("\n".join(memory) if not memory.is_empty() else "- none")


func _ask_llm(text: String, via: String) -> void:
	var focus: SquadAlly = _pick_addressee(text)
	if _manager.intel != null:
		_manager.intel.refresh()
	var msgs: Array = [{"role": "system", "content": build_system_prompt(focus)}]
	msgs.append_array(_director_history)
	msgs.append({"role": "user", "content": text})
	var id: int = client.chat_stream(msgs, tools(), 0.45)
	_pending[id] = {"ally": focus, "user_text": text, "via": via, "spoken_upto": 0, "text": ""}


func _pick_addressee(text: String) -> SquadAlly:
	var low: String = " " + text.to_lower() + " "
	var best: SquadAlly = null
	var best_pos: int = 1 << 30
	for a in _manager.allies:
		var p: int = low.find(a.get_display_name().to_lower())
		if p >= 0 and p < best_pos and not a.is_downed:
			best_pos = p
			best = a
	if best != null:
		return best
	var living: Array[SquadAlly] = _manager.get_living()
	return living[0] if not living.is_empty() else null


func _on_text_delta(id: int, delta: String) -> void:
	if not _pending.has(id):
		return
	var rec: Dictionary = _pending[id]
	rec["text"] = String(rec["text"]) + delta


func _on_chat_completed(id: int, text: String, calls: Array) -> void:
	if not _pending.has(id):
		return
	var rec: Dictionary = _pending[id]
	_pending.erase(id)
	if _manager == null:
		return
	var focus: SquadAlly = rec["ally"] as SquadAlly
	var tool_msgs: Array = []
	var spoke: int = 0
	var action_calls: int = 0
	var acted: Array[SquadAlly] = []
	# One LLM turn = one batch: same-ally calls become a chain in call order.
	_manager.begin_batch()
	# Allies given a direct order this turn are excluded from any squad-wide strategy in the same turn.
	var directly_ordered: Array[String] = []
	for c0 in calls:
		var cd0: Dictionary = c0 as Dictionary
		var a0: Dictionary = cd0.get("args", {}) as Dictionary
		match String(cd0.get("name", "")):
			"command_allies", "start_combo":
				for n0 in (a0.get("allies", []) as Array if a0.get("allies", []) is Array else []):
					if String(n0).to_lower() != "all":
						directly_ordered.append(String(n0).to_lower())
			"use_skill":
				pass  # skills cut in and resume, they never conflict
	for c in calls:
		var cd: Dictionary = c as Dictionary
		var tname: String = String(cd.get("name", ""))
		var args: Dictionary = cd.get("args", {}) as Dictionary
		if tname == "execute_strategy" and not directly_ordered.is_empty():
			var given: Array = args.get("allies", []) as Array if args.get("allies", []) is Array else []
			if given.is_empty() or given.has("all"):
				var rest: Array = []
				for a1 in _manager.get_living():
					if not directly_ordered.has(a1.get_display_name().to_lower()):
						rest.append(a1.get_display_name())
				args = args.duplicate()
				args["allies"] = rest
		var res: String = ""
		if tname == "say":
			var who: SquadAlly = _manager.find_ally(String(args.get("ally", "")))
			if who == null:
				who = focus if focus != null else _manager._leader()
			var line: String = String(args.get("text", "")).strip_edges()
			if who != null and not line.is_empty():
				if who.is_downed:
					line = "(weakly) " + line
				_voice(who, line, 1)   # subtitle is emitted by _on_voice_line when the line plays (or is dropped)
				_remember(who.get_display_name(), "said: " + line)
				spoke += 1
				res = "spoken"
			else:
				res = "no such ally"
		else:
			var cmd: Dictionary = tool_to_command(tname, args)
			if not cmd.is_empty():
				action_calls += 1
			res = _manager.issue(cmd, String(rec["via"]) + "+llm") if not cmd.is_empty() else "invalid tool call"
			_remember("squad", "%s %s -> %s" % [tname, JSON.stringify(args), res.left(80)])
			for n in (cmd.get("allies", []) as Array):
				var a2: SquadAlly = _manager.find_ally(String(n))
				if a2 != null and not acted.has(a2):
					acted.append(a2)
		tool_called.emit(String(args.get("ally", focus.get_display_name() if focus != null else "squad")), tname, args, res)
		tool_msgs.append({"role": "tool", "tool_call_id": String(cd.get("id", "")), "content": res})
	_manager.end_batch()
	# Safety net: if the LLM only talked (0 action tool calls) on an utterance that clearly contains an order,
	# run the deterministic parser so allies never acknowledge an order and then sit idle.
	if action_calls == 0:
		var parsed_cmds: Array = ParserScript.parse(String(rec["user_text"]), _manager.get_ally_names(), _manager.get_parser_context())
		var fallback_cmds: Array = []
		for pc in parsed_cmds:
			if pc is Dictionary:
				var pv: String = String((pc as Dictionary).get("verb", ""))
				if not pv.is_empty() and not (pv in ["chat", "say", "status"]):
					fallback_cmds.append(pc)
		if not fallback_cmds.is_empty():
			_manager.issue_commands(fallback_cmds, String(rec["via"]) + "+llm")
	# Shared Director history (one conversation; per-ally memory lives in _histories / RECENT EVENTS).
	_director_history.append({"role": "user", "content": String(rec["user_text"])})
	var assistant: Dictionary = {"role": "assistant", "content": text if not text.is_empty() else null}
	if not calls.is_empty():
		var tc: Array = []
		for c2 in calls:
			var cd2: Dictionary = c2 as Dictionary
			var tce: Dictionary = {"id": String(cd2.get("id", "")), "type": "function", "function": {"name": String(cd2.get("name", "")), "arguments": String(cd2.get("raw_args", "{}"))}}
			if cd2.has("extra_content"):
				tce["extra_content"] = cd2["extra_content"]
			tc.append(tce)
		assistant["tool_calls"] = tc
	_director_history.append(assistant)
	_director_history.append_array(tool_msgs)
	while _director_history.size() > HISTORY_MAX:
		_director_history.pop_front()
	while not _director_history.is_empty() and String((_director_history[0] as Dictionary).get("role", "")) != "user":
		_director_history.pop_front()
	# Plain text instead of `say`: voice it as the addressed ally. Nothing at all: a canned acknowledgement.
	var speaker: SquadAlly = focus if focus != null else (acted[0] if not acted.is_empty() else _manager._leader())
	var spoken: String = text.strip_edges()
	if spoke == 0 and speaker != null:
		if spoken.is_empty():
			spoken = speaker.profile.line("ack", "On it.") if not calls.is_empty() else speaker.profile.line("confused", "Say again?")
		_voice(speaker, spoken, 1)
		_remember(speaker.get_display_name(), "said: " + spoken)
	text_response.emit(speaker.get_display_name() if speaker != null else "squad", spoken if spoke == 0 else "(%d line(s) via say)" % spoke)
	log_entry.emit({"source": "llm", "who": "Director", "what": String(rec["user_text"]).left(40), "result": "%d tool call(s)" % calls.size()})


func _remember(who: String, what: String) -> void:
	_recent_events.append("%s %s" % [who, what])
	while _recent_events.size() > 24:
		_recent_events.pop_front()
	var h: Array = _histories.get(who, []) as Array
	h.append(what)
	while h.size() > HISTORY_MAX:
		h.pop_front()
	_histories[who] = h


## Maps an LLM tool call to the shared command schema.
static func tool_to_command(tool_name: String, args: Dictionary) -> Dictionary:
	var allies: Variant = args.get("allies", [])
	if not (allies is Array):
		allies = [String(allies)] if allies != null else []
	match tool_name:
		"command_allies":
			var action: String = String(args.get("action", "")).strip_edges().to_lower()
			match action:
				"move", "go", "push", "scout", "move_to", "go_to", "forward":
					action = "advance"
				"engage", "fight", "kill", "strike", "focus", "clear":
					action = "attack"
				"protect", "guard", "defend", "cover":
					action = "bodyguard"
				"fall_back", "back_off", "regroup":
					action = "retreat"
			var cmd: Dictionary = {"verb": action, "allies": allies, "target": String(args.get("target", "")), "count": int(args.get("count", 1))}
			if action == "auto_engage_on" or action == "auto_engage_off":
				cmd["verb"] = "auto_engage"
				cmd["enabled"] = action == "auto_engage_on"
			if action == "emote":
				cmd["text"] = String(args.get("emote", "cheer"))
			if action == "position":
				cmd["spot"] = String(args.get("spot", "behind"))
			if action == "sneak_attack":
				cmd["verb"] = "surround"
				cmd["side"] = "rear"
				cmd["angle"] = 180.0
			if action == "kite" and bool(args.get("lure_to_player", false)):
				cmd["lure"] = "player"
			if action == "wait":
				cmd["verb"] = "hold"
				cmd["step_sec"] = clampi(int(args.get("seconds", 3)), 1, 30)
			elif action == "hold" and int(args.get("seconds", 0)) > 0:
				cmd["step_sec"] = clampi(int(args.get("seconds", 0)), 1, 30)
			if action == "take_aggro":
				cmd["verb"] = "taunt"
				cmd["area"] = true
			return cmd
		"start_combo":
			return {"verb": "combo_" + String(args.get("combo", "")), "allies": allies, "target": String(args.get("target", ""))}
		"panic_order":
			return {"verb": String(args.get("order", "")), "allies": allies if not (allies as Array).is_empty() else ["all"]}
		"use_skill":
			var who: String = String(args.get("ally", ""))
			return {"verb": "skill", "skill": String(args.get("skill", "")), "allies": [who] if not who.is_empty() else [], "target": String(args.get("target", ""))}
		"execute_strategy":
			return {"verb": "strategy", "strategy": String(args.get("strategy", "")), "allies": allies, "target": String(args.get("target", ""))}
		"say":
			return {"verb": "say", "allies": [String(args.get("ally", ""))], "text": String(args.get("text", ""))}
	return {}


func _on_request_failed(id: int, kind: String, message: String) -> void:
	if OpenAIClient.is_stt_kind(kind) and id == _stt_req:
		_stt_req = -1
		_set_mic("idle")
		notify.emit("Voice transcription failed: %s" % message, "error")
		return
	if OpenAIClient.is_tts_kind(kind):
		if message.begins_with("QUOTA") and SquadAIConfig.tts_available():
			return  # the TTS player already retried on the next model
		if Time.get_ticks_msec() - _last_tts_warn > 30000:
			_last_tts_warn = Time.get_ticks_msec()
			if tts.engine() == "system":
				notify.emit("Cloud voices unavailable — switched to system voices for this session.", "info")
			elif not SquadAIConfig.tts_available():
				notify.emit("Ally voices hit today's free TTS quota — subtitles only (orders still work).", "warn")
			else:
				notify.emit("Ally voice unavailable: %s" % message.left(120), "warn")
		return
	if kind == "chat" and _pending.has(id):
		var rec: Dictionary = _pending[id]
		_pending.erase(id)
		notify.emit("Squad AI error — using offline orders. (%s)" % message, "error")
		_offline(String(rec["user_text"]), String(rec["via"]))


# ------------------------------------------------------------------ voices, subtitles, log

const SYS_PITCH: Dictionary = {"vanguard": 0.8, "skirmisher": 1.25, "artillery": 1.0}
const SYS_RATE: Dictionary = {"vanguard": 1.0, "skirmisher": 1.12, "artillery": 1.02}


func _voice(ally: SquadAlly, text: String, prio: int) -> void:
	if text.is_empty() or ally == null:
		return
	var voice: String = ally.profile.gemini_voice if SquadAIConfig.provider() == "gemini" else ally.profile.tts_voice
	var role: String = ally.get_role()
	var slot: int = maxi(0, _manager.allies.find(ally)) if _manager != null else 0
	tts.speak(ally.get_display_name(), sanitize_spoken_line(text), voice, ally.profile.tts_instructions, prio,
		float(SYS_PITCH.get(role, 1.0)), float(SYS_RATE.get(role, 1.0)), slot)


func sanitize_spoken_line(text: String) -> String:
	var t: String = text.strip_edges()
	# Strip "Say: ", "Speaks: ", "Voice: " etc.
	var patterns: PackedStringArray = ["Say: ", "Speaks: ", "Voice: "]
	for p in patterns:
		if t.begins_with(p):
			t = t.substr(p.length()).strip_edges()
	return t


## A line became audible (or will not be voiced): show it now, so text always matches what is heard.
func _on_voice_line(speaker: String, text: String) -> void:
	var a: SquadAlly = _manager.find_ally(speaker) if _manager != null else null
	subtitle.emit(speaker, text, a.profile.color if a != null else UITheme.GOLD, true)


func _on_ally_spoke(ally_name: String, text: String, _event: String, priority: int, _voice_id: String) -> void:
	var a: SquadAlly = _manager.find_ally(ally_name) if _manager != null else null
	if priority <= 0:
		# Chatter (idle lines, banter, kill/engage barks): only when ambient chatter is switched on.
		if SquadAIConfig.ambient_chatter:
			subtitle.emit(ally_name, text, a.profile.color if a != null else UITheme.GOLD, true)
		return
	if a == null:
		subtitle.emit(ally_name, text, UITheme.GOLD, true)
		return
	if priority >= SquadAIConfig.voice_min_event_priority:
		_voice(a, text, priority)
	else:
		subtitle.emit(ally_name, text, a.profile.color, true)
	_remember(ally_name, "said: " + text)


func _on_command_logged(entry: Dictionary) -> void:
	log_entry.emit(entry)
	# Squad events (downs, revives, skills, ambushes, phase failures) feed the Director's RECENT EVENTS.
	if String(entry.get("source", "")) == "event":
		_remember(String(entry.get("who", "")), "%s %s" % [entry.get("what", ""), entry.get("result", "")])


func _on_roster_changed(_roster: Array) -> void:
	if _manager == null:
		return
	# The system prompt is rebuilt from the live roster on every request; surface changes for the HUD/log.
	var down: PackedStringArray = []
	for a in _manager.allies:
		if a.is_downed:
			down.append(a.get_display_name())
	var key: String = ",".join(down)
	if key != _last_roster_text:
		_last_roster_text = key
		roster_prompt_updated.emit(_manager.get_roster_text())


func get_history(ally_name: String) -> Array:
	return _histories.get(ally_name, []) as Array
