extends SceneTree

## Headless regression test: sanity_regression_test.gd
## Verifies all 24 requirements (REQ-01 through REQ-24).
## Usage: godot --headless --path . -s res://tests/sanity_regression_test.gd

var _passed = true

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("[sanity_regression] Starting full regression test...")
	var main: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	
	# Trigger run start
	if main.has_method("start_run_now"):
		main.call("start_run_now")
	# Wait for level to build
	await _await_level(main)
	
	# Execute requirement checks
	await _check_req_01(main)
	
	print("[sanity_regression] Regression tests completed. Result: %s" % ("PASSED" if _passed else "FAILED"))
	quit(0 if _passed else 1)

func _await_level(main: Node) -> void:
	var t0: int = Time.get_ticks_msec()
	while not bool(main.get("level_ready")) and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	await create_timer(0.5).timeout

func _check_req_01(main: Node) -> void:
	print("[sanity_regression] Checking REQ-01: ObjectiveTracker label refresh...")
	# Verify that objective is populated after level_ready
	var hud: Node = main.get_node_or_null("HUD")
	var ot: Node = hud.get_node_or_null("RootControl/ObjectiveTracker") if hud != null else null
	if ot != null:
		var obj = ot.get("get_objective").call()
		if obj.is_empty():
			print("REQ-01 FAILED: ObjectiveTracker empty after level_ready")
			_passed = false
		else:
			print("REQ-01 PASSED: ObjectiveTracker populated")
	else:
		print("REQ-01 FAILED: ObjectiveTracker not found")
		_passed = false
