class_name GrandJourneyBuilder
extends ColosseumGreyboxBuilder
## "The Ascent" — the Grand Journey level (replaces the flat greybox layout).
## A cliff-top pilgrimage climbing north (+Z) and upward through the five locked GDD gameplay beats:
##   Prologue  Pilgrim's Causeway (Y 0)  ->  01 Gate of Reflections (Y 0, gameplay core unchanged)
##   Sunlit Stair  ->  02 Hall of Echoes (Y 4)  ->  Windswept Rampart  ->  03 Aqueduct Gallery (Y 6)
##   ->  04 Clock-Tower Mechanism Chamber (Y 6)  ->  Processional Stair  ->  05 Mirror Colosseum (Y 10)
##   ->  Sunset Summit (run complete).
## Gameplay node NAMES under each Stage root are kept identical to the greybox (save system + MainController
## look them up). Every puzzle keeps its proven internal dimensions; only placement/elevation changed.
## Visuals: world-space triplanar PBR (Poly Haven CC0) via realm_pbr.gdshader, procedural architecture
## (ProcMeshKit), MultiMesh-batched repeats, distance-faded lights, and a realm-reactive sky.

const ProcMesh := preload("res://scripts/environment/procedural_mesh_kit.gd")
const PBR_DIR: String = "res://assets/textures/pbr/"
const REALM_PBR_SHADER: String = "res://assets/shaders/realm_pbr.gdshader"
const SKY_SHADER: String = "res://assets/shaders/journey_sky.gdshader"
const SKY_HDRI: String = "res://assets/sky/kloppenheim_06_puresky_4k.hdr"
const CLOUD_SHADER: String = "res://assets/shaders/cloud_sea.gdshader"
const BANNER_SHADER: String = "res://assets/shaders/banner_cloth.gdshader"
const KNIGHT_MODEL: String = "res://assets/models/characters/Knight.glb"
## Roamer kind -> data-driven EnemyArchetype resource.
const ARCHETYPE_PATHS: Dictionary = {
	"hexcaster": "res://data/enemies/hollow_hexcaster.tres",
	"brute": "res://data/enemies/grave_brute.tres",
	"stalker": "res://data/enemies/shade_stalker.tres",
}

const Y_HALL: float = 4.0
const Y_GALLERY: float = 6.0
const Y_ARENA: float = 10.0
const ARENA_CENTER: Vector3 = Vector3(0.0, 10.0, 154.0)

## Horizontal direction toward the sun (ahead-left of the northward route) and the light's elevation.
const SUN_HEADING: Vector3 = Vector3(-0.65, 0.0, 0.76)
const SUN_LIGHT_ELEVATION_DEG: float = 20.0
## Where the sun sits inside the HDRI panorama (measured: u = 0.6069, elevation 8.26 deg).
const HDRI_SUN_U: float = 0.6069

@export var configure_atmosphere: bool = true
## Merge static decor meshes (draw-call reduction). Disable only for geometry audits / debugging.
@export var enable_static_batching: bool = true

var _pbr_cache: Dictionary = {}
var _std_cache: Dictionary = {}
## Environmental set dressing & realm storytelling pass (JourneySetDressing). Off = bare architecture.
@export var enable_set_dressing: bool = true
var _scenery: Node3D = null
var _decor: Node3D = null
var _anim_tweens: Array[Tween] = []
var _parapet_count: int = 0


# =====================================================================================================
# Entry points
# =====================================================================================================

## Emitted during build_greybox_progressive(): fraction 0..1 and the step being built.
signal build_progress(fraction: float, label: String)


func _init() -> void:
	# The journey is built by MainController under the loading screen (not during scene load).
	build_on_ready = false


func _ready() -> void:
	super._ready()
	if configure_atmosphere:
		call_deferred("_configure_atmosphere")


## One entry per build step: [label, Callable]. Shared by the synchronous and the progressive build.
func _build_steps() -> Array:
	return [
		["Stepping through the mirror", _step_containers],
		["Raising the Sundering Entry", func() -> void: add_child(_build_stage_01_entry())],
		["Building the Hall of Echoes", func() -> void: add_child(_build_stage_02_hall())],
		["Laying the Collapsed Gallery", func() -> void: add_child(_build_stage_03_gallery())],
		["Assembling the Mechanism", func() -> void: add_child(_build_stage_04_mechanism())],
		["Raising the Execution Arena", func() -> void: add_child(_build_stage_05_arena())],
		["Spanning the winding bridges", func() -> void: add_child(_build_routes())],
		["Hanging the banners", func() -> void: add_child(_decor)],
		["Dressing the ruins", _step_dressing],
		["Planting the scenery", _step_scenery],
		["Placing shadow casters", func() -> void: _build_occluders()],
		["Batching meshes", _step_batch],
	]


func _step_containers() -> void:
	_scenery = Node3D.new()
	_scenery.name = "Scenery"
	_decor = Node3D.new()
	_decor.name = "Decor"


func _step_dressing() -> void:
	# Environmental set dressing & realm storytelling (see JourneySetDressing for the art direction).
	if enable_set_dressing:
		(load("res://scripts/environment/journey_set_dressing.gd") as GDScript).new(self).call("build")
		# The dressing is authored in story coordinates: move it onto the stretched layout (JourneyLayout).
		for dz in _decor.get_children():
			if String(dz.name).begins_with("Dress_"):
				JourneyLayout.remap_subtree(dz)


func _step_scenery() -> void:
	add_child(_scenery)
	_build_world_scenery()


func _step_batch() -> void:
	if enable_static_batching:
		var merged: int = _static_batch(self)
		print_verbose("[GrandJourney] static-batched %d meshes" % merged)


## Synchronous build (tools / headless). Same steps as the progressive build.
func build_greybox() -> void:
	if _is_built:
		return
	_is_built = true
	for step in _build_steps():
		(step[1] as Callable).call()


## Builds one step per frame and reports progress, so the loading screen can animate and the game stays responsive.
func build_greybox_progressive() -> void:
	if _is_built:
		return
	_is_built = true
	var steps: Array = _build_steps()
	for i in range(steps.size()):
		build_progress.emit(float(i) / float(steps.size()), String((steps[i] as Array)[0]))
		await get_tree().process_frame
		((steps[i] as Array)[1] as Callable).call()
	_bind_realm_visuals()
	build_progress.emit(1.0, "Arena ready")


func get_key_anchors() -> Dictionary:
	# World coordinates (JourneyLayout). Stage 03 / 05 content is story-built and shifted by OFF_S3 / OFF_S5.
	var s3 := Vector3(0, 0, JourneyLayout.OFF_S3)
	var s5 := Vector3(0, 0, JourneyLayout.OFF_S5)
	var hc: Vector3 = JourneyLayout.HALL_CENTER
	var cc: Vector3 = JourneyLayout.CHAMBER_CENTER
	return {
		"player_spawn": Vector3(0.0, 0.0, -56.0 + JourneyLayout.OFF_S1_TERRACE),
		"entry_gap_center": Vector3(0.0, 0.0, 1.0),
		"entry_switch": Vector3(-3.1, 0.0, 3.2),
		"hall_pillar": hc,
		"skeleton_1": hc + Vector3(-18.0, 0.0, -18.0),
		"skeleton_2": hc + Vector3(18.0, 0.0, -10.0),
		"phantom_1": hc + Vector3(-18.0, 0.0, 22.0),
		"phantom_2": hc + Vector3(18.0, 0.0, 24.0),
		"gallery_bridge_center": Vector3(0.0, Y_GALLERY, 72.0) + s3,
		"shielded_guard": Vector3(0.0, Y_GALLERY, 79.5) + s3,
		"mechanism_dais": cc + Vector3(-3.0, 1.35, -1.0),
		"mechanism_plate": cc,
		"arena_entry": Vector3(0.0, Y_ARENA, ARENA_CENTER.z - 13.5) + s5,
		"warden_spawn": Vector3(0.0, Y_ARENA, ARENA_CENTER.z - 1.0) + s5,
		"arena_exit": Vector3(0.0, Y_ARENA, ARENA_CENTER.z + 13.5) + s5,
		"summit": Vector3(0.0, Y_ARENA, ARENA_CENTER.z + 40.0) + s5,
	}


## Ordered critical-path waypoints (WORLD feet positions) with the realm required to stand there.
## Feeds JourneyTerrain (it keeps the landscape below this band). Bridges come from JourneyLayout.ROUTES.
func get_route_waypoints() -> Array:
	var bridges: Dictionary = {}
	for r in JourneyLayout.ROUTES:
		var pts: Array = []
		for nd in (r as Array)[1]:
			pts.append([(nd as Array)[0], 0])
		bridges[String((r as Array)[0])] = pts
	var out: Array = [[Vector3(0, 0, -56.0 + JourneyLayout.OFF_S1_TERRACE), 0]]
	out.append_array(bridges["R1_PilgrimCauseway"] as Array)
	out.append_array([[Vector3(0, 0, -10), 0], [Vector3(0, 0, -2), 0], [Vector3(0, 0, 1), 1], [Vector3(0, 0, 4), 1], [Vector3(0, 0, 6.5), 0]])
	out.append_array(bridges["R2_SunlitBridges"] as Array)
	var hc: Vector3 = JourneyLayout.HALL_CENTER
	out.append_array([[hc + Vector3(0, 0, -26), 0], [hc + Vector3(0, 0, -8), 0], [hc + Vector3(4, 0, 0), 0], [hc + Vector3(0, 0, 8), 0], [hc + Vector3(0, 0, 27), 0]])
	out.append_array(bridges["R3_WindsweptRampart"] as Array)
	var s3 := Vector3(0, 0, JourneyLayout.OFF_S3)
	for w in [[Vector3(0, Y_GALLERY, 65), 0], [Vector3(0, Y_GALLERY, 72), 1], [Vector3(0, Y_GALLERY, 76), 1],
			[Vector3(0, Y_GALLERY, 79.5), 0], [Vector3(0, Y_GALLERY, 83.6), 0], [Vector3(0, Y_GALLERY, 86), 0]]:
		out.append([((w as Array)[0] as Vector3) + s3, (w as Array)[1]])
	var cc: Vector3 = JourneyLayout.CHAMBER_CENTER
	out.append_array([[cc + Vector3(0, 0, -14), 0], [cc + Vector3(0, 0, 14), 0]])
	out.append_array(bridges["R5_Processional"] as Array)
	var s5 := Vector3(0, 0, JourneyLayout.OFF_S5)
	for w in [[Vector3(0, Y_ARENA, 130), 0], [Vector3(0, Y_ARENA, 140), 0], [Vector3(2.6, Y_ARENA, 144), 0],
			[Vector3(6, Y_ARENA, 154), 0], [Vector3(2.6, Y_ARENA, 164), 0], [Vector3(0, Y_ARENA, 168), 0],
			[Vector3(0, Y_ARENA, 177), 0], [Vector3(0, Y_ARENA, 194), 0]]:
		out.append([((w as Array)[0] as Vector3) + s5, (w as Array)[1]])
	return out


# =====================================================================================================
# Materials
# =====================================================================================================

func _pbr(id: String, tile: float = 0.25, tint: Color = Color.WHITE, extra: Dictionary = {}) -> ShaderMaterial:
	var key: String = "%s|%.4f|%s|%s" % [id, tile, tint.to_html(), str(extra)]
	if _pbr_cache.has(key):
		return _pbr_cache[key] as ShaderMaterial
	var m := ShaderMaterial.new()
	if ResourceLoader.exists(REALM_PBR_SHADER):
		m.shader = load(REALM_PBR_SHADER) as Shader
	var base: String = PBR_DIR + id + "/" + id
	if ResourceLoader.exists(base + "_diff_2k.jpg"):
		m.set_shader_parameter("albedo_tex", load(base + "_diff_2k.jpg"))
		m.set_shader_parameter("normal_tex", load(base + "_nor_gl_2k.jpg"))
		m.set_shader_parameter("arm_tex", load(base + "_arm_2k.jpg"))
	m.set_shader_parameter("tile_scale", tile)
	m.set_shader_parameter("tint", tint)
	for k in extra:
		m.set_shader_parameter(String(k), extra[k])
	_pbr_cache[key] = m
	return m


func _m_wall() -> ShaderMaterial:
	return _pbr("large_sandstone_blocks", 0.2, Color(1.12, 0.98, 0.8))

func _m_floor() -> ShaderMaterial:
	return _pbr("stone_tiles_02", 0.28, Color(1.08, 0.95, 0.8))

func _m_path() -> ShaderMaterial:
	return _pbr("cobblestone_floor_08", 0.33, Color(1.02, 0.92, 0.8))

func _m_rock() -> ShaderMaterial:
	return _pbr("rock_face", 0.05, Color(0.92, 0.84, 0.76), {"blend_sharpness": 3.0, "macro_variation": 0.5, "rune_strength": 1.4})

func _m_rock_far() -> ShaderMaterial:
	return _pbr("rock_face", 0.01, Color(0.62, 0.58, 0.6), {"blend_sharpness": 2.0, "macro_variation": 0.7, "rune_strength": 0.5, "normal_strength": 1.4})

func _m_sand() -> ShaderMaterial:
	return _pbr("coast_sand_rocks_02", 0.16, Color(1.08, 0.9, 0.7), {"rune_strength": 1.0})

func _m_marble() -> ShaderMaterial:
	return _pbr("marble_01", 0.35, Color(1.0, 0.97, 0.93), {"roughness_bias": -0.1, "rune_strength": 1.6, "rune_threshold": 0.55})

func _m_ruin() -> ShaderMaterial:
	return _pbr("castle_brick_07", 0.3, Color(0.95, 0.9, 0.85))


func _std(key: String, albedo: Color, metallic: float, roughness: float, emission: Color = Color.BLACK, emission_energy: float = 0.0) -> StandardMaterial3D:
	if _std_cache.has(key):
		return _std_cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = roughness
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	_std_cache[key] = m
	return m

func _m_bronze() -> StandardMaterial3D:
	return _std("bronze", Color(0.42, 0.27, 0.13), 0.9, 0.38)

func _m_iron() -> StandardMaterial3D:
	return _std("iron", Color(0.11, 0.1, 0.095), 0.75, 0.55)

func _m_crystal() -> StandardMaterial3D:
	return _std("crystal", Color(0.35, 0.7, 1.0), 0.1, 0.1, Color(0.25, 0.6, 1.0), 4.0)


# =====================================================================================================
# Geometry helpers
# =====================================================================================================

func _solid(parent: Node, n: String, pos: Vector3, size: Vector3, mat: Material, layer: int = LAYER_WORLD_SHARED, rot: Vector3 = Vector3.ZERO, show_mesh: bool = true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = n
	body.position = pos
	body.rotation = rot
	body.collision_layer = layer
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	if show_mesh:
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat
		mi.mesh = bm
		body.add_child(mi)
	parent.add_child(body)
	return body


func _invisible_wall(parent: Node, n: String, pos: Vector3, size: Vector3, rot: Vector3 = Vector3.ZERO) -> StaticBody3D:
	return _solid(parent, n, pos, size, null, LAYER_WORLD_SHARED, rot, false)


func _mesh(parent: Node, n: String, mesh: Mesh, mat: Material, xform: Transform3D, shadows: bool = true, vis_range: float = 0.0, batch: bool = true) -> MeshInstance3D:
	## `batch` = may be merged by `_static_batch()` (static, no gameplay toggling, no per-node animation).
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	if mat != null:
		mi.material_override = mat
	mi.transform = xform
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_range > 0.0:
		mi.visibility_range_end = vis_range
		mi.visibility_range_end_margin = vis_range * 0.1
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if batch and mat != null:
		mi.set_meta("gj_batch", true)
	parent.add_child(mi)
	return mi


func _static_batch(root: Node) -> int:
	## Merges every MeshInstance3D flagged `gj_batch` into one mesh per (batch-root, material, shadow mode).
	## Batch roots are the realm decor groups (Shared / RealityDressing / MirrorDressing), the Scenery node
	## and each stage's "StaticArt" node, so realm visibility toggling keeps working on merged meshes.
	var groups: Dictionary = {}
	var candidates: Array[MeshInstance3D] = []
	_collect_batchable(root, candidates)
	for mi in candidates:
		var host: Node3D = _batch_host(mi)
		if host == null or mi.mesh == null:
			continue
		var key: String = "%d|%d|%d" % [host.get_instance_id(), mi.material_override.get_instance_id(), int(mi.cast_shadow)]
		if not groups.has(key):
			groups[key] = {"host": host, "mat": mi.material_override, "shadow": mi.cast_shadow, "items": []}
		(groups[key]["items"] as Array).append(mi)
	var merged_count: int = 0
	for key in groups:
		var entry: Dictionary = groups[key]
		var items: Array = entry["items"]
		if items.size() < 2:
			continue
		var host: Node3D = entry["host"]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var inv: Transform3D = host.global_transform.affine_inverse()
		for it in items:
			var mi: MeshInstance3D = it
			var xf: Transform3D = inv * mi.global_transform
			for s in range(mi.mesh.get_surface_count()):
				st.append_from(mi.mesh, s, xf)
		var merged := MeshInstance3D.new()
		merged.name = "Batched_%s" % (entry["mat"] as Material).resource_name if (entry["mat"] as Material).resource_name != "" else "Batched"
		merged.mesh = st.commit()
		merged.material_override = entry["mat"]
		merged.cast_shadow = entry["shadow"]
		host.add_child(merged)
		for it in items:
			(it as Node).queue_free()
		merged_count += items.size()
	return merged_count


func _collect_batchable(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.has_meta("gj_batch") and (node as MeshInstance3D).material_override != null:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		_collect_batchable(c, out)


func _batch_host(mi: Node) -> Node3D:
	var n: Node = mi.get_parent()
	while n != null and n != self:
		if n.name in [&"Shared", &"RealityDressing", &"MirrorDressing", &"Scenery", &"StaticArt"]:
			return n as Node3D
		n = n.get_parent()
	return null


func _multimesh(parent: Node, n: String, mesh: Mesh, mat: Material, xforms: Array, shadows: bool = true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = n
	mmi.multimesh = mm
	if mat != null:
		mmi.material_override = mat
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


func _ramp(parent: Node, n: String, from: Vector3, to: Vector3, width: float, mat: Material, show_mesh: bool = true) -> StaticBody3D:
	## Sloped walkable slab whose TOP surface runs exactly from `from` to `to` (both feet heights, along Z).
	var d: Vector3 = to - from
	var length: float = d.length()
	var pitch: float = atan2(d.y, Vector2(d.x, d.z).length())
	var yaw: float = atan2(d.x, d.z)
	var thick: float = 0.6
	var basis := Basis.from_euler(Vector3(-pitch, yaw, 0.0))
	var center: Vector3 = (from + to) * 0.5 - basis.y * (thick * 0.5)
	var body := _solid(parent, n, center, Vector3(width, thick, length + 0.4), mat, LAYER_WORLD_SHARED, Vector3(-pitch, yaw, 0.0), show_mesh)
	var mi: MeshInstance3D = body.get_node_or_null("Mesh") as MeshInstance3D
	if mi != null:
		# Visible ramps sink 3 cm and keep their exact length so their ends tuck under the floors they join
		# instead of sharing a coplanar top (the collider keeps its overlap for seamless walking).
		(mi.mesh as BoxMesh).size = Vector3(width, thick, length)
		mi.position = Vector3(0, -0.03, 0)
	return body


## Point on the line parallel to segment a->b (XZ), offset `lateral` metres to its right (+) / left (-),
## at world z = `z` (used to lay causeway parapets exactly along the ramp edges).
func _line_at_z(a: Vector3, b: Vector3, lateral: float, z: float) -> Vector3:
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var u: Vector3 = d.normalized()
	var n := Vector3(u.z, 0.0, -u.x)   # right of travel
	var base: Vector3 = a + n * lateral
	var t: float = (z - base.z) / maxf(0.0001, d.z)
	return Vector3(base.x + d.x * t, a.y, z)


func _prop_collider(parent: Node, n: String, pos: Vector3, shape: Shape3D, rot: Vector3 = Vector3.ZERO, layer: int = LAYER_WORLD_SHARED) -> StaticBody3D:
	## Collision-only body for decor props standing on walkable floors (braziers, obelisks, crystals...).
	var body := StaticBody3D.new()
	body.name = n
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = pos
	body.rotation = rot
	parent.add_child(body)
	return body


func _cyl_shape(radius: float, height: float) -> CylinderShape3D:
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = height
	return s


func _box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


func _add_roamer(parent: Node3D, kind: String, node_name: String, pos: Vector3, section: int, face_toward: Vector3 = Vector3.ZERO) -> EnemyBase:
	## Journey enemies outside the five locked encounters. Empty encounter_id => they never hold a gate shut;
	## section_id => EncounterDirector wakes them only while the player is in that section and resets them on
	## death-respawn like every other enemy.
	if not spawn_enemies:
		return null
	var e: EnemyBase = null
	var col := Color(0.82, 0.76, 0.65)
	match kind:
		"phantom":
			e = PhantomTwin.new()
			col = Color(0.25, 0.78, 1.0, 0.85)
		"shield":
			e = ShieldedGuard.new()
			col = Color(0.75, 0.58, 0.25)
		"hexcaster", "brute", "stalker":
			# Data-driven archetypes (res://data/enemies/*.tres).
			var ae := ArchetypeEnemy.new()
			ae.archetype = load(ARCHETYPE_PATHS[kind]) as EnemyArchetype
			e = ae
		_:
			e = SkeletonGuard.new()
	_configure_enemy_actor(e, node_name, "journey_" + node_name.to_lower(), pos, col)
	e.section_id = section
	e.encounter_id = ""
	if e is EnemyAI and (e as EnemyAI).patrol_radius <= 0.0 and not (e is ArchetypeEnemy):
		(e as EnemyAI).patrol_radius = 1.6
	if face_toward != Vector3.ZERO:
		var d: Vector3 = face_toward - pos
		e.rotation.y = atan2(-d.x, -d.z)
	parent.add_child(e)
	return e


## Makes a configured enemy physically bigger: model, body capsule, hurtbox, floating HP-bar height and melee reach
## all scale by `k` (the CharacterBody3D itself is never scaled — Godot physics bodies must stay unscaled).
## Call before the enemy enters the tree (right after _add_roamer / _configure_enemy_actor).
func _enlarge_enemy(e: EnemyBase, k: float) -> void:
	if e == null:
		return
	var vr: Node3D = e.get_node_or_null("VisualRoot") as Node3D
	if vr != null:
		vr.scale = Vector3.ONE * k
	var bc: CollisionShape3D = e.get_node_or_null("BodyCollider") as CollisionShape3D
	if bc != null and bc.shape is CapsuleShape3D:
		var cap := (bc.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
		cap.radius *= k
		cap.height *= k
		bc.shape = cap
		bc.position *= k
	var hb: Node3D = e.get_node_or_null("Hurtbox3D") as Node3D
	if hb != null:
		for c in hb.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
				var bs := ((c as CollisionShape3D).shape as BoxShape3D).duplicate() as BoxShape3D
				bs.size *= k
				(c as CollisionShape3D).shape = bs
				(c as CollisionShape3D).position *= k
	var atk: Node3D = e.get_node_or_null("AttackHitbox") as Node3D
	if atk != null:
		for c in atk.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
				var abs_box := ((c as CollisionShape3D).shape as BoxShape3D).duplicate() as BoxShape3D
				abs_box.size *= k
				(c as CollisionShape3D).shape = abs_box
				(c as CollisionShape3D).position *= k
	var hp: Node3D = e.get_node_or_null("FloatingHPBar") as Node3D
	if hp != null:
		hp.position *= k
	if e is EnemyAI:
		(e as EnemyAI).attack_range *= lerpf(1.0, k, 0.7)


var _thrall_serial: int = 0


## WardenBoss.summon_factory: a bone thrall (KayKit Skeleton_Minion) at a world position in the Execution Arena.
## "skeleton" = Reality-only SkeletonGuard, "phantom" = Mirror-only PhantomTwin. Weaker than section enemies
## (WardenBoss.summon_thrall_health), no encounter id (never holds a gate), freed by the Warden on reset/death.
func _spawn_warden_thrall(kind: String, global_pos: Vector3, face_toward: Vector3) -> EnemyBase:
	var holder: Node3D = get_node_or_null("Stage05_ExecutionArena/Enemies") as Node3D
	if holder == null or not holder.is_inside_tree():
		return null
	var warden: WardenBoss = holder.get_node_or_null("TheWarden") as WardenBoss
	_thrall_serial += 1
	var e: EnemyBase = PhantomTwin.new() if kind == "phantom" else SkeletonGuard.new()
	e.set_meta("model_path_override", "res://assets/models/characters/Skeleton_Minion.glb")
	e.set_meta("model_scale_override", 0.95)
	var col := Color(0.25, 0.78, 1.0, 0.85) if kind == "phantom" else Color(0.82, 0.76, 0.65)
	_configure_enemy_actor(e, "WardenThrall_%d" % _thrall_serial, "warden_thrall_%d" % _thrall_serial, holder.to_local(global_pos), col)
	e.section_id = EncounterDirector.Section.EXECUTION_ARENA
	e.encounter_id = ""
	e.max_health = warden.summon_thrall_health if warden != null else 52
	e.health = e.max_health
	if e is EnemyAI:
		(e as EnemyAI).max_chase_distance = 40.0
	var d: Vector3 = face_toward - global_pos
	if Vector2(d.x, d.z).length() > 0.01:
		e.rotation.y = atan2(-d.x, -d.z)
	holder.add_child(e)
	return e


func _roamer_group(root: Node3D) -> Node3D:
	var g: Node3D = root.get_node_or_null("Roamers") as Node3D
	if g == null:
		g = Node3D.new()
		g.name = "Roamers"
		root.add_child(g)
	return g


func _configure_enemy_actor(enemy: EnemyBase, node_name: String, unique_id: String, pos: Vector3, color: Color, body_size: Vector3 = Vector3(0.8, 1.8, 0.8)) -> void:
	super._configure_enemy_actor(enemy, node_name, unique_id, pos, color, body_size)
	# Enemies respect the same railings as the player (they must never be lured off a cliff edge).
	enemy.collision_mask |= RealmManager.LAYER_PLAYER_BLOCKER


func _parapet(parent: Node, n: String, a: Vector3, b: Vector3, mat: Material, visual_h: float = 1.05, block_h: float = 2.7, thick: float = 0.45) -> void:
	## Low balustrade (visual) + tall invisible collider (jump apex is ~1.94 m) from a to b at feet height.
	var d: Vector3 = b - a
	var length: float = d.length()
	if length < 0.05:
		return
	var yaw: float = atan2(d.x, d.z)
	var pitch: float = atan2(d.y, Vector2(d.x, d.z).length())
	var rot := Vector3(-pitch, yaw, 0.0)
	var basis := Basis.from_euler(rot)
	var mid: Vector3 = (a + b) * 0.5
	var vis := Node3D.new()
	vis.name = n
	var art: Node3D = _static_art(parent)
	art.add_child(vis)
	# Neighbouring parapets overlap at corners. Stagger height by heading octant (segments that meet always
	# differ in heading) so overlapping caps/tops never share a plane — no corner flicker.
	_parapet_count += 1
	var octant: int = posmod(roundi(yaw / (PI * 0.25)), 8)
	var h: float = visual_h + 0.012 * float(octant)
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(thick, h, length)
	_mesh(vis, "Parapet", body_mesh, mat, Transform3D(basis, mid + basis.y * (h * 0.5)))
	var cap := BoxMesh.new()
	cap.size = Vector3(thick + 0.16, 0.14, length + 0.1)
	_mesh(vis, "Cap", cap, _m_marble(), Transform3D(basis, mid + basis.y * (h + 0.07)))
	# Low visible rail (solid to the player at its real height) + tall blocker on the camera-ignored layer.
	_solid(vis, "RailBody", mid + basis.y * (h * 0.5 + 0.035), Vector3(thick + 0.16, h + 0.07, length), null, LAYER_WORLD_SHARED, rot, false)
	_solid(vis, "Blocker", mid + basis.y * (block_h * 0.5), Vector3(thick, block_h, length), null, RealmManager.LAYER_PLAYER_BLOCKER, rot, false)


func _static_art(parent: Node) -> Node3D:
	## Per-parent "StaticArt" batch root for purely visual meshes living inside a gameplay stage root.
	var existing: Node3D = parent.get_node_or_null("StaticArt") as Node3D
	if existing != null:
		return existing
	var art := Node3D.new()
	art.name = "StaticArt"
	parent.add_child(art)
	return art


func _rock(parent: Node, n: String, center_top: Vector3, size: Vector3, seed_val: int, mat: Material, boxy: float = 1.0, roughness: float = 0.16, subdiv: int = 12, shadows: bool = true, lods: bool = false) -> MeshInstance3D:
	## Rock massif whose top sits just under `center_top.y` (vertices clamped so it never pokes through floors).
	var mesh: ArrayMesh = ProcMesh.rock_mesh(size, seed_val, roughness, subdiv, boxy)
	_clamp_mesh_top(mesh, size.y * 0.5)
	if lods:
		mesh = _with_lods(mesh)
	var xf := Transform3D(Basis.IDENTITY, Vector3(center_top.x, center_top.y - size.y * 0.5, center_top.z))
	return _mesh(parent, n, mesh, mat, xf, shadows)


func _with_lods(mesh: ArrayMesh) -> ArrayMesh:
	## Auto-generates mesh LODs (meshoptimizer) for procedural meshes so Godot's per-instance LOD selection
	## drops triangles with screen size. Only for unbatched meshes (SurfaceTool merging discards LODs).
	var im := ImporterMesh.new()
	for s in range(mesh.get_surface_count()):
		im.add_surface(mesh.surface_get_primitive_type(s), mesh.surface_get_arrays(s))
	im.generate_lods(60.0, 25.0, [])
	return im.get_mesh()


func _clamp_mesh_top(mesh: ArrayMesh, max_y: float) -> void:
	if mesh.get_surface_count() == 0:
		return
	var arrays: Array = mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var changed: bool = false
	for i in range(v.size()):
		if v[i].y > max_y:
			v[i].y = max_y
			changed = true
	if not changed:
		return
	arrays[Mesh.ARRAY_VERTEX] = v
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _zone(zone_name: String) -> Array[Node3D]:
	## [shared, reality_only, mirror_only] decor groups for a zone (base `_make_realm_group` adds RealmReactive).
	var z := Node3D.new()
	z.name = zone_name
	_decor.add_child(z)
	return [
		_make_realm_group(z, "Shared", -1),
		_make_realm_group(z, "RealityDressing", RealmReactive.Affinity.REALITY_ONLY),
		_make_realm_group(z, "MirrorDressing", RealmReactive.Affinity.MIRROR_ONLY),
	]


# =====================================================================================================
# Props: braziers, banners, statues, crystals, gates, switches
# =====================================================================================================

func _brazier(groups: Array[Node3D], pos: Vector3, light: bool = true) -> void:
	var shared: Node3D = groups[0]
	var stand := ProcMesh.column_mesh(0.16, 1.1, 8)
	_mesh(shared, "BrazierStand", stand, _m_bronze(), Transform3D(Basis.IDENTITY, pos), true, 90.0)
	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.55
	bowl.bottom_radius = 0.22
	bowl.height = 0.45
	bowl.radial_segments = 16
	bowl.rings = 1
	bowl.cap_top = false # open bowl: the ember bed sits inside it (no coplanar cap to z-fight with)
	_mesh(shared, "BrazierBowl", bowl, _m_bronze(), Transform3D(Basis.IDENTITY, pos + Vector3(0, 1.3, 0)), true, 90.0)
	var coals := CylinderMesh.new()
	coals.top_radius = 0.46
	coals.bottom_radius = 0.42
	coals.height = 0.05
	coals.radial_segments = 12
	_mesh(groups[1], "Embers", coals, _std("embers", Color(0.2, 0.05, 0.0), 0.0, 1.0, Color(1.0, 0.35, 0.05), 3.0), Transform3D(Basis.IDENTITY, pos + Vector3(0, 1.44, 0)), false, 90.0)
	_prop_collider(shared, "BrazierCollider", pos + Vector3(0, 0.8, 0), _cyl_shape(0.5, 1.6))
	groups[1].add_child(_flame(pos + Vector3(0, 1.55, 0), Color(1.6, 1.0, 0.45), Color(1.0, 0.25, 0.04, 0.0), 1.0))
	groups[2].add_child(_flame(pos + Vector3(0, 1.55, 0), Color(0.7, 0.95, 1.6), Color(0.1, 0.3, 1.0, 0.0), 0.85))
	if light:
		var l: OmniLight3D = RealmTorchLightScript.new() as OmniLight3D
		l.name = "BrazierLight"
		l.omni_range = 9.0
		l.omni_attenuation = 1.3
		l.set("base_energy", 1.8)
		l.position = pos + Vector3(0, 2.1, 0)
		l.distance_fade_enabled = true
		l.distance_fade_begin = 45.0
		l.distance_fade_length = 15.0
		shared.add_child(l)


func _flame(pos: Vector3, hot: Color, cool: Color, scale_k: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Flame"
	p.amount = 26
	p.lifetime = 0.85
	p.position = pos
	p.visibility_aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3, 4, 3))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.28 * scale_k
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.8 * scale_k
	pm.initial_velocity_max = 1.6 * scale_k
	pm.gravity = Vector3(0, 1.2, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.5))
	sc.add_point(Vector2(0.25, 1.0))
	sc.add_point(Vector2(1.0, 0.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([hot, hot.lerp(cool, 0.5), cool])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.55, 0.75) * scale_k
	q.material = _flame_material()
	p.draw_pass_1 = q
	p.visibility_range_end = 80.0
	return p


func _flame_material() -> StandardMaterial3D:
	if _std_cache.has("flame_sprite"):
		return _std_cache["flame_sprite"] as StandardMaterial3D
	# Soft radial sprite (no square billboards): bright core falling off to nothing at the edge.
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.55)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.3
	_std_cache["flame_sprite"] = m
	return m


func _sword_monument(parent: Node3D, base_pos: Vector3, yaw_deg: float, height: float, collide: bool = false) -> void:
	## Colossal stone greatsword plunged point-down into a rubble mound (replaces figurative statues).
	var w: float = height * 0.11
	var blade_len: float = height * 0.72
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var blade: ArrayMesh = ProcMesh.extrude_polygon(ProcMesh.sword_blade_outline(w, blade_len), w * 0.16)
	_mesh(parent, "SwordBlade", blade, _pbr("marble_01", 0.2, Color(0.9, 0.88, 0.84), {"roughness_bias": -0.2, "rune_strength": 3.0, "rune_threshold": 0.7}), Transform3D(basis, base_pos))
	var fuller := BoxMesh.new()
	fuller.size = Vector3(w * 0.14, blade_len * 0.7, w * 0.2)
	_mesh(parent, "SwordFuller", fuller, _m_bronze(), Transform3D(basis, base_pos + Vector3(0, blade_len * 0.52, 0)))
	var guard := BoxMesh.new()
	guard.size = Vector3(w * 3.2, height * 0.055, w * 0.42)
	_mesh(parent, "SwordGuard", guard, _m_bronze(), Transform3D(basis, base_pos + Vector3(0, blade_len + height * 0.0275, 0)))
	var quillon := SphereMesh.new()
	quillon.radius = w * 0.28
	quillon.height = w * 0.56
	quillon.radial_segments = 12
	quillon.rings = 6
	for sx in [-1.0, 1.0]:
		_mesh(parent, "SwordQuillon", quillon, _m_bronze(), Transform3D(basis, base_pos + basis * Vector3(sx * w * 1.65, blade_len + height * 0.0275, 0)))
	var grip := CylinderMesh.new()
	grip.top_radius = w * 0.16
	grip.bottom_radius = w * 0.19
	grip.height = height * 0.2
	grip.radial_segments = 12
	_mesh(parent, "SwordGrip", grip, _std("leather", Color(0.18, 0.09, 0.05), 0.0, 0.7), Transform3D(basis, base_pos + Vector3(0, blade_len + height * 0.155, 0)))
	var pommel := SphereMesh.new()
	pommel.radius = w * 0.34
	pommel.height = w * 0.68
	pommel.radial_segments = 14
	pommel.rings = 7
	_mesh(parent, "SwordPommel", pommel, _m_bronze(), Transform3D(basis, base_pos + Vector3(0, blade_len + height * 0.27, 0)))
	var mound: ArrayMesh = ProcMesh.rock_mesh(Vector3(w * 2.6, w * 1.3, w * 2.3), int(base_pos.z * 7.0 + base_pos.x), 0.25, 8, 0.0)
	_mesh(parent, "SwordMound", mound, _m_ruin(), Transform3D(basis, base_pos))
	if collide:
		_prop_collider(parent, "SwordMoundCollider", base_pos + Vector3(0, w * 0.4, 0), _cyl_shape(w * 1.2, w * 0.8))
		_prop_collider(parent, "SwordBladeCollider", base_pos + Vector3(0, blade_len * 0.5, 0), _box_shape(Vector3(w * 1.05, blade_len, w * 0.3)), Vector3(0, deg_to_rad(yaw_deg), 0))


func _banner(parent: Node3D, top: Vector3, yaw_deg: float, width: float, length: float, mirror_kind: bool) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(width, length)
	q.subdivide_width = 4
	q.subdivide_depth = 12
	q.center_offset = Vector3(0, -length * 0.5, 0)
	var m := ShaderMaterial.new()
	if ResourceLoader.exists(BANNER_SHADER):
		m.shader = load(BANNER_SHADER) as Shader
	if mirror_kind:
		m.set_shader_parameter("cloth_color", Color(0.05, 0.12, 0.38))
		m.set_shader_parameter("trim_color", Color(0.55, 0.8, 1.0))
		m.set_shader_parameter("emblem_kind", 1)
		m.set_shader_parameter("emblem_glow", 2.5)
	else:
		m.set_shader_parameter("cloth_color", Color(0.5, 0.05, 0.04))
		m.set_shader_parameter("trim_color", Color(0.9, 0.65, 0.25))
		m.set_shader_parameter("emblem_kind", 0)
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	_mesh(parent, "Banner", q, m, Transform3D(basis, top), false, 140.0, false)
	var rod := BoxMesh.new()
	rod.size = Vector3(width + 0.4, 0.09, 0.09)
	_mesh(parent, "BannerRod", rod, _m_bronze(), Transform3D(basis, top + Vector3(0, 0.05, 0)), false, 140.0)


func _statue(parent: Node3D, base_pos: Vector3, yaw_deg: float, height: float, pose: String = "Idle") -> Node3D:
	## Colossal marble guardian: the KayKit Knight rig frozen in a pose and re-skinned in realm marble.
	if not ResourceLoader.exists(KNIGHT_MODEL):
		return null
	var packed: PackedScene = load(KNIGHT_MODEL) as PackedScene
	var inst: Node3D = packed.instantiate() as Node3D
	inst.name = "GuardianStatue"
	parent.add_child(inst)
	var aabb: AABB = _compute_local_aabb(inst)
	var s: float = height / maxf(aabb.size.y, 0.1)
	inst.scale = Vector3.ONE * s
	inst.position = base_pos
	inst.rotation.y = deg_to_rad(yaw_deg)
	var mat: ShaderMaterial = _pbr("marble_01", 0.12, Color(0.93, 0.89, 0.82), {"roughness_bias": 0.1, "rune_strength": 2.4, "rune_threshold": 0.6})
	_apply_override_recursive(inst, mat)
	var ap: AnimationPlayer = _find_anim_player(inst)
	if ap != null:
		for cand in [pose, "Animations/" + pose]:
			if ap.has_animation(cand):
				ap.play(cand)
				ap.seek(0.35, true)
				ap.pause()
				break
	return inst


func _apply_override_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for c in node.get_children():
		_apply_override_recursive(c, mat)


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c in node.get_children():
		var f: AnimationPlayer = _find_anim_player(c)
		if f != null:
			return f
	return null


func _crystal_cluster(parent: Node3D, pos: Vector3, size: float, seed_val: int, collide: bool = false) -> void:
	if collide:
		# Mirror-layer collider: solid only while the player is in the Mirror (RealmManager swaps masks).
		_prop_collider(parent, "CrystalCollider", pos + Vector3(0, 0.6 * size, 0), _cyl_shape(0.55 * size, 1.2 * size), Vector3.ZERO, LAYER_WORLD_MIRROR)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var prism := CylinderMesh.new()
	prism.top_radius = 0.0
	prism.bottom_radius = 0.22
	prism.height = 1.6
	prism.radial_segments = 6
	prism.rings = 1
	var xforms: Array = []
	for i in range(7):
		var h: float = rng.randf_range(0.6, 1.4) * size
		var b := Basis.from_euler(Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0, TAU), rng.randf_range(-0.6, 0.6))).scaled(Vector3(h * 0.7, h, h * 0.7))
		xforms.append(Transform3D(b, pos + Vector3(rng.randf_range(-0.6, 0.6), 0.5 * h, rng.randf_range(-0.6, 0.6)) * size * 0.5))
	_multimesh(parent, "CrystalCluster", prism, _m_crystal(), xforms, false)


func _style_gate(gate: EncounterGate, width: float = 4.6, height: float = 3.6) -> void:
	var gm: MeshInstance3D = gate.get_node_or_null("GateMesh") as MeshInstance3D
	if gm == null:
		return
	gm.mesh = ProcMesh.portcullis_mesh(width, height)
	gm.position = Vector3.ZERO
	gm.material_override = _m_iron()


func _style_switch(sw: Node3D) -> void:
	var plinth: MeshInstance3D = sw.get_node_or_null("SwitchPlinth") as MeshInstance3D
	if plinth != null:
		plinth.mesh = ProcMesh.column_mesh(0.28, 1.15, 10)
		plinth.position = Vector3.ZERO
		plinth.material_override = _m_marble()
	var rune := MeshInstance3D.new()
	rune.name = "SwitchRune"
	var gem := SphereMesh.new()
	gem.radius = 0.22
	gem.height = 0.5
	gem.radial_segments = 4
	gem.rings = 2
	rune.mesh = gem
	rune.material_override = _m_crystal()
	rune.position = Vector3(0, 1.55, 0)
	sw.add_child(rune)
	var tw := rune.create_tween().set_loops()
	tw.tween_property(rune, "rotation:y", TAU, 6.0).as_relative()


func _add_waves(root: Node3D, n: String, section: int, waves_spec: Array) -> void:
	## WaveDirector over enemies already under `root` (paths relative to root). Missing enemies are skipped.
	if not spawn_enemies:
		return
	var wd := WaveDirector.new()
	wd.name = n
	wd.section_id = section
	var waves: Array = []
	for w in waves_spec:
		var paths: Array = []
		for p in w:
			if root.get_node_or_null(String(p)) != null:
				paths.append(NodePath("../" + String(p)))
		waves.append(paths)
	wd.waves = waves
	root.add_child(wd)


func _make_knockable(prop: BreakableProp, column_h: float) -> void:
	## Topples away from the striker and crushes everything along its length (enemies take a killing blow at the
	## 2.5x enemy health; the player only if they stand in the fall line).
	prop.knock_directional = true
	prop.knock_fall_length = column_h
	prop.damage_radius = 1.8
	prop.enemy_hazard_damage = 600


func _restyle_pillar(prop: BreakableProp, column_h: float, radius: float, broken_dir: Vector3) -> void:
	var intact: Node3D = prop.get_node_or_null("IntactVisual") as Node3D
	var broken: Node3D = prop.get_node_or_null("BrokenVisual") as Node3D
	if intact != null:
		for c in intact.get_children():
			if c.name != "FractureSeam":
				c.free()
		_mesh(intact, "Column", ProcMesh.column_mesh(radius, column_h, 16), _m_marble(), Transform3D.IDENTITY)
		var seam: MeshInstance3D = intact.get_node_or_null("FractureSeam") as MeshInstance3D
		if seam != null:
			# Embedded glowing crack (half inside the fluted shaft) instead of a stick floating in front of it.
			var sm := BoxMesh.new()
			sm.size = Vector3(0.07, 1.9, 0.08)
			seam.mesh = sm
			seam.position = Vector3(0, 1.75, -radius * 0.93)
	# Collider matches the column: base plinth box + shaft (old greybox cylinder was thinner than the base).
	var solid: StaticBody3D = prop.get_node_or_null("SolidBody") as StaticBody3D
	if solid != null:
		for c in solid.get_children():
			c.free()
		var base_cs := CollisionShape3D.new()
		base_cs.shape = _box_shape(Vector3(radius * 2.6, radius * 0.9, radius * 2.6))
		base_cs.position = Vector3(0, radius * 0.45, 0)
		solid.add_child(base_cs)
		var shaft_cs := CollisionShape3D.new()
		shaft_cs.shape = _cyl_shape(radius * 1.02, column_h)
		shaft_cs.position = Vector3(0, column_h * 0.5, 0)
		solid.add_child(shaft_cs)
	if broken != null:
		for c in broken.get_children():
			c.free()
		var drum := CylinderMesh.new()
		drum.top_radius = radius * 0.92
		drum.bottom_radius = radius * 0.92
		drum.height = column_h * 0.28
		drum.radial_segments = 16
		# Fallen drums are real obstacles once the pillar is down (BreakableProp toggles these colliders).
		var debris := StaticBody3D.new()
		debris.name = "DebrisBody"
		debris.collision_layer = LAYER_WORLD_SHARED
		debris.collision_mask = 0
		broken.add_child(debris)
		var n: int = 3
		for i in range(n):
			var along: float = 1.4 + float(i) * column_h * 0.3
			var basis := Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, 0.12 * float(i - 1))
			var drum_xf := Transform3D(basis, broken_dir * along + Vector3(0.25 * float(i - 1), radius * 0.92, 0))
			_mesh(broken, "Drum%d" % i, drum, _m_marble(), drum_xf, true, 0.0, false)
			var dcs := CollisionShape3D.new()
			dcs.shape = _cyl_shape(radius * 0.92, column_h * 0.28)
			dcs.transform = drum_xf
			debris.add_child(dcs)
		_mesh(broken, "Stump", ProcMesh.column_mesh(radius, 1.1, 16), _m_marble(), Transform3D.IDENTITY, true, 0.0, false)
		var stump_cs := CollisionShape3D.new()
		stump_cs.shape = _box_shape(Vector3(radius * 2.95, 1.1, radius * 2.95)) # abacus is 2.9 r wide
		stump_cs.position = Vector3(0, 0.55, 0)
		debris.add_child(stump_cs)


# =====================================================================================================
# Stage 01 — Prologue causeway + Gate of Reflections (gameplay core identical to the greybox)
# =====================================================================================================

func _build_stage_01_entry() -> Node3D:
	var root := Node3D.new()
	root.name = "Stage01_EntryVestibule"
	var g: Array[Node3D] = _zone("Zone01_Gate")
	var floor_m: ShaderMaterial = _m_floor()
	var path_m: ShaderMaterial = _m_path()

	# --- Prologue: start terrace (moved 80 m south, 2026-11-18) and the gate forecourt. The Pilgrim's Causeway
	# between them is the winding bridge R1 with two bastions (_build_routes); its join rails close the terrace's
	# north edge (z -131) and the forecourt's south edge (z -15).
	var tz: float = -56.0 + JourneyLayout.OFF_S1_TERRACE
	_solid(root, "Prologue_StartTerrace", Vector3(0, -0.25, tz), Vector3(12, 0.5, 10), path_m)
	_solid(root, "Gate_Forecourt", Vector3(0, -0.25, -10), Vector3(14, 0.5, 10), floor_m)
	_parapet(root, "Rail_T0_S", Vector3(-6, 0, tz - 5.0), Vector3(6, 0, tz - 5.0), _m_wall())
	_parapet(root, "Rail_T0_W", Vector3(-6, 0, tz - 5.0), Vector3(-6, 0, tz + 5.0), _m_wall())
	_parapet(root, "Rail_T0_E", Vector3(6, 0, tz - 5.0), Vector3(6, 0, tz + 5.0), _m_wall())
	_parapet(root, "Rail_FC_W", Vector3(-7, 0, -15), Vector3(-7, 0, -5), _m_wall())
	_parapet(root, "Rail_FC_E", Vector3(7, 0, -15), Vector3(7, 0, -5), _m_wall())

	# --- Gameplay core (unchanged greybox coordinates) ---
	_solid(root, "EntryFloorSouth", Vector3(0.0, -0.25, -2.75), Vector3(12.0, 0.5, 4.5), floor_m)
	_solid(root, "EntryFloorNorth", Vector3(0.0, -0.25, 3.75), Vector3(12.0, 0.5, 2.5), floor_m)
	_solid(root, "Corridor01_Floor", Vector3(0.0, -0.25, 6.75), Vector3(4.6, 0.5, 3.5), floor_m)

	var stones := RealmPlatform.new()
	stones.name = "EntrySteppingStones"
	stones.position = Vector3(0.0, 0.0, 1.0)
	var reality_geo := Node3D.new()
	reality_geo.name = "RealityGeometry"
	stones.add_child(reality_geo)
	var mirror_geo := Node3D.new()
	mirror_geo.name = "MirrorGeometry"
	var span := _solid(mirror_geo, "SteppingStonesSpan", Vector3(0.0, -0.25, 0.0), Vector3(4.0, 0.5, 3.0), null, LAYER_WORLD_MIRROR, Vector3.ZERO, false)
	var spectral: ShaderMaterial = _get_spectral_material(Color(0.20, 0.72, 1.0, 0.85))
	for i in range(3):
		var slab := BoxMesh.new()
		slab.size = Vector3(1.6, 0.45, 0.9)
		var stone_mi: MeshInstance3D = _mesh(span, "Stone%d" % i, slab, spectral, Transform3D(Basis(Vector3.UP, 0.08 * float(i - 1)), Vector3(0.25 * float(i - 1), -0.02, -1.0 + float(i))))
		stone_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stones.add_child(mirror_geo)
	root.add_child(stones)

	var gate := _make_gate("Gate01_EntryToHall", Vector3(0.0, 0.0, 5.0), 0, "", false)
	_style_gate(gate)
	root.add_child(gate)
	# Gate stone beside the gate (left of the 4 m opening), not on the walking line in front of it.
	var sw := _make_switch("EntryMirrorSwitch", Vector3(-3.1, 0.0, 3.2), InteractSwitch.SwitchRole.GATE_OPENER, 1,
		NodePath("../Gate01_EntryToHall"), NodePath(), NodePath())
	_style_switch(sw)
	root.add_child(sw)

	# Gatehouse wings double as the stage-01 containment walls (old Wall_West / Wall_East footprint).
	_solid(root, "Wall_West", Vector3(-6.75, 4.0, 0.0), Vector3(1.5, 9.0, 10.5), _m_wall())
	_solid(root, "Wall_East", Vector3(6.75, 4.0, 0.0), Vector3(1.5, 9.0, 10.5), _m_wall())
	_invisible_wall(root, "Tunnel_W", Vector3(-2.4, 2.5, 6.75), Vector3(0.4, 5.0, 3.5))
	_invisible_wall(root, "Tunnel_E", Vector3(2.4, 2.5, 6.75), Vector3(0.4, 5.0, 3.5))

	root.add_child(_make_pit_kill_zone("PitKillZone_Stage01", Vector3(0.0, -4.5, 1.0), Vector3(8.0, 2.5, 4.0)))
	root.add_child(_make_section_trigger("Trigger_Stage01_Entry", Vector3(0.0, 1.25, -56.0 + JourneyLayout.OFF_S1_TERRACE), Vector3(6.0, 2.5, 3.0),
		EncounterDirector.Section.ENTRY, Vector3(0.0, 0.0, -56.0 + JourneyLayout.OFF_S1_TERRACE), "", 0, NodePath(), false))
	root.add_child(_make_section_trigger("Trigger_Stage01_Forecourt", Vector3(0.0, 1.25, -7.5), Vector3(7.0, 2.5, 1.5),
		EncounterDirector.Section.ENTRY, Vector3(0.0, 0.0, -7.5), "", 0, NodePath(), false))

	# --- Art: monumental gatehouse facade (Z 4.5 .. 7.5), statues, banners, braziers ---
	var facade: ArrayMesh = ProcMesh.arch_mesh(22.0, 15.0, 4.6, 3.1, 3.0)
	_mesh(g[0], "Gatehouse", facade, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(0, 0, 6.0)))
	_invisible_wall(root, "Gatehouse_PierW", Vector3(-7.0, 7.0, 6.0), Vector3(9.6, 14.0, 3.0))
	_invisible_wall(root, "Gatehouse_PierE", Vector3(7.0, 7.0, 6.0), Vector3(9.6, 14.0, 3.0))
	var cornice := BoxMesh.new()
	cornice.size = Vector3(23.0, 0.8, 3.6)
	_mesh(g[0], "GatehouseCornice", cornice, _m_marble(), Transform3D(Basis.IDENTITY, Vector3(0, 15.2, 6.0)))
	var merlon := BoxMesh.new()
	merlon.size = Vector3(1.0, 1.3, 0.9)
	var merlons: Array = []
	for i in range(11):
		merlons.append(Transform3D(Basis.IDENTITY, Vector3(-10.0 + 2.0 * float(i), 16.25, 4.8)))
	_multimesh(g[0], "Merlons", merlon, _m_wall(), merlons)
	var keystone := BoxMesh.new()
	keystone.size = Vector3(1.1, 1.3, 3.3)
	_mesh(g[0], "Keystone", keystone, _m_marble(), Transform3D(Basis.IDENTITY, Vector3(0, 5.75, 6.0)))
	var tunnel_roof := BoxMesh.new()
	tunnel_roof.size = Vector3(4.6, 0.6, 3.0)
	# Pedestals + colossal guardians flanking the gate, facing the approaching pilgrim (south, -Z).
	for sx in [-1.0, 1.0]:
		# Narrower plinths pushed out to the gatehouse wings (x 4.1..5.9) so the gate stone has room beside the gate.
		_solid(root, "GuardianPlinth_%s" % ("W" if sx < 0.0 else "E"), Vector3(sx * 5.0, 1.2, 3.6), Vector3(1.8, 2.4, 2.0), _m_marble())
		_sword_monument(g[0], Vector3(sx * 5.0, 2.4, 3.6), 0.0, 10.0)
		_banner(g[1], Vector3(sx * 8.5, 13.0, 4.35), 180.0, 2.2, 7.5, false)
		_banner(g[2], Vector3(sx * 8.5, 13.0, 4.35), 180.0, 2.2, 7.5, true)
	for p in [Vector3(-6.0, 0, -14.0), Vector3(6.0, 0, -14.0), Vector3(-6.0, 0, -6.0), Vector3(6.0, 0, -6.0)]:
		_brazier(g, p)
	_brazier(g, Vector3(4.5, 0, -59.5 + JourneyLayout.OFF_S1_TERRACE))
	_brazier(g, Vector3(-4.5, 0, -59.5 + JourneyLayout.OFF_S1_TERRACE))
	_crystal_cluster(g[2], Vector3(5.0, 0.0, -57.0 + JourneyLayout.OFF_S1_TERRACE), 1.0, 12, true)
	g[1].add_child(_make_ambient_particles(Vector3(0, 3, -10), Vector3(10, 3, 6), false))
	g[2].add_child(_make_ambient_particles(Vector3(0, 3, -10), Vector3(10, 3, 6), true))
	# Journey enemies (ENTRY): a Mirror phantom haunting the gate forecourt that only reveals itself once the
	# player first shifts to cross the stepping stones, plus the gate guards. The causeway ambushes now wait on
	# the two R1 bastions (_build_routes).
	var rg: Node3D = _roamer_group(root)
	_add_roamer(rg, "phantom", "ForecourtPhantom", Vector3(3.5, 0.0, -8.0), EncounterDirector.Section.ENTRY, Vector3(0, 0, -14))
	# Gate stone guards: two enlarged Shielded Guards flanking the stepping-stone pit, a Grave Brute holding the
	# forecourt and a Hexcaster on the north landing beside the gate stone.
	for gw in [["GateWarden_W", -3.2], ["GateWarden_E", 3.2]]:
		var warden_e: EnemyBase = _add_roamer(rg, "shield", String(gw[0]), Vector3(float(gw[1]), 0.0, -2.6), EncounterDirector.Section.ENTRY, Vector3(0, 0, -14))
		_enlarge_enemy(warden_e, 1.35)
		if warden_e is EnemyAI:
			(warden_e as EnemyAI).patrol_radius = 0.0
	_add_roamer(rg, "brute", "GateBrute", Vector3(0.0, 0.0, -8.5), EncounterDirector.Section.ENTRY, Vector3(0, 0, -14))
	_add_roamer(rg, "hexcaster", "GateHexcaster", Vector3(3.2, 0.0, 3.4), EncounterDirector.Section.ENTRY, Vector3(0, 0, -2))
	return root


# =====================================================================================================
# Stage 02 — Sunlit Stair + Hall of Echoes (Y 4) + Windswept Rampart
# =====================================================================================================

func _build_stage_02_hall() -> Node3D:
	## Hall of Echoes, 3x the old room: a 60 x 60 floor at Y 4 centred on JourneyLayout.HALL_CENTER, built in
	## WORLD coordinates (2026-11-18). The Sunlit Stair and Windswept Rampart are now the winding bridges R2 / R3
	## (_build_routes). Gameplay node names are unchanged (save system + objective tracker look them up).
	var root := Node3D.new()
	root.name = "Stage02_HallOfEchoes"
	var g: Array[Node3D] = _zone("Zone02_Hall")
	var y: float = Y_HALL
	var c: Vector3 = JourneyLayout.HALL_CENTER
	var h: float = JourneyLayout.HALL_HALF
	var zs: float = c.z - h
	var zn: float = c.z + h

	var hall_floor := _solid(root, "HallFloor", Vector3(c.x, y - 0.25, c.z), Vector3(h * 2.0, 0.5, h * 2.0), _m_floor())
	var ring := ProcMesh.ring_sector_mesh(16.8, 19.8, 0.0, 0.03, 0.0, TAU, 96)
	_mesh(hall_floor, "MosaicRing", ring, _m_marble(), Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0)), false)
	var seal := _make_gate("Gate02a_HallSouthSeal", Vector3(0.0, y, zs), 1, "", true)
	_style_gate(seal)
	root.add_child(seal)
	_build_hall_walls(root, g, y)

	# Every column in the hall is a weapon: Heavy (RMB) one and it topples AWAY from whoever struck it, crushing
	# every enemy along its whole length (directional knock, BreakableProp.knock_directional). No world label.
	var pillar := _make_breakable_pillar("CrackedCentralPillar", Vector3(c.x, y, c.z), BreakableProp.PropKind.CRACKED_PILLAR, 1, 0.60, Vector3(0.0, 0.0, 2.5), 2.5)
	_restyle_pillar(pillar, 9.0, 0.7, Vector3(0, 0, 1))
	_make_knockable(pillar, 9.0)
	root.add_child(pillar)
	# A ring of eight great columns (r 17) breaks up the big floor: cover from the hexcasters, lanes to kite through.
	for i in range(8):
		var a: float = TAU * (float(i) + 0.5) / 8.0
		var cp := Vector3(c.x + sin(a) * 17.0, y, c.z + cos(a) * 17.0)
		var col := _make_breakable_pillar("HallColumn_%d" % (i + 1), cp, BreakableProp.PropKind.CRACKED_PILLAR, 1, 0.60, Vector3(0.0, 0.0, 2.5), 2.5)
		_restyle_pillar(col, 12.0, 0.9, Vector3(0, 0, 1))
		_make_knockable(col, 12.0)
		root.add_child(col)

	# Encounter garrison: every one counts toward "hall_of_echoes"; the exit gate opens when all are down.
	var hall_specs: Array = [
		["skeleton", "SkeletonGuard_1", "hall_skel_1", Vector3(-18, 0, -18)],
		["skeleton", "SkeletonGuard_2", "hall_skel_2", Vector3(18, 0, -10)],
		["skeleton", "SkeletonGuard_3", "hall_skel_3", Vector3(-10, 0, 6)],
		["skeleton", "SkeletonGuard_4", "hall_skel_4", Vector3(12, 0, 12)],
		["skeleton", "SkeletonGuard_5", "hall_skel_5", Vector3(-20, 0, 18)],
		["shield", "HallShield_1", "hall_shield_1", Vector3(-6, 0, -20)],
		["shield", "HallShield_2", "hall_shield_2", Vector3(6, 0, -22)],
		["shield", "HallShield_3", "hall_shield_3", Vector3(-24, 0, -6)],
		["shield", "HallShield_4", "hall_shield_4", Vector3(24, 0, -14)],
		["phantom", "PhantomTwin_1", "hall_phantom_1", Vector3(-18, 0, 22)],
		["phantom", "PhantomTwin_4", "hall_phantom_4", Vector3(-24, 0, 10)],
		["phantom", "PhantomTwin_6", "hall_phantom_6", Vector3(0, 0, -10)],
		# Wave 3 (all 8 enlarged Shielded Guards — 6 encounter + 2 roamers below)
		["shield", "HallShield_W3_1", "hall_shield_w3_1", Vector3(-20, 0, 18)],
		["shield", "HallShield_W3_2", "hall_shield_w3_2", Vector3(20, 0, 20)],
		["shield", "HallShield_W3_3", "hall_shield_w3_3", Vector3(-8, 0, 24)],
		["shield", "HallShield_W3_4", "hall_shield_w3_4", Vector3(10, 0, 26)],
		["shield", "HallShield_W3_5", "hall_shield_w3_5", Vector3(-16, 0, -14)],
		["shield", "HallShield_W3_6", "hall_shield_w3_6", Vector3(16, 0, -14)],
	]
	var exit_gate := _make_gate("Gate02_HallToGallery", Vector3(0.0, y, zn), 1, "hall_of_echoes", false)
	_style_gate(exit_gate)
	root.add_child(exit_gate)
	root.add_child(_make_section_trigger("Trigger_Stage02_Hall", Vector3(0.0, y + 1.25, zs + 2.0), Vector3(5.0, 2.5, 1.5),
		EncounterDirector.Section.HALL_COMBAT, Vector3(0.0, y, zs + 1.6), "hall_of_echoes", hall_specs.size(), NodePath("../Gate02a_HallSouthSeal"), false))

	if spawn_enemies:
		var enemies := Node3D.new()
		enemies.name = "Enemies"
		for spec in hall_specs:
			var e: EnemyBase = null
			var tint := Color(0.82, 0.76, 0.65)
			var kind_s: String = String(spec[0])
			if kind_s == "phantom":
				e = PhantomTwin.new()
				tint = Color(0.25, 0.78, 1.0, 0.85)
			elif kind_s == "shield":
				e = ShieldedGuard.new()
				tint = Color(0.75, 0.58, 0.25)
			else:
				e = SkeletonGuard.new()
				e.died.connect(_on_hall_skeleton_died)
			_configure_enemy_actor(e, String(spec[1]), String(spec[2]), c + (spec[3] as Vector3), tint)
			e.section_id = EncounterDirector.Section.HALL_COMBAT
			e.encounter_id = "hall_of_echoes"
			if kind_s == "shield":
				_enlarge_enemy(e, 1.35)
			enemies.add_child(e)
		root.add_child(enemies)
	# Roamers (HALL section, never hold the gate): enlarged brutes, flanks, and 2 extra enlarged Shielded Guards for Wave 3.
	var hrg: Node3D = _roamer_group(root)
	_add_roamer(hrg, "hexcaster", "HallHexcaster_W", c + Vector3(-24, 0, 0), EncounterDirector.Section.HALL_COMBAT, Vector3(0, y, zs))
	_add_roamer(hrg, "hexcaster", "HallHexcaster_E", c + Vector3(24, 0, 4), EncounterDirector.Section.HALL_COMBAT, Vector3(0, y, zs))
	var hall_brute_2: EnemyBase = _add_roamer(hrg, "brute", "HallBrute_2", c + Vector3(0, 0, -24), EncounterDirector.Section.HALL_COMBAT, Vector3(0, y, zs))
	_enlarge_enemy(hall_brute_2, 1.28)
	_add_roamer(hrg, "stalker", "HallStalker", c + Vector3(14, 0, -2), EncounterDirector.Section.HALL_COMBAT, Vector3(0, y, zs))
	var hall_sh7: EnemyBase = _add_roamer(hrg, "shield", "HallShield_W3_7", c + Vector3(-14, 0, 26), EncounterDirector.Section.HALL_COMBAT, Vector3(0, y, zs))
	_enlarge_enemy(hall_sh7, 1.35)
	var hall_sh8: EnemyBase = _add_roamer(hrg, "shield", "HallShield_W3_8", c + Vector3(0, 0, 24), EncounterDirector.Section.HALL_COMBAT, Vector3(0, y, zs))
	_enlarge_enemy(hall_sh8, 1.35)
	# Three waves of eight: Waves 1-2 mix skeletons, phantoms, brutes & enlarged Shielded Guards; Wave 3 = all 8 enlarged Shielded Guards.
	_add_waves(root, "HallWaves", EncounterDirector.Section.HALL_COMBAT, [
		["Enemies/SkeletonGuard_1", "Enemies/SkeletonGuard_2", "Enemies/SkeletonGuard_3", "Enemies/HallShield_1",
			"Enemies/HallShield_2", "Enemies/PhantomTwin_6", "Roamers/HallHexcaster_W", "Roamers/HallBrute_2"],
		["Enemies/SkeletonGuard_4", "Enemies/SkeletonGuard_5", "Enemies/HallShield_3", "Enemies/HallShield_4",
			"Enemies/PhantomTwin_1", "Enemies/PhantomTwin_4", "Roamers/HallHexcaster_E", "Roamers/HallStalker"],
		["Enemies/HallShield_W3_1", "Enemies/HallShield_W3_2", "Enemies/HallShield_W3_3", "Enemies/HallShield_W3_4",
			"Enemies/HallShield_W3_5", "Enemies/HallShield_W3_6", "Roamers/HallShield_W3_7", "Roamers/HallShield_W3_8"],
	])

	for p in [Vector3(-(h - 1.8), y, zs + 1.8), Vector3(h - 1.8, y, zs + 1.8), Vector3(-(h - 1.8), y, zn - 1.8), Vector3(h - 1.8, y, zn - 1.8),
			Vector3(-(h - 1.8), y, c.z), Vector3(h - 1.8, y, c.z)]:
		_brazier(g, p)
	for bx in [-15.0, -5.0, 5.0, 15.0]:
		_banner(g[1], Vector3(bx, y + 11.0, zn - 0.7), 180.0, 2.4, 8.0, false)
		_banner(g[2], Vector3(bx, y + 11.0, zn - 0.7), 180.0, 2.4, 8.0, true)
	# Crystals grow on the cliff just outside the arcades: seen through the grilles, never in the fighting space.
	_crystal_cluster(g[2], Vector3(-(h + 2.3), 3.4, c.z), 1.4, 21)
	_crystal_cluster(g[2], Vector3(h + 2.3, 3.4, c.z - 4.0), 1.2, 22)
	# Gate-arch piers flanking both gates protrude onto the landings: give them real collision.
	for sx in [-1.0, 1.0]:
		for gz in [zs - 0.7, zn + 0.7]:
			_prop_collider(root, "GateArchPier_%d" % int(sx), Vector3(sx * 2.6, y + 4.0, gz), _box_shape(Vector3(0.8, 8.0, 1.6)))
	g[1].add_child(_make_ambient_particles(Vector3(c.x, y + 3.5, c.z), Vector3(h - 3.0, 3.5, h - 3.0), false))
	g[2].add_child(_make_ambient_particles(Vector3(c.x, y + 3.5, c.z), Vector3(h - 3.0, 3.5, h - 3.0), true))
	return root


func _build_hall_walls(root: Node3D, g: Array[Node3D], y: float) -> void:
	var c: Vector3 = JourneyLayout.HALL_CENTER
	var h: float = JourneyLayout.HALL_HALF
	var zs: float = c.z - h
	var zn: float = c.z + h
	var wall_m: ShaderMaterial = _m_wall()
	# Collision: four sides, with 4 m openings for the south seal gate and north exit gate.
	_invisible_wall(root, "Wall_West", Vector3(-h - 0.25, y + 4.0, c.z), Vector3(0.5, 8.0, h * 2.0 + 0.5))
	_invisible_wall(root, "Wall_East", Vector3(h + 0.25, y + 4.0, c.z), Vector3(0.5, 8.0, h * 2.0 + 0.5))
	var seg_w: float = h - 2.0 + 0.2
	for sx in [-1.0, 1.0]:
		_invisible_wall(root, "Wall_South_%d" % int(sx), Vector3(sx * (2.0 + seg_w * 0.5), y + 4.0, zs - 0.25), Vector3(seg_w, 8.0, 0.5))
		_invisible_wall(root, "Wall_North_%d" % int(sx), Vector3(sx * (2.0 + seg_w * 0.5), y + 4.0, zn + 0.25), Vector3(seg_w, 8.0, 0.5))

	# Visual: two-storey arcades on all four sides (arch modules + grilles), corner towers, cornice.
	var mod_w: float = 4.0
	var arch_low: ArrayMesh = ProcMesh.arch_mesh(mod_w, 8.0, 2.6, 3.6, 1.4)
	var arch_up: ArrayMesh = ProcMesh.arch_mesh(mod_w, 5.0, 2.4, 2.4, 1.0)
	var grille: ArrayMesh = ProcMesh.portcullis_mesh(2.6, 4.6, 0.08, 0.32)
	var low_x: Array = []
	var up_x: Array = []
	var grille_x: Array = []
	# West/East sides: 4 m modules along Z (15 per 60 m side), facing inward.
	var n_mod: int = int(round(h * 2.0 / mod_w))
	for sx in [-1.0, 1.0]:
		for i in range(n_mod):
			var z: float = zs + mod_w * (float(i) + 0.5)
			var b := Basis(Vector3.UP, PI * 0.5)
			low_x.append(Transform3D(b, Vector3(sx * (h + 0.7), y, z)))
			up_x.append(Transform3D(b, Vector3(sx * (h + 0.9), y + 8.0, z)))
			grille_x.append(Transform3D(b, Vector3(sx * (h + 0.7), y, z)))
	# South/North sides: eight equal bays each side of the 6 m gate arch tile x 3 .. h exactly (no overlaps).
	var bays: int = 8
	var bay_w: float = (h - 3.0) / float(bays)
	var side_low: ArrayMesh = ProcMesh.arch_mesh(bay_w, 8.0, bay_w - 1.2, 3.6, 1.4)
	var side_up: ArrayMesh = ProcMesh.arch_mesh(bay_w, 5.0, bay_w - 1.4, 2.4, 1.0)
	var side_grille: ArrayMesh = ProcMesh.portcullis_mesh(bay_w - 1.2, 4.6, 0.08, 0.32)
	var gate_arch: ArrayMesh = ProcMesh.arch_mesh(6.0, 8.0, 4.4, 3.4, 1.6)
	var gate_up: ArrayMesh = ProcMesh.arch_mesh(6.0, 5.0, 3.4, 2.4, 1.0)
	var side_low_x: Array = []
	var side_up_x: Array = []
	var side_grille_x: Array = []
	for sz in [zs - 0.7, zn + 0.7]:
		for k in range(bays):
			var bx: float = 3.0 + bay_w * (float(k) + 0.5)
			for sx in [-1.0, 1.0]:
				side_low_x.append(Transform3D(Basis.IDENTITY, Vector3(sx * bx, y, sz)))
				side_up_x.append(Transform3D(Basis.IDENTITY, Vector3(sx * bx, y + 8.0, sz)))
				side_grille_x.append(Transform3D(Basis.IDENTITY, Vector3(sx * bx, y, sz)))
		_mesh(g[0], "GateArch", gate_arch, wall_m, Transform3D(Basis.IDENTITY, Vector3(0, y, sz)))
		_mesh(g[0], "GateArchUpper", gate_up, wall_m, Transform3D(Basis.IDENTITY, Vector3(0, y + 8.0, sz)))
	_multimesh(g[0], "HallArcadeLower", arch_low, wall_m, low_x)
	_multimesh(g[0], "HallArcadeUpper", arch_up, wall_m, up_x)
	_multimesh(g[0], "HallGrilles", grille, _m_iron(), grille_x)
	_multimesh(g[0], "HallArcadeLowerNS", side_low, wall_m, side_low_x)
	_multimesh(g[0], "HallArcadeUpperNS", side_up, wall_m, side_up_x)
	_multimesh(g[0], "HallGrillesNS", side_grille, _m_iron(), side_grille_x)
	# Corner towers
	var tower := BoxMesh.new()
	tower.size = Vector3(4.0, 24.0, 4.0)
	var towers: Array = []
	for cx in [-(h + 2.0), h + 2.0]:
		for cz in [zs - 2.0, zn + 2.0]:
			towers.append(Transform3D(Basis.IDENTITY, Vector3(cx, y + 6.0, cz)))
	_multimesh(g[0], "HallTowers", tower, wall_m, towers)
	var tower_cap := BoxMesh.new()
	tower_cap.size = Vector3(4.8, 0.8, 4.8)
	var caps: Array = []
	for t in towers:
		var tt: Transform3D = t
		caps.append(Transform3D(Basis.IDENTITY, tt.origin + Vector3(0, 12.4, 0)))
	_multimesh(g[0], "HallTowerCaps", tower_cap, _m_marble(), caps)
	# Cornice ring
	var cor := BoxMesh.new()
	cor.size = Vector3(1.6, 0.7, h * 2.0 + 4.0)
	_mesh(g[0], "CorniceW", cor, _m_marble(), Transform3D(Basis.IDENTITY, Vector3(-(h + 0.9), y + 13.35, c.z)))
	_mesh(g[0], "CorniceE", cor, _m_marble(), Transform3D(Basis.IDENTITY, Vector3(h + 0.9, y + 13.35, c.z)))
	# N/S runs sit 4 cm higher so the overlapping corner blocks never share a top/bottom plane.
	_mesh(g[0], "CorniceS", cor, _m_marble(), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, y + 13.39, zs - 1.0)))
	_mesh(g[0], "CorniceN", cor, _m_marble(), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, y + 13.39, zn + 1.0)))


# =====================================================================================================
# Winding bridges (2026-11-18): the four connectors as long zig-zag bridges with two bastions each.
# Geometry lives in JourneyLayout.ROUTES (world coordinates); garrisons below.
# =====================================================================================================

## Bastion garrisons per bridge: [bastion 1 kinds, bastion 2 kinds] (roamer kinds of _add_roamer).
const ROUTE_ENEMIES: Dictionary = {
	"R1_PilgrimCauseway": [["skeleton", "skeleton", "hexcaster"], ["skeleton", "shield", "hexcaster"]],
	"R2_SunlitBridges": [["phantom", "skeleton", "stalker"], ["skeleton", "skeleton", "hexcaster"]],
	"R3_WindsweptRampart": [["skeleton", "stalker", "hexcaster"], ["brute", "skeleton", "phantom"]],
	"R5_Processional": [["phantom", "skeleton", "hexcaster"], ["shield", "skeleton", "brute"]],
}


func _route_section(route_name: String) -> int:
	## The section that is current while the player walks this bridge (roamers wake only in their section).
	match route_name:
		"R3_WindsweptRampart":
			return EncounterDirector.Section.HALL_COMBAT
		"R5_Processional":
			return EncounterDirector.Section.MECHANISM_CHAMBER
		_:
			return EncounterDirector.Section.ENTRY


func _build_routes() -> Node3D:
	var all := Node3D.new()
	all.name = "Journey_Routes"
	var g: Array[Node3D] = _zone("Zone_Routes")
	var seed_i: int = 900
	for r in JourneyLayout.ROUTES:
		var rname: String = String((r as Array)[0])
		var nodes: Array = (r as Array)[1]
		var root := Node3D.new()
		root.name = rname
		all.add_child(root)
		var kinds: Array = ROUTE_ENEMIES.get(rname, [])
		var bi: int = 0
		for i in range(1, nodes.size() - 1):
			var nd: Array = nodes[i]
			if float(nd[1]) <= 0.0:
				continue
			var bk: Array = []
			if bi < kinds.size():
				bk = kinds[bi]
			var prev_p: Vector3 = (nodes[i - 1] as Array)[0]
			var next_p: Vector3 = (nodes[i + 1] as Array)[0]
			_build_bastion(root, g, "%s_Bastion%d" % [rname, bi + 1], nd[0] as Vector3, float(nd[1]), [prev_p, next_p], bk, _route_section(rname), seed_i)
			seed_i += 1
			bi += 1
		for i in range(nodes.size() - 1):
			_build_bridge_leg(root, g, "%s_Leg%d" % [rname, i + 1], nodes[i] as Array, nodes[i + 1] as Array)
	return all


func _build_bastion(root: Node3D, g: Array[Node3D], bname: String, c: Vector3, r: float, neighbours: Array, kinds: Array, section: int, seed_val: int) -> void:
	## Round fortified platform: walkable disc on a masonry drum and rock spur, ring parapet with openings exactly
	## where the bridge legs arrive, merlons, two braziers on the far side, and a garrison of roamers.
	var off: float = JourneyLayout.BRIDGE_WIDTH * 0.5 + 0.2
	var rr: float = r - 0.2
	var body := StaticBody3D.new()
	body.name = bname
	body.position = Vector3(c.x, c.y - 0.25, c.z)
	body.collision_layer = LAYER_WORLD_SHARED
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = _cyl_shape(r, 0.5)
	body.add_child(cs)
	var deck := CylinderMesh.new()
	deck.top_radius = r
	deck.bottom_radius = r
	deck.height = 0.5
	deck.radial_segments = 40
	deck.rings = 1
	_mesh(body, "Deck", deck, _m_floor(), Transform3D.IDENTITY, true, 0.0, false)
	root.add_child(body)
	var drum := CylinderMesh.new()
	drum.top_radius = r + 0.3
	drum.bottom_radius = r + 1.4
	drum.height = 8.0
	drum.radial_segments = 32
	drum.rings = 1
	_mesh(g[0], "BastionDrum", drum, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(c.x, c.y - 0.52 - 4.0, c.z)))
	var rk: MeshInstance3D = _rock(_scenery, "BastionRock", Vector3(c.x, c.y - 8.6, c.z), Vector3(r * 2.0 + 5.0, 60.0, r * 2.0 + 5.0), seed_val, _m_rock(), 0.72, 0.24, 14, false, true)
	rk.remove_meta("gj_batch")
	# Ring parapet: arcs between the openings. Each opening spans +-asin(off / rr) around a leg direction, so the
	# leg's side rails end exactly on the arc ends (no gap to fall through).
	var opens: Array[float] = []
	for nb in neighbours:
		var d: Vector3 = (nb as Vector3) - c
		opens.append(atan2(d.x, d.z))
	opens.sort()
	var beta: float = asin(clampf(off / rr, 0.0, 1.0))
	var arcs: Array = []
	for i in range(opens.size()):
		var a0: float = opens[i] + beta
		var a1: float = opens[(i + 1) % opens.size()] - beta
		if i == opens.size() - 1:
			a1 += TAU
		if a1 - a0 > 0.05:
			arcs.append([a0, a1])
	var merlon := BoxMesh.new()
	merlon.size = Vector3(0.9, 1.0, 0.55)
	var merlons: Array = []
	var seg: int = 0
	var far_arc: Array = [0.0, 0.0]
	for arc in arcs:
		var a0: float = float(arc[0])
		var a1: float = float(arc[1])
		if a1 - a0 > float(far_arc[1]) - float(far_arc[0]):
			far_arc = [a0, a1]
		var n: int = maxi(1, ceili((a1 - a0) / 0.26))
		for k in range(n):
			var t0: float = lerpf(a0, a1, float(k) / float(n))
			var t1: float = lerpf(a0, a1, float(k + 1) / float(n))
			var p0 := Vector3(c.x + sin(t0) * rr, c.y, c.z + cos(t0) * rr)
			var p1 := Vector3(c.x + sin(t1) * rr, c.y, c.z + cos(t1) * rr)
			_parapet(root, "%s_Ring%d" % [bname, seg], p0, p1, _m_wall())
			seg += 1
		var nm: int = int((a1 - a0) * rr / 2.4)
		for k in range(nm):
			var am: float = lerpf(a0, a1, (float(k) + 0.5) / float(nm))
			merlons.append(Transform3D(Basis(Vector3.UP, am), Vector3(c.x + sin(am) * rr, c.y + 1.75, c.z + cos(am) * rr)))
	if not merlons.is_empty():
		_multimesh(g[0], "BastionMerlons", merlon, _m_wall(), merlons)
	# Braziers on the far (outer) side of the bend, garrison spread around the centre facing the way in.
	var m: float = (float(far_arc[0]) + float(far_arc[1])) * 0.5
	for s in [-0.42, 0.42]:
		_brazier(g, Vector3(c.x + sin(m + s) * (rr - 1.3), c.y, c.z + cos(m + s) * (rr - 1.3)))
	var face: Vector3 = neighbours[0] as Vector3
	var spots: Array = [m, m + 2.2, m - 2.2]
	for ei in range(kinds.size()):
		var a: float = float(spots[ei % spots.size()])
		var ep := Vector3(c.x + sin(a) * 3.4, c.y, c.z + cos(a) * 3.4)
		var kind: String = String(kinds[ei])
		var roamer := _add_roamer(_roamer_group(root), kind, "%s_%s%d" % [bname, kind.capitalize(), ei + 1], ep, section, face)
		if roamer is EnemyAI:
			(roamer as EnemyAI).patrol_radius = maxf(2.0, r - 2.5)


func _build_bridge_leg(root: Node3D, g: Array[Node3D], lname: String, na: Array, nb: Array) -> void:
	## One straight span between two bridge nodes: sloped deck between the bastion edges (or from a floor edge,
	## with a flat apron tucked into that floor so the angled end leaves no hole), side parapets, join rails along
	## a floor edge, and masonry piers under long spans.
	var a: Vector3 = na[0]
	var b: Vector3 = nb[0]
	var ra: float = float(na[1])
	var rb: float = float(nb[1])
	var w: float = JourneyLayout.BRIDGE_WIDTH
	var off: float = w * 0.5 + 0.2
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var u: Vector3 = flat.normalized()
	var nrm := Vector3(u.z, 0.0, -u.x)
	var tan_th: float = absf(u.x) / maxf(absf(u.z), 0.05)
	var a_deck: Vector3 = a + u * (ra - 0.4) if ra > 0.0 else a
	var b_deck: Vector3 = b - u * (rb - 0.4) if rb > 0.0 else b
	if ra <= 0.0:
		var apron_a := _ramp(root, lname + "_ApronA", a - u * (w * 0.5 * tan_th + 0.6), a, w, _m_path())
		apron_a.position.y -= 0.02
	if rb <= 0.0:
		var apron_b := _ramp(root, lname + "_ApronB", b, b + u * (w * 0.5 * tan_th + 0.6), w, _m_path())
		apron_b.position.y -= 0.02
	_ramp(root, lname, a_deck, b_deck, w, _m_path())
	# Side parapets: from the bastion ring (or the floor edge line) to the next ring / edge.
	for s in [-1.0, 1.0]:
		var p0: Vector3
		var p1: Vector3
		if ra > 0.0:
			p0 = a + u * sqrt(maxf(0.0, (ra - 0.2) * (ra - 0.2) - off * off)) + nrm * (s * off)
		else:
			p0 = _line_at_z(a, b, s * off, float(na[2]))
		if rb > 0.0:
			p1 = b - u * sqrt(maxf(0.0, (rb - 0.2) * (rb - 0.2) - off * off)) + nrm * (s * off)
		else:
			p1 = _line_at_z(a, b, s * off, float(nb[2]))
		p0.y = a.y
		p1.y = b.y
		_parapet(root, "%s_Rail%s" % [lname, "R" if s > 0.0 else "L"], p0, p1, _m_wall())
	# Join rails along a floor edge (z = edge_z, edge opening |x| <= edge_half_width) out to the bridge rails.
	for e in [[na, ra, a], [nb, rb, b]]:
		if float(e[1]) > 0.0:
			continue
		var nd: Array = e[0]
		var ez: float = float(nd[2])
		var hw: float = float(nd[3])
		var ey: float = (e[2] as Vector3).y
		var xl: float = _line_at_z(a, b, -off, ez).x
		var xr: float = _line_at_z(a, b, off, ez).x
		var lo: float = minf(xl, xr)
		var hi: float = maxf(xl, xr)
		var join_hw: float = hw + 0.25
		if lo < -join_hw:
			_parapet(root, lname + "_JoinW", Vector3(-join_hw, ey, ez), Vector3(lo, ey, ez), _m_wall())
		elif lo > -hw + 0.05:
			_parapet(root, lname + "_JoinW", Vector3(-hw, ey, ez), Vector3(lo, ey, ez), _m_wall())
		if hi > join_hw:
			_parapet(root, lname + "_JoinE", Vector3(join_hw, ey, ez), Vector3(hi, ey, ez), _m_wall())
		elif hi < hw - 0.05:
			_parapet(root, lname + "_JoinE", Vector3(hi, ey, ez), Vector3(hw, ey, ez), _m_wall())
	# Masonry piers under long spans (visual only; the kill plane still catches falls).
	var piers: int = int(flat.length() / 16.0)
	for k in range(piers):
		var pp: Vector3 = a_deck.lerp(b_deck, (float(k) + 1.0) / float(piers + 1))
		var pier := BoxMesh.new()
		pier.size = Vector3(w * 0.55, 30.0, 2.2)
		_mesh(g[0], "BridgePier", pier, _m_wall(), Transform3D(Basis(Vector3.UP, atan2(u.x, u.z)), Vector3(pp.x, pp.y - 0.62 - 15.0, pp.z)))


# =====================================================================================================
# Stage 03 — Aqueduct Gallery over the gorge (Y 6)
# =====================================================================================================

func _build_stage_03_gallery() -> Node3D:
	var root := Node3D.new()
	root.name = "Stage03_CollapsedGallery"
	var g: Array[Node3D] = _zone("Zone03_Gallery")
	# Story-coordinate stage: the stage root and its decor zone are shifted onto the stretched layout.
	root.position.z = JourneyLayout.OFF_S3
	(g[0].get_parent() as Node3D).position.z = JourneyLayout.OFF_S3
	var y: float = Y_GALLERY

	_solid(root, "GalleryFloorSouth", Vector3(0.0, y - 0.25, 65.0), Vector3(8.0, 0.5, 10.0), _m_path())
	# North deck = the Shielded Guard's duel ground: 18 m wide so the fight has room (was 8 m, the guard got
	# wedged between wall and gate).
	_solid(root, "GalleryFloorNorth", Vector3(0.0, y - 0.25, 79.0), Vector3(18.0, 0.5, 10.0), _m_path())
	_solid(root, "Corridor03_Floor", Vector3(0.0, y - 0.25, 86.0), Vector3(4.0, 0.5, 4.0), _m_floor())
	root.add_child(_make_pit_kill_zone("PitKillZone_Stage03", Vector3(0.0, y - 4.5, 72.0), Vector3(8.0, 2.5, 14.0)))
	(root.get_node("PitKillZone_Stage03") as PitKillZone).kill_y_threshold = y - 3.0

	var bridge := RealmPlatform.new()
	bridge.name = "GallerySpectralBridge"
	bridge.position = Vector3(0.0, y, 72.0)
	var reality_geo := Node3D.new()
	reality_geo.name = "RealityGeometry"
	bridge.add_child(reality_geo)
	var mirror_geo := Node3D.new()
	mirror_geo.name = "MirrorGeometry"
	mirror_geo.add_child(_make_box_body("SpectralBridgeSpan", Vector3(0.0, -0.25, 0.0), Vector3(3.0, 0.5, 4.0), LAYER_WORLD_MIRROR, Color(0.20, 0.72, 1.0, 0.85)))
	bridge.add_child(mirror_geo)
	var repaired_geo := Node3D.new()
	repaired_geo.name = "RepairedGeometry"
	var repaired := _solid(repaired_geo, "RepairedBridgeSpan", Vector3(0.0, -0.25, 0.0), Vector3(3.0, 0.5, 4.0), _m_marble(), LAYER_WORLD_SHARED | LAYER_WORLD_REALITY)
	# After repair both spans are visible in the Mirror: lift the stone span's mesh 1.5 cm so it cleanly
	# covers the spectral slab instead of z-fighting with it (colliders untouched).
	(repaired.get_node("Mesh") as Node3D).position = Vector3(0, 0.015, 0)
	bridge.add_child(repaired_geo)
	root.add_child(bridge)

	# One clear Mirror lesson, no side errands: the bridge and the guard's shield both answer to the realms.
	# Cross the spectral span in the Mirror, break the Shielded Guard (shield exists only in Reality) on the wide
	# north deck; his fall opens the gate AND rebuilds the bridge in stone (way back for the squad).
	var gate := _make_gate("Gate03_GalleryToMechanism", Vector3(0.0, y, 84.0), 2, "shielded_guard", false)
	_style_gate(gate)
	root.add_child(gate)
	root.add_child(_make_section_trigger("Trigger_Stage03_Gallery", Vector3(0.0, y + 1.25, 61.5), Vector3(4.0, 2.5, 1.5),
		EncounterDirector.Section.COLLAPSED_GALLERY, Vector3(0.0, y, 61.5 + JourneyLayout.OFF_S3), "shielded_guard", 1, NodePath(), false))
	if spawn_enemies:
		var enemies := Node3D.new()
		enemies.name = "Enemies"
		var sg := ShieldedGuard.new()
		_configure_enemy_actor(sg, "ShieldedGuard_1", "gallery_shielded_1", Vector3(0.0, y, 79.5), Color(0.75, 0.58, 0.25))
		sg.died.connect(func(_e: Node, _ctx: Dictionary) -> void:
			if is_instance_valid(bridge) and not bridge.is_permanently_repaired:
				bridge.repair_for_reality())
		enemies.add_child(sg)
		root.add_child(enemies)
	# Gallery deck patrol (roamers: they never hold the gallery gate shut).
	var grg: Node3D = _roamer_group(root)
	_add_roamer(grg, "skeleton", "GallerySkeleton_A", Vector3(-2.4, y, 63.5), EncounterDirector.Section.COLLAPSED_GALLERY, Vector3(0, y, 60))
	_add_roamer(grg, "skeleton", "GallerySkeleton_B", Vector3(2.4, y, 66.5), EncounterDirector.Section.COLLAPSED_GALLERY, Vector3(0, y, 60))

	# Deck edges: parapets except across the broken span.
	for sx in [-1.0, 1.0]:
		_parapet(root, "Rail_S_%d" % int(sx), Vector3(sx * 3.95, y, 60.0), Vector3(sx * 3.95, y, 70.0), _m_wall())
		_parapet(root, "Rail_N_%d" % int(sx), Vector3(sx * 8.95, y, 74.0), Vector3(sx * 8.95, y, 84.0), _m_wall())
		# South edge of the wide north deck: open only where the 3 m bridge lands (the gap stays a real pit).
		_parapet(root, "Rail_NorthDeckS_%d" % int(sx), Vector3(sx * 2.0, y, 74.0), Vector3(sx * 8.95, y, 74.0), _m_wall())
		_parapet(root, "Rail_SouthJoin_%d" % int(sx), Vector3(sx * 2.9, y, 60.0), Vector3(sx * 3.95, y, 60.0), _m_wall())
		_parapet(root, "Rail_NorthJoin_%d" % int(sx), Vector3(sx * 2.2, y, 84.0), Vector3(sx * 8.95, y, 84.0), _m_wall())
	_parapet(root, "Corridor03_W", Vector3(-2.2, y, 84.0), Vector3(-2.2, y, 87.0), _m_wall())
	_parapet(root, "Corridor03_E", Vector3(2.2, y, 84.0), Vector3(2.2, y, 87.0), _m_wall())

	# --- Art: aqueduct arcade plunging into the gorge, broken at the gap ---
	var aq: ArrayMesh = ProcMesh.arch_mesh(5.0, 46.0, 3.2, 31.0, 7.6)
	var aqx: Array = []
	for z in [62.5, 67.5, 76.5, 81.5]:
		aqx.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, y - 0.5 - 46.0, z)))
	_multimesh(g[0], "AqueductArches", aq, _m_wall(), aqx)
	# Broken masonry stubs hanging under the gap; tops clamped 0.6 m below the deck so nothing at walking
	# height suggests a footing that isn't there.
	_rock(g[0], "BrokenSpanSouth", Vector3(0, y - 0.6, 70.6), Vector3(7.0, 4.0, 3.0), 77, _m_wall(), 1.0, 0.3, 8)
	_rock(g[0], "BrokenSpanNorth", Vector3(0, y - 0.7, 73.4), Vector3(7.0, 4.0, 3.0), 78, _m_wall(), 1.0, 0.3, 8)
	# Ruined colonnade on the deck edges (collidable shafts), some snapped short.
	var shafts: Array = [[61.5, 4.5], [65.5, 2.0], [69.0, 4.5], [75.5, 4.5], [79.5, 1.6], [83.0, 4.5]]
	for sx in [-1.0, 1.0]:
		for s in shafts:
			var h: float = float(s[1]) if sx < 0.0 else float(s[1]) * (0.6 if float(s[0]) > 70.0 else 1.0)
			var pos := Vector3(sx * (3.45 if float(s[0]) < 72.0 else 8.45), y, float(s[0]))
			_mesh(g[0], "RuinColumn", ProcMesh.column_mesh(0.3, h, 12), _m_marble(), Transform3D(Basis.IDENTITY, pos), true, 160.0)
			var body := StaticBody3D.new()
			body.name = "RuinColumnBody"
			body.collision_layer = LAYER_WORLD_SHARED
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.5 # covers the 0.78 m square base block of the ruin column
			cyl.height = h
			cs.shape = cyl
			body.add_child(cs)
			body.position = pos + Vector3(0, h * 0.5, 0)
			root.add_child(body)
	# Gorge walls framing the crossing + mist rising from the depths.
	# Gorge walls frame only the broken span (kept short of the rampart so its sunset vista stays open).
	_rock(_scenery, "GorgeWallWest", Vector3(-36.0, y + 12.0, 76.0 + JourneyLayout.OFF_S3), Vector3(26.0, 84.0, 28.0), 301, _m_rock(), 1.0, 0.2, 14)
	_rock(_scenery, "GorgeWallEast", Vector3(36.0, y + 20.0, 72.0 + JourneyLayout.OFF_S3), Vector3(26.0, 92.0, 34.0), 302, _m_rock(), 1.0, 0.2, 14)
	_brazier(g, Vector3(-3.0, y, 61.0))
	_brazier(g, Vector3(3.0, y, 61.0))
	_crystal_cluster(g[2], Vector3(0.0, y - 3.0, 70.2), 1.6, 31)
	_crystal_cluster(g[2], Vector3(-0.6, y - 3.0, 73.8), 1.4, 32)
	var mist := _make_ambient_particles(Vector3(0, y - 14.0, 72.0), Vector3(14, 10, 18), false)
	mist.name = "GorgeMist"
	g[0].add_child(mist)
	g[1].add_child(_make_ambient_particles(Vector3(0, y + 2.5, 72), Vector3(4, 2.5, 12), false))
	g[2].add_child(_make_ambient_particles(Vector3(0, y + 2.5, 72), Vector3(5, 3, 12), true))
	return root


# =====================================================================================================
# Stage 04 — Clock-Tower Mechanism Chamber (Y 6)
# =====================================================================================================

func _build_stage_04_mechanism() -> Node3D:
	## Clock-Tower Mechanism Chamber, 3x the old room: a 36 x 36 floor at Y 6 centred on
	## JourneyLayout.CHAMBER_CENTER, built in WORLD coordinates (2026-11-18). The puzzle (dais, weight, plate)
	## keeps its proven dimensions at the centre; the room, clockwork, tower and garrison grew around it.
	var root := Node3D.new()
	root.name = "Stage04_MechanismChamber"
	var g: Array[Node3D] = _zone("Zone04_Tower")
	var y: float = Y_GALLERY
	var cz: float = JourneyLayout.CHAMBER_CENTER.z
	var h: float = JourneyLayout.CHAMBER_HALF
	var wall_h: float = 24.0
	var span: float = h * 2.0 + 3.0

	_solid(root, "ChamberFloor", Vector3(0.0, y - 0.25, cz), Vector3(h * 2.0, 0.5, h * 2.0), _m_floor())
	_solid(root, "RaisedImpactDais", Vector3(-3.0, y + 0.675, cz - 1.0), Vector3(2.5, 1.35, 2.5), _m_marble())
	# Walls (visible, tall) with 4 m openings south & north.
	_solid(root, "Wall_West", Vector3(-h - 0.75, y + wall_h * 0.5, cz), Vector3(1.5, wall_h, h * 2.0 + 1.5), _m_wall())
	_solid(root, "Wall_East", Vector3(h + 0.75, y + wall_h * 0.5, cz), Vector3(1.5, wall_h, h * 2.0 + 1.5), _m_wall())
	var seg_w: float = h - 2.0
	for sx in [-1.0, 1.0]:
		# Segments butt exactly against the side walls' inner faces (x = +-h): no overlapping corners.
		_solid(root, "Wall_South_%d" % int(sx), Vector3(sx * (2.0 + seg_w * 0.5), y + wall_h * 0.5, cz - h - 0.6), Vector3(seg_w, wall_h, 1.2), _m_wall())
		_solid(root, "Wall_North_%d" % int(sx), Vector3(sx * (2.0 + seg_w * 0.5), y + wall_h * 0.5, cz + h + 0.6), Vector3(seg_w, wall_h, 1.2), _m_wall())
	var lintel := BoxMesh.new()
	lintel.size = Vector3(4.0, wall_h - 4.0, 1.2)
	_mesh(g[0], "LintelSouth", lintel, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(0, y + 4.0 + (wall_h - 4.0) * 0.5, cz - h - 0.6)))
	_mesh(g[0], "LintelNorth", lintel, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(0, y + 4.0 + (wall_h - 4.0) * 0.5, cz + h + 0.6)))
	# Ceiling with a 4 x 4 oculus at the top of the walls.
	var ceil_y: float = y + wall_h + 0.5
	var ceil_piece := BoxMesh.new()
	ceil_piece.size = Vector3(span, 1.0, h - 0.5)
	_mesh(g[0], "CeilingS", ceil_piece, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(0, ceil_y, cz - 2.0 - (h - 0.5) * 0.5)))
	_mesh(g[0], "CeilingN", ceil_piece, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(0, ceil_y, cz + 2.0 + (h - 0.5) * 0.5)))
	var ceil_side := BoxMesh.new()
	ceil_side.size = Vector3(h - 0.5, 1.0, 4.0)
	_mesh(g[0], "CeilingW", ceil_side, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(-2.0 - (h - 0.5) * 0.5, ceil_y, cz)))
	_mesh(g[0], "CeilingE", ceil_side, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(2.0 + (h - 0.5) * 0.5, ceil_y, cz)))
	# Tower exterior rising above: spire block + pyramid roof.
	var spire := BoxMesh.new()
	spire.size = Vector3(span, 14.0, span)
	_mesh(g[0], "TowerUpper", spire, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(0, y + wall_h + 8.0, cz)))
	var roof := CylinderMesh.new()
	roof.top_radius = 0.0
	roof.bottom_radius = span * 0.7
	roof.height = 24.0
	roof.radial_segments = 4
	roof.rings = 1
	_mesh(g[0], "TowerRoof", roof, _m_bronze(), Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, y + wall_h + 27.0, cz)))

	var gate := _make_gate("Gate04_MechanismToArena", Vector3(0.0, y, cz + h), 3, "", false)
	_style_gate(gate)
	root.add_child(gate)
	root.add_child(_make_section_trigger("Trigger_Stage04_Mechanism", Vector3(0.0, y + 1.25, cz - h + 1.5), Vector3(4.5, 2.5, 1.5),
		EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0.0, y, cz - h + 1.5), "", 0, NodePath(), false))

	var puzzle := MechanismPuzzle.new()
	puzzle.name = "ChamberMechanismPuzzle"
	puzzle.position = Vector3(0.0, y, cz)
	puzzle.linked_gate_path = NodePath("../Gate04_MechanismToArena")
	puzzle.weight_node_path = NodePath("SuspendedWeight")
	puzzle.plate_node_path = NodePath("PressurePlate")
	var weight := Node3D.new()
	weight.name = "SuspendedWeight"
	weight.position = Vector3(0.0, 2.5, 0.0)
	weight.add_child(_make_mesh_box("WeightMesh", Vector3(1.2, 1.2, 1.2), Color(0.20, 0.72, 1.0, 0.85)))
	var chain := BoxMesh.new()
	chain.size = Vector3(0.08, 14.0, 0.08)
	for cx in [-0.45, 0.45]:
		_mesh(weight, "Chain", chain, _m_crystal(), Transform3D(Basis.IDENTITY, Vector3(cx, 7.6, 0)), false)
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
	var plate_mesh := CylinderMesh.new()
	plate_mesh.top_radius = 0.95
	plate_mesh.bottom_radius = 1.05
	plate_mesh.height = 0.14
	plate_mesh.radial_segments = 24
	# Recessed plate: top sits 3 cm proud of the floor (was 14 cm, which feet clipped through).
	_mesh(plate, "PlateMesh", plate_mesh, _m_bronze(), Transform3D(Basis.IDENTITY, Vector3(0, -0.04, 0)), true, 0.0, false)
	puzzle.add_child(plate)
	root.add_child(puzzle)

	# Clockwork: bronze gears turning on both side walls. [side, height (old y-6 datum), z offset, radius,
	# turns per 40 s, inset]. Meshing pairs sit on different depth planes (0.4 m apart) and clear the pilasters.
	for spec in [[-1.0, 12.0, -0.7, 3.4, 1.0, 0.0], [-1.0, 15.5, 2.2, 2.2, -1.6, 0.4], [1.0, 11.0, 1.2, 3.0, -1.0, 0.0], [1.0, 15.0, -2.4, 2.0, 1.4, 0.4],
			[-1.0, 14.0, 10.5, 4.0, 0.7, 0.0], [-1.0, 18.5, 10.5, 2.6, -1.2, 0.4], [1.0, 13.0, -10.5, 4.0, -0.8, 0.0], [1.0, 18.0, -10.5, 2.8, 1.1, 0.4]]:
		var gear: ArrayMesh = ProcMesh.gear_mesh(float(spec[3]), 0.35, int(float(spec[3]) * 6.0), 0.35)
		var gpos := Vector3(float(spec[0]) * (h - 0.05 - float(spec[5])), y + float(spec[1]) - 6.0, cz + float(spec[2]))
		var gm := _mesh(g[0], "Gear", gear, _m_bronze(), Transform3D(Basis(Vector3.UP, PI * 0.5), gpos), true, 0.0, false)
		var tw := gm.create_tween().set_loops()
		tw.tween_property(gm, "rotation:x", TAU * signf(float(spec[4])), 40.0 / absf(float(spec[4]))).as_relative()
		_anim_tweens.append(tw)
	# Pilasters
	var pil := BoxMesh.new()
	pil.size = Vector3(0.4, wall_h - 1.0, 0.9)
	var pils: Array = []
	for sx in [-1.0, 1.0]:
		for dz in [-16.0, -5.5, 5.5, 16.0]:
			var pp := Vector3(sx * (h - 0.2), y + (wall_h - 1.0) * 0.5, cz + dz)
			pils.append(Transform3D(Basis.IDENTITY, pp))
			_prop_collider(root, "PilasterCollider", pp, _box_shape(Vector3(0.4, wall_h - 1.0, 0.9)))
	_multimesh(g[0], "Pilasters", pil, _m_marble(), pils)
	_brazier(g, Vector3(-(h - 1.4), y, cz + h - 1.0))
	_brazier(g, Vector3(h - 1.4, y, cz + h - 1.0))
	_brazier(g, Vector3(-(h - 1.4), y, cz - h + 1.4))
	_crystal_cluster(g[2], Vector3(h - 1.4, y, cz - h + 1.4), 1.0, 41, true)
	g[1].add_child(_make_ambient_particles(Vector3(0, y + 6, cz), Vector3(h - 0.5, 6, h - 0.5), false))
	g[2].add_child(_make_ambient_particles(Vector3(0, y + 6, cz), Vector3(h - 0.5, 6, h - 0.5), true))
	# Tower garrison (MECHANISM section): skeletons and a brute hold the floor, a hexcaster and a stalker work
	# the flanks, and a phantom harries the player in the Mirror while they line up the landing slam.
	var rg: Node3D = _roamer_group(root)
	var door := Vector3(0, y, cz - h)
	_add_roamer(rg, "skeleton", "TowerSkeleton_A", Vector3(10.0, y, cz + 10.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "skeleton", "TowerSkeleton_B", Vector3(-12.0, y, cz + 9.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "phantom", "TowerPhantom", Vector3(11.0, y, cz - 6.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	var t_sh1: EnemyBase = _add_roamer(rg, "shield", "TowerShield_1", Vector3(-6.0, y, cz - 14.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_enlarge_enemy(t_sh1, 1.35)
	var t_sh2: EnemyBase = _add_roamer(rg, "shield", "TowerShield_2", Vector3(14.0, y, cz - 12.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_enlarge_enemy(t_sh2, 1.35)
	_add_roamer(rg, "skeleton", "TowerSkeleton_H", Vector3(8.0, y, cz + 4.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)

	_add_roamer(rg, "skeleton", "TowerSkeleton_C", Vector3(-10.0, y, cz - 10.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	var t_sh3: EnemyBase = _add_roamer(rg, "shield", "TowerShield_3", Vector3(6.0, y, cz + 14.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_enlarge_enemy(t_sh3, 1.35)
	_add_roamer(rg, "hexcaster", "TowerHexcaster", Vector3(-14.0, y, cz + 2.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	var t_sh4: EnemyBase = _add_roamer(rg, "shield", "TowerShield_4", Vector3(-15.0, y, cz + 14.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_enlarge_enemy(t_sh4, 1.35)
	_add_roamer(rg, "phantom", "TowerPhantom_2", Vector3(-8.0, y, cz + 6.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_add_roamer(rg, "hexcaster", "TowerHexcaster_2", Vector3(15.0, y, cz + 10.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)

	var t_b1: EnemyBase = _add_roamer(rg, "brute", "TowerBrute", Vector3(0.0, y, cz + 12.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_enlarge_enemy(t_b1, 1.30)
	var t_b2: EnemyBase = _add_roamer(rg, "brute", "TowerBrute_2", Vector3(-4.0, y, cz + 15.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_enlarge_enemy(t_b2, 1.30)
	var t_sh5: EnemyBase = _add_roamer(rg, "shield", "TowerShield_5", Vector3(14.0, y, cz + 3.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_enlarge_enemy(t_sh5, 1.35)
	var t_sh6: EnemyBase = _add_roamer(rg, "shield", "TowerShield_6", Vector3(6.0, y, cz - 15.0), EncounterDirector.Section.MECHANISM_CHAMBER, door)
	_enlarge_enemy(t_sh6, 1.35)
	_add_waves(root, "ChamberWaves", EncounterDirector.Section.MECHANISM_CHAMBER, [
		["Roamers/TowerSkeleton_A", "Roamers/TowerSkeleton_B", "Roamers/TowerPhantom", "Roamers/TowerShield_1",
			"Roamers/TowerShield_2", "Roamers/TowerSkeleton_H"],
		["Roamers/TowerSkeleton_C", "Roamers/TowerShield_3", "Roamers/TowerHexcaster", "Roamers/TowerShield_4",
			"Roamers/TowerPhantom_2", "Roamers/TowerHexcaster_2"],
		["Roamers/TowerBrute", "Roamers/TowerShield_5", "Roamers/TowerBrute_2", "Roamers/TowerShield_6"],
	])
	return root


# =====================================================================================================
# Stage 05 — Processional Stair + Mirror Colosseum (Y 10) + Sunset Summit
# =====================================================================================================

func _build_stage_05_arena() -> Node3D:
	var root := Node3D.new()
	root.name = "Stage05_ExecutionArena"
	var g: Array[Node3D] = _zone("Zone05_Colosseum")
	# Story-coordinate stage: the stage root and its decor zone are shifted onto the stretched layout.
	root.position.z = JourneyLayout.OFF_S5
	(g[0].get_parent() as Node3D).position.z = JourneyLayout.OFF_S5
	var y0: float = Y_GALLERY
	var y: float = Y_ARENA
	var c: Vector3 = ARENA_CENTER

	# --- Esplanade Z 116..120 (story). The Processional is now the winding bridge R5 (_build_routes), which
	# arrives at the esplanade's south edge; its join rails close that edge out to x +-9.
	_solid(root, "Processional_Esplanade", Vector3(0.0, y - 0.25, 118.0), Vector3(18.0, 0.5, 4.0), _m_floor())
	_parapet(root, "Rail_Esp_W", Vector3(-9.0, y, 116.0), Vector3(-9.0, y, 120.0), _m_wall())
	_parapet(root, "Rail_Esp_E", Vector3(9.0, y, 116.0), Vector3(9.0, y, 120.0), _m_wall())
	for p in [Vector3(-7.8, y, 117.5), Vector3(7.8, y, 117.5)]:
		_brazier(g, p)
	# Colosseum approach (still MECHANISM section until the arena trigger): an armoured gatekeeper on the
	# esplanade flanked by a skeleton, and a phantom stalking the stair in the Mirror.
	var rg: Node3D = _roamer_group(root)
	_add_roamer(rg, "shield", "EsplanadeGatekeeper", Vector3(0.0, y, 118.4), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0, y0, 104))
	_add_roamer(rg, "skeleton", "EsplanadeSkeleton", Vector3(-5.5, y, 118.0), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0, y0, 104))
	# Grave Brute: slow ground-slam heavy guarding the east half of the esplanade.
	_add_roamer(rg, "brute", "EsplanadeBrute", Vector3(5.5, y, 118.0), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0, y0, 104))
	_add_roamer(rg, "hexcaster", "EsplanadeHexcaster", Vector3(-3.0, y, 117.4), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0, y0, 104))
	var esp_support := BoxMesh.new()
	# Slightly inset under the esplanade slab so no side face is coplanar with the floor's edges.
	esp_support.size = Vector3(17.8, 5.0, 6.8)
	_mesh(g[0], "EsplanadeSupport", esp_support, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(0, y - 2.77, 119.6)))

	# --- Arena: sand disc R 13 inside a podium wall; entrance/exit tunnels through the cavea ---
	var arena_floor := _solid(root, "ArenaFloor", Vector3(c.x, y - 0.25, c.z), Vector3(28.0, 0.5, 28.0), null, LAYER_WORLD_SHARED, Vector3.ZERO, false)
	var sand := CylinderMesh.new()
	sand.top_radius = 13.6
	sand.bottom_radius = 13.6
	sand.height = 0.5
	sand.radial_segments = 64
	sand.rings = 1
	# 1.5 cm below the tunnel floors so the disc edge never z-fights where the tunnels meet the arena.
	_mesh(arena_floor, "SandDisc", sand, _m_sand(), Transform3D(Basis.IDENTITY, Vector3(0, -0.015, 0)))
	_mesh(arena_floor, "SandBorder", ProcMesh.ring_sector_mesh(12.4, 13.6, 0.25, 0.29, 0.0, TAU, 72), _m_marble(), Transform3D.IDENTITY, false)
	_mesh(arena_floor, "Sigil", ProcMesh.ring_sector_mesh(3.6, 4.1, 0.25, 0.27, 0.0, TAU, 48), _m_marble(), Transform3D.IDENTITY, false)
	# Podium ring wall (collision segments) with openings for the two tunnels.
	var seg_count: int = 32
	for i in range(seg_count):
		var a: float = TAU * (float(i) + 0.5) / float(seg_count)
		var dir := Vector3(sin(a), 0, cos(a))
		if absf(dir.x) < 0.2:
			continue # tunnel mouths at +Z (north) and -Z (south)
		var p: Vector3 = c + dir * 13.9 + Vector3(0, 2.5, 0)
		_invisible_wall(root, "PodiumWall_%02d" % i, p, Vector3(2.9, 5.0, 0.8), Vector3(0, a, 0))
	var podium_gap: float = 0.225
	for half in [[podium_gap, PI - podium_gap], [PI + podium_gap, TAU - podium_gap]]:
		_mesh(g[0], "Podium", ProcMesh.ring_sector_mesh(13.6, 14.4, 0.0, 4.4, float(half[0]), float(half[1]), 24), _m_wall(), Transform3D(Basis.IDENTITY, Vector3(c.x, y, c.z)))
		_mesh(g[0], "PodiumCap", ProcMesh.ring_sector_mesh(13.45, 14.6, 4.4, 4.75, float(half[0]), float(half[1]), 24), _m_marble(), Transform3D(Basis.IDENTITY, Vector3(c.x, y, c.z)))

	# Cavea seating (10 tiers) and the outer three-storey arcade facade.
	var cav_gap: float = 0.215
	for half in [[cav_gap, PI - cav_gap], [PI + cav_gap, TAU - cav_gap]]:
		_mesh(g[0], "Cavea", ProcMesh.cavea_mesh(14.4, 1.6, 1.05, 10, 4.4, float(half[0]), float(half[1]), 40), _m_wall(), Transform3D(Basis.IDENTITY, Vector3(c.x, y, c.z)))
		_mesh(g[0], "CaveaWalk", ProcMesh.ring_sector_mesh(30.4, 30.9, 0.0, 14.9, float(half[0]), float(half[1]), 40), _m_wall(), Transform3D(Basis.IDENTITY, Vector3(c.x, y, c.z)))
		_mesh(g[0], "FacadePodium", ProcMesh.ring_sector_mesh(31.0, 32.6, -26.0, 4.4, float(half[0]) - 0.02, float(half[1]) + 0.02, 32), _m_wall(), Transform3D(Basis.IDENTITY, Vector3(c.x, y, c.z)))
	var facade_r: float = 31.8
	var bays: int = 44
	var bay_w: float = TAU * facade_r / float(bays) + 0.05
	var arch_bay: ArrayMesh = ProcMesh.arch_mesh(bay_w, 7.2, bay_w * 0.62, 3.6, 1.6)
	var bay_x: Array = []
	for i in range(bays):
		var a: float = TAU * (float(i) + 0.5) / float(bays)
		if absf(sin(a)) < 0.276:
			continue # bays nearest the portals would cut into the 13 m portal towers
		var dir := Vector3(sin(a), 0, cos(a))
		for storey in range(3):
			bay_x.append(Transform3D(Basis(Vector3.UP, a), c + dir * facade_r + Vector3(0, 4.4 + 7.2 * float(storey) - (y - c.y), 0)))
	_multimesh(g[0], "FacadeArcade", arch_bay, _m_wall(), bay_x)
	_mesh(g[0], "FacadeAttic", ProcMesh.ring_sector_mesh(31.0, 32.7, 26.0, 29.5, 0.0, TAU, 64), _m_wall(), Transform3D(Basis.IDENTITY, Vector3(c.x, y, c.z)))
	_mesh(g[0], "FacadeCornice", ProcMesh.ring_sector_mesh(30.8, 33.1, 29.5, 30.2, 0.0, TAU, 64), _m_marble(), Transform3D(Basis.IDENTITY, Vector3(c.x, y, c.z)))
	# Monumental portal towers over both tunnels (inner + outer arches).
	for dz in [-1.0, 1.0]:
		var portal: ArrayMesh = ProcMesh.arch_mesh(13.0, 26.0, 6.0, 5.2, 18.0)
		_mesh(g[0], "PortalTower", portal, _m_wall(), Transform3D(Basis.IDENTITY, c + Vector3(0, 0, dz * 22.4) + Vector3(0, y - c.y, 0)))
		var crown := BoxMesh.new()
		crown.size = Vector3(13.8, 1.0, 18.6)
		_mesh(g[0], "PortalCrown", crown, _m_marble(), Transform3D(Basis.IDENTITY, c + Vector3(0, 26.5, dz * 22.4)))
	# Velarium masts with alternating realm banners around the rim.
	var mast := CylinderMesh.new()
	mast.top_radius = 0.12
	mast.bottom_radius = 0.18
	mast.height = 12.0
	mast.radial_segments = 8
	var masts: Array = []
	for i in range(16):
		var a: float = TAU * (float(i) + 0.25) / 16.0
		var dir := Vector3(sin(a), 0, cos(a))
		var mp: Vector3 = c + dir * 32.2 + Vector3(0, 36.0, 0)
		masts.append(Transform3D(Basis.IDENTITY, mp))
		var yaw: float = rad_to_deg(a)
		_banner(g[1], mp + Vector3(0, 4.8, 0) - dir * 0.3, yaw, 2.0, 7.5, false)
		_banner(g[2], mp + Vector3(0, 4.8, 0) - dir * 0.3, yaw, 2.0, 7.5, true)
	_multimesh(g[0], "VelariumMasts", mast, _m_bronze(), masts, false)
	# Braziers on the podium cap ring
	for i in range(8):
		var a: float = TAU * (float(i) + 0.5) / 8.0
		_brazier(g, c + Vector3(sin(a), 0, cos(a)) * 14.0 + Vector3(0, 4.75, 0))

	# --- Tunnels through the cavea (south entrance from the esplanade, north exit to the summit) ---
	var s_from: float = 120.0
	var s_to: float = c.z - 13.5
	var n_from: float = c.z + 13.5
	var n_to: float = c.z + 32.0
	_solid(root, "TunnelSouth_Floor", Vector3(0.0, y - 0.25, (s_from + s_to) * 0.5), Vector3(6.0, 0.5, s_to - s_from), _m_floor())
	_solid(root, "TunnelNorth_Floor", Vector3(0.0, y - 0.25, (n_from + n_to) * 0.5), Vector3(6.0, 0.5, n_to - n_from), _m_floor())
	for span in [[s_from, s_to], [n_from, n_to]]:
		var tz: float = (float(span[0]) + float(span[1])) * 0.5
		var tl: float = float(span[1]) - float(span[0])
		_invisible_wall(root, "TunnelWall_W", Vector3(-3.2, y + 3.0, tz), Vector3(0.4, 6.0, tl))
		_invisible_wall(root, "TunnelWall_E", Vector3(3.2, y + 3.0, tz), Vector3(0.4, 6.0, tl))
	_parapet(root, "Rail_Esp_NW", Vector3(-9.0, y, 120.0), Vector3(-3.0, y, 120.0), _m_wall())
	_parapet(root, "Rail_Esp_NE", Vector3(9.0, y, 120.0), Vector3(3.0, y, 120.0), _m_wall())

	var seal := _make_gate("Gate04b_ArenaSouthSeal", Vector3(0.0, y, c.z - 13.5), 4, "", true)
	_style_gate(seal)
	root.add_child(seal)

	# --- Central Mirror Plane (obsidian) bisecting the arena along X = 0 ---
	var mirror_plane := BreakableProp.new()
	mirror_plane.name = "CentralMirrorPlane"
	mirror_plane.position = Vector3(0.0, y, c.z)
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
	var frame_post := BoxMesh.new()
	frame_post.size = Vector3(0.6, 6.4, 0.6)
	# Frame posts are solid while the plane stands; BreakableProp disables this body when it shatters.
	var frame_body := StaticBody3D.new()
	frame_body.name = "FrameBody"
	frame_body.collision_layer = LAYER_WORLD_SHARED
	for dz in [-11.2, 11.2]:
		_mesh(intact_vis, "PlaneFrame", frame_post, _m_bronze(), Transform3D(Basis.IDENTITY, Vector3(0, 3.2, dz)), true, 0.0, false)
		var fcs := CollisionShape3D.new()
		fcs.shape = _box_shape(Vector3(0.6, 6.4, 0.6))
		fcs.position = Vector3(0, 3.2, dz)
		frame_body.add_child(fcs)
	mirror_plane.add_child(frame_body)
	mirror_plane.add_child(intact_vis)
	mirror_plane.shatter_extent = Vector3(0.12, 5.5, 22.0)
	mirror_plane.shatter_center_offset = Vector3(0.0, 2.75, 0.0)
	# Phase 1 purpose: walking through the glass swaps realm instantly (no Q cooldown); thralls step out of it.
	var gate := MirrorGate.new()
	gate.name = "MirrorGate"
	var gate_cs := CollisionShape3D.new()
	gate_cs.shape = _box_shape(Vector3(0.5, 5.0, 21.6))
	gate_cs.position = Vector3(0.0, 2.5, 0.0)
	gate.add_child(gate_cs)
	mirror_plane.add_child(gate)
	root.add_child(mirror_plane)

	var exit_gate := _make_gate("Gate05_ArenaExit", Vector3(0.0, y, c.z + 13.5), 4, "the_warden", false)
	_style_gate(exit_gate)
	root.add_child(exit_gate)
	root.add_child(_make_section_trigger("Trigger_Stage05_Arena", Vector3(0.0, y + 1.25, c.z - 11.5), Vector3(6.0, 2.5, 1.5),
		EncounterDirector.Section.EXECUTION_ARENA, Vector3(0.0, y, c.z - 11.5 + JourneyLayout.OFF_S5), "the_warden", 1, NodePath("../Gate04b_ArenaSouthSeal"), false))

	# --- Sunset Summit (run complete), Z c+32 .. c+48 ---
	var sz0: float = c.z + 32.0
	var sz1: float = c.z + 48.0
	_solid(root, "SunlitExitFloor", Vector3(0.0, y - 0.25, (sz0 + sz1) * 0.5), Vector3(18.0, 0.5, sz1 - sz0), _m_floor())
	_parapet(root, "Rail_Summit_W", Vector3(-9.0, y, sz0), Vector3(-9.0, y, sz1), _m_wall())
	_parapet(root, "Rail_Summit_E", Vector3(9.0, y, sz0), Vector3(9.0, y, sz1), _m_wall())
	_parapet(root, "Rail_Summit_N", Vector3(-9.0, y, sz1), Vector3(9.0, y, sz1), _m_wall())
	_parapet(root, "Rail_Summit_SW", Vector3(-9.0, y, sz0), Vector3(-3.2, y, sz0), _m_wall())
	_parapet(root, "Rail_Summit_SE", Vector3(9.0, y, sz0), Vector3(3.2, y, sz0), _m_wall())
	root.add_child(_make_section_trigger("Trigger_RunComplete", Vector3(0.0, y + 1.25, sz0 + 3.0), Vector3(4.0, 2.5, 1.5),
		EncounterDirector.Section.COMPLETE, Vector3(0.0, y, sz0 + 3.0 + JourneyLayout.OFF_S5), "", 0, NodePath(), true))
	_mesh(g[0], "SummitObelisk", ProcMesh.column_mesh(0.7, 14.0, 16), _m_marble(), Transform3D(Basis.IDENTITY, Vector3(-6.0, y, sz1 - 3.0)))
	_prop_collider(g[0], "SummitObeliskCollider", Vector3(-6.0, y + 7.0, sz1 - 3.0), _cyl_shape(0.95, 14.0))
	_prop_collider(g[0], "SummitObeliskBase", Vector3(-6.0, y + 0.42, sz1 - 3.0), _box_shape(Vector3(1.86, 0.84, 1.86)))
	_sword_monument(g[0], Vector3(5.5, y, sz1 - 3.5), 25.0, 9.0, true)
	_brazier(g, Vector3(-7.5, y, sz0 + 2.0))
	_brazier(g, Vector3(7.5, y, sz0 + 2.0))

	if spawn_enemies:
		var enemies := Node3D.new()
		enemies.name = "Enemies"
		var warden := WardenBoss.new()
		_configure_enemy_actor(warden, "TheWarden", "boss_the_warden", Vector3(0.0, y, c.z - 1.0), Color(0.32, 0.14, 0.14), Vector3(1.15, 2.3, 1.15))
		# Bone colossus: ~3.6 m tall (model x1.42, whole actor x1.3 incl. capsule, hurtbox, reach, HP-bar height).
		_enlarge_enemy(warden, 1.3)
		warden.mirror_plane_prop_path = NodePath("../../CentralMirrorPlane")
		warden.summon_factory = _spawn_warden_thrall
		warden.health_changed.connect(_on_warden_health_changed)
		enemies.add_child(warden)
		root.add_child(enemies)

	# Crystals crown the podium (out of the duel space) instead of sitting on the arena sand.
	for spec in [[2.3, 1.4, 51], [4.0, 1.3, 52], [5.6, 1.2, 53]]:
		var a: float = float(spec[0])
		_crystal_cluster(g[2], c + Vector3(sin(a), 0, cos(a)) * 14.05 + Vector3(0, 4.75, 0), float(spec[1]), int(spec[2]))
	g[1].add_child(_make_ambient_particles(c + Vector3(0, 4, 0), Vector3(13, 4, 13), false))
	g[2].add_child(_make_ambient_particles(c + Vector3(0, 6, 0), Vector3(16, 6, 16), true))
	return root


# =====================================================================================================
# World scenery: massifs, gorge, crags, distant ranges, cloud sea, floating mirror isles, kill plane
# =====================================================================================================

func _build_world_scenery() -> void:
	var rock_m: ShaderMaterial = _m_rock()
	# Massifs beneath every walkable region (tops clamped just under the floors).
	var massifs: Array = [
		# [center_top, size, seed] in WORLD coordinates (JourneyLayout). The bridges span open air between them;
		# every bridge bastion stands on its own rock spur (_build_bastion).
		[Vector3(0, -0.6, -136), Vector3(17, 70, 15), 1],
		# Stage 01 is split around the stepping-stone gap (Z -0.5..2.5) so the chasm stays a real drop.
		[Vector3(0, -0.6, -10.5), Vector3(26, 74, 16), 5],
		[Vector3(0, -0.6, 5.6), Vector3(26, 74, 3.0), 13],
		[Vector3(0, 3.4, 86), Vector3(70, 80, 66), 14],
		[Vector3(0, 5.4, 165), Vector3(14, 70, 6), 8],
		[Vector3(0, 5.4, 210), Vector3(42, 84, 42), 9],
		[Vector3(0, 9.4, 278), Vector3(20, 84, 8), 10],
		[Vector3(0, 9.4, 317), Vector3(76, 96, 70), 11],
		[Vector3(0, 9.4, 354), Vector3(26, 90, 20), 12],
	]
	var mi_idx: int = 0
	for mdef in massifs:
		# Each massif top sits a few cm lower than its neighbour so overlapping clamped tops never z-fight.
		var top: Vector3 = (mdef[0] as Vector3) + Vector3(0, -0.035 * float(mi_idx % 5), 0)
		var rk: MeshInstance3D = _rock(_scenery, "Massif", top, mdef[1], int(mdef[2]), rock_m, 0.72, 0.24, 18, false, true)
		rk.remove_meta("gj_batch")
		mi_idx += 1

	# Continuous landscape: ridge crest under the route, forested valleys, river canyon, sunset lake,
	# rolling mountain ring (replaces the old isolated crag spires + cloud sea). See JourneyTerrain.
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var terrain = (load("res://scripts/environment/journey_terrain.gd") as GDScript).new(get_route_waypoints(), SUN_HEADING)
	terrain.call("build", _scenery, _with_lods)

	# Mirror-only floating isles with crystal crowns drifting around the summit.
	var isles: Array[Node3D] = _zone("Zone_SkyIsles")
	var isle_mesh: ArrayMesh = ProcMesh.rock_mesh(Vector3(1, 1, 1), 555, 0.3, 8, 0.0)
	for i in range(10):
		var ang: float = TAU * float(i) / 10.0
		var pos := Vector3(sin(ang) * rng.randf_range(45.0, 90.0), rng.randf_range(18.0, 55.0), 120.0 + JourneyLayout.OFF_S5 + cos(ang) * rng.randf_range(50.0, 95.0))
		var s: float = rng.randf_range(4.0, 9.0)
		# Isle + its crystal crown share one bobbing pivot (they used to drift apart).
		var pivot := Node3D.new()
		pivot.name = "SkyIslePivot"
		pivot.position = pos
		isles[2].add_child(pivot)
		_mesh(pivot, "SkyIsle", isle_mesh, rock_m, Transform3D(Basis.IDENTITY.scaled(Vector3(s, s * 0.7, s)), Vector3.ZERO), false, 0.0, false)
		_crystal_cluster(pivot, Vector3(0, s * 0.3, 0), s * 0.5, 600 + i)
		var tw := pivot.create_tween().set_loops()
		tw.tween_property(pivot, "position:y", pos.y + 2.5, 4.0 + float(i) * 0.3).set_trans(Tween.TRANS_SINE)
		tw.tween_property(pivot, "position:y", pos.y - 2.5, 4.0 + float(i) * 0.3).set_trans(Tween.TRANS_SINE)
		_anim_tweens.append(tw)

	# One world kill plane catches every fall off the cliffs.
	var kz := _make_pit_kill_zone("PitKillZone_World", Vector3(0.0, -25.0, 113.0), Vector3(700.0, 19.0, 700.0))
	kz.kill_y_threshold = -6.0
	_scenery.add_child(kz)


# =====================================================================================================
# Occlusion culling: conservative box occluders strictly INSIDE solid geometry
# (requires rendering/occlusion_culling/use_occlusion_culling = true in project.godot)
# =====================================================================================================

func _occluder(parent: Node3D, n: String, pos: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	var oi := OccluderInstance3D.new()
	oi.name = n
	var box := BoxOccluder3D.new()
	box.size = size
	oi.occluder = box
	oi.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	parent.add_child(oi)


func _build_occluders() -> void:
	var occ := Node3D.new()
	occ.name = "Occluders"
	add_child(occ)
	# Gatehouse piers (facade x +-2.3..+-11, z 4.5..7.5, y 0..15).
	for sx in [-1.0, 1.0]:
		_occluder(occ, "GatehousePier", Vector3(sx * 6.65, 7.3, 6.0), Vector3(8.3, 14.2, 2.6))
	# Hall corner towers (world, JourneyLayout.HALL_CENTER).
	var hc: Vector3 = JourneyLayout.HALL_CENTER
	var hh: float = JourneyLayout.HALL_HALF
	for cx in [-(hh + 2.0), hh + 2.0]:
		for cz in [hc.z - hh - 2.0, hc.z + hh + 2.0]:
			_occluder(occ, "HallTower", Vector3(cx, Y_HALL + 6.0, cz), Vector3(3.6, 23.4, 3.6))
	# Clock tower: four walls + upper block (world, JourneyLayout.CHAMBER_CENTER).
	var ty: float = Y_GALLERY
	var cc: Vector3 = JourneyLayout.CHAMBER_CENTER
	var ch: float = JourneyLayout.CHAMBER_HALF
	_occluder(occ, "TowerWallW", Vector3(-ch - 0.75, ty + 12.0, cc.z), Vector3(1.2, 23.4, ch * 2.0 + 1.0))
	_occluder(occ, "TowerWallE", Vector3(ch + 0.75, ty + 12.0, cc.z), Vector3(1.2, 23.4, ch * 2.0 + 1.0))
	for sx in [-1.0, 1.0]:
		_occluder(occ, "TowerWallS", Vector3(sx * (2.0 + (ch - 2.0) * 0.5), ty + 12.0, cc.z - ch - 0.6), Vector3(ch - 2.4, 23.4, 0.9))
		_occluder(occ, "TowerWallN", Vector3(sx * (2.0 + (ch - 2.0) * 0.5), ty + 12.0, cc.z + ch + 0.6), Vector3(ch - 2.4, 23.4, 0.9))
	_occluder(occ, "TowerUpper", Vector3(0, ty + 32.0, cc.z), Vector3(ch * 2.0 + 2.4, 13.4, ch * 2.0 + 2.4))
	# Colosseum: portal-tower piers beside both tunnels, and the solid facade podium ring (as chords).
	var c: Vector3 = ARENA_CENTER + Vector3(0, 0, JourneyLayout.OFF_S5)
	for dz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			_occluder(occ, "PortalPier", c + Vector3(sx * 4.75, 12.5, dz * 22.4), Vector3(3.1, 24.6, 17.4))
	for i in range(24):
		var a: float = TAU * (float(i) + 0.5) / 24.0
		if absf(sin(a)) < 0.3:
			continue
		var dir := Vector3(sin(a), 0, cos(a))
		var chord: float = 2.0 * 31.2 * sin(PI / 24.0) * 0.92
		_occluder(occ, "FacadePodium", c + dir * 31.85 + Vector3(0, -6.0, 0), Vector3(chord, 19.0, 0.9), a)
	# Rock massif cores (well inside the noisy hulls), world coordinates.
	for mdef in [[Vector3(0, -12, -10.5), Vector3(16, 20, 10)], [Vector3(0, -8, 86), Vector3(44, 20, 40)], [Vector3(0, -6, 210), Vector3(26, 20, 26)],
			[Vector3(0, -6, 317), Vector3(50, 24, 46)], [Vector3(0, -6, 354), Vector3(16, 20, 12)]]:
		_occluder(occ, "MassifCore", mdef[0], mdef[1])


# =====================================================================================================
# Atmosphere: sky (HDRI <-> moonlit night), sun aligned to the HDRI, fog, volumetrics, tonemapping
# =====================================================================================================

func get_sun_direction() -> Vector3:
	var h: Vector3 = SUN_HEADING.normalized()
	var e: float = deg_to_rad(SUN_LIGHT_ELEVATION_DEG)
	return Vector3(h.x * cos(e), sin(e), h.z * cos(e)).normalized()


func _configure_atmosphere() -> void:
	var main: Node = get_parent()
	if main == null:
		return
	var sun: DirectionalLight3D = main.get_node_or_null("SunLight") as DirectionalLight3D
	var we: WorldEnvironment = main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var sun_dir: Vector3 = get_sun_direction()
	if sun != null:
		sun.global_transform = Transform3D(Basis.looking_at(-sun_dir, Vector3.UP), Vector3(0, 40, 60))
		sun.light_energy = 1.6
		sun.light_angular_distance = 0.8
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = 140.0
		sun.directional_shadow_blend_splits = true
		sun.shadow_blur = 2.0
		sun.light_volumetric_fog_energy = 1.4
	if we == null:
		return
	if we.environment == null:
		we.environment = Environment.new()
	var env: Environment = we.environment
	var sky_mat := ShaderMaterial.new()
	if ResourceLoader.exists(SKY_SHADER):
		sky_mat.shader = load(SKY_SHADER) as Shader
	if ResourceLoader.exists(SKY_HDRI):
		sky_mat.set_shader_parameter("hdri", load(SKY_HDRI))
	# Rotate the panorama so its baked sun sits on our heading: u_tex = u_world + rot / TAU.
	var h: Vector3 = SUN_HEADING.normalized()
	var u_world: float = atan2(h.x, -h.z) / TAU + 0.5
	sky_mat.set_shader_parameter("sky_rotation", (HDRI_SUN_U - u_world) * TAU)
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("exposure", 1.0)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	# Incremental: radiance updates after a realm shift are spread over several frames (no frame spike).
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.82, 0.66, 0.5)
	env.fog_density = 0.00075
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.08
	env.fog_sun_scatter = 0.25
	env.fog_height = -18.0
	env.fog_height_density = 0.012
	# Stylized look: no volumetric light shafts (photoreal haze clashed with the low-poly art; also cheaper).
	env.volumetric_fog_enabled = false
	env.volumetric_fog_density = 0.0035
	env.volumetric_fog_albedo = Color(1.0, 0.93, 0.85)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 80.0
	env.volumetric_fog_ambient_inject = 0.12
	env.volumetric_fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.0
	env.adjustment_saturation = 1.15
	# Zone-driven weather (golden -> storm -> blood moon over the Warden -> clear aftermath).
	if main.get_node_or_null("WeatherDirector") == null:
		var wd: Node = (load("res://scripts/environment/weather_director.gd") as GDScript).new()
		wd.name = "WeatherDirector"
		wd.set("base_fog_density", env.fog_density)
		wd.set("world_environment_path", NodePath("../WorldEnvironment"))
		wd.set("sun_path", NodePath("../SunLight"))
		wd.set("realm_controller_path", NodePath("../RealmEnvironmentController"))
		wd.set("warden_path", NodePath("../%s/Stage05_ExecutionArena/Enemies/TheWarden" % String(name)))
		main.add_child(wd)
	# Let the realm controller re-apply palette + sky blend onto the new sky.
	var rec: Node = main.get_node_or_null("RealmEnvironmentController")
	if rec != null and rec.has_method("apply_state_immediate"):
		rec.call("apply_state_immediate", String(rec.get("active_palette_state")))
	# Re-apply user graphics settings (they may disable fog/volumetrics/SSAO on lower presets).
	var store: Node = get_tree().root.get_node_or_null("LeaderboardStore") if get_tree() != null else null
	if store != null and store.has_method("apply_settings"):
		store.call("apply_settings")
