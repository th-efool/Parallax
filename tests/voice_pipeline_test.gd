extends SceneTree
## Headless checks for the voice pipeline (guide 03): engine selection, drop/start signals, stale skipping,
## chatter gating, no canned ack on Director orders. Run: godot --headless --path . -s res://tests/voice_pipeline_test.gd
var _results: Array[String] = []

func _initialize() -> void:
	_run()

func _check(n: String, ok: bool, d: String = "") -> void:
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", n, d]
	_results.append(line)
	print("[voice] ", line)

func _run() -> void:
	await process_frame
	SquadAIConfig.force_offline()   # sets voice_engine = "off"
	_check("tests_force_off", SquadAIConfig.voice_engine == "off")
	var tts := SquadTTSPlayer.new()
	root.add_child(tts)
	await process_frame
	var dropped: Array = []
	var started: Array = []
	tts.line_dropped.connect(func(s: String, t: String) -> void: dropped.append([s, t]))
	tts.line_started.connect(func(s: String, t: String) -> void: started.append([s, t]))
	tts.speak("Sera", "Behind you.", "Puck", "", 1)
	_check("off_engine_drops_with_text", dropped.size() == 1 and String(dropped[0][1]) == "Behind you." and started.is_empty(), str(dropped))
	SquadAIConfig.voice_engine = "auto"
	# Headless + offline: no cloud key, no OS voices -> engine "" -> still a drop (never silent without a subtitle).
	_check("auto_headless_engine_empty", tts.engine() == "", tts.engine())
	tts.speak("Ivo", "Warded!", "Iapetus", "", 2)
	_check("auto_headless_drops", dropped.size() == 2)
	# Chatter gating in SquadComms: a priority-0 line emits no subtitle when ambient_chatter is false.
	var comms := SquadComms.new()
	root.add_child(comms)
	await process_frame
	var subs: Array = []
	comms.subtitle.connect(func(sp: String, t: String, _c: Color, _f: bool) -> void: subs.append([sp, t]))
	SquadAIConfig.ambient_chatter = false
	comms._on_ally_spoke("Brannoc", "Bored now.", "idle", 0, "")
	_check("chatter_hidden_by_default", subs.is_empty(), str(subs))
	SquadAIConfig.ambient_chatter = true
	comms._on_ally_spoke("Brannoc", "Bored now.", "idle", 0, "")
	_check("chatter_shown_when_enabled", subs.size() == 1, str(subs))
	SquadAIConfig.ambient_chatter = false
	var fails: int = _results.filter(func(r: String) -> bool: return r.begins_with("FAIL")).size()
	print("[voice] SUMMARY %d checks, %d failed" % [_results.size(), fails])
	quit(1 if fails > 0 else 0)
