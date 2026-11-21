extends SceneTree
## Windowed: screenshots the title, the loading screen, the Warden victory outro and the results screen.
## Run: godot --path . -s res://tests/ui_menu_shots.gd -- --shots=<dir>
var _shots: String = ""
var _t: int = 0
var _stage: int = 0
var _summary: Dictionary = {"score": 5420, "time_sec": 612.0, "time_bonus": 388, "warden_bonus": 1000, "rank": "S"}


func _initialize() -> void:
	SquadAIConfig.force_offline()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.substr(8)
	var main: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main


func _snap(n: String) -> void:
	if _shots.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(_shots)
	root.get_viewport().get_texture().get_image().save_png(_shots.path_join(n + ".png"))
	print("[ui-shots] ", n)


func _process(_d: float) -> bool:
	_t += 1
	var mc: Node = get_first_node_in_group("main_controller")
	if _stage == 0 and _t == 90:
		_snap("01_title")
		var title: Node = get_first_node_in_group("title_screen")
		if title != null:
			title.set("show_quote_on_start", false)
			title.call("press_start")
		_stage = 1
		_t = 0
	elif _stage == 1 and _t == 4:
		_snap("02_loading")
		_stage = 2
	elif _stage == 2 and mc != null and bool(mc.get("level_ready")):
		_stage = 3
		_t = 0
	elif _stage == 3 and _t == 90:
		var results: Node = get_first_node_in_group("results_screen")
		if results != null:
			results.call("_on_run_finalized", _summary)
		_stage = 4
		_t = 0
	elif _stage == 4 and _t == 130:
		_snap("03_victory_outro")
		_stage = 5
		_t = 0
	elif _stage == 5 and _t == 360:
		_snap("04_results")
		var results: Node = get_first_node_in_group("results_screen")
		if results != null:
			for ch: String in ["K", "Z"]:
				var ev := InputEventKey.new()
				ev.pressed = true
				ev.keycode = OS.find_keycode_from_string(ch)
				ev.unicode = ch.unicode_at(0)
				results.call("_input", ev)
		_stage = 6
		_t = 0
	elif _stage == 6 and _t == 120:
		_snap("05_results_typed")
		quit(0)
	if _t > 8000:
		quit(1)
	return false
