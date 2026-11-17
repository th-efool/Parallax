extends SceneTree
## LIVE provider test (uses real API quota — ~4 requests). Run only with a key configured (env / .env):
##   godot --headless --path . -s res://tests/squad_ai_live_test.gd
## 1) typed order through the LLM path (streaming + tool calls, expects parallel calls)
## 2) streamed TTS for one ally line  3) STT round-trip: the TTS audio is resampled to a 16 kHz WAV and transcribed.

var _checks: int = 0
var _fails: int = 0


func _check(n: String, ok: bool, d: String = "") -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[live] %s %s %s" % ["PASS" if ok else "FAIL", n, d])


func _initialize() -> void:
	create_timer(150.0).timeout.connect(func() -> void:
		print("[live] WATCHDOG")
		quit(2))
	_run()


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
	var comms: SquadComms = root.find_child("SquadComms", true, false) as SquadComms
	var mgr: AllySquadManager = AllySquadManager.instance
	var player: Node3D = get_first_node_in_group("player") as Node3D
	player.global_position = Vector3(0, 0, -14)
	mgr.regroup(false)
	var level: Node = main.get_node("LevelRoot")
	level.call("_add_roamer", level, "skeleton", "Test_live_1", Vector3(-3, 0, -6), EncounterDirector.Section.ENTRY, Vector3(0, 0, -14))
	await create_timer(0.5).timeout

	# 1) LLM order
	var tools: Array = []
	var texts: Array[String] = []
	var errors: Array[String] = []
	comms.tool_called.connect(func(a: String, t: String, args: Dictionary, r: String) -> void:
		tools.append([a, t, args, r])
		print("[live] tool %s %s %s -> %s" % [a, t, JSON.stringify(args), r]))
	comms.text_response.connect(func(a: String, t: String) -> void:
		texts.append(t)
		print("[live] %s says: %s" % [a, t]))
	comms.notify.connect(func(t: String, lv: String) -> void:
		if lv == "error" or lv == "warn":
			errors.append(t)
		print("[live] notify[%s] %s" % [lv, t]))
	comms.submit_utterance("Brannoc, guard me. Sera and Ivo, kite and nuke that skeleton.", "chat")
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 40000 and texts.is_empty() and errors.is_empty():
		await process_frame
	_check("llm_response", not texts.is_empty(), str(errors))
	_check("llm_tool_calls", tools.size() >= 1, "%d call(s)" % tools.size())
	_check("llm_parallel_tool_calls", tools.size() >= 2, "%d call(s)" % tools.size())
	var bran: SquadAlly = mgr.find_ally("Brannoc")
	_check("llm_bodyguard_executed", bran.current != null and (bran.current.verb == "bodyguard" or bran.queue.any(func(q: SquadCommand) -> bool: return q.verb == "bodyguard")), bran.get_state_text())

	# 1b) Second turn to the same ally: history (incl. tool calls + Gemini thought signatures) must be accepted.
	await create_timer(3.0).timeout
	texts.clear()
	errors.clear()
	comms.submit_utterance("Brannoc, how are you holding up?", "chat")
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000 and texts.is_empty() and errors.is_empty():
		await process_frame
	_check("llm_second_turn_history_ok", not texts.is_empty() and errors.is_empty(), str(errors))

	# 2) TTS
	await create_timer(6.0).timeout
	comms.tts.stop_all()
	var pcm := PackedByteArray()
	var tts_err: Array[String] = []
	var req: int = comms.client.speak_stream("Everyone ceasefire.", mgr.find_ally("Sera").profile.gemini_voice if SquadAIConfig.provider() == "gemini" else "nova", "Clearly")
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
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 40000 and not done[0]:
		await process_frame
	_check("tts_streamed_pcm", pcm.size() > 4800, "%d bytes %s" % [pcm.size(), str(tts_err)])

	# 3) STT round-trip
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
		t0 = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 40000 and heard.is_empty():
			await process_frame
		var txt: String = heard[0] if not heard.is_empty() else ""
		_check("stt_roundtrip", txt.to_lower().contains("cease"), txt)
	print("[live] SUMMARY %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
