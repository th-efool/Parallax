extends SceneTree
## Checks guide 04 placements in the built level (headless).
var _results: Array[String] = []
var _main: Node = null

func _initialize() -> void:
	SquadAIConfig.force_offline()
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	_run()

func _check(n: String, ok: bool, d: String = "") -> void:
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", n, d]
	_results.append(line)
	print("[props] ", line)

func _run() -> void:
	for _i in range(5):
		await process_frame
	_main.call("start_run_now")
	var t0: int = Time.get_ticks_msec()
	while not bool(_main.get("level_ready")) and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	var lv: Node = _main.get_node("LevelRoot")
	var s1: Node3D = lv.get_node("Stage01_EntryVestibule") as Node3D
	var sw: Node3D = s1.get_node("EntryMirrorSwitch") as Node3D
	var gate: Node3D = s1.get_node("Gate01_EntryToHall") as Node3D
	var rel: Vector3 = sw.global_position - gate.global_position
	_check("gate_stone_beside_gate", absf(rel.x) >= 2.8 and absf(rel.z) < 2.5, str(rel))
	for n in ["GateWarden_W", "GateWarden_E", "GateBrute", "GateHexcaster"]:
		_check("guard_" + n, s1.get_node_or_null("Roamers/" + n) != null)
	var gw: Node3D = s1.get_node_or_null("Roamers/GateWarden_W") as Node3D
	_check("warden_enlarged", gw != null and (gw.get_node("VisualRoot") as Node3D).scale.x > 1.3)
	var s3: Node3D = lv.get_node("Stage03_CollapsedGallery") as Node3D
	# Gallery: no support/anchor errand; the guard duels on a wide deck and his death rebuilds the bridge.
	_check("no_support_puzzle", s3.get_node_or_null("WeakStoneSupport") == null and s3.get_node_or_null("BridgeAnchorSwitch") == null and s3.get_node_or_null("SupportLedge") == null)
	var deck_size: Vector3 = (((s3.get_node("GalleryFloorNorth") as Node3D).get_child(0) as CollisionShape3D).shape as BoxShape3D).size
	_check("guard_deck_wide", deck_size.x >= 16.0, str(deck_size))
	var sg: EnemyBase = s3.get_node("Enemies/ShieldedGuard_1") as EnemyBase
	var brg: Node = s3.get_node("GallerySpectralBridge")
	sg.is_active = true   # enemies outside the current section are dormant; wake for the test
	sg.apply_damage(999999, true, "environmental")
	for _i in range(3):
		await process_frame
	_check("guard_death_rebuilds_bridge", bool(brg.get("is_permanently_repaired")))
	# Hall: every column is a directional knock weapon.
	var s2: Node3D = lv.get_node("Stage02_HallOfEchoes") as Node3D
	var knockable: int = 0
	for ch in s2.get_children():
		if ch is BreakableProp and (ch as BreakableProp).knock_directional:
			knockable += 1
	_check("hall_columns_knockable", knockable >= 9, "%d" % knockable)
	var col: BreakableProp = s2.get_node("HallColumn_1") as BreakableProp
	var victim: EnemyBase = s2.get_node("Enemies/SkeletonGuard_1") as EnemyBase
	var striker := Node3D.new()
	s2.add_child(striker)
	striker.global_position = col.global_position - Vector3(3.0, 0, 0)   # strike from the west: falls east
	victim.global_position = col.global_position + Vector3(6.0, 0, 0.3)
	victim.is_active = true
	var hp0: int = victim.health
	col.trigger_break(true, striker)
	col.complete_break_now()
	_check("knock_falls_away_from_striker", col.fall_zone_offset.x > 4.0, str(col.fall_zone_offset))
	_check("knock_crushes_in_fall_line", victim.health < hp0 or victim.is_dead, "%d -> %d" % [hp0, victim.health])
	_check("gallery_extra_enemies", s3.get_node_or_null("Roamers/GallerySkeleton_A") != null and s3.get_node_or_null("Roamers/GallerySkeleton_B") != null)
	var fails: int = _results.filter(func(r: String) -> bool: return r.begins_with("FAIL")).size()
	print("[props] SUMMARY %d checks, %d failed" % [_results.size(), fails])
	quit(1 if fails > 0 else 0)
