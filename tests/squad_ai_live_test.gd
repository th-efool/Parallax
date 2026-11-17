extends SceneTree
## LIVE provider test (uses real API quota — ~6 requests). Run only with a key configured (env / .env):
##   godot --headless --path . -s res://tests/squad_ai_live_test.gd
## Natural-language orders with no trigger words go through the single Squad Director:
##   1) describe an enemy by look ("purple wizard thing") + a bodyguard request in the same sentence
##   2) a casual skill request ("patch Brannoc up a bit")
##   3) a whole-squad plan in plain words ("swarm the big green brute from every side")
##   4) streamed TTS, 5) STT round-trip of that audio.

var _checks: int = 0
var _fails: int = 0
var comms: SquadComms = null
var mgr: AllySquadManager = null
var texts: Array[String] = []
var errors: Array[String] = []
var tools: Array = []


func _check(n: String, ok: bool, d: String = "") -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[live] %s %s %s" % ["PASS" if ok else "FAIL", n, d])


func _initialize() -> void:
	create_timer(200.0).timeout.connect(func() -> void:
		print("[live] WATCHDOG")
		quit(2))
	_run()


func _ask(text: String) -> void:
	texts.clear()
	errors.clear()
	tools.clear()
	print("[live] YOU> ", text)
	comms.submit_utterance(text, "chat")
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000 and texts.is_empty() and errors.is_empty():
		await process_frame
	await create_timer(0.3).timeout


func _targets_of(a: SquadAlly) -> Array:
	var out: Array = []
	var cmds: Array = [a.current] if a.current != null else []
	cmds.append_array(a.queue)
	for c in cmds:
		var cmd: SquadCommand = c as SquadCommand
		var sel: String = String(cmd.args.get("target", ""))
		if not sel.is_empty():
			out.append(mgr.resolve_enemy(sel, a.global_position))
		if cmd.data.has("enemy"):
			out.append(cmd.data["enemy"])
	return out


func _run() -> void:
	SquadAIConfig.ensure_loaded()
	print("[live] provider=%s model=%s key=%s" % [SquadAIConfig.provider(), SquadAIConfig.model(), SquadAIConfig.key_source()])
	if not SquadAIConfig.is_online():
		print("[live] no key — skipping")
		quit(0)
		return
	var main: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await create_timer(2.0).timeout
	var title: Node = get_first_node_in_group("title_screen")
	if title != null:
		if "show_quote_on_start" in title:
			title.set("show_quote_on_start", false)
		title.call("press_start")
	await create_timer(2.5).timeout
	comms = root.find_child("SquadComms", true, false) as SquadComms
	mgr = AllySquadManager.instance
	var player: PlayerController = get_first_node_in_group("player") as PlayerController
	player.max_health = 100000
	player.health = 100000
	player.global_position = Vector3(0, 0, -14)
	player.set_facing_direction(Vector3(0, 0, 1))
	mgr.regroup(false)
	var level: Node = main.get_node("LevelRoot")
	var caster: EnemyBase = level.call("_add_roamer", level, "hexcaster", "Test_live_caster", Vector3(-4, 0, -6), EncounterDirector.Section.ENTRY, Vector3(0, 0, -14)) as EnemyBase
	var brute: EnemyBase = level.call("_add_roamer", level, "brute", "Test_live_brute", Vector3(4, 0, -6), EncounterDirector.Section.ENTRY, Vector3(0, 0, -14)) as EnemyBase
	for e in [caster, brute]:
		e.max_health = 5000
		e.health = 5000
	await create_timer(1.5).timeout
	comms.tool_called.connect(func(a: String, t: String, args: Dictionary, r: String) -> void:
		tools.append([a, t, args, r])
		print("[live]   tool %s %s -> %s" % [t, JSON.stringify(args), r.left(110)]))
	comms.text_response.connect(func(a: String, t: String) -> void:
		texts.append(t))
	comms.subtitle.connect(func(sp: String, t: String, _c: Color, fin: bool) -> void:
		if fin and sp != "YOU":
			print("[live]   %s: %s" % [sp, t]))
	comms.notify.connect(func(t: String, lv: String) -> void:
		if lv == "error":
			errors.append(t)
		print("[live]   notify[%s] %s" % [lv, t]))

	# 1) Description-based target + bodyguard, no keywords.
	await _ask("ok listen up, that purple wizard thing keeps blasting me, can somebody shut it up? and Brannoc, stick close to me")
	_check("nl1_response", not texts.is_empty() and errors.is_empty(), str(errors))
	var hits_caster: bool = false
	for a in mgr.get_living():
		if _targets_of(a).has(caster):
			hits_caster = true
	_check("nl1_targets_purple_caster", hits_caster, mgr.get_roster_text().left(300))
	var bran: SquadAlly = mgr.find_ally("Brannoc")
	var guards: bool = (bran.current != null and bran.current.verb == "bodyguard") or bran.queue.any(func(q: SquadCommand) -> bool: return q.verb == "bodyguard")
	_check("nl1_brannoc_guards_player", guards, bran.get_state_text())
	_check("nl1_has_say_or_text", tools.any(func(t: Array) -> bool: return t[1] == "say") or not texts.is_empty())

	# 2) Casual skill request.
	await create_timer(2.0).timeout
	bran.health = int(bran.max_health * 0.5)
	var before: int = bran.health
	await _ask("Ivo could you patch Brannoc up a little, he looks rough")
	_check("nl2_skill_call", tools.any(func(t: Array) -> bool: return t[1] == "use_skill"), str(tools.map(func(t: Array) -> String: return t[1])))
	await create_timer(3.0).timeout
	_check("nl2_brannoc_healed", bran.health > before, "%d -> %d" % [before, bran.health])

	# 3) Whole-squad plan in plain words.
	await create_timer(2.0).timeout
	await _ask("alright everyone, let's swarm the big green brute from every side")
	var strat_ok: bool = tools.any(func(t: Array) -> bool: return t[1] == "execute_strategy") or tools.filter(func(t: Array) -> bool: return t[1] == "command_allies").size() >= 2
	_check("nl3_squad_plan", strat_ok, "active strategy: %s" % mgr.active_strategy)
	var on_brute: int = 0
	for a in mgr.get_living():
		if _targets_of(a).has(brute):
			on_brute += 1
	_check("nl3_targets_brute", on_brute >= 2, "%d allies on the brute" % on_brute)

	# 4) TTS
	await create_timer(4.0).timeout
	comms.tts.stop_all()
	var pcm := PackedByteArray()
	var tts_err: Array[String] = []
	var voice: String = mgr.find_ally("Sera").profile.gemini_voice if SquadAIConfig.provider() == "gemini" else "nova"
	var req: int = comms.client.speak_stream("Everyone ceasefire.", voice, "Clearly")
	comms.client.tts_chunk.connect(func(id: int, b: PackedByteArray) -> void:
		if id == req:
			pcm.append_array(b))
	var done: Array[bool] = [false]
	comms.client.tts_finished.connect(func(id: int) -> void:
		if id == req:
			done[0] = true)
	comms.client.request_failed.connect(func(id: int, _k: String, m: String) -> void:
		if id == req:
			tts_err.append(m)
			done[0] = true)
	var t1: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 40000 and not done[0]:
		await process_frame
	_check("tts_streamed_pcm", pcm.size() > 4800, "%d bytes %s" % [pcm.size(), str(tts_err)])

	# 5) STT round-trip
	if pcm.size() > 4800:
		var frames := PackedVector2Array()
		for i in range(pcm.size() / 2):
			var v: float = float(pcm.decode_s16(i * 2)) / 32768.0
			frames.append(Vector2(v, v))
		var wav: PackedByteArray = SquadMicCapture.encode_wav(frames, 24000.0)
		var heard: Array[String] = []
		var sreq: int = comms.client.transcribe(wav, "")
		comms.client.transcribed.connect(func(id: int, t: String) -> void:
			if id == sreq:
				heard.append(t))
		comms.client.request_failed.connect(func(id: int, _k: String, m: String) -> void:
			if id == sreq:
				heard.append("ERR " + m))
		t1 = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < 40000 and heard.is_empty():
			await process_frame
		var txt: String = heard[0] if not heard.is_empty() else ""
		_check("stt_roundtrip", txt.to_lower().contains("cease"), txt)
	print("[live] SUMMARY %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)

## Waits until MainController has built the level behind the loading screen (Start shows it now).
func _await_level() -> void:
	var mc: Node = get_first_node_in_group("main_controller")
	var t0: int = Time.get_ticks_msec()
	while mc != null and not bool(mc.get("level_ready")) and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	await create_timer(0.5).timeout