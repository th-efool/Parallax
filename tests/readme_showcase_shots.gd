extends SceneTree
## Windowed: captures the README showcase screenshots from a real run (1920x1080, JPEG).
## Run: godot --path . -s res://tests/readme_showcase_shots.gd -- --shots=<dir>   (default: res://docs/media)
## Starting a run clears user://savegame.cfg: back it up first.

var _shots: String = ""
var _main: Node = null
var _cam: Camera3D = null
var _player: Node3D = null
var _hud: SquadCommsHUD = null
var _game_cam: Camera3D = null


func _initialize() -> void:
	SquadAIConfig.force_offline()
	_shots = ProjectSettings.globalize_path("res://docs/media")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.substr(8)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	_run()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _snap(n: String) -> void:
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute(_shots)
	var img: Image = root.get_viewport().get_texture().get_image()
	if img.get_width() != 1920:
		img.resize(1920, int(1920.0 * float(img.get_height()) / float(img.get_width())), Image.INTERPOLATE_LANCZOS)
	img.save_jpg(_shots.path_join(n + ".jpg"), 0.86)
	print("[showcase] ", n)


func _keep_alive() -> void:
	if _player != null and _player.get("max_health") != null:
		_player.set("health", _player.get("max_health"))


func _hud_on(on: bool) -> void:
	for h in get_nodes_in_group("hud"):
		if h is CanvasItem or h is CanvasLayer:
			h.set("visible", on)
	if _hud != null:
		_hud.visible = on


func _free_cam(from: Vector3, look: Vector3, fov: float = 62.0) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.far = 4000.0
		root.add_child(_cam)
	_cam.fov = fov
	_cam.global_position = from
	_cam.look_at(look, Vector3.UP)
	_cam.make_current()


func _player_cam(pos: Vector3, look_dir: Vector3, pitch_deg: float = -14.0) -> void:
	_player.global_position = pos
	_player.set("velocity", Vector3.ZERO)
	var d := Vector3(look_dir.x, 0, look_dir.z).normalized()
	if _player.has_method("set_facing_direction"):
		_player.call("set_facing_direction", d)
	_player.set("camera_yaw", atan2(-d.x, -d.z))
	_player.set("camera_pitch", deg_to_rad(pitch_deg))
	if _game_cam != null:
		_game_cam.make_current()


func _realm(mirror: bool) -> void:
	if RealmManager.instance != null:
		RealmManager.instance.force_realm(RealmManager.Realm.MIRROR if mirror else RealmManager.Realm.REALITY)


func _enter(trigger_name: String) -> void:
	var trig: Node3D = root.find_child(trigger_name, true, false) as Node3D
	if trig != null:
		_player.global_position = trig.global_position + Vector3(0, -1.0, 0)


func _n(path: String) -> Node3D:
	return _main.get_node_or_null("LevelRoot/" + path) as Node3D


func _run() -> void:
	await _wait(1.2)
	await _snap("01_title")
	var title: Node = get_first_node_in_group("title_screen")
	if title != null:
		title.set("show_quote_on_start", false)
		title.call("press_start")
	await _wait(0.9)
	await _snap("02_loading")
	var t0: int = Time.get_ticks_msec()
	while not bool(_main.get("level_ready")) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	await _wait(2.0)
	_player = get_first_node_in_group("player") as Node3D
	_hud = root.find_child("SquadCommsHUD", true, false) as SquadCommsHUD
	_game_cam = root.get_viewport().get_camera_3d()
	var routes: Array = JourneyLayout.ROUTES
	var weather: Node = get_first_node_in_group("weather_director")

	# --- Start terrace and the winding causeway ---
	_keep_alive()
	_hud_on(false)
	_free_cam(Vector3(10, 26, -158), Vector3(-4, 0, -60), 60.0)
	await _wait(1.5)
	await _snap("03_causeway_vista")
	var b1: Vector3 = ((routes[0] as Array)[1] as Array)[1][0]
	_free_cam(b1 + Vector3(-15, 7, -13), b1 + Vector3(0, 1, 0), 58.0)
	await _wait(1.0)
	await _snap("04_bastion")

	# --- Gate of Reflections: Reality vs Mirror ---
	_hud_on(true)
	_player_cam(Vector3(0, 0, -9), Vector3(0, 0, 1), -10.0)
	_keep_alive()
	await _wait(1.2)
	await _snap("05_gate_reality")
	_realm(true)
	await _wait(1.0)
	await _snap("06_gate_mirror")
	_realm(false)

	# --- Squad command on the terrace (HUD + subtitles) ---
	_player_cam(Vector3(0, 0, -137), Vector3(0, 0, 1), -14.0)
	_keep_alive()
	await _wait(1.5)
	if _hud != null and _hud.has_method("submit_chat_text"):
		_hud.submit_chat_text("Brannoc take point, Sera and Ivo cover the rear")
	await _wait(1.6)
	await _snap("18_squad_command")

	# --- Hall of Echoes: wide, fight HUD, Mirror, column topple ---
	_enter("Trigger_Stage02_Hall")
	await _wait(1.5)
	_keep_alive()
	var hc: Vector3 = JourneyLayout.HALL_CENTER
	_hud_on(false)
	_free_cam(hc + Vector3(-24, 16, -34), hc + Vector3(4, 0, 6), 64.0)
	await _wait(1.0)
	await _snap("07_hall_wide")
	_hud_on(true)
	_player_cam(hc + Vector3(-2, 0, -18), Vector3(0, 0, 1), -12.0)
	_keep_alive()
	await _wait(1.5)
	await _snap("08_hall_fight")
	_realm(true)
	await _wait(1.0)
	await _snap("09_hall_mirror")
	_realm(false)
	var col: BreakableProp = _n("Stage02_HallOfEchoes/HallColumn_5") as BreakableProp
	if col != null:
		_hud_on(false)
		_player.global_position = col.global_position + Vector3(2.5, 0, 0)
		_free_cam(col.global_position + Vector3(4, 4, -12), col.global_position + Vector3(-3, 3, 0), 60.0)
		await _wait(0.6)
		col.trigger_break(true, _player)
		await _wait(0.42)
		await _snap("10_column_topple")
		await _wait(1.0)

	# --- Collapsed Gallery: Mirror bridge and the guard's duel deck ---
	_enter("Trigger_Stage03_Gallery")
	await _wait(1.0)
	_keep_alive()
	var s3 := Vector3(0, 0, JourneyLayout.OFF_S3)
	_hud_on(true)
	_player_cam(Vector3(0, 6, 66) + s3, Vector3(0, 0, 1), -8.0)
	_realm(true)
	await _wait(1.2)
	await _snap("11_gallery_mirror_bridge")
	_realm(false)
	_hud_on(false)
	var sg: Node3D = _n("Stage03_CollapsedGallery/Enemies/ShieldedGuard_1")
	var sgp: Vector3 = sg.global_position if sg != null else Vector3(0, 6, 79.5) + s3
	_free_cam(sgp + Vector3(-5.5, 3.2, -6.5), sgp + Vector3(0, 1.2, 0), 55.0)
	await _wait(1.0)
	await _snap("12_guard_deck")

	# --- Clock-tower chamber ---
	_enter("Trigger_Stage04_Mechanism")
	await _wait(1.2)
	_keep_alive()
	var cc: Vector3 = JourneyLayout.CHAMBER_CENTER
	_free_cam(cc + Vector3(-15, 11, -15), cc + Vector3(0, 2.5, 2), 66.0)
	await _wait(1.0)
	await _snap("13_clock_chamber")

	# --- Processional bridges toward the colosseum ---
	var r5: Array = (routes[3] as Array)[1]
	var p_s: Vector3 = (r5[0] as Array)[0]
	if weather != null:
		weather.set("forced_profile", "golden")
	_free_cam(p_s + Vector3(42, 26, 10), p_s + Vector3(-8, 2, 34), 60.0)
	await _wait(1.0)
	await _snap("14_processional_aerial")

	# --- Mirror Colosseum and The Warden ---
	_enter("Trigger_Stage05_Arena")
	await _wait(1.5)
	_keep_alive()
	var warden: Node3D = root.find_child("TheWarden", true, false) as Node3D
	var c5: Vector3 = Vector3(0, 10, 154) + Vector3(0, 0, JourneyLayout.OFF_S5)
	if weather != null:
		weather.set("forced_profile", "")
	_free_cam(c5 + Vector3(-8, 9, -12), c5 + Vector3(2, 1.5, 6), 70.0)
	await _wait(1.5)
	await _snap("15_colosseum")
	if warden != null:
		for a in get_nodes_in_group("squad_ally"):
			(a as Node3D).visible = false
		_player.visible = false
		var wp: Vector3 = warden.global_position
		var to_c := Vector3(c5.x - wp.x, 0, c5.z - wp.z)
		to_c = to_c.normalized() if to_c.length() > 0.5 else Vector3(0, 0, -1)
		_free_cam(wp + to_c * 7.5 + Vector3(0, 2.4, 0) + to_c.cross(Vector3.UP) * 2.0, wp + Vector3(0, 2.0, 0), 55.0)
		await _wait(1.0)
		await _snap("16_warden")
		for a in get_nodes_in_group("squad_ally"):
			(a as Node3D).visible = true
		_player.visible = true

	# --- Summit (sunset weather) ---
	if weather != null:
		weather.set("forced_profile", "golden")
	_player.global_position = c5 + Vector3(0, 0, 38)
	_free_cam(c5 + Vector3(-4, 5, 34), c5 + Vector3(-30, 4, 90), 64.0)
	await _wait(4.0)
	await _snap("17_summit")
	print("[showcase] DONE")
	quit(0)
