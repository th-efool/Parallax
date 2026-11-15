class_name ColosseumGreyboxBuilder
extends Node3D
## Deterministic collision-accurate greybox generator for Stages 01-05 (+Z North, Y=0 walkable plane).
## Provides walkable floors, realm-specific platforms/bridges, gates, switches, breakables, mechanism puzzle, and anchors.

const LAYER_WORLD_SHARED: int = RealmManager.LAYER_WORLD_SHARED
const LAYER_WORLD_REALITY: int = RealmManager.LAYER_WORLD_REALITY
const LAYER_WORLD_MIRROR: int = RealmManager.LAYER_WORLD_MIRROR
const LAYER_INTERACTABLE: int = RealmManager.LAYER_INTERACTABLE
const LAYER_PLAYER: int = RealmManager.LAYER_PLAYER
const LAYER_HITBOX: int = RealmManager.LAYER_HITBOX

var _is_built: bool = false


func _ready() -> void:
	build_greybox()


func build_greybox() -> void:
	if _is_built:
		return
	_is_built = true

	var stages: Array[Node3D] = [
		_build_stage_01_entry(),
		_build_stage_02_hall(),
		_build_stage_03_gallery(),
		_build_stage_04_mechanism(),
		_build_stage_05_arena(),
	]
	for st in stages:
		add_child(st)


func get_key_anchors() -> Dictionary:
	return {
		"player_spawn": Vector3(0.0, 0.0, -3.0),
		"entry_gap_center": Vector3(0.0, 0.0, 1.0),
		"entry_switch": Vector3(0.0, 0.0, 4.0),
		"hall_pillar": Vector3(0.0, 0.0, 20.0),
		"skeleton_1": Vector3(-6.0, 0.0, 16.0),
		"skeleton_2": Vector3(6.0, 0.0, 24.0),
		"phantom_1": Vector3(-6.0, 0.0, 26.0),
		"phantom_2": Vector3(6.0, 0.0, 26.0),
		"gallery_bridge_center": Vector3(0.0, 0.0, 46.0),
		"weak_stone_support": Vector3(0.0, 0.0, 51.0),
		"bridge_anchor": Vector3(0.0, 0.0, 53.0),
		"shielded_guard": Vector3(0.0, 0.0, 56.0),
		"mechanism_dais": Vector3(-3.0, 1.35, 67.0),
		"mechanism_plate": Vector3(0.0, 0.0, 68.0),
		"arena_entry": Vector3(0.0, 0.0, 76.0),
		"warden_spawn": Vector3(0.0, 0.0, 88.0),
		"arena_exit": Vector3(0.0, 0.0, 102.0),
	}


func _build_stage_01_entry() -> Node3D:
	var root := Node3D.new()
	root.name = "Stage01_EntryVestibule"

	root.add_child(_make_box_body("EntryFloorSouth", Vector3(0.0, -0.25, -2.75), Vector3(12.0, 0.5, 4.5), LAYER_WORLD_SHARED, Color(0.55, 0.48, 0.38)))
	root.add_child(_make_box_body("EntryFloorNorth", Vector3(0.0, -0.25, 3.75), Vector3(12.0, 0.5, 2.5), LAYER_WORLD_SHARED, Color(0.55, 0.48, 0.38)))
	root.add_child(_make_box_body("Corridor01_Floor", Vector3(0.0, -0.25, 7.5), Vector3(4.0, 0.5, 5.0), LAYER_WORLD_SHARED, Color(0.50, 0.44, 0.35)))

	var stones := RealmPlatform.new()
	stones.name = "EntrySteppingStones"
	stones.position = Vector3(0.0, 0.0, 1.0)
	var reality_geo := Node3D.new()
	reality_geo.name = "RealityGeometry"
	stones.add_child(reality_geo)
	var mirror_geo := Node3D.new()
	mirror_geo.name = "MirrorGeometry"
	mirror_geo.add_child(_make_box_body("SteppingStonesSpan", Vector3(0.0, -0.25, 0.0), Vector3(4.0, 0.5, 3.0), LAYER_WORLD_MIRROR, Color(0.20, 0.72, 1.0, 0.85)))
	stones.add_child(mirror_geo)
	root.add_child(stones)

	var gate := _make_gate("Gate01_EntryToHall", Vector3(0.0, 0.0, 5.0), 0, "", false)
	root.add_child(gate)

	var sw := _make_switch(
		"EntryMirrorSwitch",
		Vector3(0.0, 0.0, 4.0),
		InteractSwitch.SwitchRole.GATE_OPENER,
		1,
		NodePath("../Gate01_EntryToHall"),
		NodePath(),
		NodePath()
	)
	root.add_child(sw)
	return root


func _build_stage_02_hall() -> Node3D:
	var root := Node3D.new()
	root.name = "Stage02_HallOfEchoes"

	root.add_child(_make_box_body("HallFloor", Vector3(0.0, -0.25, 20.0), Vector3(20.0, 0.5, 20.0), LAYER_WORLD_SHARED, Color(0.56, 0.47, 0.37)))
	root.add_child(_make_box_body("Corridor02_Floor", Vector3(0.0, -0.25, 32.0), Vector3(4.0, 0.5, 4.0), LAYER_WORLD_SHARED, Color(0.50, 0.44, 0.35)))

	var pillar := _make_breakable_pillar("CrackedCentralPillar", Vector3(0.0, 0.0, 20.0), BreakableProp.PropKind.CRACKED_PILLAR, 1, 0.60, Vector3(0.0, 0.0, 2.5), 2.5)
	root.add_child(pillar)

	root.add_child(_make_gate("Gate02_HallToGallery", Vector3(0.0, 0.0, 30.0), 1, "hall_of_echoes", false))
	return root


func _build_stage_03_gallery() -> Node3D:
	var root := Node3D.new()
	root.name = "Stage03_CollapsedGallery"

	root.add_child(_make_box_body("GalleryFloorSouth", Vector3(0.0, -0.25, 39.0), Vector3(8.0, 0.5, 10.0), LAYER_WORLD_SHARED, Color(0.52, 0.45, 0.36)))
	root.add_child(_make_box_body("GalleryFloorNorth", Vector3(0.0, -0.25, 53.0), Vector3(8.0, 0.5, 10.0), LAYER_WORLD_SHARED, Color(0.52, 0.45, 0.36)))
	root.add_child(_make_box_body("Corridor03_Floor", Vector3(0.0, -0.25, 60.0), Vector3(4.0, 0.5, 4.0), LAYER_WORLD_SHARED, Color(0.50, 0.44, 0.35)))

	var bridge := RealmPlatform.new()
	bridge.name = "GallerySpectralBridge"
	bridge.position = Vector3(0.0, 0.0, 46.0)
	var reality_geo := Node3D.new()
	reality_geo.name = "RealityGeometry"
	bridge.add_child(reality_geo)
	var mirror_geo := Node3D.new()
	mirror_geo.name = "MirrorGeometry"
	mirror_geo.add_child(_make_box_body("SpectralBridgeSpan", Vector3(0.0, -0.25, 0.0), Vector3(3.0, 0.5, 4.0), LAYER_WORLD_MIRROR, Color(0.20, 0.72, 1.0, 0.85)))
	bridge.add_child(mirror_geo)
	var repaired_geo := Node3D.new()
	repaired_geo.name = "RepairedGeometry"
	repaired_geo.add_child(_make_box_body("RepairedBridgeSpan", Vector3(0.0, -0.25, 0.0), Vector3(3.0, 0.5, 4.0), LAYER_WORLD_SHARED | LAYER_WORLD_REALITY, Color(0.68, 0.60, 0.48)))
	bridge.add_child(repaired_geo)
	root.add_child(bridge)

	var support := _make_breakable_pillar("WeakStoneSupport", Vector3(0.0, 0.0, 51.0), BreakableProp.PropKind.WEAK_STONE_SUPPORT, 2, 0.0, Vector3.ZERO, 1.5)
	root.add_child(support)

	var anchor := _make_switch(
		"BridgeAnchorSwitch",
		Vector3(0.0, 0.0, 53.0),
		InteractSwitch.SwitchRole.BRIDGE_ANCHOR,
		1,
		NodePath(),
		NodePath("../GallerySpectralBridge"),
		NodePath("../WeakStoneSupport")
	)
	root.add_child(anchor)

	root.add_child(_make_gate("Gate03_GalleryToMechanism", Vector3(0.0, 0.0, 58.0), 2, "shielded_guard", false))
	return root


func _build_stage_04_mechanism() -> Node3D:
	var root := Node3D.new()
	root.name = "Stage04_MechanismChamber"

	root.add_child(_make_box_body("ChamberFloor", Vector3(0.0, -0.25, 68.0), Vector3(12.0, 0.5, 12.0), LAYER_WORLD_SHARED, Color(0.54, 0.46, 0.37)))
	root.add_child(_make_box_body("RaisedImpactDais", Vector3(-3.0, 0.675, 67.0), Vector3(2.5, 1.35, 2.5), LAYER_WORLD_SHARED, Color(0.62, 0.54, 0.44)))
	root.add_child(_make_box_body("Corridor04_Floor", Vector3(0.0, -0.25, 75.0), Vector3(4.0, 0.5, 2.0), LAYER_WORLD_SHARED, Color(0.50, 0.44, 0.35)))

	root.add_child(_make_gate("Gate04_MechanismToArena", Vector3(0.0, 0.0, 74.0), 3, "", false))

	var puzzle := MechanismPuzzle.new()
	puzzle.name = "ChamberMechanismPuzzle"
	puzzle.position = Vector3(0.0, 0.0, 68.0)
	puzzle.linked_gate_path = NodePath("../Gate04_MechanismToArena")
	puzzle.weight_node_path = NodePath("SuspendedWeight")
	puzzle.plate_node_path = NodePath("PressurePlate")

	var weight := Node3D.new()
	weight.name = "SuspendedWeight"
	weight.position = Vector3(0.0, 2.5, 0.0)
	weight.add_child(_make_mesh_box("WeightMesh", Vector3(1.2, 1.2, 1.2), Color(0.20, 0.72, 1.0, 0.85)))
	var hurt := Hurtbox3D.new()
	hurt.name = "Hurtbox3D"
	hurt.owner_actor_path = NodePath("..")
	hurt.is_enemy_hurtbox = false
	hurt.collision_layer = LAYER_INTERACTABLE | LAYER_HITBOX
	hurt.collision_mask = LAYER_HITBOX
	var hcol := CollisionShape3D.new()
	var hs := BoxShape3D.new()
	hs.size = Vector3(1.4, 1.4, 1.4)
	hcol.shape = hs
	hurt.add_child(hcol)
	weight.add_child(hurt)
	puzzle.add_child(weight)

	var plate := Node3D.new()
	plate.name = "PressurePlate"
	var plate_mesh := _make_mesh_box("PlateMesh", Vector3(1.6, 0.14, 1.6), Color(0.85, 0.65, 0.25))
	plate_mesh.position = Vector3(0.0, 0.07, 0.0)
	plate.add_child(plate_mesh)
	puzzle.add_child(plate)

	root.add_child(puzzle)
	return root


func _build_stage_05_arena() -> Node3D:
	var root := Node3D.new()
	root.name = "Stage05_ExecutionArena"

	root.add_child(_make_box_body("ArenaFloor", Vector3(0.0, -0.25, 90.5), Vector3(26.0, 0.5, 29.0), LAYER_WORLD_SHARED, Color(0.45, 0.40, 0.34)))

	var mirror_plane := BreakableProp.new()
	mirror_plane.name = "CentralMirrorPlane"
	mirror_plane.position = Vector3(0.0, 0.0, 89.0)
	mirror_plane.prop_kind = BreakableProp.PropKind.CENTRAL_MIRROR_PLANE
	mirror_plane.section_id = 4
	mirror_plane.warning_duration = 0.0
	var intact_vis := Node3D.new()
	intact_vis.name = "IntactVisual"
	var plane_mesh := _make_mesh_box("MirrorPlaneMesh", Vector3(0.12, 5.5, 22.0), Color(0.25, 0.72, 1.0, 0.35))
	plane_mesh.position = Vector3(0.0, 2.75, 0.0)
	intact_vis.add_child(plane_mesh)
	mirror_plane.add_child(intact_vis)
	root.add_child(mirror_plane)

	root.add_child(_make_gate("Gate05_ArenaExit", Vector3(0.0, 0.0, 102.0), 4, "the_warden", false))
	return root


func _make_box_body(node_name: String, pos: Vector3, box_size: Vector3, layer_mask: int, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.collision_layer = layer_mask
	body.collision_mask = 0

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	col.shape = shape
	body.add_child(col)
	body.add_child(_make_mesh_box("Mesh", box_size, color))
	return body


func _make_mesh_box(node_name: String, box_size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if color.a < 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	mi.mesh = mesh
	return mi


func _make_gate(node_name: String, pos: Vector3, sec_id: int, encounter_id: String, starts_open_flag: bool) -> EncounterGate:
	var gate := EncounterGate.new()
	gate.name = node_name
	gate.position = pos
	gate.section_id = sec_id
	gate.linked_encounter_id = encounter_id
	gate.starts_open = starts_open_flag
	gate.gate_mesh_path = NodePath("GateMesh")

	var mesh := _make_mesh_box("GateMesh", Vector3(4.0, 3.0, 0.35), Color(0.75, 0.32, 0.18))
	mesh.position = Vector3(0.0, 1.5, 0.0)
	gate.add_child(mesh)

	var body := StaticBody3D.new()
	body.name = "BlockerBody"
	body.collision_layer = LAYER_WORLD_SHARED
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.0, 3.0, 0.4)
	col.shape = shape
	col.position = Vector3(0.0, 1.5, 0.0)
	body.add_child(col)
	gate.add_child(body)
	return gate


func _make_switch(
	node_name: String,
	pos: Vector3,
	role: int,
	req_realm: int,
	gate_path: NodePath,
	platform_path: NodePath,
	blocker_path: NodePath
) -> InteractSwitch:
	var sw := InteractSwitch.new()
	sw.name = node_name
	sw.position = pos
	sw.switch_role = role as InteractSwitch.SwitchRole
	sw.required_realm = req_realm
	sw.linked_gate_path = gate_path
	sw.linked_platform_path = platform_path
	sw.blocking_prop_path = blocker_path
	sw.collision_layer = LAYER_INTERACTABLE
	sw.collision_mask = LAYER_PLAYER

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.5
	col.shape = shape
	col.position = Vector3(0.0, 0.8, 0.0)
	sw.add_child(col)

	var plinth := _make_mesh_box("SwitchPlinth", Vector3(0.7, 1.2, 0.7), Color(0.25, 0.78, 1.0))
	plinth.position = Vector3(0.0, 0.6, 0.0)
	sw.add_child(plinth)
	return sw


func _make_breakable_pillar(
	node_name: String,
	pos: Vector3,
	kind: int,
	sec_id: int,
	warn_sec: float,
	fall_offset: Vector3,
	dmg_radius: float
) -> BreakableProp:
	var prop := BreakableProp.new()
	prop.name = node_name
	prop.position = pos
	prop.prop_kind = kind as BreakableProp.PropKind
	prop.section_id = sec_id
	prop.warning_duration = warn_sec
	prop.fall_zone_offset = fall_offset
	prop.damage_radius = dmg_radius

	var intact := Node3D.new()
	intact.name = "IntactVisual"
	var cyl := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.65
	cm.bottom_radius = 0.7
	cm.height = 3.5
	cyl.mesh = cm
	cyl.position = Vector3(0.0, 1.75, 0.0)
	intact.add_child(cyl)
	prop.add_child(intact)

	var broken := Node3D.new()
	broken.name = "BrokenVisual"
	var rubble := _make_mesh_box("Rubble", Vector3(1.6, 0.4, 2.2), Color(0.45, 0.40, 0.34))
	rubble.position = Vector3(0.0, 0.2, 1.0)
	broken.add_child(rubble)
	prop.add_child(broken)

	var body := StaticBody3D.new()
	body.name = "SolidBody"
	body.collision_layer = LAYER_WORLD_SHARED
	body.collision_mask = 0
	var bcol := CollisionShape3D.new()
	var bshape := CylinderShape3D.new()
	bshape.radius = 0.68
	bshape.height = 3.5
	bcol.shape = bshape
	bcol.position = Vector3(0.0, 1.75, 0.0)
	body.add_child(bcol)
	prop.add_child(body)

	var hurt := Hurtbox3D.new()
	hurt.name = "Hurtbox3D"
	hurt.owner_actor_path = NodePath("..")
	hurt.is_enemy_hurtbox = false
	hurt.is_breakable_hurtbox = true
	hurt.collision_layer = LAYER_INTERACTABLE
	hurt.collision_mask = LAYER_HITBOX
	var hcol := CollisionShape3D.new()
	var hshape := CylinderShape3D.new()
	hshape.radius = 0.9
	hshape.height = 3.0
	hcol.shape = hshape
	hcol.position = Vector3(0.0, 1.5, 0.0)
	hurt.add_child(hcol)
	prop.add_child(hurt)

	return prop
