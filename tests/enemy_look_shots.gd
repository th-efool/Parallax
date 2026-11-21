extends SceneTree
## Windowed visual + behaviour check for enemy looks and the Warden arena:
##  - Hall of Echoes wide shot + Hexcaster (Skeleton_Mage) close-up; dumps any enemy still using a flat material_override.
##  - Warden (bone colossus) close-up, a forced summon (cast sigils, then thralls), and walking through the Mirror Plane.
## Run: godot --path . -s res://tests/enemy_look_shots.gd -- --shots=<dir>
var _shots: String = ""
var _t: int = 0
var _stage: int = 0
var _cam: Camera3D = null
var _fails: int = 0
var _cross_realm_before: int = -1


func _initialize() -> void:
	SquadAIConfig.force_offline()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.substr(8)
	var main: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main


func _check(n: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
	print("[enemy-shots] %s %s %s" % ["PASS" if ok else "FAIL", n, detail])


func _snap(n: String) -> void:
	if _shots.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(_shots)
	root.get_viewport().get_texture().get_image().save_png(_shots.path_join(n + ".png"))
	print("[enemy-shots] shot ", n)


func _player() -> Node3D:
	return get_first_node_in_group("player") as Node3D


func _enter(trigger_name: String) -> void:
	var trig: Node3D = root.find_child(trigger_name, true, false) as Node3D
	if trig != null and _player() != null:
		_player().global_position = trig.global_position + Vector3(0, -1.0, 0)


func _camera_at(from: Vector3, look_at_pos: Vector3) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		root.add_child(_cam)
	_cam.global_position = from
	_cam.look_at(look_at_pos, Vector3.UP)
	_cam.make_current()


func _close_up(e: Node3D, dist: float, height: float, aim: float) -> void:
	var p: Node3D = _player()
	var dir: Vector3 = (p.global_position - e.global_position) if p != null else Vector3.BACK
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.BACK
	_camera_at(e.global_position + dir * dist + Vector3(0, height, 0), e.global_position + Vector3(0, aim, 0))


func _flat_red_overrides(stage_name: String) -> int:
	var stage: Node = root.find_child(stage_name, true, false)
	var n: int = 0
	if stage == null:
		return 0
	for mi in stage.find_children("*", "MeshInstance3D", true, false):
		var m: Material = (mi as MeshInstance3D).material_override
		if m is StandardMaterial3D and (m as StandardMaterial3D).albedo_texture == null and (m as StandardMaterial3D).emission_enabled \
				and (m as StandardMaterial3D).emission.r > 0.4 and (m as StandardMaterial3D).emission.g < 0.1:
			var owner_enemy: Node = mi
			while owner_enemy != null and not (owner_enemy is EnemyBase):
				owner_enemy = owner_enemy.get_parent()
			if owner_enemy != null:
				n += 1
	return n


func _process(_d: float) -> bool:
	_t += 1
	var mc: Node = get_first_node_in_group("main_controller")
	var warden: WardenBoss = root.find_child("TheWarden", true, false) as WardenBoss
	if _stage == 0 and _t > 30:
		var title: Node = get_first_node_in_group("title_screen")
		if title != null:
			title.set("show_quote_on_start", false)
			title.call("press_start")
		_stage = 1
	elif _stage == 1 and mc != null and bool(mc.get("level_ready")):
		_enter("Trigger_Stage02_Hall")
		_stage = 2
		_t = 0
	elif _stage == 2 and _t == 90:
		var hall: Node3D = root.find_child("Stage02_HallOfEchoes", true, false) as Node3D
		var trig: Node3D = root.find_child("Trigger_Stage02_Hall", true, false) as Node3D
		_camera_at(trig.global_position + Vector3(0, 2.5, -2.0), trig.global_position + Vector3(0, 0.5, 14.0))
		_check("no_flat_red_enemy_overrides_in_hall", _flat_red_overrides("Stage02_HallOfEchoes") == 0, "count=%d" % _flat_red_overrides("Stage02_HallOfEchoes"))
		if hall == null:
			_check("hall_found", false)
	elif _stage == 2 and _t == 140:
		_snap("hall_wide")
		var hx: Node3D = root.find_child("HallHexcaster_W", true, false) as Node3D
		if hx != null:
			_close_up(hx, 3.2, 1.5, 1.0)
			var has_staff: bool = hx.find_child("Skeleton_Staff", true, false) != null
			var has_mage: bool = hx.find_child("Skeleton_Mage_Body", true, false) != null
			_check("hexcaster_is_mage_with_staff", has_staff and has_mage, "staff=%s mage=%s" % [has_staff, has_mage])
	elif _stage == 2 and _t == 170:
		_snap("hexcaster_close")
		var sk: Node3D = root.find_child("SkeletonGuard_1", true, false) as Node3D
		if sk != null:
			_close_up(sk, 3.0, 1.4, 0.9)
	elif _stage == 2 and _t == 200:
		_snap("skeleton_guard_close")
		_enter("Trigger_Stage05_Arena")
		_stage = 3
		_t = 0
	elif _stage == 3 and _t == 90 and warden != null:
		# Portrait: hide the squad (they crowd the boss) and the player model; shoot from the front-left so the
		# Mirror Plane (the Warden spawns inside it) is behind the camera's line of sight.
		for a in get_nodes_in_group("squad_ally"):
			(a as Node3D).visible = false
		if _player() != null:
			_player().visible = false
		var fwd: Vector3 = warden.get_facing_direction()
		_camera_at(warden.global_position + fwd * 6.0 + Vector3(-3.0, 2.2, 0.0), warden.global_position + Vector3(0, 1.9, 0))
		var horns: bool = warden.find_child("WardenHorns", true, false) != null
		var axe: bool = warden.find_child("2H_Axe", true, false) != null
		var minion: bool = warden.find_child("Skeleton_Minion_Body", true, false) != null
		_check("warden_is_dressed_colossus", horns and axe and minion, "horns=%s axe=%s minion=%s" % [horns, axe, minion])
	elif _stage == 3 and _t == 150 and warden != null:
		_snap("warden_close")
		for a in get_nodes_in_group("squad_ally"):
			(a as Node3D).visible = true
		if _player() != null:
			_player().visible = true
		var n: int = warden.begin_summon()
		_check("summon_count_in_range", n >= warden.summon_min and n <= warden.summon_max, "n=%d" % n)
		var plane: Node3D = root.find_child("CentralMirrorPlane", true, false) as Node3D
		if plane != null:
			_camera_at(plane.global_position + Vector3(9.0, 4.5, -9.0), plane.global_position + Vector3(0, 0.8, 0))
	elif _stage == 3 and _t == 175:
		_snap("warden_summon_cast")
	elif _stage == 3 and _t == 300 and warden != null:
		_snap("warden_thralls")
		var alive: int = warden.get_alive_summon_count()
		_check("thralls_spawned", alive >= warden.summon_min, "alive=%d" % alive)
		# Walk the player through the Mirror Plane from its west face to its east face.
		var plane2: Node3D = root.find_child("CentralMirrorPlane", true, false) as Node3D
		var rm: RealmManager = RealmManager.instance as RealmManager
		_cross_realm_before = int(rm.current_realm) if rm != null else -1
		if plane2 != null and _player() != null:
			_player().global_position = plane2.global_position + Vector3(-1.4, 0.05, 4.0)
		_stage = 4
		_t = 0
	elif _stage == 4 and _t <= 40:
		var plane3: Node3D = root.find_child("CentralMirrorPlane", true, false) as Node3D
		if plane3 != null and _player() != null and _t > 5:
			_player().global_position = plane3.global_position + Vector3(-1.4 + 2.8 * float(_t - 5) / 35.0, 0.05, 4.0)
	elif _stage == 4 and _t == 60:
		var rm2: RealmManager = RealmManager.instance as RealmManager
		var after: int = int(rm2.current_realm) if rm2 != null else -1
		_check("mirror_plane_crossing_swaps_realm", after != _cross_realm_before and rm2.cooldown_timer <= 0.0, "before=%d after=%d cd=%.2f" % [_cross_realm_before, after, rm2.cooldown_timer if rm2 else -1.0])
		_snap("after_crossing")
		print("[enemy-shots] SUMMARY fails=%d" % _fails)
		quit(0 if _fails == 0 else 1)
	if _t > 9000:
		print("[enemy-shots] TIMEOUT stage=%d" % _stage)
		quit(2)
	return false
