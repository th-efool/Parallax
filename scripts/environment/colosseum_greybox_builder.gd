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

const STONE_SHADER_PATH: String = "res://assets/shaders/realm_stone.gdshader"
const SPECTRAL_SHADER_PATH: String = "res://assets/shaders/mirror_spectral.gdshader"
const OBSIDIAN_SHADER_PATH: String = "res://assets/shaders/mirror_obsidian.gdshader"
const DUNGEON_DIR: String = "res://assets/models/dungeon/"
const RealmTorchLightScript := preload("res://scripts/environment/realm_torch_light.gd")
const REALM_BLEND_DURATION: float = 0.20

signal hall_mirror_hint_pulsed()

@export var spawn_enemies: bool = true
## Claude Pass B: purely cosmetic KayKit props, torches, banners & ambient particles (no colliders).
@export var dress_environment: bool = true

var _is_built: bool = false
var _hall_mirror_hint_emitted: bool = false
var _stone_mat_cache: Dictionary = {}
var _spectral_mat_cache: Dictionary = {}
var _mirror_plane_mat: ShaderMaterial = null
var _model_cache: Dictionary = {}
var _realm_blend: float = 0.0
var _realm_blend_tween: Tween = null


func _ready() -> void:
	build_greybox()
	_bind_realm_visuals()


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

	if dress_environment:
		_dress_environment()


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
	var plate_mesh := _make_mesh_box("PlateMesh", Vector3(1.6, 0.14, 1.6), Color(0.85, 0.65, 0.25), "plain")
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
	var plane_mesh := _make_mesh_box("MirrorPlaneMesh", Vector3(0.12, 5.5, 22.0), Color(0.25, 0.72, 1.0, 0.35), "plain")
	plane_mesh.position = Vector3(0.0, 2.75, 0.0)
	var obsidian: ShaderMaterial = _get_mirror_plane_material()
	if obsidian != null:
		plane_mesh.material_override = obsidian
	plane_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	intact_vis.add_child(plane_mesh)
	mirror_plane.add_child(intact_vis)
	mirror_plane.shatter_extent = Vector3(0.12, 5.5, 22.0)
	mirror_plane.shatter_center_offset = Vector3(0.0, 2.75, 0.0)
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
		warden.health_changed.connect(_on_warden_health_changed)
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


func _make_mesh_box(node_name: String, box_size: Vector3, color: Color, surface: String = "auto") -> MeshInstance3D:
	## surface: "auto" (opaque -> realm stone, translucent -> mirror spectral), "stone", "spectral", "plain".
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = box_size
	mesh.material = _material_for_surface(color, surface)
	mi.mesh = mesh
	return mi


func _material_for_surface(color: Color, surface: String) -> Material:
	var kind: String = surface
	if kind == "auto":
		kind = "spectral" if color.a < 0.99 else "stone"
	if kind == "stone":
		var sm: ShaderMaterial = _get_stone_material(color)
		if sm != null:
			return sm
	elif kind == "spectral":
		var sp: ShaderMaterial = _get_spectral_material(color)
		if sp != null:
			return sp
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if color.a < 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


func _get_stone_material(color: Color) -> ShaderMaterial:
	var key: String = color.to_html(false)
	if _stone_mat_cache.has(key):
		return _stone_mat_cache[key] as ShaderMaterial
	if not ResourceLoader.exists(STONE_SHADER_PATH):
		return null
	var sh: Shader = load(STONE_SHADER_PATH) as Shader
	if sh == null:
		return null
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("reality_tint", color.lightened(0.18))
	var lum: float = clampf(color.get_luminance() * 1.6, 0.6, 1.3)
	m.set_shader_parameter("mirror_tint", Color(0.10 * lum, 0.14 * lum, 0.23 * lum, 1.0))
	m.set_shader_parameter("mirror_blend", _realm_blend)
	_stone_mat_cache[key] = m
	return m


func _get_spectral_material(color: Color) -> ShaderMaterial:
	var key: String = color.to_html(true)
	if _spectral_mat_cache.has(key):
		return _spectral_mat_cache[key] as ShaderMaterial
	if not ResourceLoader.exists(SPECTRAL_SHADER_PATH):
		return null
	var sh: Shader = load(SPECTRAL_SHADER_PATH) as Shader
	if sh == null:
		return null
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("base_tint", Color(color.r * 0.35, color.g * 0.45, color.b * 0.6, clampf(color.a * 0.75, 0.35, 0.9)))
	m.set_shader_parameter("rim_color", Color(0.25, 0.78, 1.0, 1.0))
	m.set_shader_parameter("min_alpha", 0.35)
	_spectral_mat_cache[key] = m
	return m


func _get_mirror_plane_material() -> ShaderMaterial:
	if _mirror_plane_mat != null:
		return _mirror_plane_mat
	if not ResourceLoader.exists(OBSIDIAN_SHADER_PATH):
		return null
	var sh: Shader = load(OBSIDIAN_SHADER_PATH) as Shader
	if sh == null:
		return null
	_mirror_plane_mat = ShaderMaterial.new()
	_mirror_plane_mat.shader = sh
	_mirror_plane_mat.set_shader_parameter("crack_amount", 0.0)
	return _mirror_plane_mat


func _on_warden_health_changed(current_hp: int, max_hp: int) -> void:
	if _mirror_plane_mat == null:
		return
	# Cracks spread from full HP down to the 50% Phase-2 shatter threshold.
	var half: float = float(maxi(1, max_hp)) * 0.5
	var crack: float = clampf((float(max_hp) - float(current_hp)) / half, 0.0, 1.0)
	_mirror_plane_mat.set_shader_parameter("crack_amount", crack)


# --- Realm visual blend (stone shader `mirror_blend`) ---

func _bind_realm_visuals() -> void:
	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm == null:
		_apply_realm_blend(0.0)
		return
	if not rm.realm_changed.is_connected(_on_realm_visual_changed):
		rm.realm_changed.connect(_on_realm_visual_changed)
	if not rm.realms_merged.is_connected(_on_realms_visual_merged):
		rm.realms_merged.connect(_on_realms_visual_merged)
	_apply_realm_blend(_target_blend_for(int(rm.current_realm), rm.is_merged))


func _target_blend_for(realm: int, merged: bool) -> float:
	if merged:
		return 0.5
	return 1.0 if realm == RealmManager.Realm.MIRROR else 0.0


func _on_realm_visual_changed(new_realm: int) -> void:
	var merged: bool = RealmManager.instance != null and bool(RealmManager.instance.is_merged)
	_tween_realm_blend(_target_blend_for(new_realm, merged))


func _on_realms_visual_merged() -> void:
	_tween_realm_blend(0.5)


func _tween_realm_blend(target: float) -> void:
	if _realm_blend_tween != null and _realm_blend_tween.is_valid():
		_realm_blend_tween.kill()
	if not is_inside_tree():
		_apply_realm_blend(target)
		return
	_realm_blend_tween = create_tween()
	_realm_blend_tween.tween_method(_apply_realm_blend, _realm_blend, target, REALM_BLEND_DURATION)


func _apply_realm_blend(value: float) -> void:
	_realm_blend = value
	for key in _stone_mat_cache:
		var m: ShaderMaterial = _stone_mat_cache[key] as ShaderMaterial
		if m != null:
			m.set_shader_parameter("mirror_blend", value)


func get_realm_blend() -> float:
	return _realm_blend


func _make_gate(node_name: String, pos: Vector3, sec_id: int, encounter_id: String, starts_open_flag: bool) -> EncounterGate:
	var gate := EncounterGate.new()
	gate.name = node_name
	gate.position = pos
	gate.section_id = sec_id
	gate.linked_encounter_id = encounter_id
	gate.starts_open = starts_open_flag
	gate.gate_mesh_path = NodePath("GateMesh")

	var mesh := _make_mesh_box("GateMesh", Vector3(4.0, 3.0, 0.35), Color(0.75, 0.32, 0.18), "plain")
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

	var plinth := _make_mesh_box("SwitchPlinth", Vector3(0.7, 1.2, 0.7), Color(0.25, 0.78, 1.0), "plain")
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
	var stone: ShaderMaterial = _get_stone_material(Color(0.62, 0.55, 0.45))
	if stone != null:
		cyl.material_override = stone
	intact.add_child(cyl)

	# Glowing amber fracture seam on the approach (south, -Z) face marks the Heavy-attack weak point.
	var seam := MeshInstance3D.new()
	seam.name = "FractureSeam"
	var seam_mesh := BoxMesh.new()
	seam_mesh.size = Vector3(0.10, 2.2, 0.06)
	seam.mesh = seam_mesh
	var seam_mat := StandardMaterial3D.new()
	seam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	seam_mat.albedo_color = Color(1.0, 0.62, 0.20)
	seam_mat.emission_enabled = true
	seam_mat.emission = Color(1.0, 0.55, 0.15)
	seam_mat.emission_energy_multiplier = 2.5
	seam.material_override = seam_mat
	seam.position = Vector3(0.0, 1.6, -0.68)
	seam.rotation.z = deg_to_rad(8.0)
	intact.add_child(seam)
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
	var model_path: String = "res://assets/models/characters/Skeleton_Warrior.glb"
	var model_scale: Vector3 = Vector3.ONE
	var archetype: EnemyArchetype = (enemy as ArchetypeEnemy).archetype if enemy is ArchetypeEnemy else null
	if archetype != null:
		model_path = archetype.model_path
		model_scale = Vector3.ONE * archetype.model_scale
	elif enemy is ShieldedGuard:
		model_path = "res://assets/models/characters/Knight.glb"
		model_scale = Vector3(1.06, 1.06, 1.06)
	elif enemy is WardenBoss:
		model_path = "res://assets/models/characters/Barbarian.glb"
		model_scale = Vector3(1.42, 1.42, 1.42)
	elif node_name.ends_with("_2") and not (enemy is PhantomTwin):
		model_path = "res://assets/models/characters/Skeleton_Rogue.glb"

	var model_added: bool = false
	if ResourceLoader.exists(model_path):
		var packed: PackedScene = load(model_path) as PackedScene
		if packed != null:
			var model_inst: Node3D = packed.instantiate() as Node3D
			if model_inst != null:
				model_inst.name = "ModelRoot"
				model_inst.transform = Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3.ZERO)
				model_inst.scale = model_scale
				vis_root.add_child(model_inst)
				model_added = true

	if not model_added:
		var mesh := _make_mesh_box("ProxyMesh", body_size, color, "spectral" if color.a < 0.99 else "plain")
		mesh.position = Vector3(0.0, body_size.y * 0.5, 0.0)
		vis_root.add_child(mesh)
	enemy.add_child(vis_root)

	var anim_bridge := CharacterAnimationBridge.new()
	anim_bridge.name = "CharacterAnimationBridge"
	anim_bridge.actor_path = NodePath("..")
	anim_bridge.model_root_path = NodePath("../VisualRoot/ModelRoot")
	anim_bridge.apply_spectral_shader = (enemy is PhantomTwin)
	# Archetype rigs get their loadout from data (ArchetypeEnemy._dress_model), not the default trim.
	anim_bridge.apply_default_loadout = archetype == null
	enemy.add_child(anim_bridge)

	_attach_enemy_hp_bar(enemy, body_size.y + 0.55)

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


func _attach_enemy_hp_bar(enemy: EnemyBase, height_offset: float) -> void:
	var lbl := Label3D.new()
	lbl.name = "FloatingHPBar"
	lbl.position = Vector3(0.0, height_offset, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.pixel_size = 0.0085
	lbl.font_size = 24
	lbl.outline_size = 6
	lbl.outline_modulate = Color(0.05, 0.05, 0.08, 0.95)
	lbl.modulate = Color(0.28, 0.85, 1.0, 0.95) if (enemy is PhantomTwin) else Color(0.95, 0.30, 0.25, 0.95)
	if enemy is ArchetypeEnemy and (enemy as ArchetypeEnemy).archetype != null:
		lbl.modulate = (enemy as ArchetypeEnemy).archetype.hp_bar_color
	enemy.add_child(lbl)

	var update_fn := func(cur_hp: int, m_hp: int) -> void:
		if not is_instance_valid(lbl):
			return
		var ratio: float = clampf(float(cur_hp) / float(maxi(1, m_hp)), 0.0, 1.0)
		var filled: int = int(round(ratio * 10.0))
		var bar_str: String = "█".repeat(filled) + "░".repeat(10 - filled)
		lbl.text = "%s  %d/%d" % [bar_str, cur_hp, m_hp]
		lbl.visible = cur_hp > 0

	enemy.health_changed.connect(update_fn)
	update_fn.call(enemy.health, enemy.max_health)


# =====================================================================================================
# Claude Pass B — Environmental art dressing (cosmetic only: every instanced model has its colliders
# stripped, so gameplay collision stays exactly as authored above / in MEMORY/04).
# Layout per stage: Shared (walls, columns, lights, scatter), RealityDressing (torches, red sun banners,
# dust motes) and MirrorDressing (cobalt crystal sconces, blue moon banners, glass flecks), the latter two
# gated by a RealmReactive child (Golden Collision Rule for Mirror-only cosmetics).
# =====================================================================================================

func _dress_environment() -> void:
	var root := Node3D.new()
	root.name = "EnvironmentDressing"
	add_child(root)

	var side_t2: Array[float] = [0.25, 0.75]
	var side_t3: Array[float] = [1.0 / 6.0, 0.5, 5.0 / 6.0]
	var banner_t1: Array[float] = [0.5]
	var banner_t2: Array[float] = [1.0 / 3.0, 2.0 / 3.0]

	# Stage 01 — Entry Vestibule
	_dress_stage(root, "Stage01_Dressing", [
		[Vector3(-6.0, 0.0, -5.0), Vector3(6.0, 0.0, -5.0), Vector3(0.0, 0.0, 1.0)],
		[Vector3(-6.0, 0.0, -5.0), Vector3(-6.0, 0.0, 5.25), Vector3(1.0, 0.0, 0.0)],
		[Vector3(6.0, 0.0, -5.0), Vector3(6.0, 0.0, 5.25), Vector3(-1.0, 0.0, 0.0)],
	], 3.5, ["wall_arched.gltf.glb", "wall.gltf.glb", "wall_pillar.gltf.glb"], side_t2, banner_t1, 1.0,
	Vector3(0.0, 2.0, 0.0), Vector3(6.0, 2.0, 5.0), [
		["barrel_large.gltf.glb", Vector3(-5.2, 0.0, -4.2), 1.0],
		["box_large.gltf.glb", Vector3(5.2, 0.0, -4.3), 0.9],
	])

	# Stage 02 — Hall of Echoes
	_dress_stage(root, "Stage02_Dressing", [
		[Vector3(-10.0, 0.0, 10.0), Vector3(-10.0, 0.0, 30.0), Vector3(1.0, 0.0, 0.0)],
		[Vector3(10.0, 0.0, 10.0), Vector3(10.0, 0.0, 30.0), Vector3(-1.0, 0.0, 0.0)],
	], 3.5, ["wall_pillar.gltf.glb", "wall.gltf.glb", "wall_cracked.gltf.glb", "wall.gltf.glb"], side_t2, banner_t1, 1.0,
	Vector3(0.0, 2.5, 20.0), Vector3(10.0, 2.5, 10.0), [
		["pillar_decorated.gltf.glb", Vector3(-8.6, 0.0, 11.4), 3.6],
		["pillar_decorated.gltf.glb", Vector3(8.6, 0.0, 11.4), 3.6],
		["pillar_decorated.gltf.glb", Vector3(-8.6, 0.0, 28.6), 3.6],
		["pillar_decorated.gltf.glb", Vector3(8.6, 0.0, 28.6), 3.6],
		["barrel_large.gltf.glb", Vector3(-9.1, 0.0, 13.0), 1.1],
		["barrel_large.gltf.glb", Vector3(-9.2, 0.0, 14.1), 1.0],
		["box_large.gltf.glb", Vector3(9.1, 0.0, 26.8), 1.0],
		["rubble_large.gltf.glb", Vector3(8.9, 0.0, 13.2), 0.8],
	])

	# Stage 03 — Collapsed Gallery (open chasm: no wall runs, broken columns along the floor edges)
	var none_t: Array[float] = []
	_dress_stage(root, "Stage03_Dressing", [], 3.0, [], none_t, none_t, 1.0,
	Vector3(0.0, 2.0, 46.0), Vector3(4.0, 2.0, 12.0), [
		["pillar.gltf.glb", Vector3(-3.5, 0.0, 34.8), 3.0],
		["pillar.gltf.glb", Vector3(3.5, 0.0, 34.8), 3.0],
		["pillar.gltf.glb", Vector3(-3.5, 0.0, 43.2), 2.2],
		["pillar.gltf.glb", Vector3(3.5, 0.0, 43.2), 3.0],
		["pillar.gltf.glb", Vector3(-3.5, 0.0, 48.8), 3.0],
		["pillar.gltf.glb", Vector3(3.5, 0.0, 48.8), 2.4],
		["pillar.gltf.glb", Vector3(-3.5, 0.0, 57.2), 3.0],
		["pillar.gltf.glb", Vector3(3.5, 0.0, 57.2), 3.0],
		["rubble_large.gltf.glb", Vector3(-3.0, 0.0, 43.4), 0.6],
		["rubble_large.gltf.glb", Vector3(2.9, 0.0, 48.6), 0.6],
	])

	# Stage 04 — Mechanism Chamber
	_dress_stage(root, "Stage04_Dressing", [
		[Vector3(-6.0, 0.0, 62.0), Vector3(-6.0, 0.0, 74.0), Vector3(1.0, 0.0, 0.0)],
		[Vector3(6.0, 0.0, 62.0), Vector3(6.0, 0.0, 74.0), Vector3(-1.0, 0.0, 0.0)],
	], 3.5, ["wall.gltf.glb", "wall_gated.gltf.glb", "wall.gltf.glb"], side_t2, banner_t1, 1.0,
	Vector3(0.0, 2.0, 68.0), Vector3(6.0, 2.0, 6.0), [
		["barrel_large.gltf.glb", Vector3(5.1, 0.0, 72.9), 1.0],
		["box_large.gltf.glb", Vector3(-5.1, 0.0, 63.2), 1.0],
		["box_large.gltf.glb", Vector3(-5.2, 0.0, 64.3), 0.8],
	])

	# Stage 05 — Execution Arena
	_dress_stage(root, "Stage05_Dressing", [
		[Vector3(-13.0, 0.0, 76.0), Vector3(-13.0, 0.0, 102.0), Vector3(1.0, 0.0, 0.0)],
		[Vector3(13.0, 0.0, 76.0), Vector3(13.0, 0.0, 102.0), Vector3(-1.0, 0.0, 0.0)],
	], 4.5, ["wall_arched.gltf.glb", "wall_pillar.gltf.glb", "wall_broken.gltf.glb", "wall_pillar.gltf.glb"], side_t3, banner_t2, 1.4,
	Vector3(0.0, 3.0, 89.0), Vector3(13.0, 3.0, 13.0), [
		["pillar_decorated.gltf.glb", Vector3(-11.6, 0.0, 80.0), 4.8],
		["pillar_decorated.gltf.glb", Vector3(-11.6, 0.0, 88.0), 4.8],
		["pillar_decorated.gltf.glb", Vector3(-11.6, 0.0, 96.0), 4.8],
		["pillar_decorated.gltf.glb", Vector3(11.6, 0.0, 80.0), 4.8],
		["pillar_decorated.gltf.glb", Vector3(11.6, 0.0, 88.0), 4.8],
		["pillar_decorated.gltf.glb", Vector3(11.6, 0.0, 96.0), 4.8],
		["rubble_large.gltf.glb", Vector3(-11.4, 0.0, 100.6), 0.9],
		["rubble_large.gltf.glb", Vector3(11.3, 0.0, 77.6), 0.9],
		["box_large.gltf.glb", Vector3(-11.9, 0.0, 77.4), 1.0],
	])


func _dress_stage(
	parent: Node3D,
	stage_name: String,
	wall_runs: Array,
	wall_height: float,
	wall_variants: Array,
	torch_t: Array[float],
	banner_t: Array[float],
	banner_bottom: float,
	ambient_center: Vector3,
	ambient_extents: Vector3,
	props: Array
) -> void:
	var stage := Node3D.new()
	stage.name = stage_name
	parent.add_child(stage)
	var shared: Node3D = _make_realm_group(stage, "Shared", -1)
	var reality: Node3D = _make_realm_group(stage, "RealityDressing", RealmReactive.Affinity.REALITY_ONLY)
	var mirror: Node3D = _make_realm_group(stage, "MirrorDressing", RealmReactive.Affinity.MIRROR_ONLY)

	var variants: Array[String] = []
	for v in wall_variants:
		variants.append(String(v))

	for run in wall_runs:
		var start: Vector3 = run[0]
		var end: Vector3 = run[1]
		var inward: Vector3 = run[2]
		if not variants.is_empty():
			_dress_wall_run(shared, start, end, inward, wall_height, variants)
		if absf(inward.x) < 0.5:
			continue # torches/banners only on the long side walls
		for t in torch_t:
			_place_wall_torch(shared, reality, mirror, start.lerp(end, t), inward)
		for t in banner_t:
			var bp: Vector3 = start.lerp(end, t) + Vector3(0.0, banner_bottom, 0.0)
			var yaw: float = rad_to_deg(atan2(inward.x, inward.z))
			_place_model(reality, "banner_red.gltf.glb", bp, yaw, 2.6, inward)
			_place_model(mirror, "banner_blue.gltf.glb", bp, yaw, 2.6, inward)

	for prop in props:
		var file: String = String(prop[0])
		var pos: Vector3 = prop[1]
		var h: float = float(prop[2])
		var yaw_hash: float = fmod(absf(pos.x * 37.0 + pos.z * 11.0), 360.0)
		_place_model(shared, file, pos, yaw_hash, h)

	reality.add_child(_make_ambient_particles(ambient_center, ambient_extents, false))
	mirror.add_child(_make_ambient_particles(ambient_center, ambient_extents, true))


func _make_realm_group(parent: Node3D, group_name: String, affinity: int) -> Node3D:
	var g := Node3D.new()
	g.name = group_name
	if affinity >= 0:
		var rr := RealmReactive.new()
		rr.name = "RealmReactive"
		rr.realm_affinity = affinity as RealmReactive.Affinity
		rr.target_node_path = NodePath("..")
		rr.manage_collisions = false
		g.add_child(rr)
	parent.add_child(g)
	return g


func _place_wall_torch(shared: Node3D, reality: Node3D, mirror: Node3D, wall_point: Vector3, inward: Vector3) -> void:
	var yaw: float = rad_to_deg(atan2(inward.x, inward.z))
	var mount: Vector3 = wall_point + Vector3(0.0, 1.75, 0.0)
	_place_model(reality, "torch_lit.gltf.glb", mount, yaw, 0.9, inward)

	# Mirror counterpart: cold cobalt crystal sconce.
	var crystal := MeshInstance3D.new()
	crystal.name = "CrystalSconce"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.11
	cm.height = 0.42
	cm.radial_segments = 6
	cm.rings = 1
	crystal.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.albedo_color = Color(0.45, 0.78, 1.0)
	cmat.emission_enabled = true
	cmat.emission = Color(0.3, 0.65, 1.0)
	cmat.emission_energy_multiplier = 3.0
	crystal.material_override = cmat
	crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crystal.position = mount + inward.normalized() * 0.22 + Vector3(0.0, 0.45, 0.0)
	mirror.add_child(crystal)

	var light: OmniLight3D = RealmTorchLightScript.new() as OmniLight3D
	light.name = "TorchLight"
	light.omni_range = 7.5
	light.omni_attenuation = 1.4
	light.position = mount + inward.normalized() * 0.45 + Vector3(0.0, 0.6, 0.0)
	shared.add_child(light)


func _dress_wall_run(parent: Node3D, start: Vector3, end: Vector3, inward: Vector3, height: float, variants: Array[String]) -> void:
	var run: Vector3 = end - start
	var length: float = run.length()
	if length < 0.5 or variants.is_empty():
		return
	var dir: Vector3 = run / length
	var probe: Node3D = _instance_dungeon_model(variants[0])
	if probe == null:
		return
	var pa: AABB = _compute_local_aabb(probe)
	probe.free()
	if pa.size.y <= 0.001:
		return
	var module_len: float = maxf(pa.size.x, pa.size.z) * (height / pa.size.y)
	var count: int = maxi(1, int(round(length / maxf(0.5, module_len))))
	var seg: float = length / float(count)
	for i in range(count):
		var file: String = variants[i % variants.size()]
		var center: Vector3 = start + dir * (seg * (float(i) + 0.5))
		_place_model(parent, file, center, 0.0, height, inward, dir, seg)


func _place_model(
	parent: Node3D,
	file_name: String,
	pos: Vector3,
	yaw_deg: float = 0.0,
	fit_height: float = -1.0,
	wall_inward: Vector3 = Vector3.ZERO,
	align_dir: Vector3 = Vector3.ZERO,
	stretch_long_to: float = -1.0
) -> Node3D:
	## Instances a KayKit dungeon model, scales it to `fit_height`, rests its AABB bottom on `pos.y`, centres it
	## on `pos.xz`, optionally aligns its long axis with `align_dir` (stretching to `stretch_long_to`), and
	## optionally pushes it off a wall face along `wall_inward` so its back sits flush against the wall.
	var inst: Node3D = _instance_dungeon_model(file_name)
	if inst == null:
		return null
	var aabb: AABB = _compute_local_aabb(inst)
	var s: float = 1.0
	if fit_height > 0.0 and aabb.size.y > 0.001:
		s = fit_height / aabb.size.y
	var sc := Vector3(s, s, s)
	var long_is_x: bool = aabb.size.x >= aabb.size.z
	if stretch_long_to > 0.0:
		var cur_len: float = (aabb.size.x if long_is_x else aabb.size.z) * s
		if cur_len > 0.001:
			var k: float = stretch_long_to / cur_len
			if long_is_x:
				sc.x *= k
			else:
				sc.z *= k
	var yaw: float = deg_to_rad(yaw_deg)
	if align_dir.length_squared() > 0.0001:
		yaw = atan2(-align_dir.z, align_dir.x) if long_is_x else atan2(align_dir.x, align_dir.z)
	inst.scale = sc
	inst.rotation = Vector3(0.0, yaw, 0.0)
	parent.add_child(inst)

	var placed: AABB = Transform3D(inst.transform.basis, Vector3.ZERO) * aabb
	var c: Vector3 = placed.get_center()
	var p: Vector3 = pos - Vector3(c.x, placed.position.y, c.z)
	if wall_inward.length_squared() > 0.0001:
		var n: Vector3 = wall_inward.normalized()
		var thick: float = absf(placed.size.x * n.x) + absf(placed.size.z * n.z)
		p += n * (thick * 0.5 + 0.02)
	inst.position = p
	return inst


func _instance_dungeon_model(file_name: String) -> Node3D:
	var path: String = DUNGEON_DIR + file_name
	var packed: PackedScene = null
	if _model_cache.has(path):
		packed = _model_cache[path] as PackedScene
	elif ResourceLoader.exists(path):
		packed = load(path) as PackedScene
		_model_cache[path] = packed
	if packed == null:
		return null
	var inst: Node3D = packed.instantiate() as Node3D
	if inst == null:
		return null
	inst.name = file_name.get_basename().get_basename().to_pascal_case()
	_strip_model_collisions(inst)
	return inst


func _strip_model_collisions(node: Node) -> void:
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	for child in node.get_children():
		_strip_model_collisions(child)


func _compute_local_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var has_any: bool = false
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var n: Node = item[0]
		var xf: Transform3D = item[1]
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var box: AABB = xf * (n as MeshInstance3D).mesh.get_aabb()
			result = box if not has_any else result.merge(box)
			has_any = true
		for child in n.get_children():
			if child is Node3D:
				stack.append([child, xf * (child as Node3D).transform])
	return result


func _make_ambient_particles(center: Vector3, extents: Vector3, mirror_style: bool) -> GPUParticles3D:
	## Reality: warm dry dust motes drifting down. Mirror: cobalt glass flecks floating up and glinting.
	var p := GPUParticles3D.new()
	p.name = "GlassFlecks" if mirror_style else "DustMotes"
	p.amount = clampi(int(extents.x * extents.z * 0.9), 40, 160)
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.randomness = 0.5
	p.position = center
	p.visibility_aabb = AABB(-extents - Vector3.ONE, (extents + Vector3.ONE) * 2.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3(0.2, 1.0, 0.1)
	pm.spread = 70.0
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.12
	pm.gravity = Vector3(0.0, 0.05, 0.0) if mirror_style else Vector3(0.0, -0.025, 0.0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.08
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	var base: Color = Color(0.55, 0.82, 1.0, 0.9) if mirror_style else Color(1.0, 0.86, 0.62, 0.35)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	grad.colors = PackedColorArray([
		Color(base.r, base.g, base.b, 0.0), base, base, Color(base.r, base.g, base.b, 0.0)
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_ramp = ramp
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06) if mirror_style else Vector2(0.035, 0.035)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if mirror_style else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	p.draw_pass_1 = quad
	return p
