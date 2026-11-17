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
	var sup: Node3D = s3.get_node("WeakStoneSupport") as Node3D
	var ledge: Node3D = s3.get_node("SupportLedge") as Node3D
	var deck_y: float = (s3.get_node("GalleryFloorNorth") as Node3D).global_position.y + 0.25
	_check("support_high", sup.global_position.y - deck_y > 3.4, "%.2f above deck" % (sup.global_position.y - deck_y))
	_check("ledge_exists", ledge != null)
	for i in [1, 2, 3]:
		_check("parkour_step_%d" % i, s3.get_node_or_null("ParkourStep_%d" % i) != null)
	var anchor: Node3D = s3.get_node("BridgeAnchorSwitch") as Node3D
	_check("anchor_on_ledge", absf(anchor.global_position.y - sup.global_position.y) < 0.1 and anchor.global_position.z > sup.global_position.z)
	_check("gallery_extra_enemies", s3.get_node_or_null("Roamers/GallerySkeleton_A") != null and s3.get_node_or_null("Roamers/GallerySkeleton_B") != null)
	var fails: int = _results.filter(func(r: String) -> bool: return r.begins_with("FAIL")).size()
	print("[props] SUMMARY %d checks, %d failed" % [_results.size(), fails])
	quit(1 if fails > 0 else 0)
