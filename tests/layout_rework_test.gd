extends SceneTree
## Guide 05 checks (headless): JourneyLayout math; the four winding bridges (length vs the old connectors, bends,
## bastions, garrisons, walkable centre line, rails, bastion rings); the 3x hall and chamber and their garrisons;
## stage offsets; the moved start terrace.
var _results: Array[String] = []
var _main: Node = null

const OLD_LENGTH: Dictionary = {"R1_PilgrimCauseway": 40.0, "R2_SunlitBridges": 16.0, "R3_WindsweptRampart": 16.0, "R5_Processional": 16.0}
const FLOOR_MASK: int = 4 | 8 | 16   # World_Shared | World_Reality | World_Mirror
const WALL_MASK: int = 4 | 128       # World_Shared | Player_Blocker


func _initialize() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func() -> void: print("[layout] WATCHDOG TIMEOUT"); quit(2))
	SquadAIConfig.force_offline()
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	_run()


func _line_at_z_x(a: Vector3, b: Vector3, lateral: float, z: float) -> float:
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var u: Vector3 = d.normalized()
	var n := Vector3(u.z, 0.0, -u.x)
	var base: Vector3 = a + n * lateral
	var t: float = (z - base.z) / maxf(0.0001, d.z)
	return base.x + d.x * t


func _check(n: String, ok: bool, d: String = "") -> void:
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", n, d]
	_results.append(line)
	print("[layout] ", line)


func _dist_to_line_xz(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	if ab.length() < 0.001:
		return ap.length()
	return absf(ab.x * ap.y - ab.y * ap.x) / ab.length()


func _run() -> void:
	# --- Pure math ---
	_check("map_terrace", is_equal_approx(JourneyLayout.to_world_z(-56.0), -136.0))
	_check("map_hall_south", is_equal_approx(JourneyLayout.to_world_z(24.0), 56.0))
	var hw: Vector3 = JourneyLayout.to_world(Vector3(10, 4, 34))
	_check("map_hall_scaled", is_equal_approx(hw.x, 30.0) and is_equal_approx(hw.z, 86.0), str(hw))
	_check("map_gallery", is_equal_approx(JourneyLayout.to_world_z(72.0), 176.0))
	_check("map_arena", is_equal_approx(JourneyLayout.to_world_z(154.0), 314.0))
	var rt_ok: bool = true
	for z in [-60.0, -30.0, 0.0, 15.0, 30.0, 50.0, 70.0, 95.0, 110.0, 160.0]:
		if absf(JourneyLayout.story_z(JourneyLayout.to_world_z(z)) - z) > 0.001:
			rt_ok = false
	_check("map_round_trip", rt_ok)
	_check("map_dropped", JourneyLayout.is_dropped(-30.0) and JourneyLayout.is_dropped(15.0) and not JourneyLayout.is_dropped(-56.0) and not JourneyLayout.is_dropped(34.0))

	# --- Build the level like a real run ---
	for _i in range(5):
		await process_frame
	_main.call("start_run_now")
	var t0: int = Time.get_ticks_msec()
	while not bool(_main.get("level_ready")) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	for _i in range(3):
		await physics_frame
	var lv: Node3D = _main.get_node("LevelRoot") as Node3D
	var space: PhysicsDirectSpaceState3D = lv.get_world_3d().direct_space_state
	var off: float = JourneyLayout.BRIDGE_WIDTH * 0.5 + 0.2

	# --- Bridges ---
	for r in JourneyLayout.ROUTES:
		var rname: String = String((r as Array)[0])
		var nodes: Array = (r as Array)[1]
		var rr: Node3D = lv.get_node_or_null("Journey_Routes/" + rname) as Node3D
		_check("route_exists_" + rname, rr != null)
		if rr == null:
			continue
		var p_first: Vector3 = (nodes[0] as Array)[0]
		var p_last: Vector3 = (nodes[nodes.size() - 1] as Array)[0]
		var poly: float = 0.0
		var max_dev: float = 0.0
		var bastions: int = 0
		for i in range(nodes.size()):
			var p: Vector3 = (nodes[i] as Array)[0]
			if i > 0:
				poly += p.distance_to((nodes[i - 1] as Array)[0])
			max_dev = maxf(max_dev, _dist_to_line_xz(p, p_first, p_last))
			if float((nodes[i] as Array)[1]) > 0.0:
				bastions += 1
		var old_len: float = float(OLD_LENGTH[rname])
		_check("route_length_" + rname, poly >= 4.0 * old_len, "%.0f m vs old %.0f m (x%.1f)" % [poly, old_len, poly / old_len])
		_check("route_not_straight_" + rname, max_dev >= 10.0, "bastions %.1f m off the straight line" % max_dev)
		_check("route_bastions_" + rname, bastions >= 2, "%d" % bastions)
		var rg: Node = rr.get_node_or_null("Roamers")
		var n_en: int = rg.get_child_count() if rg != null else 0
		_check("route_enemies_" + rname, n_en >= 2 * bastions, "%d enemies" % n_en)
		# Walkable: floor under the centre line every <= 1.5 m, plus 1 m into the floors at both ends.
		var probes: Array[Vector3] = []
		for i in range(nodes.size() - 1):
			var a: Vector3 = (nodes[i] as Array)[0]
			var b: Vector3 = (nodes[i + 1] as Array)[0]
			var steps: int = int(a.distance_to(b) / 1.5) + 1
			for k in range(steps + 1):
				probes.append(a.lerp(b, float(k) / float(steps)))
		var p_second: Vector3 = (nodes[1] as Array)[0]
		var p_before_last: Vector3 = (nodes[nodes.size() - 2] as Array)[0]
		probes.append(p_first - Vector3(p_second.x - p_first.x, 0, p_second.z - p_first.z).normalized())
		probes.append(p_last + Vector3(p_last.x - p_before_last.x, 0, p_last.z - p_before_last.z).normalized())
		var holes: int = 0
		for p in probes:
			var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.2, 0), p + Vector3(0, -1.2, 0), FLOOR_MASK))
			if hit.is_empty():
				holes += 1
				print("[layout]   no floor at ", p)
		_check("route_walkable_" + rname, holes == 0, "%d of %d centre-line probes without floor" % [holes, probes.size()])
		# Railed: from each leg's midpoint a sideways ray must meet a rail within 4 m on both sides.
		var unrailed: int = 0
		for i in range(nodes.size() - 1):
			var a2: Vector3 = (nodes[i] as Array)[0]
			var b2: Vector3 = (nodes[i + 1] as Array)[0]
			var mid: Vector3 = a2.lerp(b2, 0.5) + Vector3(0, 1.0, 0)
			var u: Vector3 = Vector3(b2.x - a2.x, 0, b2.z - a2.z).normalized()
			var nrm := Vector3(u.z, 0, -u.x)
			for s in [-1.0, 1.0]:
				var hit2: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(mid, mid + nrm * s * 6.0, WALL_MASK))
				if hit2.is_empty() or (hit2["position"] as Vector3).distance_to(mid) > off + 0.8:
					unrailed += 1
		_check("route_railed_" + rname, unrailed == 0, "%d leg sides without a rail" % unrailed)
		# Bastion rings: closed except where the legs arrive.
		for i in range(1, nodes.size() - 1):
			var nd: Array = nodes[i]
			if float(nd[1]) <= 0.0:
				continue
			var c: Vector3 = nd[0]
			var rr2: float = float(nd[1]) - 0.2
			var beta: float = asin(off / rr2)
			var opens: Array[float] = []
			for j in [i - 1, i + 1]:
				var q: Vector3 = (nodes[j] as Array)[0]
				opens.append(atan2(q.x - c.x, q.z - c.z))
			var gaps: int = 0
			for k in range(24):
				var ang: float = TAU * float(k) / 24.0
				var near_open: bool = false
				for o in opens:
					if absf(wrapf(ang - o, -PI, PI)) < beta + 0.12:
						near_open = true
				if near_open:
					continue
				var from: Vector3 = c + Vector3(0, 1.0, 0)
				var hit3: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(sin(ang), 0, cos(ang)) * (rr2 + 1.0), WALL_MASK))
				if hit3.is_empty():
					gaps += 1
			_check("bastion_ring_%s_%d" % [rname, i], gaps == 0, "%d open directions" % gaps)
		# Junction floor & rail closure at both floor-edge endpoints.
		var j_floor_holes: int = 0
		var j_rail_gaps: int = 0
		for ep in [[nodes[0], nodes[1], true], [nodes[nodes.size() - 1], nodes[nodes.size() - 2], false]]:
			var nd_e: Array = ep[0]
			var nd_o: Array = ep[1]
			var is_start: bool = bool(ep[2])
			if float(nd_e[1]) > 0.0:
				continue
			var a_leg: Vector3 = nd_e[0] if is_start else nd_o[0]
			var b_leg: Vector3 = nd_o[0] if is_start else nd_e[0]
			var ra_leg: float = float(nd_e[1]) if is_start else float(nd_o[1])
			var rb_leg: float = float(nd_o[1]) if is_start else float(nd_e[1])
			var u_leg: Vector3 = Vector3(b_leg.x - a_leg.x, 0.0, b_leg.z - a_leg.z).normalized()
			var p_a: Vector3 = a_leg + u_leg * (ra_leg - 0.4) if ra_leg > 0.0 else a_leg
			var p_b: Vector3 = b_leg - u_leg * (rb_leg - 0.4) if rb_leg > 0.0 else b_leg
			p_a.y = a_leg.y
			p_b.y = b_leg.y
			var ab2 := Vector2(p_b.x - p_a.x, p_b.z - p_a.z)
			var ez: float = float(nd_e[2])
			var j_hw: float = float(nd_e[3])
			var ey: float = (nd_e[0] as Vector3).y
			var xl: float = _line_at_z_x(a_leg, b_leg, -off, ez)
			var xr: float = _line_at_z_x(a_leg, b_leg, off, ez)
			var lo: float = minf(xl, xr)
			var hi: float = maxf(xl, xr)
			for z_probe in [ez - 0.4, ez, ez + 0.4]:
				var xb0: float = _line_at_z_x(a_leg, b_leg, -(JourneyLayout.BRIDGE_WIDTH * 0.5 - 0.5), z_probe)
				var xb1: float = _line_at_z_x(a_leg, b_leg, JourneyLayout.BRIDGE_WIDTH * 0.5 - 0.5, z_probe)
				var x_start: float = minf(xb0, xb1)
				var x_end: float = maxf(xb0, xb1)
				var is_plat_side: bool = (is_start and z_probe <= ez + 0.05) or (not is_start and z_probe >= ez - 0.05)
				if is_plat_side:
					x_start = maxf(x_start, -j_hw + 0.25)
					x_end = minf(x_end, j_hw - 0.25)
				var x_pts: Array[float] = []
				var x_cur: float = x_start
				while x_cur <= x_end + 0.001:
					x_pts.append(x_cur)
					x_cur += 0.8
				if x_pts.is_empty() or absf(x_pts[x_pts.size() - 1] - x_end) > 0.01:
					x_pts.append(x_end)
				for px in x_pts:
					var t_along: float = clampf(Vector2(px - p_a.x, z_probe - p_a.z).dot(ab2) / maxf(0.0001, ab2.length_squared()), 0.0, 1.0)
					var exp_y: float = lerpf(p_a.y, p_b.y, t_along)
					var hit_f: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(
						Vector3(px, exp_y + 0.5, z_probe), Vector3(px, exp_y - 1.2, z_probe), FLOOR_MASK))
					if hit_f.is_empty() or (hit_f["position"] as Vector3).y > exp_y + 0.25:
						j_floor_holes += 1
						print("[layout]   junction floor hole ", rname, " at ", Vector3(px, exp_y, z_probe), " hit=", hit_f)
			if lo > -j_hw + 0.5 or lo < -j_hw - 0.75:
				var x_rw: float = (-j_hw + lo) * 0.5 if lo > -j_hw + 0.5 else (-j_hw - 0.25 + lo) * 0.5
				var hit_rw: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(
					Vector3(x_rw, ey + 1.0, ez - 1.5), Vector3(x_rw, ey + 1.0, ez + 1.5), WALL_MASK))
				if hit_rw.is_empty():
					j_rail_gaps += 1
					print("[layout]   missing west join rail ", rname, " at x=", x_rw, " z=", ez)
			if hi < j_hw - 0.5 or hi > j_hw + 0.75:
				var x_re: float = (hi + j_hw) * 0.5 if hi < j_hw - 0.5 else (j_hw + 0.25 + hi) * 0.5
				var hit_re: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(
					Vector3(x_re, ey + 1.0, ez - 1.5), Vector3(x_re, ey + 1.0, ez + 1.5), WALL_MASK))
				if hit_re.is_empty():
					j_rail_gaps += 1
					print("[layout]   missing east join rail ", rname, " at x=", x_re, " z=", ez)
		_check("route_junction_floor_" + rname, j_floor_holes == 0, "%d junction floor holes" % j_floor_holes)
		_check("route_junction_rails_" + rname, j_rail_gaps == 0, "%d junction rail gaps" % j_rail_gaps)

	# --- 3x hall and chamber ---
	var s2: Node3D = lv.get_node("Stage02_HallOfEchoes") as Node3D
	var hsize: Vector3 = (((s2.get_node("HallFloor") as Node3D).get_child(0) as CollisionShape3D).shape as BoxShape3D).size
	_check("hall_3x", hsize.x >= 59.0 and hsize.z >= 59.0, str(hsize))
	var hall_en: Node = s2.get_node("Enemies")
	_check("hall_more_enemies", hall_en.get_child_count() >= 8, "%d encounter enemies (was 4)" % hall_en.get_child_count())
	_check("hall_encounter_count_matches", int(s2.get_node("Trigger_Stage02_Hall").get("encounter_enemy_count")) == hall_en.get_child_count())
	_check("hall_roamers", s2.get_node_or_null("Roamers") != null and s2.get_node("Roamers").get_child_count() >= 3)
	var s4: Node3D = lv.get_node("Stage04_MechanismChamber") as Node3D
	var csize: Vector3 = (((s4.get_node("ChamberFloor") as Node3D).get_child(0) as CollisionShape3D).shape as BoxShape3D).size
	_check("chamber_3x", csize.x >= 35.9 and csize.z >= 35.9, str(csize))
	var tr: Node = s4.get_node_or_null("Roamers")
	_check("chamber_more_enemies", tr != null and tr.get_child_count() >= 7, "%d (was 3)" % (tr.get_child_count() if tr != null else 0))
	var puz: Node3D = s4.get_node("ChamberMechanismPuzzle") as Node3D
	_check("puzzle_centred", puz.global_position.distance_to(JourneyLayout.CHAMBER_CENTER) < 0.01)

	# --- Story stages shifted, checkpoints in world space, spawn on the moved terrace ---
	_check("gallery_offset", is_equal_approx((lv.get_node("Stage03_CollapsedGallery") as Node3D).position.z, JourneyLayout.OFF_S3))
	_check("arena_offset", is_equal_approx((lv.get_node("Stage05_ExecutionArena") as Node3D).position.z, JourneyLayout.OFF_S5))
	var gt: Node = lv.get_node("Stage03_CollapsedGallery/Trigger_Stage03_Gallery")
	_check("gallery_checkpoint_world", absf((gt.get("checkpoint_spawn_position") as Vector3).z - (61.5 + JourneyLayout.OFF_S3)) < 0.01)
	var pl: Node3D = _main.get_node("Player") as Node3D
	_check("spawn_on_terrace", absf(pl.global_position.z + 136.0) < 2.0, str(pl.global_position))

	var fails: int = _results.filter(func(r2: String) -> bool: return r2.begins_with("FAIL")).size()
	print("[layout] SUMMARY %d checks, %d failed" % [_results.size(), fails])
	quit(1 if fails > 0 else 0)
