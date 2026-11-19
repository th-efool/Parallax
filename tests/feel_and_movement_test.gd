extends SceneTree
## Windowed test for (1) the "character spins in place" bug under frame hitches + attack spam,
## (2) the LMB chain (rhythm FLOW, 5 steps, mash chaining, pause branch, reset), (3) ally spatial awareness
## (spacing from each other / the player, wall grinding) while following and fighting.
## Run: godot --path . -s res://tests/feel_and_movement_test.gd -- --shots=<dir>

var _shots: String = ""
var _results: Array[String] = []
var _main: Node = null
var _player: PlayerController = null
var _mgr: AllySquadManager = null
var _attacks: Array = []


func _initialize() -> void:
	SquadAIConfig.force_offline()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.substr(8)
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	create_timer(220.0).timeout.connect(func() -> void:
		print("[feel] WATCHDOG")
		_finish())
	_run()


func _check(n: String, ok: bool, d: String = "") -> void:
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", n, d]
	_results.append(line)
	print("[feel] ", line)


func _shot(n: String) -> void:
	await process_frame
	await process_frame
	if not _shots.is_empty():
		root.get_viewport().get_texture().get_image().save_png(_shots.path_join(n + ".png"))


## A tap held for one physics tick (scripted presses made between physics ticks are otherwise invisible
## to is_action_just_pressed in _physics_process; real device input arrives before physics).
func _tap() -> void:
	await physics_frame
	Input.action_press("light_attack")
	await physics_frame
	await physics_frame
	Input.action_release("light_attack")


func _model_yaw_error() -> float:
	var model: Node3D = _player.get_node_or_null("VisualRoot/ModelRoot") as Node3D
	if model == null:
		return 0.0
	# ModelRoot rests at yaw PI (+twist flourish); anything far beyond the twist clamp is a spin.
	return absf(wrapf(model.rotation.y - PI, -PI, PI))


func _run() -> void:
	await create_timer(1.0).timeout
	var title: Node = get_first_node_in_group("title_screen")
	if title != null:
		if "show_quote_on_start" in title:
			title.set("show_quote_on_start", false)
		title.call("press_start")
	await _await_level()
	_player = get_first_node_in_group("player") as PlayerController
	_mgr = AllySquadManager.instance
	_player.max_health = 100000
	_player.health = 100000
	# Deterministic chain: random light crits would open the finisher window and turn the next LMB into REND.
	_player.crit_chance_light = 0.0
	_player.crit_chance_flow = 0.0
	_player.attack_started.connect(func(n: String, t: Dictionary) -> void: _attacks.append([n, int(t.get("chain_step", 0)), bool(t.get("flow", false)), String(t.get("branch", ""))]))
	_player.global_position = Vector3(0, 0, -136)
	_player.set_facing_direction(Vector3(0, 0, 1))
	_player.camera_yaw = PI
	_mgr.regroup(false)
	await create_timer(0.6).timeout

	# ---- 1) Spin regression: attack spam with real frame hitches.
	var max_err: float = 0.0
	for i in range(40):
		await _tap()
		if i % 6 == 0:
			OS.delay_msec(260)   # a 0.26 s hitch (worse than the load hitch)
		await process_frame
		max_err = maxf(max_err, _model_yaw_error())
	await create_timer(1.0).timeout
	for _k in range(30):
		await process_frame
		max_err = maxf(max_err, _model_yaw_error())
	_check("no_spin_under_hitches", max_err < 1.05, "max model yaw deviation %.2f rad (twist clamp 1.0)" % max_err)

	# ---- 2) LMB chain.
	await create_timer(1.2).timeout
	# Section 1's chain enders always crit; a leftover slow-mo finisher window would skew the rhythm timing.
	_player._finisher_cooldown_end_ms = Time.get_ticks_msec() + 60000
	if _player.is_finisher_window_open():
		_player._close_finisher_window("")
	_attacks.clear()
	# Rhythm taps: wait until the swing's flow window opens, then tap.
	await _tap()
	for _s in range(4):
		var t0: int = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 1500 and not _player._is_flow_timing():
			await process_frame
		var before: String = _player.current_attack_name
		await _tap()
		# Wait for the swing this tap queued to actually start before reading the next rhythm window.
		var t3: int = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t3 < 700 and _player.current_attack_name == before:
			await process_frame
	await create_timer(0.8).timeout
	var steps: Array = _attacks.map(func(a: Array) -> int: return a[1])
	var flows: int = _attacks.filter(func(a: Array) -> bool: return a[2]).size()
	_check("chain_reaches_5_distinct_moves", steps == [1, 2, 3, 4, 5], str(_attacks.map(func(a: Array) -> String: return a[0])))
	_check("rhythm_taps_flow", flows >= 3, "%d of 4 follow-ups in FLOW" % flows)
	await _shot("20_chain_counter")
	# Mash: hammer taps early -> still chains (buffered), but not FLOW.
	await create_timer(1.3).timeout
	_attacks.clear()
	for _m in range(10):
		await _tap()
		await create_timer(0.04).timeout
	await create_timer(1.0).timeout
	var mash_steps: int = _attacks.size()
	var mash_flow: int = _attacks.filter(func(a: Array) -> bool: return a[2]).size()
	_check("mash_still_chains", mash_steps >= 3, "%d swings from 10 rapid taps, %d flow" % [mash_steps, mash_flow])
	_check("mash_earns_no_flow", mash_flow <= 1, "%d flow swings while mashing (rhythm should be rewarded, not spam)" % mash_flow)
	# Reset after idling.
	await create_timer(1.4).timeout
	_attacks.clear()
	await _tap()
	await create_timer(0.6).timeout
	_check("chain_resets_after_idle", not _attacks.is_empty() and int(_attacks[0][1]) == 1, str(_attacks))
	# Pause branch: swing, let it finish, wait a beat, tap.
	await create_timer(0.45 - 0.0).timeout
	_attacks.clear()
	await _tap()
	await create_timer(0.6).timeout
	_check("pause_branch_rising_arc", not _attacks.is_empty() and String(_attacks[0][0]) == "light_rise", str(_attacks))
	await create_timer(1.5).timeout

	# ---- 3) Ally spatial awareness while following (walk a loop) and fighting.
	var samples: int = 0
	var crowd: int = 0
	var wall: int = 0
	var min_pair: float = 99.0
	var cam_block: int = 0
	_player.global_position = Vector3(0, 0, -138)   # start terrace (moved 80 m south, JourneyLayout)
	_mgr.regroup(false)
	await create_timer(0.5).timeout
	# Measure following, not the 40 m run-in from the previous section: wait until the squad has arrived.
	var t_arrive: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_arrive < 6000:
		var far: bool = false
		for a0 in _mgr.get_living():
			if a0.global_position.distance_to(_player.global_position) > 4.5:
				far = true
		if not far:
			break
		await process_frame
	await create_timer(0.4).timeout
	var path: Array[Vector2] = [Vector2(0, -1), Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]
	for leg in path:
		Input.action_release("move_forward")
		Input.action_release("move_back")
		Input.action_release("move_left")
		Input.action_release("move_right")
		if leg.y < 0:
			Input.action_press("move_forward")
		elif leg.y > 0:
			Input.action_press("move_back")
		if leg.x > 0:
			Input.action_press("move_right")
		elif leg.x < 0:
			Input.action_press("move_left")
		var t1: int = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < 1100:
			await process_frame
			samples += 1
			var al: Array[SquadAlly] = _mgr.get_living()
			for i in range(al.size()):
				if al[i].is_on_wall() and Vector2(al[i].velocity.x, al[i].velocity.z).length() > 0.5:
					wall += 1
				if al[i].global_position.distance_to(_player.global_position) < 0.9:
					crowd += 1
				if al[i]._camera_blocking_at(al[i].global_position, _player):
					cam_block += 1
				for j in range(i + 1, al.size()):
					var dd: float = al[i].global_position.distance_to(al[j].global_position)
					min_pair = minf(min_pair, dd)
					if dd < 0.85:
						crowd += 1
	for act in ["move_forward", "move_back", "move_left", "move_right"]:
		Input.action_release(act)
	var total: float = float(samples * maxi(1, _mgr.get_living().size()))
	_check("follow_no_crowding", float(crowd) / total < 0.05, "crowded %.1f%% of ally-frames, min pair %.2f m" % [100.0 * float(crowd) / total, min_pair])
	_check("follow_no_wall_grinding", float(wall) / total < 0.12, "wall-pushing %.1f%% of ally-frames" % [100.0 * float(wall) / total])
	_check("follow_not_blocking_camera", float(cam_block) / total < 0.10, "in the camera's sight line %.1f%% of ally-frames" % [100.0 * float(cam_block) / total])
	await _shot("21_follow_spacing")
	# Fight: enemies + massacre on the forecourt.
	_player.global_position = Vector3(0, 0, -14)
	_mgr.regroup(false)
	var level: Node = _main.get_node("LevelRoot")
	for k in range(3):
		var e: EnemyBase = level.call("_add_roamer", level, "skeleton", "Test_mv_%d" % k, Vector3(-3.0 + 3.0 * float(k), 0, -6.5), EncounterDirector.Section.ENTRY, Vector3(0, 0, -14)) as EnemyBase
		e.max_health = 3000
		e.health = 3000
	await create_timer(0.5).timeout
	(root.find_child("SquadCommsHUD", true, false) as SquadCommsHUD).submit_chat_text("everyone massacre")
	samples = 0
	crowd = 0
	min_pair = 99.0
	var t2: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t2 < 6000:
		await process_frame
		samples += 1
		var al2: Array[SquadAlly] = _mgr.get_living()
		for i in range(al2.size()):
			for j in range(i + 1, al2.size()):
				var dd2: float = al2[i].global_position.distance_to(al2[j].global_position)
				min_pair = minf(min_pair, dd2)
				if dd2 < 0.85:
					crowd += 1
	_check("fight_no_ally_stacking", float(crowd) / float(maxi(1, samples * 3)) < 0.06, "ally pairs <0.85 m in %.1f%% of frames, min %.2f m" % [100.0 * float(crowd) / float(maxi(1, samples * 3)), min_pair])
	await _shot("22_fight_spacing")

	# ---- 4) New finishers: Q (Mirror Break) and F (Execution) inside the crit window; Q must not shift realms.
	var victims: Array = level.get_tree().get_nodes_in_group("enemy").filter(func(n: Node) -> bool: return n is EnemyBase and not (n as EnemyBase).is_dead and (n as EnemyBase).is_hittable_now() and (n as Node3D).global_position.distance_to(_player.global_position) < 12.0)
	var victim: EnemyBase = victims[0] as EnemyBase if not victims.is_empty() else null
	if victim != null:
		_player.global_position = victim.global_position - Vector3(0, 0, 1.8)
		_player.set_facing_direction(Vector3(0, 0, 1))
		_player._finisher_cooldown_end_ms = 0
		var rm: Node = root.find_child("RealmManager", true, false)
		var realm_before: int = int(rm.get("current_realm")) if rm != null else -1
		_player.open_finisher_window(victim)
		await create_timer(0.1).timeout
		await _shot("23_finisher_prompt")
		_attacks.clear()
		await _tap_action("dimension_shift")
		await create_timer(0.3).timeout
		var realm_after: int = int(rm.get("current_realm")) if rm != null else -1
		_check("q_in_window_is_mirror_break", not _attacks.is_empty() and String(_attacks[0][0]) == "fin_mirror_break" and realm_before == realm_after, "%s realm %d->%d" % [str(_attacks), realm_before, realm_after])
		await create_timer(1.6).timeout
		victim.health = int(victim.max_health * 0.3)
		_player.global_position = victim.global_position - Vector3(0, 0, 1.8)
		_player.set_facing_direction(Vector3(0, 0, 1))
		_player._finisher_cooldown_end_ms = 0
		_player.open_finisher_window(victim)
		await process_frame
		_attacks.clear()
		await _tap_action("landing_attack")
		await create_timer(1.6).timeout
		_check("f_in_window_executes", not _attacks.is_empty() and String(_attacks[0][0]) == "fin_execution" and victim.is_dead, "%s dead=%s hp=%d" % [str(_attacks), str(victim.is_dead), victim.health])
		await _shot("24_execution")
	else:
		_check("finisher_victim_found", false, "no enemy near the player")
	_finish()


## Real input events (so RealmManager._unhandled_input sees Q too), held across physics frames.
func _tap_action(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await physics_frame
	await physics_frame
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await physics_frame


func _finish() -> void:
	var fails: int = _results.filter(func(r: String) -> bool: return r.begins_with("FAIL")).size()
	print("[feel] SUMMARY %d checks, %d failed" % [_results.size(), fails])
	quit(1 if fails > 0 else 0)

## Waits until MainController has built the level behind the loading screen (Start shows it now).
func _await_level() -> void:
	var mc: Node = get_first_node_in_group("main_controller")
	var t0: int = Time.get_ticks_msec()
	while mc != null and not bool(mc.get("level_ready")) and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	await create_timer(0.5).timeout