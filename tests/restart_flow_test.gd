extends SceneTree
## Restart-flow test. Checks the restart fix: start a run, kill an enemy, trigger Replay (the results screen path), and verify the
## reloaded world is complete again (enemy back, no leftover state). Headless.

var _stage: int = 0
var _t: int = 0
var _enemies_before: int = -1
var _killed: EnemyBase = null
var _start_ms: int = 0
var _old_id: int = 0


func _init() -> void:
	_start_ms = Time.get_ticks_msec()
	var main: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main   # as the project's main scene would be


func _process(_delta: float) -> bool:
	_t += 1
	if Time.get_ticks_msec() - _start_ms > 150000:
		print("[restart_test] WATCHDOG stage=%d" % _stage)
		quit(2)
		return false
	var mc: Node = get_first_node_in_group("main_controller")
	match _stage:
		0:
			if _t > 5:
				var title: Node = get_first_node_in_group("title_screen")
				if title != null:
					title.set("show_quote_on_start", false)
					title.call("press_start")
				_stage = 1
		1:
			if mc != null and bool(mc.get("level_ready")) and _t > 240:
				_enemies_before = get_nodes_in_group("enemy").size()
				_killed = null
				for e in get_nodes_in_group("enemy"):
					if e is EnemyBase and not (e as EnemyBase).is_dead:
						_killed = e as EnemyBase
						break
				if _killed != null:
					_killed.apply_damage(99999, true, "environmental", null)
				print("[restart_test] run 1 ready: enemies=%d killed=%s" % [_enemies_before, str(_killed != null)])
				# Results-screen Replay path.
				mc.call("_on_start_run_requested")
				_old_id = mc.get_instance_id()
				_stage = 2
				_t = 0
		2:
			# Waiting for the reload to replace the scene (MainController keeps its group name on the new node).
			if _t % 120 == 0:
				print("[restart_test] waiting t=%d new_ready=%s" % [_t, str(mc != null and mc.get_instance_id() != _old_id)])
			if _t > 3 and mc != null and mc.get_instance_id() != _old_id:
				_stage = 3
				_t = 0
		3:
			var mc2: Node = get_first_node_in_group("main_controller")
			if mc2 != null and bool(mc2.get("level_ready")) and _t > 10:
				var n: int = get_nodes_in_group("enemy").size()
				var dead_back: bool = _killed == null or (is_instance_valid(_killed) and not _killed.is_dead) or not is_instance_valid(_killed)
				var ok: bool = n == _enemies_before and dead_back
				print("[restart_test] run 2 ready: enemies=%d (expected %d) killed-enemy-restored=%s => %s" % [n, _enemies_before, str(dead_back), "PASS" if ok else "FAIL"])
				quit(0 if ok else 1)
				return false
			if _t > 3000:
				print("[restart_test] FAIL: reload never became ready")
				quit(1)
				return false
	return false
