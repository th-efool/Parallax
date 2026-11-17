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
const HISTORY_MAX: int = 18

var client: OpenAIClient = null
var mic: SquadMicCapture = null
var tts: SquadTTSPlayer = null
var mic_state: String = "idle"

var _histories: Dictionary = {}     # ally name -> Array of messages
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
	var cmds: Array = ParserScript.parse(t, _manager.get_ally_names())
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
	var hint: String = "PARALLAX squad orders. Allies: %s. Words: kite, nuke, bodyguard, massacre, ceasefire, scatter, revive, lure, detonate, charge, finish." % ", ".join(_manager.get_ally_names() if _manager != null else [])
	_stt_req = client.transcribe(wav, hint)


func _set_mic(s: String) -> void:
	mic_state = s
	mic_state_changed.emit(s)


func _on_transcribed(id: int, text: String) -> void:
	if id != _stt_req:
		return
	_stt_req = -1
	_set_mic("idle")
	if text.strip_edges().is_empty():
		notify.emit("Heard nothing intelligible.", "info")
		return
	submit_utterance(text, "voice")


# ------------------------------------------------------------------ LLM path

const TOOLS: Array = [
	{"type": "function", "function": {
		"name": "command_allies",
		"description": "Give an order to one or more squad allies. Call once per distinct order; call several in parallel for multi-part orders.",
		"parameters": {"type": "object", "properties": {
			"allies": {"type": "array", "items": {"type": "string"}, "description": "Ally names from the roster, or [\"all\"]."},
			"action": {"type": "string", "enum": ["follow", "hold", "attack", "retreat", "taunt", "take_aggro", "peel", "hit_and_run", "bodyguard", "kite", "nuke", "revive", "split", "hunt", "destroy", "interact", "jump", "dance", "emote", "status", "stop", "auto_engage_on", "auto_engage_off"]},
			"target": {"type": "string", "description": "Enemy selector (nearest, strongest, weakest, brute, caster, stalker, phantom, shield, skeleton, warden, or 'ally:<Name>' = that ally's target). For bodyguard: an ally name, 'player' or 'objective'. For revive: an ally name. For interact: 'chest' or blank. take_aggro pulls everything off the player; peel pulls one enemy off the player; split spreads the squad left/right/center."},
			"count": {"type": "integer", "description": "Repetitions for jump (1-12)."},
			"emote": {"type": "string", "enum": ["wave", "cheer", "sit", "bow", "salute", "spin", "flex"]}
		}, "required": ["allies", "action"]}}},
	{"type": "function", "function": {
		"name": "start_combo",
		"description": "Two-ally handshake combo. kite_nuke: skirmisher kites enemies into a cluster then artillery nukes them. charge_finish: vanguard charges and knocks down, skirmisher finishes. lure_detonate: artillery plants a mirror sigil, skirmisher lures enemies onto it, then it detonates. The game substitutes downed allies automatically.",
		"parameters": {"type": "object", "properties": {
			"combo": {"type": "string", "enum": ["kite_nuke", "charge_finish", "lure_detonate"]},
			"target": {"type": "string"},
			"allies": {"type": "array", "items": {"type": "string"}, "description": "Optional preferred participants."}
		}, "required": ["combo"]}}},
	{"type": "function", "function": {
		"name": "panic_order",
		"description": "Overrides everything. massacre: all-out attack, no retreat. ceasefire: stop attacking and regroup. scatter: spread away from danger.",
		"parameters": {"type": "object", "properties": {
			"order": {"type": "string", "enum": ["massacre", "ceasefire", "scatter"]},
			"allies": {"type": "array", "items": {"type": "string"}}
		}, "required": ["order"]}}},
]


func build_system_prompt(ally: SquadAlly) -> String:
	var p: AllyProfile = ally.profile
	var roster: String = _manager.get_roster_text() if _manager != null else ""
	var situ: String = _manager.get_combat_summary() if _manager != null else ""
	return ("You are %s, the %s of the player's squad of mirror-bound 'Echoes' in PARALLAX, a dark-fantasy mirror-realm arena combat game. Personality: %s\n" % [p.ally_name, p.role, p.personality]) \
		+ "The player is the condemned champion you fight beside. Reply IN CHARACTER as %s in one or two short spoken sentences (max 25 words): it is voiced aloud, so no lists, emojis or stage directions.\n" % p.ally_name \
		+ "When the player gives an order, ALWAYS call the matching tool(s) in this same response (several in parallel if needed; you may order any squad member, not just yourself) AND say a short in-character acknowledgement. Pick allies by role: vanguard = bodyguard/charge/taunt, skirmisher = kite/lure/finish, artillery = nuke/sigil mines.\n" \
		+ "massacre, ceasefire and scatter are panic orders that override everything. Silly orders (jumping, dancing, emotes) are fine: use the tools. If something is impossible (an ally is DOWN), say so and suggest a revive. Never invent allies, enemies or abilities that are not listed.\n" \
		+ "LIVE SQUAD ROSTER:\n%s\nSITUATION: %s" % [roster, situ]


func _ask_llm(text: String, via: String) -> void:
	var ally: SquadAlly = _pick_addressee(text)
	if ally == null:
		_offline(text, via)
		return
	var hist: Array = _histories.get(ally.get_display_name(), []) as Array
	var msgs: Array = [{"role": "system", "content": build_system_prompt(ally)}]
	msgs.append_array(hist)
	msgs.append({"role": "user", "content": text})
	var id: int = client.chat_stream(msgs, TOOLS)
	_pending[id] = {"ally": ally, "user_text": text, "via": via, "spoken_upto": 0, "text": ""}


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
	var ally: SquadAlly = rec["ally"] as SquadAlly
	if not is_instance_valid(ally):
		return
	subtitle.emit(ally.get_display_name(), String(rec["text"]), ally.profile.color, false)
	# Sentence-chunked TTS: voice each finished sentence while the rest is still streaming.
	var full: String = String(rec["text"])
	var upto: int = int(rec["spoken_upto"])
	var cut: int = -1
	for i in range(upto, full.length() - 1):
		var ch: String = full[i]
		if (ch == "." or ch == "!" or ch == "?") and full[i + 1] == " ":
			cut = i + 1
	if cut > upto:
		_voice(ally, full.substr(upto, cut - upto).strip_edges(), 1)
		rec["spoken_upto"] = cut


func _on_chat_completed(id: int, text: String, calls: Array) -> void:
	if not _pending.has(id):
		return
	var rec: Dictionary = _pending[id]
	_pending.erase(id)
	var ally: SquadAlly = rec["ally"] as SquadAlly
	if not is_instance_valid(ally) or _manager == null:
		return
	var results: Array[String] = []
	var tool_msgs: Array = []
	for c in calls:
		var cd: Dictionary = c as Dictionary
		var cmd: Dictionary = tool_to_command(String(cd.get("name", "")), cd.get("args", {}) as Dictionary)
		var res: String = _manager.issue(cmd, String(rec["via"]) + "+llm") if not cmd.is_empty() else "invalid tool call"
		results.append(res)
		tool_called.emit(ally.get_display_name(), String(cd.get("name", "")), cd.get("args", {}) as Dictionary, res)
		tool_msgs.append({"role": "tool", "tool_call_id": String(cd.get("id", "")), "content": res})
	# Remember the exchange in this ally's own history.
	var hist: Array = _histories.get(ally.get_display_name(), []) as Array
	hist.append({"role": "user", "content": String(rec["user_text"])})
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
	hist.append(assistant)
	hist.append_array(tool_msgs)
	while hist.size() > HISTORY_MAX:
		hist.pop_front()
	# Never leave a dangling tool message at the head of the history.
	while not hist.is_empty() and String((hist[0] as Dictionary).get("role", "")) != "user":
		hist.pop_front()
	_histories[ally.get_display_name()] = hist
	var spoken: String = text.strip_edges()
	if spoken.is_empty():
		spoken = ally.profile.line("ack", "On it.") if not calls.is_empty() else ally.profile.line("confused", "Say again?")
		subtitle.emit(ally.get_display_name(), spoken, ally.profile.color, true)
		_voice(ally, spoken, 1)
	else:
		subtitle.emit(ally.get_display_name(), spoken, ally.profile.color, true)
		var rest: String = text.substr(int(rec["spoken_upto"])).strip_edges()
		if not rest.is_empty():
			_voice(ally, rest, 1)
	text_response.emit(ally.get_display_name(), spoken)
	log_entry.emit({"source": "llm", "who": ally.get_display_name(), "what": spoken, "result": "%d tool call(s)" % calls.size()})


## Maps an LLM tool call to the shared command schema.
static func tool_to_command(tool_name: String, args: Dictionary) -> Dictionary:
	var allies: Variant = args.get("allies", [])
	if not (allies is Array):
		allies = [String(allies)] if allies != null else []
	match tool_name:
		"command_allies":
			var action: String = String(args.get("action", ""))
			var cmd: Dictionary = {"verb": action, "allies": allies, "target": String(args.get("target", "")), "count": int(args.get("count", 1))}
			if action == "auto_engage_on" or action == "auto_engage_off":
				cmd["verb"] = "auto_engage"
				cmd["enabled"] = action == "auto_engage_on"
			if action == "emote":
				cmd["text"] = String(args.get("emote", "cheer"))
			if action == "take_aggro":
				cmd["verb"] = "taunt"
				cmd["area"] = true
			return cmd
		"start_combo":
			return {"verb": "combo_" + String(args.get("combo", "")), "allies": allies, "target": String(args.get("target", "nearest"))}
		"panic_order":
			return {"verb": String(args.get("order", "")), "allies": allies if not (allies as Array).is_empty() else ["all"]}
	return {}


func _on_request_failed(id: int, kind: String, message: String) -> void:
	if OpenAIClient.is_stt_kind(kind) and id == _stt_req:
		_stt_req = -1
		_set_mic("idle")
		notify.emit("Voice transcription failed: %s" % message, "error")
		return
	if OpenAIClient.is_tts_kind(kind):
		if Time.get_ticks_msec() - _last_tts_warn > 30000:
			_last_tts_warn = Time.get_ticks_msec()
			notify.emit("Ally voice unavailable: %s" % message, "warn")
		return
	if kind == "chat" and _pending.has(id):
		var rec: Dictionary = _pending[id]
		_pending.erase(id)
		notify.emit("Squad AI error — using offline orders. (%s)" % message, "error")
		_offline(String(rec["user_text"]), String(rec["via"]))


# ------------------------------------------------------------------ voices, subtitles, log

func _voice(ally: SquadAlly, text: String, prio: int) -> void:
	if text.is_empty() or ally == null:
		return
	var voice: String = ally.profile.gemini_voice if SquadAIConfig.provider() == "gemini" else ally.profile.tts_voice
	tts.speak(ally.get_display_name(), text, voice, ally.profile.tts_instructions, prio)


func _on_ally_spoke(ally_name: String, text: String, _event: String, priority: int, _voice_id: String) -> void:
	var a: SquadAlly = _manager.find_ally(ally_name) if _manager != null else null
	var col: Color = a.profile.color if a != null else UITheme.GOLD
	subtitle.emit(ally_name, text, col, true)
	# Chatter stays subtitle-only; real lines are voiced (higher priority interrupts lower).
	if priority >= 1 and a != null:
		_voice(a, text, priority)


func _on_command_logged(entry: Dictionary) -> void:
	log_entry.emit(entry)


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
