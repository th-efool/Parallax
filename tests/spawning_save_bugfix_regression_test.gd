extends SceneTree
## Dedicated regression suite verifying Guide 04 fixes (SRS-01 .. SRS-15).
## Usage: godot --headless --path . -s res://tests/spawning_save_bugfix_regression_test.gd

const MainScene := preload("res://scenes/main/main.tscn")
const AudioManagerScript := preload("res://scripts/core/audio_manager.gd")
const EncounterDirectorScript := preload("res://scripts/core/encounter_director.gd")
const LeaderboardStoreScript := preload("res://scripts/core/leaderboard_store.gd")
const MainControllerScript := preload("res://scripts/core/main_controller.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const RealmManagerScript := preload("res://scripts/core/realm_manager.gd")
const ScoreManagerScript := preload("res://scripts/core/score_manager.gd")
const AllySquadManagerScript := preload("res://scripts/allies/ally_squad_manager.gd")
const EncounterGateScript := preload("res://scripts/environment/encounter_gate.gd")
const InteractSwitchScript := preload("res://scripts/environment/interact_switch.gd")
const MechanismPuzzleScript := preload("res://scripts/environment/mechanism_puzzle.gd")
const RealmPlatformScript := preload("res://scripts/environment/realm_platform.gd")
const SectionTriggerScript := preload("res://scripts/environment/section_trigger_volume.gd")
const WeatherDirectorScript := preload("res://scripts/environment/weather_director.gd")
const OptionsScreenScript := preload("res://scripts/ui/options_screen_controller.gd")
const PauseMenuScript := preload("res://scripts/ui/pause_menu_controller.gd")
const ResultsScreenScript := preload("res://scripts/ui/results_screen_controller.gd")
const TitleScreenScript := preload("res://scripts/ui/title_screen_controller.gd")

const TEST_LB_PATH: String = "user://_test_srs_lb.cfg"
const TEST_SETTINGS_PATH: String = "user://_test_srs_settings.cfg"
const TEST_SAVE_PATH: String = "user://_test_srs_save.cfg"

var _checks: int = 0
var _fails: int = 0
var _orig_lb_path: String = ""
var _orig_settings_path: String = ""
var _orig_save_path: String = ""


func _check(id: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[srs_test] %s %s %s" % ["PASS" if ok else "FAIL", id, detail])


func _initialize() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func() -> void:
		print("[srs_test] WATCHDOG TIMEOUT")
		_cleanup_temp_store()
		quit(2))
	_run.call_deferred()


func _cleanup_temp_store() -> void:
	var store: Node = root.get_node_or_null("LeaderboardStore")
	if store != null and not _orig_save_path.is_empty():
		store.set("leaderboard_path", _orig_lb_path)
		store.set("settings_path", _orig_settings_path)
		store.set("savegame_path", _orig_save_path)
		if store.has_method("_load_leaderboard_from_disk"):
			store.call("_load_leaderboard_from_disk")
		if store.has_method("_load_settings_from_disk"):
			store.call("_load_settings_from_disk")
		if store.has_method("_load_savegame_from_disk"):
			store.call("_load_savegame_from_disk")
	for p in [TEST_LB_PATH, TEST_SETTINGS_PATH, TEST_SAVE_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _await_level_ready(mc: Node, timeout_ms: int = 45000) -> bool:
	var t0: int = Time.get_ticks_msec()
	while is_instance_valid(mc) and not bool(mc.get("level_ready")) and Time.get_ticks_msec() - t0 < timeout_ms:
		await process_frame
	await process_frame
	return is_instance_valid(mc) and bool(mc.get("level_ready"))


func _run() -> void:
	var store: Node = root.get_node_or_null("LeaderboardStore")
	var run_state: Node = root.get_node_or_null("RunState")
	if store != null:
		_orig_lb_path = String(store.get("leaderboard_path"))
		_orig_settings_path = String(store.get("settings_path"))
		_orig_save_path = String(store.get("savegame_path"))
		store.set("leaderboard_path", TEST_LB_PATH)
		store.set("settings_path", TEST_SETTINGS_PATH)
		store.set("savegame_path", TEST_SAVE_PATH)
		store.set("_entries", ([] as Array[Dictionary]))
		if store.has_method("get_default_settings"):
			store.set("_settings", (store.call("get_default_settings") as Dictionary).duplicate(true))
		if store.has_method("get_default_save_data"):
			store.set("_save_data", (store.call("get_default_save_data") as Dictionary).duplicate(true))

	# ---- Unit check for SRS-14 (rebind/reset preserves non-keybind working_settings)
	var opts := OptionsScreenScript.new() as Control
	opts.build_default_ui_if_empty = false
	root.add_child(opts)
	await process_frame
	var ws: Dictionary = (opts.get("working_settings") as Dictionary).duplicate(true)
	ws["master_volume"] = 0.42
	ws["mouse_sensitivity"] = 0.0091
	opts.set("working_settings", ws)
	var rebind_res: Dictionary = opts.call("try_rebind_action", "interact", "KEY:%d" % KEY_T, false) as Dictionary
	var ws_after_rebind: Dictionary = opts.get("working_settings") as Dictionary
	var srs14_rebind: bool = bool(rebind_res.get("valid", false)) and absf(float(ws_after_rebind.get("master_volume", 0.0)) - 0.42) < 0.001 and absf(float(ws_after_rebind.get("mouse_sensitivity", 0.0)) - 0.0091) < 0.0001
	opts.call("press_reset_controls")
	var ws_after_reset: Dictionary = opts.get("working_settings") as Dictionary
	var srs14_reset: bool = absf(float(ws_after_reset.get("master_volume", 0.0)) - 0.42) < 0.001
	_check("srs14", srs14_rebind and srs14_reset, "master=%s" % str(ws_after_reset.get("master_volume")))
	opts.queue_free()

	# ---- Instantiate Main on Title Screen
	var main := MainScene.instantiate()
	root.add_child(main)
	current_scene = main
	for _i in range(6):
		await process_frame

	# SRS-09: Only GameAudio active; no Main/AudioManager node in scene
	var dup_audio: Node = main.get_node_or_null("AudioManager")
	var audio_mgr: AudioManager = AudioManagerScript.instance as AudioManager
	_check("srs09_no_duplicate", dup_audio == null and audio_mgr != null and audio_mgr == root.get_node_or_null("GameAudio"), "dup=%s" % str(dup_audio))

	# SRS-05 (pre-start): Allies did NOT spawn on Title Screen before floors exist
	var squad := main.get_node_or_null("AllySquad")
	var allies_on_title: Array = squad.get("allies") if squad != null else []
	_check("srs05_title_no_allies", allies_on_title.is_empty(), "allies_on_title=%d" % allies_on_title.size())

	# SRS-10: EncounterDirector checkpoint_transform initialized to Start Terrace (z = -136)
	var ed := EncounterDirectorScript.instance as EncounterDirector
	var init_pos_ok: bool = ed != null and ed.checkpoint_transform.origin.distance_to(Vector3(0.0, 0.0, -136.0)) < 0.1
	_check("srs10_default_spawn", init_pos_ok, "origin=%s" % str(ed.checkpoint_transform.origin if ed != null else Vector3.ZERO))

	# SRS-07: PauseMenu toggle rejected on Title Screen
	var pause_ui := main.get_node_or_null("MenusLayer/PauseMenu") as Control
	if pause_ui != null:
		pause_ui.call("toggle_pause")
	_check("srs07_pause_blocked_on_title", pause_ui != null and not bool(pause_ui.get("is_paused_state")) and not paused, "paused=%s" % str(paused))

	# SRS-06: Title Q does not shift RealmManager
	var rm := RealmManagerScript.instance as RealmManager
	var title_ui := main.get_node_or_null("MenusLayer/TitleScreen") as Control
	var realm_before_q: int = int(rm.current_realm) if rm != null else 0
	if title_ui != null:
		title_ui.set("quote_overlay_visible", false)
		var q_ev := InputEventKey.new()
		q_ev.keycode = KEY_Q
		q_ev.pressed = true
		if rm != null:
			rm._unhandled_input(q_ev)
	_check("srs06_realm_locked_on_title", rm != null and int(rm.current_realm) == realm_before_q, "realm=%d" % (int(rm.current_realm) if rm != null else -1))

	# ---- Start run
	if title_ui != null:
		title_ui.set("show_quote_on_start", false)
		title_ui.call("press_start")
	var ready_ok: bool = await _await_level_ready(main)
	_check("srs05_allies_spawned_after_load", ready_ok and squad != null and (squad.get("allies") as Array).size() >= 3, "allies=%d" % ((squad.get("allies") as Array).size() if squad != null else -1))

	# SRS-15: WeatherDirector bound to TheWarden
	var wd := main.get_node_or_null("WeatherDirector")
	var warden := main.get_node_or_null("LevelRoot/Stage05_ExecutionArena/Enemies/TheWarden")
	var bound_ok: bool = wd != null and warden != null and wd.get("_bound_warden") == warden
	if wd != null and warden != null:
		wd.call("_on_warden_phase_changed", 3)
		var p2_prof: String = String(wd.call("get_profile_for", 150.0))
		wd.call("_on_warden_defeated")
		var dead_prof: String = String(wd.call("get_profile_for", 150.0))
		wd.call("_on_warden_health_changed", int(warden.get("max_health")), int(warden.get("max_health")))
		var reset_prof: String = String(wd.call("get_profile_for", 150.0))
		bound_ok = bound_ok and p2_prof == "blood_frenzy" and dead_prof == "aftermath" and reset_prof == "blood"
	_check("srs15_weather_bound", bound_ok, "wd=%s" % str(wd))

	# SRS-13: Player respawn_at resets full combat/stamina/buffer state & _verify_spawn_safety guards null/self
	var player := main.get_node_or_null("Player") as CharacterBody3D
	if player != null:
		player.set("stamina", 12.0)
		player.set("_flow_streak", 4)
		player.set("_flow_tap", true)
		player.set("_ally_ward_hp", 25)
		player.set("_finisher_cooldown_end_ms", 99999999)
		player.set("_jump_buffer_timer", 0.3)
		player.call("respawn_at", Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 0.0, -136.0)))
		var safe_null := Vector3(1.0, 2.0, 3.0)
		var temp_player := PlayerControllerScript.new() as Node3D
		var out_of_tree_pos: Vector3 = temp_player.call("_verify_spawn_safety", safe_null) as Vector3
		temp_player.free()
		var srs13_ok: bool = absf(float(player.get("stamina")) - float(player.get("max_stamina"))) < 0.01 \
			and int(player.get("_flow_streak")) == 0 and not bool(player.get("_flow_tap")) \
			and int(player.get("_ally_ward_hp")) == 0 and int(player.get("_finisher_cooldown_end_ms")) == 0 \
			and absf(float(player.get("_jump_buffer_timer"))) < 0.001 and out_of_tree_pos.is_equal_approx(safe_null)
		_check("srs13_player_respawn_reset", srs13_ok)

	# SRS-02 + SRS-04: Death rewind across 3 checkpoints resets failed_section, gates, switches, puzzle, bridge & does NOT auto-begin combat inside _on_section_reset_requested
	var reset_counts: Dictionary = {}
	if ed != null:
		ed.section_reset_requested.connect(func(sec_i: int) -> void:
			reset_counts[sec_i] = int(reset_counts.get(sec_i, 0)) + 1)
		var hall_xform := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 4.0, 58.0))
		var gal_xform := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 6.0, 165.5))
		var arena_xform := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 10.0, 300.0))
		ed.advance_to_section(EncounterDirectorScript.Section.HALL_COMBAT, hall_xform, true)
		ed.advance_to_section(EncounterDirectorScript.Section.COLLAPSED_GALLERY, gal_xform, true)
		ed.advance_to_section(EncounterDirectorScript.Section.EXECUTION_ARENA, arena_xform, true)

		var sw3 := main.get_node_or_null("LevelRoot/Stage03_CollapsedGallery/BridgeAnchorSwitch")
		var brg := main.get_node_or_null("LevelRoot/Stage03_CollapsedGallery/GallerySpectralBridge")
		var gate2a := main.get_node_or_null("LevelRoot/Stage02_HallOfEchoes/Gate02a_HallSouthSeal")
		var gate2 := main.get_node_or_null("LevelRoot/Stage02_HallOfEchoes/Gate02_HallToGallery")
		var gate4b := main.get_node_or_null("LevelRoot/Stage05_ExecutionArena/Gate04b_ArenaSouthSeal")
		var puz := main.get_node_or_null("LevelRoot/Stage04_MechanismChamber/ChamberMechanismPuzzle")
		if sw3 != null:
			sw3.set("is_activated", true)
		if brg != null:
			brg.call("repair_for_reality")
		if gate2a != null:
			gate2a.call("seal_gate_for_encounter")
		if gate2 != null:
			gate2.call("unlock_and_open")
		if gate4b != null:
			gate4b.call("seal_gate_for_encounter")
		if puz != null:
			puz.call("force_solve_bypass")
		ed.completed_encounters["hall_of_echoes"] = true
		ed.completed_encounters["the_warden"] = true

		# Trigger reset test for SRS-04: Hall trigger reset must NOT start encounter immediately
		var trig2 := main.get_node_or_null("LevelRoot/Stage02_HallOfEchoes/Trigger_Stage02_Hall")
		if trig2 != null:
			ed.completed_encounters.erase("hall_of_echoes")
			trig2.set("has_triggered", true)
			ed.current_encounter_id = ""
			trig2.call("_on_section_reset_requested", EncounterDirectorScript.Section.HALL_COMBAT)
			var srs04_ok: bool = not bool(trig2.get("has_triggered")) and String(ed.current_encounter_id).is_empty()
			_check("srs04_no_immediate_encounter_on_reset", srs04_ok, "enc=%s" % String(ed.current_encounter_id))

		ed.completed_encounters["hall_of_echoes"] = true
		reset_counts.clear()
		ed.handle_player_death(player)
		var dedup_ok: bool = int(reset_counts.get(1, 0)) == 1 and int(reset_counts.get(2, 0)) == 1 and int(reset_counts.get(3, 0)) == 1 and int(reset_counts.get(4, 0)) == 1
		var world_reset_ok: bool = int(ed.current_section) == EncounterDirectorScript.Section.HALL_COMBAT \
			and (gate2a == null or bool(gate2a.get("is_open"))) \
			and (gate2 == null or not bool(gate2.get("is_open"))) \
			and (gate4b == null or bool(gate4b.get("is_open"))) \
			and (sw3 == null or not bool(sw3.get("is_activated"))) \
			and (brg == null or not bool(brg.get("is_permanently_repaired"))) \
			and (puz == null or not bool(puz.get("is_solved"))) \
			and not ed.completed_encounters.has("hall_of_echoes") \
			and not ed.completed_encounters.has("the_warden")
		_check("srs02_dedup_and_full_section_reset", dedup_ok and world_reset_ok, "counts=%s sec=%d" % [str(reset_counts), int(ed.current_section)])

	# SRS-11: Live unbanked score saved + Save error status shown
	if run_state != null and store != null:
		run_state.call("start_new_run")
		run_state.set("banked_score", 300)
		run_state.set("score", 650)
		var bad_path: String = "user://__missing_dir__/fail.cfg"
		store.set("savegame_path", bad_path)
		if pause_ui != null:
			var fail_res: Dictionary = pause_ui.call("press_save_checkpoint") as Dictionary
			_check("srs11_save_error_reported", String(pause_ui.get("last_save_status_text")) == "SAVE FAILED" and not bool(fail_res.get("_save_ok", true)))
		store.set("savegame_path", TEST_SAVE_PATH)

	# SRS-01 + SRS-03 + SRS-12: Save multi-checkpoint Stage 04 run, test Continue reload without overwrite
	if ed != null and store != null and run_state != null:
		ed.restart_full_run()
		var cp1 := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 4.0, 58.0))
		var cp2 := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 6.0, 165.5))
		var cp3 := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 6.0, 194.0))
		ed.advance_to_section(EncounterDirectorScript.Section.HALL_COMBAT, cp1, true)
		ed.advance_to_section(EncounterDirectorScript.Section.COLLAPSED_GALLERY, cp2, true)
		ed.advance_to_section(EncounterDirectorScript.Section.MECHANISM_CHAMBER, cp3, true)
		# Set unbanked score AFTER advance_to_section() because set_checkpoint() banks score.
		run_state.set("banked_score", 400)
		run_state.set("score", 775)
		ed.completed_encounters["hall_of_echoes"] = true
		ed.completed_encounters["shielded_guard"] = true
		ed.completed_encounters["the_warden"] = true
		var puz_s := main.get_node_or_null("LevelRoot/Stage04_MechanismChamber/ChamberMechanismPuzzle")
		if puz_s != null:
			puz_s.call("force_solve_bypass")
		store.call("capture_and_save_world_state", main)

		# Simulate Continue reload sequence
		main.call("_on_continue_requested")
		var old_id: int = main.get_instance_id()
		var t_wait: int = 0
		while t_wait < 600:
			await process_frame
			t_wait += 1
			var cur_mc: Node = get_first_node_in_group("main_controller")
			if cur_mc != null and cur_mc.get_instance_id() != old_id:
				main = cur_mc
				break
		var cont_ready: bool = await _await_level_ready(main)
		var ed2 := EncounterDirectorScript.instance as EncounterDirector
		var puz2 := main.get_node_or_null("LevelRoot/Stage04_MechanismChamber/ChamberMechanismPuzzle")
		var gate5_2 := main.get_node_or_null("LevelRoot/Stage05_ExecutionArena/Gate05_ArenaExit")
		var warden2 := main.get_node_or_null("LevelRoot/Stage05_ExecutionArena/Enemies/TheWarden")
		var trig1_2 := main.get_node_or_null("LevelRoot/Stage01_EntryVestibule/Trigger_Stage01_Entry")
		var hist2: Array = ed2.get("_checkpoint_history") if ed2 != null else []
		_check("srs01_continue_not_overwritten", cont_ready and ed2 != null and int(ed2.current_section) == EncounterDirectorScript.Section.MECHANISM_CHAMBER, "sec=%d" % (int(ed2.current_section) if ed2 != null else -1))
		_check("srs03_checkpoint_history_restored", hist2.size() >= 3, "hist_size=%d" % hist2.size())
		_check("srs11_live_score_restored", run_state != null and int(run_state.get("score")) == 775 and int(run_state.get("banked_score")) == 400, "score=%d banked=%d" % [int(run_state.get("score")), int(run_state.get("banked_score"))])
		_check("srs12_world_and_triggers_restored", puz2 != null and bool(puz2.get("is_solved")) and bool(puz2.get("is_plate_pressed")) and warden2 != null and bool(warden2.get("is_dead")) and gate5_2 != null and bool(gate5_2.get("is_open")) and trig1_2 != null and bool(trig1_2.get("has_triggered")),
			"puz=%s plate=%s w_dead=%s g5=%s t1=%s" % [str(puz2.get("is_solved") if puz2 else null), str(puz2.get("is_plate_pressed") if puz2 else null), str(warden2.get("is_dead") if warden2 else null), str(gate5_2.get("is_open") if gate5_2 else null), str(trig1_2.get("has_triggered") if trig1_2 else null)])

	# SRS-08: ScoreManager.finalize_run() idempotency
	if run_state != null and store != null:
		run_state.call("start_new_run")
		var emit_box: Dictionary = {"count": 0}
		var cb := func(_s: Dictionary) -> void: emit_box["count"] = int(emit_box["count"]) + 1
		run_state.connect("run_finalized", cb)
		var before_runs: int = int(((store.call("get_saved_run_data") as Dictionary).get("profile_stats", {}) as Dictionary).get("total_runs_completed", 0))
		run_state.call("finalize_run", true)
		run_state.call("finalize_run", true)
		var after_runs: int = int(((store.call("get_saved_run_data") as Dictionary).get("profile_stats", {}) as Dictionary).get("total_runs_completed", 0))
		if run_state.is_connected("run_finalized", cb):
			run_state.disconnect("run_finalized", cb)
		var finalized_emits: int = int(emit_box["count"])
		_check("srs08_finalize_idempotent", finalized_emits == 1 and (after_runs - before_runs) == 1, "emits=%d delta=%d" % [finalized_emits, after_runs - before_runs])

	# SRS-06: Results screen + Return to Title freeze SceneTree & lock player/HUD/input
	var results_ui := main.get_node_or_null("MenusLayer/ResultsScreen") as Control
	var hud_node := main.get_node_or_null("HUD") as CanvasLayer
	var player2 := main.get_node_or_null("Player")
	if results_ui != null:
		results_ui.call("populate_from_summary", {"score": 1200, "time_sec": 45.0, "time_bonus": 300, "warden_bonus": 1000, "rank": "B"})
		var res_frozen: bool = paused and PlayerControllerScript.ui_input_locked and player2 != null and player2.process_mode == Node.PROCESS_MODE_DISABLED and hud_node != null and not hud_node.visible
		_check("srs06_results_freezes_world", res_frozen, "paused=%s lock=%s pmode=%s hud=%s" % [str(paused), str(PlayerControllerScript.ui_input_locked), str(player2.process_mode if player2 else -1), str(hud_node.visible if hud_node else null)])
		results_ui.call("press_main_menu")
		var title_frozen: bool = paused and not PlayerControllerScript.ui_input_locked and player2 != null and player2.process_mode == Node.PROCESS_MODE_DISABLED and hud_node != null and not hud_node.visible
		_check("srs06_return_to_title_freezes_world", title_frozen, "paused=%s lock=%s pmode=%s hud=%s" % [str(paused), str(PlayerControllerScript.ui_input_locked), str(player2.process_mode if player2 else -1), str(hud_node.visible if hud_node else null)])

	paused = false
	PlayerControllerScript.ui_input_locked = false
	_cleanup_temp_store()
	print("[srs_test] SUMMARY %d checks, %d failed" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)
