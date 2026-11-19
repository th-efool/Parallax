extends SceneTree
## Headless checks: RMB hold-to-charge heavy + live-stick aiming between chain swings.
## Run: godot --headless --path . -s res://tests/charged_heavy_test.gd   (exit code 1 on any FAIL)
var _results: Array[String] = []
var _main: Node = null
var _pc: PlayerController = null
var _executed: Array = []  # [attack_name, damage, heavy]
var _starts: Array = []  # [attack_name, facing_at_start, had_target]


func _initialize() -> void:
	SquadAIConfig.force_offline()
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	_run()


func _check(n: String, ok: bool, d: String = "") -> void:
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", n, d]
	_results.append(line)
	print("[charged] ", line)


func _wait(sec: float) -> void:
	var end_ms: int = Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end_ms:
		await physics_frame


func _tap(action: String, frames: int = 2) -> void:
	Input.action_press(action)
	for _i in range(frames):
		await physics_frame
	Input.action_release(action)


## Back to neutral LOCOMOTION with the chain window closed, event logs cleared.
func _settle() -> void:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000 and _pc.current_state != PlayerController.State.LOCOMOTION:
		await physics_frame
	await _wait(1.3)
	_executed.clear()
	_starts.clear()


func _run() -> void:
	for _i in range(5):
		await process_frame
	_main.call("start_run_now")
	var t0: int = Time.get_ticks_msec()
	while not bool(_main.get("level_ready")) and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	_pc = get_first_node_in_group("player") as PlayerController
	_check("player_found", _pc != null)
	if _pc == null:
		quit(1)
		return
	await _wait(1.0)
	_pc.attack_executed.connect(func(n: String, _s: int, dmg: int, heavy: bool) -> void: _executed.append([n, dmg, heavy]))
	_pc.attack_started.connect(func(n: String, _t: Dictionary) -> void: _starts.append([n, _pc.get_facing_direction(), _pc.current_target != null]))
	await _settle()

	# 1. Tap: the heavy still fires promptly at base damage.
	await _tap("heavy_attack", 2)
	await _wait(1.6)
	_check("tap_heavy_executes_once", _executed.size() == 1 and String(_executed[0][0]) == "heavy", str(_executed))
	_check("tap_heavy_base_damage", _executed.size() == 1 and int(_executed[0][1]) == _pc.heavy_attack_damage, str(_executed))
	await _settle()

	# 2. Hold: frozen at the raised pose, nothing executes until release, ratio builds, 3 s = guaranteed crit.
	Input.action_press("heavy_attack")
	await _wait(0.6)
	_check("hold_pose_frozen_windup", _pc.current_state == PlayerController.State.HEAVY_ATTACK and _pc.attack_phase == PlayerController.AttackPhase.WINDUP, "state=%d phase=%d" % [_pc.current_state, _pc.attack_phase])
	var w: float = float(_pc.current_attack.get("windup", 0.3))
	_check("hold_elapsed_pinned", _pc.get_attack_elapsed() <= w * 0.96, "elapsed=%.3f windup=%.3f" % [_pc.get_attack_elapsed(), w])
	_check("hold_not_executed_early", _executed.is_empty(), str(_executed))
	_check("hold_charging_flag", _pc.is_heavy_charging())
	await _wait(1.5)
	var mid: float = _pc.get_heavy_charge_ratio()
	_check("hold_ratio_builds_mid", mid > 0.3 and mid < 0.85, "ratio=%.3f" % mid)
	_check("hold_still_not_executed", _executed.is_empty() and _pc.attack_phase == PlayerController.AttackPhase.WINDUP)
	await _wait(1.8)
	_check("hold_ratio_full_after_3s", _pc.get_heavy_charge_ratio() >= 0.999, "ratio=%.3f" % _pc.get_heavy_charge_ratio())
	_check("hold_full_still_not_executed", _executed.is_empty())
	Input.action_release("heavy_attack")
	await _wait(0.15)
	var full_dmg: int = int(round(float(_pc.heavy_attack_damage) * _pc.heavy_charge_max_damage_mult))
	_check("release_executes_once", _executed.size() == 1 and String(_executed[0][0]) == "heavy", str(_executed))
	_check("release_full_damage", _executed.size() == 1 and int(_executed[0][1]) == full_dmg, "%s expect %d" % [str(_executed), full_dmg])
	_check("release_full_is_crit", bool(_pc.current_attack.get("finisher", false)))
	await _settle()

	# 3. Dodge cancels a held charge; nothing executes.
	Input.action_press("heavy_attack")
	await _wait(0.6)
	await _tap("dodge", 2)
	await _wait(0.3)
	Input.action_release("heavy_attack")
	await _wait(0.4)
	_check("dodge_cancels_hold", _executed.is_empty() and _pc.get_heavy_charge_ratio() == 0.0, str(_executed))
	await _settle()

	# 4. Live aim: swing 2 of a chain turns to the CURRENT stick / camera direction.
	_pc.camera_yaw = 0.0
	await _wait(0.2)
	await _tap("light_attack", 2)
	await _wait(0.05)
	_pc.camera_yaw = PI * 0.5
	Input.action_press("move_forward")
	var cw: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - cw < 1500 and not _pc._in_cancel_window():
		await physics_frame
	await _tap("light_attack", 2)
	var sw: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - sw < 1000 and _starts.size() < 2:
		await physics_frame
	var want: Vector3 = _pc._read_move_dir().normalized()
	Input.action_release("move_forward")
	_check("chain_second_swing_started", _starts.size() >= 2, str(_starts.size()))
	if _starts.size() >= 2:
		var f: Vector3 = _starts[1][1]
		if bool(_starts[1][2]):
			_check("live_aim_turns_to_stick_skipped_enemy_magnetised", true, "target magnetised; aim assertion skipped")
		else:
			_check("live_aim_turns_to_stick", f.dot(want) > 0.97, "facing=%s want=%s" % [str(f), str(want)])

	var fails: int = _results.filter(func(r: String) -> bool: return r.begins_with("FAIL")).size()
	print("[charged] SUMMARY %d checks, %d failed" % [_results.size(), fails])
	quit(1 if fails > 0 else 0)
