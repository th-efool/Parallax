extends SceneTree
## Windowed: starts a run, waits for the level, saves HUD screenshots at the spawn and near the first prop hint.
## Run: godot --path . -s res://tests/visual_check_shots.gd -- --shots=<dir>
var _shots: String = ""
var _t: int = 0
var _stage: int = 0
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
	print("[visual] ", n)
func _process(_d: float) -> bool:
	_t += 1
	var mc: Node = get_first_node_in_group("main_controller")
	if _stage == 0 and _t > 30:
		var title: Node = get_first_node_in_group("title_screen")
		if title != null:
			title.set("show_quote_on_start", false)
			title.call("press_start")
		_stage = 1
	elif _stage == 1 and mc != null and bool(mc.get("level_ready")):
		_stage = 2
		_t = 0
	elif _stage == 2 and _t == 120:
		_snap("40_spawn_hud")
		var p: Node3D = get_first_node_in_group("player") as Node3D
		if p != null:
			p.global_position = Vector3(0, 0, -8)   # forecourt, facing the gate / Mirror Switch hint
		_stage = 3
		_t = 0
	elif _stage == 3 and _t == 90:
		var hud: Node = root.find_child("SquadCommsHUD", true, false)
		_snap("41_prop_hint")
		if hud != null:
			hud.call("_input", _make_l_press())
		_stage = 4
		_t = 0
	elif _stage == 4 and _t == 20:
		_snap("42_log_toggled_on")
		quit(0)
	if _t > 6000:
		quit(1)
	return false
func _make_l_press() -> InputEvent:
	var ev := InputEventAction.new()
	ev.action = "toggle_command_log"
	ev.pressed = true
	return ev
