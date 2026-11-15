class_name ColosseumGreyboxBuilder
extends Node3D
## Deterministic collision-accurate greybox generator for Stages 01-05 (+Z North, Y=0 walkable plane).
## Provides walkable floors, realm-specific platforms/bridges, gates, switches, breakables, mechanism puzzle, and anchors.

const LAYER_WORLD_SHARED: int = RealmManager.LAYER_WORLD_SHARED
const LAYER_WORLD_REALITY: int = RealmManager.LAYER_WORLD_REALITY
const LAYER_WORLD_MIRROR: int = RealmManager.LAYER_WORLD_MIRROR
const LAYER_INTERACTABLE: int = RealmManager.LAYER_INTERACTABLE
const LAYER_PLAYER: int = RealmManager.LAYER_PLAYER
const LAYER_ENEMY: int = RealmManager.LAYER_ENEMY
const LAYER_HITBOX: int = RealmManager.LAYER_HITBOX

signal hall_mirror_hint_pulsed()

@export var spawn_enemies: bool = true

var _is_built: bool = false
var _hall_mirror_hint_emitted: bool = false


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

	# Perimeter walls for Stage 01
	root.add_child(_make_box_body("Wall_South", Vector3(0.0, 1.5, -5.25), Vector3(12.5, 3.5, 0.5), LAYER_WORLD_SHARED, Color(0.42, 0.37, 0.31)))
	root.add_child(_make_box_body("Wall_West", Vector3(-6.25, 1.5, 0.0), Vector3(0.5, 3.5, 10.5), LAYER_WORLD_SHARED, Color(0.42, 0.37, 0.31)))
	root.add_child(_make_box_body("Wall_East", Vector3(6.25, 1.5, 0.0), Vector3(0.5, 3.5, 10.5), LAYER_WORLD_SHARED, Color(0.42, 0.37, 0.31)))

	# Pit kill zone below Entry Gap (Z = -0.5..2.5)
	root.add_child(_make_pit_kill_zone("PitKillZone_Stage01", Vector3(0.0, -4.5, 1.0), Vector3(8.0, 2.5, 4.0)))

	# Entry section trigger
	root.add_child(_make_section_trigger(
		"Trigger_Stage01_Entry",
		Vector3(0.0, 1.25, -3.0),
		Vector3(5.0, 2.5, 1.5),
		EncounterDirector.Section.ENTRY,
		Vector3(0.0, 0.0, -3.0),
		"",
		0,
		NodePath(),
		false
	))
	return root


func _build_stage_02_hall() -> Node3D:
	var root := Node3D.new()
	root.name = "Stage02_HallOfEchoes"

	root.add_child(_make_box_body("HallFloor", Vector3(0.0, -0.25, 20.0), Vector3(20.0, 0.5, 20.0), LAYER_WORLD_SHARED, Color(0.56, 0.47, 0.37)))
	root.add_child(_make_box_body("Corridor02_Floor", Vector3(0.0, -0.25, 32.0), Vector3(4.0, 0.5, 4.0), LAYER_WORLD_SHARED, Color(0.50, 0.44, 0.35)))

	# Perimeter walls for Stage 02 (20x20m arena)
	root.add_child(_make_box_body("Wall_West", Vector3(-10.25, 1.5, 20.0), Vector3(0.5, 3.5, 20.5), LAYER_WORLD_SHARED, Color(0.42, 0.37, 0.31)))
	root.add_child(_make_box_body("Wall_East", Vector3(10.25, 1.5, 20.0), Vector3(0.5, 3.5, 20.5), LAYER_WORLD_SHARED, Color(0.42, 0.37, 0.31)))

	var pillar := _make_breakable_pillar("CrackedCentralPillar", Vector3(0.0, 0.0, 20.0), BreakableProp.PropKind.CRACKED_PILLAR, 1, 0.60, Vector3(0.0, 0.0, 2.5), 2.5)
	root.add_child(pillar)

	root.add_child(_make_gate("Gate02_HallToGallery", Vector3(0.0, 0.0, 30.0), 1, "hall_of_echoes", false))

	root.add_child(_make_section_trigger(
		"Trigger_Stage02_Hall",
		Vector3(0.0, 1.25, 11.5),
		Vector3(5.0, 2.5, 1.5),
		EncounterDirector.Section.HALL_COMBAT,
		Vector3(0.0, 0.0, 11.5),
		"hall_of_echoes",
		4,
		NodePath("../../Stage01_EntryVestibule/Gate01_EntryToHall"),
		false
	))

	if spawn_enemies:
		var enemies_node := Node3D.new()
		enemies_node.name = "Enemies"
		var skel1 := SkeletonGuard.new()
		_configure_enemy_actor(skel1, "SkeletonGuard_1", "hall_skel_1", Vector3(-6.0, 0.0, 16.0), Color(0.82, 0.76, 0.65))
		skel1.died.connect(_on_hall_skeleton_died)
		enemies_node.add_child(skel1)

		var skel2 := SkeletonGuard.new()
		_configure_enemy_actor(skel2, "SkeletonGuard_2", "hall_skel_2", Vector3(6.0, 0.0, 24.0), Color(0.82, 0.76, 0.65))
		skel2.died.connect(_on_hall_skeleton_died)
		enemies_node.add_child(skel2)

		var phan1 := PhantomTwin.new()
		_configure_enemy_actor(phan1, "PhantomTwin_1", "hall_phantom_1", Vector3(-6.0, 0.0, 26.0), Color(0.25, 0.78, 1.0, 0.85))
		enemies_node.add_child(phan1)

		var phan2 := PhantomTwin.new()
		_configure_enemy_actor(phan2, "PhantomTwin_2", "hall_phantom_2", Vector3(6.0, 0.0, 26.0), Color(0.25, 0.78, 1.0, 0.85))
		enemies_node.add_child(phan2)

		root.add_child(enemies_node)

	return root


func _build_stage_03_gallery() -> Node3D:
	var root := Node3D.new()
	root.name = "Stage03_CollapsedGallery"

	root.add_child(_make_box_body("GalleryFloorSouth", Vector3(0.0, -0.25, 39.0), Vector3(8.0, 0.5, 10.0), LAYER_WORLD_SHARED, Color(0.52, 0.45, 0.36)))
	root.add_child(_make_box_body("GalleryFloorNorth", Vector3(0.0, -0.25, 53.0), Vector3(8.0, 0.5, 10.0), LAYER_WORLD_SHARED, Color(0.52, 0.45, 0.36)))
	root.add_child(_make_box_body("Corridor03_Floor", Vector3(0.0, -0.25, 60.0), Vector3(4.0, 0.5, 4.0), LAYER_WORLD_SHARED, Color(0.50, 0.44, 0.35)))

	# Pit kill zone below Gallery Chasm (Z = 34..58)
	root.add_child(_make_pit_kill_zone("PitKillZone_Stage03", Vector3(0.0, -4.5, 46.0), Vector3(8.0, 2.5, 14.0)))

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

	root.add_child(_make_section_trigger(
		"Trigger_Stage03_Gallery",
		Vector3(0.0, 1.25, 35.5),
		Vector3(4.0, 2.5, 1.5),
		EncounterDirector.Section.COLLAPSED_GALLERY,
		Vector3(0.0, 0.0, 35.5),
		"shielded_guard",
		1,
		NodePath(),
		false
	))

	if spawn_enemies:
		var enemies_node := Node3D.new()
		enemies_node.name = "Enemies"
		var sg := ShieldedGuard.new()
		_configure_enemy_actor(sg, "ShieldedGuard_1", "gallery_shielded_1", Vector3(0.0, 0.0, 56.0), Color(0.75, 0.58, 0.25))
		enemies_node.add_child(sg)
		root.add_child(enemies_node)

	return root


func _build_stage_04_mechanism() -> Node3D:
	var root := Node3D.new()
	root.name = "Stage04_MechanismChamber"

	root.add_child(_make_box_body("ChamberFloor", Vector3(0.0, -0.25, 68.0), Vector3(12.0, 0.5, 12.0), LAYER_WORLD_SHARED, Color(0.54, 0.46, 0.37)))
	root.add_child(_make_box_body("RaisedImpactDais", Vector3(-3.0, 0.675, 67.0), Vector3(2.5, 1.35, 2.5), LAYER_WORLD_SHARED, Color(0.62, 0.54, 0.44)))
	root.add_child(_make_box_body("Corridor04_Floor", Vector3(0.0, -0.25, 75.0), Vector3(4.0, 0.5, 2.0), LAYER_WORLD_SHARED, Color(0.50, 0.44, 0.35)))

	# Perimeter walls for Stage 04
	root.add_child(_make_box_body("Wall_West", Vector3(-6.25, 1.5, 68.0), Vector3(0.5, 3.5, 12.5), LAYER_WORLD_SHARED, Color(0.42, 0.37, 0.31)))
	root.add_child(_make_box_body("Wall_East", Vector3(6.25, 1.5, 68.0), Vector3(0.5, 3.5, 12.5), LAYER_WORLD_SHARED, Color(0.42, 0.37, 0.31)))

	root.add_child(_make_gate("Gate04_MechanismToArena", Vector3(0.0, 0.0, 74.0), 3, "", false))

	root.add_child(_make_section_trigger(
		"Trigger_Stage04_Mechanism",
		Vector3(0.0, 1.25, 63.0),
		Vector3(5.0, 2.5, 1.5),
		EncounterDirector.Section.MECHANISM_CHAMBER,
		Vector3(0.0, 0.0, 63.0),
		"",
		0,
		NodePath(),
		false
	))

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
	hurt.owner_actor_path = NodePath("../..")
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
	root.add_child(_make_box_body("SunlitExitFloor", Vector3(0.0, -0.25, 105.5), Vector3(8.0, 0.5, 7.0), LAYER_WORLD_SHARED, Color(0.85, 0.76, 0.58)))

	# Perimeter containment walls for Execution Arena
	root.add_child(_make_box_body("Wall_West", Vector3(-13.25, 2.0, 89.0), Vector3(0.5, 4.5, 26.5), LAYER_WORLD_SHARED, Color(0.38, 0.33, 0.28)))
	root.add_child(_make_box_body("Wall_East", Vector3(13.25, 2.0, 89.0), Vector3(0.5, 4.5, 26.5), LAYER_WORLD_SHARED, Color(0.38, 0.33, 0.28)))

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

	root.add_child(_make_section_trigger(
		"Trigger_Stage05_Arena",
		Vector3(0.0, 1.25, 77.5),
		Vector3(6.0, 2.5, 1.5),
		EncounterDirector.Section.EXECUTION_ARENA,
		Vector3(0.0, 0.0, 77.5),
		"the_warden",
		1,
		NodePath("../../Stage04_MechanismChamber/Gate04_MechanismToArena"),
		false
	))

	root.add_child(_make_section_trigger(
		"Trigger_RunComplete",
		Vector3(0.0, 1.25, 104.5),
		Vector3(4.0, 2.5, 1.5),
		EncounterDirector.Section.COMPLETE,
		Vector3(0.0, 0.0, 104.5),
		"",
		0,
		NodePath(),
		true
	))

	if spawn_enemies:
		var enemies_node := Node3D.new()
		enemies_node.name = "Enemies"
		var warden := WardenBoss.new()
		_configure_enemy_actor(warden, "TheWarden", "boss_the_warden", Vector3(0.0, 0.0, 88.0), Color(0.32, 0.14, 0.14), Vector3(1.15, 2.3, 1.15))
		warden.mirror_plane_prop_path = NodePath("../../CentralMirrorPlane")
		enemies_node.add_child(warden)
		root.add_child(enemies_node)

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


func _make_pit_kill_zone(node_name: String, pos: Vector3, extents: Vector3) -> PitKillZone:
	var zone := PitKillZone.new()
	zone.name = node_name
	zone.position = pos
	zone.half_extents = extents
	zone.kill_y_threshold = -3.0

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = extents * 2.0
	col.shape = shape
	zone.add_child(col)
	return zone


func _make_section_trigger(
	node_name: String,
	pos: Vector3,
	extents: Vector3,
	sec_id: int,
	checkpoint_pos: Vector3,
	enc_id: String,
	enemy_count: int,
	seal_gate_path: NodePath,
	complete_run: bool
) -> SectionTriggerVolume:
	var trig := SectionTriggerVolume.new()
	trig.name = node_name
	trig.position = pos
	trig.half_extents = extents
	trig.target_section = sec_id
	trig.checkpoint_spawn_position = checkpoint_pos
	trig.encounter_id = enc_id
	trig.encounter_enemy_count = enemy_count
	trig.entry_gate_to_seal_path = seal_gate_path
	trig.complete_run_on_enter = complete_run

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = extents * 2.0
	col.shape = shape
	trig.add_child(col)
	return trig


func _configure_enemy_actor(
	enemy: EnemyBase,
	node_name: String,
	unique_id: String,
	pos: Vector3,
	color: Color,
	body_size: Vector3 = Vector3(0.8, 1.8, 0.8)
) -> void:
	enemy.name = node_name
	enemy.enemy_id = unique_id
	enemy.position = pos
	enemy.collision_layer = LAYER_ENEMY
	enemy.collision_mask = LAYER_WORLD_SHARED | LAYER_WORLD_REALITY | LAYER_WORLD_MIRROR

	var bcol := CollisionShape3D.new()
	bcol.name = "BodyCollider"
	var cap := CapsuleShape3D.new()
	cap.radius = body_size.x * 0.5
	cap.height = body_size.y
	bcol.shape = cap
	bcol.position = Vector3(0.0, body_size.y * 0.5, 0.0)
	enemy.add_child(bcol)

	var vis_root := Node3D.new()
	vis_root.name = "VisualRoot"
	var mesh := _make_mesh_box("ProxyMesh", body_size, color)
	mesh.position = Vector3(0.0, body_size.y * 0.5, 0.0)
	vis_root.add_child(mesh)
	enemy.add_child(vis_root)

	var hurt := Hurtbox3D.new()
	hurt.name = "Hurtbox3D"
	hurt.owner_actor_path = NodePath("..")
	hurt.is_enemy_hurtbox = true
	hurt.collision_layer = LAYER_ENEMY | LAYER_HITBOX
	hurt.collision_mask = LAYER_HITBOX
	var hcol := CollisionShape3D.new()
	var hshape := BoxShape3D.new()
	hshape.size = body_size * 1.15
	hcol.shape = hshape
	hcol.position = Vector3(0.0, body_size.y * 0.5, 0.0)
	hurt.add_child(hcol)
	enemy.add_child(hurt)

	var atk := Hitbox3D.new()
	atk.name = "AttackHitbox"
	atk.owner_actor_path = NodePath("..")
	atk.affects_player = true
	atk.affects_enemies = false
	atk.affects_breakables = false
	atk.collision_layer = LAYER_HITBOX
	atk.collision_mask = LAYER_PLAYER | LAYER_HITBOX
	var acol := CollisionShape3D.new()
	var ashape := BoxShape3D.new()
	ashape.size = Vector3(1.6, 1.4, 1.8)
	acol.shape = ashape
	acol.position = Vector3(0.0, body_size.y * 0.5, -1.0)
	atk.add_child(acol)
	enemy.add_child(atk)


func _on_hall_skeleton_died(_enemy: EnemyBase, _context: Dictionary) -> void:
	if not _hall_mirror_hint_emitted:
		_hall_mirror_hint_emitted = true
		hall_mirror_hint_pulsed.emit()
