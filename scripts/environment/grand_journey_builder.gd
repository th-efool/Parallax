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
var _scenery: Node3D = null
var _decor: Node3D = null
var _anim_tweens: Array[Tween] = []
var _parapet_count: int = 0


# =====================================================================================================
# Entry points
# =====================================================================================================

func _ready() -> void:
	super._ready()
	if configure_atmosphere:
		call_deferred("_configure_atmosphere")


func build_greybox() -> void:
	if _is_built:
		return
	_is_built = true

	_scenery = Node3D.new()
	_scenery.name = "Scenery"
	_decor = Node3D.new()
	_decor.name = "Decor"

	var stages: Array[Node3D] = [
		_build_stage_01_entry(),
		_build_stage_02_hall(),
		_build_stage_03_gallery(),
		_build_stage_04_mechanism(),
		_build_stage_05_arena(),
	]
	for st in stages:
		add_child(st)
	add_child(_decor)
	add_child(_scenery)
	_build_world_scenery()
	_build_occluders()
	if enable_static_batching:
		var merged: int = _static_batch(self)
		print_verbose("[GrandJourney] static-batched %d meshes" % merged)


func get_key_anchors() -> Dictionary:
	return {
		"player_spawn": Vector3(0.0, 0.0, -56.0),
		"entry_gap_center": Vector3(0.0, 0.0, 1.0),
		"entry_switch": Vector3(0.0, 0.0, 4.0),
		"hall_pillar": Vector3(0.0, Y_HALL, 34.0),
		"skeleton_1": Vector3(-6.0, Y_HALL, 30.0),
		"skeleton_2": Vector3(6.0, Y_HALL, 38.0),
		"phantom_1": Vector3(-6.0, Y_HALL, 40.0),
		"phantom_2": Vector3(6.0, Y_HALL, 40.0),
		"gallery_bridge_center": Vector3(0.0, Y_GALLERY, 72.0),
		"weak_stone_support": Vector3(0.0, Y_GALLERY, 77.0),
		"bridge_anchor": Vector3(0.0, Y_GALLERY, 79.0),
		"shielded_guard": Vector3(0.0, Y_GALLERY, 82.0),
		"mechanism_dais": Vector3(-3.0, Y_GALLERY + 1.35, 93.0),
		"mechanism_plate": Vector3(0.0, Y_GALLERY, 94.0),
		"arena_entry": Vector3(0.0, Y_ARENA, ARENA_CENTER.z - 13.5),
		"warden_spawn": Vector3(0.0, Y_ARENA, ARENA_CENTER.z - 1.0),
		"arena_exit": Vector3(0.0, Y_ARENA, ARENA_CENTER.z + 13.5),
		"summit": Vector3(0.0, Y_ARENA, ARENA_CENTER.z + 40.0),
	}


## Ordered critical-path waypoints (feet positions) with the realm required to stand there.
## Used by the route-verification test; keep in sync with the stage builders below.
func get_route_waypoints() -> Array:
	return [
		[Vector3(0, 0, -56), 0], [Vector3(-3.5, 0, -44), 0], [Vector3(-7, 0, -33), 0], [Vector3(-3.5, 0, -22), 0],
		[Vector3(0, 0, -10), 0], [Vector3(0, 0, -2), 0], [Vector3(0, 0, 1), 1], [Vector3(0, 0, 4), 1],
		[Vector3(0, 0, 6.5), 0], [Vector3(0, 2.0, 15), 0], [Vector3(0, Y_HALL, 23), 0], [Vector3(0, Y_HALL, 26), 0],
		[Vector3(3.5, Y_HALL, 30), 0], [Vector3(3.5, Y_HALL, 40), 0], [Vector3(0, Y_HALL, 43), 0],
		[Vector3(0, Y_HALL, 46), 0], [Vector3(0, 5.0, 53), 0], [Vector3(0, Y_GALLERY, 59), 0],
		[Vector3(0, Y_GALLERY, 65), 0], [Vector3(0, Y_GALLERY, 72), 1], [Vector3(0, Y_GALLERY, 76), 1],
		[Vector3(0, Y_GALLERY, 83), 0], [Vector3(0, Y_GALLERY, 86), 0], [Vector3(0, Y_GALLERY, 90), 0],
		[Vector3(0, Y_GALLERY, 101), 0], [Vector3(0, 8.0, 109), 0], [Vector3(0, Y_ARENA, 118), 0],
		[Vector3(0, Y_ARENA, 130), 0], [Vector3(0, Y_ARENA, 140), 0], [Vector3(2.6, Y_ARENA, 144), 0],
		[Vector3(6, Y_ARENA, 154), 0], [Vector3(2.6, Y_ARENA, 164), 0], [Vector3(0, Y_ARENA, 168), 0],
		[Vector3(0, Y_ARENA, 177), 0], [Vector3(0, Y_ARENA, 194), 0],
	]


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
		_:
			e = SkeletonGuard.new()
	_configure_enemy_actor(e, node_name, "journey_" + node_name.to_lower(), pos, col)
	e.section_id = section
	e.encounter_id = ""
	if face_toward != Vector3.ZERO:
		var d: Vector3 = face_toward - pos
		e.rotation.y = atan2(-d.x, -d.z)
	parent.add_child(e)
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


func _style_gate(gate: EncounterGate, width: float = 4.0, height: float = 3.2) -> void:
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

	# --- Prologue: Pilgrim's Causeway (start terrace -> two causeway spans -> overlook -> forecourt) ---
	_solid(root, "Prologue_StartTerrace", Vector3(0, -0.25, -56), Vector3(12, 0.5, 10), path_m)
	_ramp(root, "Prologue_CausewayA", Vector3(0, 0, -51.5), Vector3(-7, 0, -36), 5.0, path_m)
	_solid(root, "Prologue_Overlook", Vector3(-7, -0.25, -33), Vector3(9, 0.5, 7), path_m)
	_ramp(root, "Prologue_CausewayB", Vector3(-7, 0, -30), Vector3(0, 0, -14.5), 5.0, path_m)
	_solid(root, "Gate_Forecourt", Vector3(0, -0.25, -10), Vector3(14, 0.5, 10), floor_m)

	# Parapets along the whole prologue (gaps only where segments join).
	_parapet(root, "Rail_T0_S", Vector3(-6, 0, -61), Vector3(6, 0, -61), _m_wall())
	_parapet(root, "Rail_T0_W", Vector3(-6, 0, -61), Vector3(-6, 0, -51), _m_wall())
	_parapet(root, "Rail_T0_E", Vector3(6, 0, -61), Vector3(6, 0, -51), _m_wall())
	_parapet(root, "Rail_T0_NE", Vector3(6, 0, -51), Vector3(2.6, 0, -51), _m_wall())
	_parapet(root, "Rail_T0_NW", Vector3(-6, 0, -51), Vector3(-2.3, 0, -51), _m_wall())
	_parapet(root, "Rail_CA_W", Vector3(-2.2, 0, -52.5), Vector3(-9.2, 0, -37.0), _m_wall())
	_parapet(root, "Rail_CA_E", Vector3(2.2, 0, -50.5), Vector3(-4.8, 0, -35.0), _m_wall())
	_parapet(root, "Rail_OL_W", Vector3(-11.5, 0, -36.5), Vector3(-11.5, 0, -29.5), _m_wall())
	_parapet(root, "Rail_OL_S", Vector3(-11.5, 0, -36.5), Vector3(-9.4, 0, -36.5), _m_wall())
	_parapet(root, "Rail_OL_SE", Vector3(-4.6, 0, -36.5), Vector3(-2.5, 0, -36.5), _m_wall())
	_parapet(root, "Rail_OL_N", Vector3(-11.5, 0, -29.5), Vector3(-9.4, 0, -29.5), _m_wall())
	_parapet(root, "Rail_OL_NE", Vector3(-4.6, 0, -29.5), Vector3(-2.5, 0, -29.5), _m_wall())
	_parapet(root, "Rail_OL_E", Vector3(-2.5, 0, -36.5), Vector3(-2.5, 0, -29.5), _m_wall())
	_parapet(root, "Rail_CB_W", Vector3(-9.2, 0, -29.0), Vector3(-2.2, 0, -13.5), _m_wall())
	_parapet(root, "Rail_CB_E", Vector3(-4.8, 0, -31.0), Vector3(2.2, 0, -15.5), _m_wall())
	_parapet(root, "Rail_FC_W", Vector3(-7, 0, -15), Vector3(-7, 0, -5), _m_wall())
	_parapet(root, "Rail_FC_E", Vector3(7, 0, -15), Vector3(7, 0, -5), _m_wall())
	_parapet(root, "Rail_FC_SW", Vector3(-7, 0, -15), Vector3(-2.6, 0, -15), _m_wall())
	_parapet(root, "Rail_FC_SE", Vector3(7, 0, -15), Vector3(2.8, 0, -15), _m_wall())

	# --- Gameplay core (unchanged greybox coordinates) ---
	_solid(root, "EntryFloorSouth", Vector3(0.0, -0.25, -2.75), Vector3(12.0, 0.5, 4.5), floor_m)
	_solid(root, "EntryFloorNorth", Vector3(0.0, -0.25, 3.75), Vector3(12.0, 0.5, 2.5), floor_m)
	_solid(root, "Corridor01_Floor", Vector3(0.0, -0.25, 6.5), Vector3(4.0, 0.5, 3.0), floor_m)

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
	var sw := _make_switch("EntryMirrorSwitch", Vector3(0.0, 0.0, 4.0), InteractSwitch.SwitchRole.GATE_OPENER, 1,
		NodePath("../Gate01_EntryToHall"), NodePath(), NodePath())
	_style_switch(sw)
	root.add_child(sw)

	# Gatehouse wings double as the stage-01 containment walls (old Wall_West / Wall_East footprint).
	_solid(root, "Wall_West", Vector3(-6.75, 4.0, 0.0), Vector3(1.5, 9.0, 10.5), _m_wall())
	_solid(root, "Wall_East", Vector3(6.75, 4.0, 0.0), Vector3(1.5, 9.0, 10.5), _m_wall())
	_invisible_wall(root, "Tunnel_W", Vector3(-2.2, 2.5, 6.5), Vector3(0.4, 5.0, 3.0))
	_invisible_wall(root, "Tunnel_E", Vector3(2.2, 2.5, 6.5), Vector3(0.4, 5.0, 3.0))

	root.add_child(_make_pit_kill_zone("PitKillZone_Stage01", Vector3(0.0, -4.5, 1.0), Vector3(8.0, 2.5, 4.0)))
	root.add_child(_make_section_trigger("Trigger_Stage01_Entry", Vector3(0.0, 1.25, -56.0), Vector3(6.0, 2.5, 3.0),
		EncounterDirector.Section.ENTRY, Vector3(0.0, 0.0, -56.0), "", 0, NodePath(), false))
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
		_solid(root, "GuardianPlinth_%s" % ("W" if sx < 0.0 else "E"), Vector3(sx * 4.3, 1.2, 3.6), Vector3(2.6, 2.4, 2.4), _m_marble())
		_sword_monument(g[0], Vector3(sx * 4.3, 2.4, 3.6), 0.0, 10.0)
		_banner(g[1], Vector3(sx * 8.5, 13.0, 4.35), 180.0, 2.2, 7.5, false)
		_banner(g[2], Vector3(sx * 8.5, 13.0, 4.35), 180.0, 2.2, 7.5, true)
	for p in [Vector3(-6.0, 0, -14.0), Vector3(6.0, 0, -14.0), Vector3(-6.0, 0, -6.0), Vector3(6.0, 0, -6.0)]:
		_brazier(g, p)
	_brazier(g, Vector3(4.5, 0, -59.5))
	_brazier(g, Vector3(-4.5, 0, -59.5))
	# Prologue waystones and a toppled colossus on the overlook (looking out over the cloud sea).
	var fallen := CylinderMesh.new()
	fallen.top_radius = 0.9
	fallen.bottom_radius = 1.0
	fallen.height = 7.0
	fallen.radial_segments = 16
	# Toppled column lies along the west balustrade (clear of the causeway-to-causeway walking line).
	fallen.height = 4.4
	var fallen_basis: Basis = Basis(Vector3(1, 0, 0), PI * 0.5).rotated(Vector3.UP, 0.06)
	_mesh(g[0], "FallenColumn", fallen, _m_marble(), Transform3D(fallen_basis, Vector3(-10.3, 0.95, -31.75)))
	var fallen_col := _prop_collider(g[0], "FallenColumnCollider", Vector3(-10.3, 0.95, -31.75), _cyl_shape(0.98, 4.4))
	fallen_col.basis = fallen_basis
	_mesh(g[0], "OverlookObelisk", ProcMesh.column_mesh(0.45, 6.5, 12), _m_marble(), Transform3D(Basis.IDENTITY, Vector3(-10.5, 0, -35.5)))
	_prop_collider(g[0], "OverlookObeliskCollider", Vector3(-10.5, 3.25, -35.5), _cyl_shape(0.75, 6.5))
	for z in [-48.0, -40.0, -26.0, -19.0]:
		var x: float = lerpf(0.0, -7.0, clampf((z + 51.5) / 15.5, 0.0, 1.0)) if z < -30.0 else lerpf(-7.0, 0.0, clampf((z + 30.0) / 15.5, 0.0, 1.0))
		_mesh(g[0], "Waystone", ProcMesh.column_mesh(0.25, 2.2, 8), _m_wall(), Transform3D(Basis.IDENTITY, Vector3(x + 3.2, 0, z)), true, 120.0)
	_crystal_cluster(g[2], Vector3(-3.5, 0.0, -35.4), 1.2, 11, true)
	_crystal_cluster(g[2], Vector3(5.0, 0.0, -57.0), 1.0, 12, true)
	g[1].add_child(_make_ambient_particles(Vector3(0, 3, -30), Vector3(10, 3, 30), false))
	g[2].add_child(_make_ambient_particles(Vector3(0, 3, -30), Vector3(10, 3, 30), true))
	# Journey enemies (ENTRY): a two-skeleton teaching ambush on the overlook, and a Mirror phantom haunting
	# the gate forecourt that only reveals itself once the player first shifts to cross the stepping stones.
	var rg: Node3D = _roamer_group(root)
	_add_roamer(rg, "skeleton", "OverlookSkeleton_A", Vector3(-8.0, 0.0, -31.0), EncounterDirector.Section.ENTRY, Vector3(-7, 0, -40))
	_add_roamer(rg, "skeleton", "OverlookSkeleton_B", Vector3(-5.0, 0.0, -30.5), EncounterDirector.Section.ENTRY, Vector3(-7, 0, -40))
	_add_roamer(rg, "phantom", "ForecourtPhantom", Vector3(3.5, 0.0, -8.0), EncounterDirector.Section.ENTRY, Vector3(0, 0, -14))
	return root


# =====================================================================================================
# Stage 02 — Sunlit Stair + Hall of Echoes (Y 4) + Windswept Rampart
# =====================================================================================================

func _build_stage_02_hall() -> Node3D:
	var root := Node3D.new()
	root.name = "Stage02_HallOfEchoes"
	var g: Array[Node3D] = _zone("Zone02_Hall")
	var y: float = Y_HALL

	# --- Sunlit Stair: Z 8 -> 22, Y 0 -> 4 ---
	# Ramp collider runs through the middle of each step (shifted half a run) so feet neither sink into the
	# nosings nor float over the treads; an invisible top-step slab closes the gap to the landing.
	var s_run: float = 14.0 / 20.0
	_ramp(root, "SunlitStair_Ramp", Vector3(0, 0, 8.0 - s_run * 0.5), Vector3(0, y, 22.0 - s_run * 0.5), 8.0, null, false)
	_solid(root, "SunlitStair_TopStep", Vector3(0, y - 0.25, 22.0 - s_run * 0.5), Vector3(8.0, 0.5, s_run), null, LAYER_WORLD_SHARED, Vector3.ZERO, false)
	_mesh(g[0], "SunlitStair_Steps", ProcMesh.steps_mesh(8.0, y, 14.0, 20), _m_floor(), Transform3D(Basis.IDENTITY, Vector3(0, 0, 8.0)))
	_solid(root, "SunlitStair_Landing", Vector3(0, y - 0.25, 23.0), Vector3(8.0, 0.5, 2.0), _m_floor())
	_parapet(root, "Rail_Stair_W", Vector3(-4.2, 0, 7.6), Vector3(-4.2, y, 22.0), _m_wall())
	_parapet(root, "Rail_Stair_E", Vector3(4.2, 0, 7.6), Vector3(4.2, y, 22.0), _m_wall())
	_parapet(root, "Rail_Landing_W", Vector3(-4.2, y, 22.0), Vector3(-4.2, y, 23.8), _m_wall())
	_parapet(root, "Rail_Landing_E", Vector3(4.2, y, 22.0), Vector3(4.2, y, 23.8), _m_wall())
	# Sloped plinth walls carrying a colonnade on each flank (bases sunk slightly so none float on the slope).
	var col_mesh: ArrayMesh = ProcMesh.column_mesh(0.42, 7.5, 16)
	var cols: Array = []
	var cheek_pitch: float = atan2(y, 14.0)
	var cheek := BoxMesh.new()
	cheek.size = Vector3(2.6, 2.6, 14.6)
	for sx in [-1.0, 1.0]:
		var cb := Basis.from_euler(Vector3(-cheek_pitch, 0, 0))
		_mesh(g[0], "StairCheek", cheek, _m_wall(), Transform3D(cb, Vector3(sx * 5.75, 0.6 + y * 0.5, 15.0) - cb.y * 1.3))
		for i in range(5):
			var z: float = 9.4 + float(i) * 3.0
			var yy: float = 0.6 + (z - 8.0) / 14.0 * y - 0.18
			cols.append(Transform3D(Basis.IDENTITY, Vector3(sx * 5.75, yy, z)))
	_multimesh(g[0], "StairColonnade", col_mesh, _m_marble(), cols)
	var architrave := BoxMesh.new()
	architrave.size = Vector3(1.3, 0.9, 15.0)
	for sx in [-1.0, 1.0]:
		var basis := Basis.from_euler(Vector3(-atan2(y, 14.0), 0, 0))
		_mesh(g[0], "StairArchitrave", architrave, _m_marble(), Transform3D(basis, Vector3(sx * 5.75, 0.6 + 7.95 + y * 0.5, 15.2)))

	# --- Hall of Echoes: 20 x 20 at Y 4, centre (0, 4, 34) ---
	var hall_floor := _solid(root, "HallFloor", Vector3(0.0, y - 0.25, 34.0), Vector3(20.0, 0.5, 20.0), _m_floor())
	var ring := ProcMesh.ring_sector_mesh(5.6, 6.6, 0.0, 0.03, 0.0, TAU, 64)
	_mesh(hall_floor, "MosaicRing", ring, _m_marble(), Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0)), false)
	var seal := _make_gate("Gate02a_HallSouthSeal", Vector3(0.0, y, 24.0), 1, "", true)
	_style_gate(seal)
	root.add_child(seal)
	_build_hall_walls(root, g, y)

	var pillar := _make_breakable_pillar("CrackedCentralPillar", Vector3(0.0, y, 34.0), BreakableProp.PropKind.CRACKED_PILLAR, 1, 0.60, Vector3(0.0, 0.0, 2.5), 2.5)
	_restyle_pillar(pillar, 9.0, 0.7, Vector3(0, 0, 1))
	root.add_child(pillar)

	var exit_gate := _make_gate("Gate02_HallToGallery", Vector3(0.0, y, 44.0), 1, "hall_of_echoes", false)
	_style_gate(exit_gate)
	root.add_child(exit_gate)
	root.add_child(_make_section_trigger("Trigger_Stage02_Hall", Vector3(0.0, y + 1.25, 26.0), Vector3(5.0, 2.5, 1.5),
		EncounterDirector.Section.HALL_COMBAT, Vector3(0.0, y, 25.6), "hall_of_echoes", 4, NodePath("../Gate02a_HallSouthSeal"), false))

	if spawn_enemies:
		var enemies := Node3D.new()
		enemies.name = "Enemies"
		var skel1 := SkeletonGuard.new()
		_configure_enemy_actor(skel1, "SkeletonGuard_1", "hall_skel_1", Vector3(-6.0, y, 30.0), Color(0.82, 0.76, 0.65))
		skel1.died.connect(_on_hall_skeleton_died)
		enemies.add_child(skel1)
		var skel2 := SkeletonGuard.new()
		_configure_enemy_actor(skel2, "SkeletonGuard_2", "hall_skel_2", Vector3(6.0, y, 38.0), Color(0.82, 0.76, 0.65))
		skel2.died.connect(_on_hall_skeleton_died)
		enemies.add_child(skel2)
		var phan1 := PhantomTwin.new()
		_configure_enemy_actor(phan1, "PhantomTwin_1", "hall_phantom_1", Vector3(-6.0, y, 40.0), Color(0.25, 0.78, 1.0, 0.85))
		enemies.add_child(phan1)
		var phan2 := PhantomTwin.new()
		_configure_enemy_actor(phan2, "PhantomTwin_2", "hall_phantom_2", Vector3(6.0, y, 40.0), Color(0.25, 0.78, 1.0, 0.85))
		enemies.add_child(phan2)
		root.add_child(enemies)

	for p in [Vector3(-8.2, y, 25.8), Vector3(8.2, y, 25.8), Vector3(-8.2, y, 42.2), Vector3(8.2, y, 42.2)]:
		_brazier(g, p)
	_banner(g[1], Vector3(-5.0, y + 11.0, 43.3), 180.0, 2.4, 8.0, false)
	_banner(g[1], Vector3(5.0, y + 11.0, 43.3), 180.0, 2.4, 8.0, false)
	_banner(g[2], Vector3(-5.0, y + 11.0, 43.3), 180.0, 2.4, 8.0, true)
	_banner(g[2], Vector3(5.0, y + 11.0, 43.3), 180.0, 2.4, 8.0, true)
	# Crystals grow on the cliff just outside the arcades: seen through the grilles, never in the fighting space.
	_crystal_cluster(g[2], Vector3(-12.3, 3.4, 34.0), 1.4, 21)
	_crystal_cluster(g[2], Vector3(12.3, 3.4, 30.0), 1.2, 22)
	# Gate-arch piers flanking the south seal gate protrude onto the landing: give them real collision.
	for sx in [-1.0, 1.0]:
		for gz in [23.3, 44.7]:
			_prop_collider(root, "GateArchPier_%d" % int(sx), Vector3(sx * 2.6, y + 4.0, gz), _box_shape(Vector3(0.8, 8.0, 1.6)))
	g[1].add_child(_make_ambient_particles(Vector3(0, y + 3.5, 34), Vector3(9, 3.5, 9), false))
	g[2].add_child(_make_ambient_particles(Vector3(0, y + 3.5, 34), Vector3(9, 3.5, 9), true))

	# --- Windswept Rampart: Z 44 -> 60, Y 4 -> 6, open to the sunset on the west ---
	_solid(root, "Corridor02_Floor", Vector3(0.0, y - 0.25, 46.0), Vector3(4.0, 0.5, 4.0), _m_floor())
	_ramp(root, "Rampart_Ramp", Vector3(0, y, 48.0), Vector3(0, Y_GALLERY, 58.0), 5.0, _m_path())
	_solid(root, "Rampart_Landing", Vector3(0, Y_GALLERY - 0.25, 59.0), Vector3(6.0, 0.5, 2.0), _m_path())
	# Visible balustrades instead of invisible walls on the open-air corridor.
	_parapet(root, "Corridor02_W", Vector3(-2.2, y, 44.4), Vector3(-2.2, y, 48.0), _m_wall())
	_parapet(root, "Corridor02_E", Vector3(2.2, y, 44.4), Vector3(2.2, y, 48.0), _m_wall())
	_parapet(root, "Rail_Rampart_W", Vector3(-2.7, y, 47.8), Vector3(-2.7, Y_GALLERY, 58.0), _m_wall())
	_parapet(root, "Rail_Rampart_LW", Vector3(-3.0, Y_GALLERY, 58.0), Vector3(-3.0, Y_GALLERY, 60.0), _m_wall())
	_parapet(root, "Rail_Rampart_LE", Vector3(3.0, Y_GALLERY, 58.0), Vector3(3.0, Y_GALLERY, 60.0), _m_wall())
	# East: a tall buttressed curtain wall.
	_solid(root, "Rampart_CurtainWall", Vector3(3.6, y + 3.0, 53.0), Vector3(1.4, 12.0, 13.0), _m_wall())
	var buttress := BoxMesh.new()
	buttress.size = Vector3(1.6, 10.0, 1.2)
	var bts: Array = []
	for i in range(4):
		bts.append(Transform3D(Basis.IDENTITY, Vector3(4.9, y + 1.0, 48.5 + float(i) * 3.4)))
	_multimesh(g[0], "Buttresses", buttress, _m_wall(), bts)
	_banner(g[1], Vector3(2.85, y + 6.5, 53.0), -90.0, 1.6, 5.0, false)
	_banner(g[2], Vector3(2.85, y + 6.5, 53.0), -90.0, 1.6, 5.0, true)
	# Rampart sentry (HALL section stays current until the gallery trigger): holds the narrow ramp.
	_add_roamer(_roamer_group(root), "skeleton", "RampartSentry", Vector3(0.0, Y_GALLERY, 58.6), EncounterDirector.Section.HALL_COMBAT, Vector3(0, y, 48))
	return root


func _build_hall_walls(root: Node3D, g: Array[Node3D], y: float) -> void:
	var wall_m: ShaderMaterial = _m_wall()
	# Collision: four sides, with 4 m openings for the south seal gate and north exit gate.
	_invisible_wall(root, "Wall_West", Vector3(-10.25, y + 4.0, 34.0), Vector3(0.5, 8.0, 20.5))
	_invisible_wall(root, "Wall_East", Vector3(10.25, y + 4.0, 34.0), Vector3(0.5, 8.0, 20.5))
	for sx in [-1.0, 1.0]:
		_invisible_wall(root, "Wall_South_%d" % int(sx), Vector3(sx * 6.1, y + 4.0, 23.75), Vector3(8.2, 8.0, 0.5))
		_invisible_wall(root, "Wall_North_%d" % int(sx), Vector3(sx * 6.1, y + 4.0, 44.25), Vector3(8.2, 8.0, 0.5))

	# Visual: two-storey arcades on all four sides (arch modules + grilles), corner towers, cornice.
	var mod_w: float = 4.0
	var arch_low: ArrayMesh = ProcMesh.arch_mesh(mod_w, 8.0, 2.6, 3.6, 1.4)
	var arch_up: ArrayMesh = ProcMesh.arch_mesh(mod_w, 5.0, 2.4, 2.4, 1.0)
	var grille: ArrayMesh = ProcMesh.portcullis_mesh(2.6, 4.6, 0.08, 0.32)
	var low_x: Array = []
	var up_x: Array = []
	var grille_x: Array = []
	# West/East sides (modules run along Z, face inward)
	for sx in [-1.0, 1.0]:
		for i in range(5):
			var z: float = 26.0 + float(i) * mod_w
			var b := Basis(Vector3.UP, PI * 0.5)
			low_x.append(Transform3D(b, Vector3(sx * 10.7, y, z)))
			up_x.append(Transform3D(b, Vector3(sx * 10.9, y + 8.0, z)))
			grille_x.append(Transform3D(b, Vector3(sx * 10.7, y, z)))
	# South/North sides: two 3.5 m bays each side of the 6 m gate arch tile the 20 m wall exactly
	# (x 3..6.5 and 6.5..10), so no two modules overlap (the old 4 m bays overlapped by 0.6 m and z-fought).
	var side_low: ArrayMesh = ProcMesh.arch_mesh(3.5, 8.0, 2.3, 3.6, 1.4)
	var side_up: ArrayMesh = ProcMesh.arch_mesh(3.5, 5.0, 2.1, 2.4, 1.0)
	var side_grille: ArrayMesh = ProcMesh.portcullis_mesh(2.3, 4.6, 0.08, 0.32)
	var gate_arch: ArrayMesh = ProcMesh.arch_mesh(6.0, 8.0, 4.4, 3.4, 1.6)
	var gate_up: ArrayMesh = ProcMesh.arch_mesh(6.0, 5.0, 3.4, 2.4, 1.0)
	var side_low_x: Array = []
	var side_up_x: Array = []
	var side_grille_x: Array = []
	for sz in [23.3, 44.7]:
		for x in [-8.25, -4.75, 4.75, 8.25]:
			side_low_x.append(Transform3D(Basis.IDENTITY, Vector3(x, y, sz)))
			side_up_x.append(Transform3D(Basis.IDENTITY, Vector3(x, y + 8.0, sz)))
			side_grille_x.append(Transform3D(Basis.IDENTITY, Vector3(x, y, sz)))
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
	for cx in [-12.0, 12.0]:
		for cz in [22.0, 46.0]:
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
	cor.size = Vector3(1.6, 0.7, 24.0)
	_mesh(g[0], "CorniceW", cor, _m_marble(), Transform3D(Basis.IDENTITY, Vector3(-10.9, y + 13.35, 34.0)))
	_mesh(g[0], "CorniceE", cor, _m_marble(), Transform3D(Basis.IDENTITY, Vector3(10.9, y + 13.35, 34.0)))
	# N/S runs sit 4 cm higher so the overlapping corner blocks never share a top/bottom plane.
	_mesh(g[0], "CorniceS", cor, _m_marble(), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, y + 13.39, 23.0)))
	_mesh(g[0], "CorniceN", cor, _m_marble(), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, y + 13.39, 45.0)))


# =====================================================================================================
# Stage 03 — Aqueduct Gallery over the gorge (Y 6)
# =====================================================================================================

func _build_stage_03_gallery() -> Node3D:
	var root := Node3D.new()
	root.name = "Stage03_CollapsedGallery"
	var g: Array[Node3D] = _zone("Zone03_Gallery")
	var y: float = Y_GALLERY

	_solid(root, "GalleryFloorSouth", Vector3(0.0, y - 0.25, 65.0), Vector3(8.0, 0.5, 10.0), _m_path())
	_solid(root, "GalleryFloorNorth", Vector3(0.0, y - 0.25, 79.0), Vector3(8.0, 0.5, 10.0), _m_path())
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

	var support := _make_breakable_pillar("WeakStoneSupport", Vector3(0.0, y, 77.0), BreakableProp.PropKind.WEAK_STONE_SUPPORT, 2, 0.0, Vector3.ZERO, 1.5)
	var sup_intact: Node3D = support.get_node("IntactVisual") as Node3D
	for c in sup_intact.get_children():
		if c.name != "FractureSeam":
			c.free()
	var block := BoxMesh.new()
	block.size = Vector3(3.2, 3.4, 1.4)
	_mesh(sup_intact, "BarrierBlock", block, _m_ruin(), Transform3D(Basis.IDENTITY, Vector3(0, 1.7, 0)), true, 0.0, false)
	(sup_intact.get_node("FractureSeam") as Node3D).position = Vector3(0, 1.7, -0.69)
	# Collider = the barrier block (the greybox cylinder let players walk through both ends of the wall).
	var sup_body: StaticBody3D = support.get_node("SolidBody") as StaticBody3D
	for c in sup_body.get_children():
		c.free()
	var sup_cs := CollisionShape3D.new()
	sup_cs.shape = _box_shape(Vector3(3.2, 3.4, 1.4))
	sup_cs.position = Vector3(0, 1.7, 0)
	sup_body.add_child(sup_cs)
	# Rubble: low piles pushed against the balustrades, clear of the anchor switch path.
	var sup_broken: Node3D = support.get_node("BrokenVisual") as Node3D
	for c in sup_broken.get_children():
		c.free()
	var rubble_body := StaticBody3D.new()
	rubble_body.name = "DebrisBody"
	rubble_body.collision_layer = LAYER_WORLD_SHARED
	sup_broken.add_child(rubble_body)
	for sx in [-1.0, 1.0]:
		var pile: ArrayMesh = ProcMesh.rock_mesh(Vector3(1.6, 0.5, 1.4), 88 + int(sx), 0.3, 6, 0.0)
		_mesh(sup_broken, "Rubble", pile, _m_ruin(), Transform3D(Basis.IDENTITY, Vector3(sx * 2.7, 0.05, 0.2)), true, 0.0, false)
		var rcs := CollisionShape3D.new()
		rcs.shape = _box_shape(Vector3(1.6, 0.45, 1.3))
		rcs.position = Vector3(sx * 2.7, 0.22, 0.2)
		rubble_body.add_child(rcs)
	root.add_child(support)

	var anchor := _make_switch("BridgeAnchorSwitch", Vector3(0.0, y, 79.0), InteractSwitch.SwitchRole.BRIDGE_ANCHOR, 1,
		NodePath(), NodePath("../GallerySpectralBridge"), NodePath("../WeakStoneSupport"))
	_style_switch(anchor)
	root.add_child(anchor)
	var gate := _make_gate("Gate03_GalleryToMechanism", Vector3(0.0, y, 84.0), 2, "shielded_guard", false)
	_style_gate(gate)
	root.add_child(gate)
	root.add_child(_make_section_trigger("Trigger_Stage03_Gallery", Vector3(0.0, y + 1.25, 61.5), Vector3(4.0, 2.5, 1.5),
		EncounterDirector.Section.COLLAPSED_GALLERY, Vector3(0.0, y, 61.5), "shielded_guard", 1, NodePath(), false))
	if spawn_enemies:
		var enemies := Node3D.new()
		enemies.name = "Enemies"
		var sg := ShieldedGuard.new()
		_configure_enemy_actor(sg, "ShieldedGuard_1", "gallery_shielded_1", Vector3(0.0, y, 82.0), Color(0.75, 0.58, 0.25))
		enemies.add_child(sg)
		root.add_child(enemies)

	# Deck edges: parapets except across the broken span.
	for sx in [-1.0, 1.0]:
		_parapet(root, "Rail_S_%d" % int(sx), Vector3(sx * 3.95, y, 60.0), Vector3(sx * 3.95, y, 70.0), _m_wall())
		_parapet(root, "Rail_N_%d" % int(sx), Vector3(sx * 3.95, y, 74.0), Vector3(sx * 3.95, y, 84.0), _m_wall())
		_parapet(root, "Rail_SouthJoin_%d" % int(sx), Vector3(sx * 2.9, y, 60.0), Vector3(sx * 3.95, y, 60.0), _m_wall())
		_parapet(root, "Rail_NorthJoin_%d" % int(sx), Vector3(sx * 2.2, y, 84.0), Vector3(sx * 3.95, y, 84.0), _m_wall())
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
			var pos := Vector3(sx * 3.45, y, float(s[0]))
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
	_rock(_scenery, "GorgeWallWest", Vector3(-36.0, y + 12.0, 76.0), Vector3(26.0, 84.0, 28.0), 301, _m_rock(), 1.0, 0.2, 14)
	_rock(_scenery, "GorgeWallEast", Vector3(36.0, y + 20.0, 72.0), Vector3(26.0, 92.0, 34.0), 302, _m_rock(), 1.0, 0.2, 14)
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
	var root := Node3D.new()
	root.name = "Stage04_MechanismChamber"
	var g: Array[Node3D] = _zone("Zone04_Tower")
	var y: float = Y_GALLERY
	var cz: float = 94.0

	_solid(root, "ChamberFloor", Vector3(0.0, y - 0.25, cz), Vector3(12.0, 0.5, 12.0), _m_floor())
	_solid(root, "RaisedImpactDais", Vector3(-3.0, y + 0.675, cz - 1.0), Vector3(2.5, 1.35, 2.5), _m_marble())
	# Walls (visible, tall) with 4 m openings south & north.
	_solid(root, "Wall_West", Vector3(-6.75, y + 9.0, cz), Vector3(1.5, 18.0, 13.5), _m_wall())
	_solid(root, "Wall_East", Vector3(6.75, y + 9.0, cz), Vector3(1.5, 18.0, 13.5), _m_wall())
	for sx in [-1.0, 1.0]:
		# 4.0 m segments butt exactly against the side walls' inner faces (x = ±6) — no overlapping corners.
		_solid(root, "Wall_South_%d" % int(sx), Vector3(sx * 4.0, y + 9.0, cz - 6.6), Vector3(4.0, 18.0, 1.2), _m_wall())
		_solid(root, "Wall_North_%d" % int(sx), Vector3(sx * 4.0, y + 9.0, cz + 6.6), Vector3(4.0, 18.0, 1.2), _m_wall())
	var lintel := BoxMesh.new()
	lintel.size = Vector3(4.0, 14.0, 1.2)
	_mesh(g[0], "LintelSouth", lintel, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(0, y + 11.0, cz - 6.6)))
	_mesh(g[0], "LintelNorth", lintel, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(0, y + 11.0, cz + 6.6)))
	# Ceiling with an oculus (4 x 4 opening) at y + 18 -> god rays through volumetric fog.
	var ceil_piece := BoxMesh.new()
	ceil_piece.size = Vector3(15.0, 1.0, 5.5)
	_mesh(g[0], "CeilingS", ceil_piece, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(0, y + 18.5, cz - 4.75)))
	_mesh(g[0], "CeilingN", ceil_piece, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(0, y + 18.5, cz + 4.75)))
	var ceil_side := BoxMesh.new()
	ceil_side.size = Vector3(5.5, 1.0, 4.0)
	_mesh(g[0], "CeilingW", ceil_side, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(-4.75, y + 18.5, cz)))
	_mesh(g[0], "CeilingE", ceil_side, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(4.75, y + 18.5, cz)))
	# Tower exterior rising above: spire block + crenels
	var spire := BoxMesh.new()
	spire.size = Vector3(15.0, 14.0, 15.0)
	_mesh(g[0], "TowerUpper", spire, _m_wall(), Transform3D(Basis.IDENTITY, Vector3(0, y + 26.0, cz)))
	var roof := CylinderMesh.new()
	roof.top_radius = 0.0
	roof.bottom_radius = 10.5
	roof.height = 12.0
	roof.radial_segments = 4
	roof.rings = 1
	_mesh(g[0], "TowerRoof", roof, _m_bronze(), Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, y + 39.0, cz)))

	var gate := _make_gate("Gate04_MechanismToArena", Vector3(0.0, y, cz + 6.0), 3, "", false)
	_style_gate(gate)
	root.add_child(gate)
	root.add_child(_make_section_trigger("Trigger_Stage04_Mechanism", Vector3(0.0, y + 1.25, 89.5), Vector3(4.5, 2.5, 1.5),
		EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0.0, y, 89.5), "", 0, NodePath(), false))

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

	# Clockwork: big bronze gears turning on both side walls.
	# Meshing pairs sit on different depth planes (0.4 m apart) and clear the pilasters at z 89 / 99.
	for spec in [[-5.95, 12.0, 93.3, 3.4, 1.0], [-5.55, 15.5, 96.2, 2.2, -1.6], [5.95, 11.0, 95.2, 3.0, -1.0], [5.55, 15.0, 91.6, 2.0, 1.4]]:
		var gear: ArrayMesh = ProcMesh.gear_mesh(float(spec[3]), 0.35, int(float(spec[3]) * 6.0), 0.35)
		var gm := _mesh(g[0], "Gear", gear, _m_bronze(), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(float(spec[0]), y + float(spec[1]) - 6.0, float(spec[2]))), true, 0.0, false)
		var tw := gm.create_tween().set_loops()
		tw.tween_property(gm, "rotation:x", TAU * signf(float(spec[4])), 40.0 / absf(float(spec[4]))).as_relative()
		_anim_tweens.append(tw)
	# Pilasters
	var pil := BoxMesh.new()
	pil.size = Vector3(0.4, 17.0, 0.9)
	var pils: Array = []
	for sx in [-1.0, 1.0]:
		for z in [89.0, 99.0]:
			pils.append(Transform3D(Basis.IDENTITY, Vector3(sx * 5.8, y + 8.5, z)))
			_prop_collider(root, "PilasterCollider", Vector3(sx * 5.8, y + 8.5, z), _box_shape(Vector3(0.4, 17.0, 0.9)))
	_multimesh(g[0], "Pilasters", pil, _m_marble(), pils)
	_brazier(g, Vector3(-4.6, y, 99.0))
	_brazier(g, Vector3(4.6, y, 99.0))
	_crystal_cluster(g[2], Vector3(4.6, y, 89.4), 1.0, 41, true)
	g[1].add_child(_make_ambient_particles(Vector3(0, y + 6, cz), Vector3(5.5, 6, 5.5), false))
	g[2].add_child(_make_ambient_particles(Vector3(0, y + 6, cz), Vector3(5.5, 6, 5.5), true))
	# Tower wardens (MECHANISM section): a Reality skeleton pair guarding the dais, and a phantom that
	# harries the player in the Mirror while they line up the landing slam.
	var rg: Node3D = _roamer_group(root)
	_add_roamer(rg, "skeleton", "TowerSkeleton_A", Vector3(3.5, y, 97.5), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0, y, 90))
	_add_roamer(rg, "skeleton", "TowerSkeleton_B", Vector3(-4.2, y, 97.0), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0, y, 90))
	_add_roamer(rg, "phantom", "TowerPhantom", Vector3(3.8, y, 91.0), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(-3, y, 93))
	return root


# =====================================================================================================
# Stage 05 — Processional Stair + Mirror Colosseum (Y 10) + Sunset Summit
# =====================================================================================================

func _build_stage_05_arena() -> Node3D:
	var root := Node3D.new()
	root.name = "Stage05_ExecutionArena"
	var g: Array[Node3D] = _zone("Zone05_Colosseum")
	var y0: float = Y_GALLERY
	var y: float = Y_ARENA
	var c: Vector3 = ARENA_CENTER

	# --- Processional: corridor Z 100..102, stair Z 102..116 (Y 6 -> 10), esplanade Z 116..120 ---
	_solid(root, "Corridor04_Floor", Vector3(0.0, y0 - 0.25, 101.0), Vector3(4.0, 0.5, 2.0), _m_floor())
	_parapet(root, "Corridor04_W", Vector3(-2.2, y0, 100.6), Vector3(-2.2, y0, 102.0), _m_wall())
	_parapet(root, "Corridor04_E", Vector3(2.2, y0, 100.6), Vector3(2.2, y0, 102.0), _m_wall())
	var p_run: float = 14.0 / 22.0
	_ramp(root, "Processional_Ramp", Vector3(0, y0, 102.0 - p_run * 0.5), Vector3(0, y, 116.0 - p_run * 0.5), 12.0, null, false)
	_solid(root, "Processional_TopStep", Vector3(0, y - 0.25, 116.0 - p_run * 0.5), Vector3(12.0, 0.5, p_run), null, LAYER_WORLD_SHARED, Vector3.ZERO, false)
	_mesh(g[0], "Processional_Steps", ProcMesh.steps_mesh(12.0, y - y0, 14.0, 22), _m_floor(), Transform3D(Basis.IDENTITY, Vector3(0, y0, 102.0)))
	_solid(root, "Processional_Esplanade", Vector3(0.0, y - 0.25, 118.0), Vector3(18.0, 0.5, 4.0), _m_floor())
	_parapet(root, "Rail_Proc_W", Vector3(-6.2, y0, 101.8), Vector3(-6.2, y, 116.0), _m_wall())
	_parapet(root, "Rail_Proc_E", Vector3(6.2, y0, 101.8), Vector3(6.2, y, 116.0), _m_wall())
	_parapet(root, "Rail_Esp_W", Vector3(-9.0, y, 116.0), Vector3(-9.0, y, 120.0), _m_wall())
	_parapet(root, "Rail_Esp_E", Vector3(9.0, y, 116.0), Vector3(9.0, y, 120.0), _m_wall())
	_parapet(root, "Rail_Esp_SW", Vector3(-9.0, y, 116.0), Vector3(-6.2, y, 116.0), _m_wall())
	_parapet(root, "Rail_Esp_SE", Vector3(9.0, y, 116.0), Vector3(6.2, y, 116.0), _m_wall())
	# Colossal statues on stepped plinths flanking the stair, facing the path.
	for sx in [-1.0, 1.0]:
		for z in [105.5, 112.5]:
			var top: float = y0 + (z - 102.0) / 14.0 * (y - y0) + 2.0
			_solid(root, "StatuePlinth", Vector3(sx * 8.6, top - 7.0, z), Vector3(3.2, 14.0, 3.2), _m_marble())
			_sword_monument(g[0], Vector3(sx * 8.6, top, z), 90.0, 13.0)
	for p in [Vector3(-7.8, y, 117.5), Vector3(7.8, y, 117.5)]:
		_brazier(g, p)
	# Colosseum approach (still MECHANISM section until the arena trigger): an armoured gatekeeper on the
	# esplanade flanked by a skeleton, and a phantom stalking the stair in the Mirror.
	var rg: Node3D = _roamer_group(root)
	_add_roamer(rg, "shield", "EsplanadeGatekeeper", Vector3(0.0, y, 118.4), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0, y0, 104))
	_add_roamer(rg, "skeleton", "EsplanadeSkeleton", Vector3(-5.5, y, 118.0), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0, y0, 104))
	_add_roamer(rg, "phantom", "StairPhantom", Vector3(3.0, 8.3, 110.0), EncounterDirector.Section.MECHANISM_CHAMBER, Vector3(0, y0, 102))
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
	root.add_child(mirror_plane)

	var exit_gate := _make_gate("Gate05_ArenaExit", Vector3(0.0, y, c.z + 13.5), 4, "the_warden", false)
	_style_gate(exit_gate)
	root.add_child(exit_gate)
	root.add_child(_make_section_trigger("Trigger_Stage05_Arena", Vector3(0.0, y + 1.25, c.z - 11.5), Vector3(6.0, 2.5, 1.5),
		EncounterDirector.Section.EXECUTION_ARENA, Vector3(0.0, y, c.z - 11.5), "the_warden", 1, NodePath("../Gate04b_ArenaSouthSeal"), false))

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
		EncounterDirector.Section.COMPLETE, Vector3(0.0, y, sz0 + 3.0), "", 0, NodePath(), true))
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
		warden.mirror_plane_prop_path = NodePath("../../CentralMirrorPlane")
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
		# [center_top, size, seed]
		[Vector3(0, -0.6, -56), Vector3(17, 70, 15), 1],
		[Vector3(-3.5, -0.6, -44), Vector3(9, 60, 15), 2],
		[Vector3(-7, -0.6, -33), Vector3(13, 66, 11), 3],
		[Vector3(-3.5, -0.6, -22), Vector3(9, 60, 15), 4],
		# Stage 01 is split around the stepping-stone gap (Z -0.5..2.5) so the chasm stays a real drop.
		[Vector3(0, -0.6, -10.5), Vector3(26, 74, 16), 5],
		[Vector3(0, -0.6, 5.6), Vector3(26, 74, 3.0), 13],
		[Vector3(0, -0.6, 15), Vector3(16, 70, 16), 6],
		[Vector3(0, 3.4, 35), Vector3(28, 80, 26), 14],
		[Vector3(0, 3.4, 52), Vector3(24, 80, 18), 7],
		[Vector3(0, 5.4, 61), Vector3(14, 70, 6), 8],
		[Vector3(0, 5.4, 92), Vector3(22, 84, 26), 9],
		[Vector3(0, 5.4, 112), Vector3(28, 84, 24), 10],
		[Vector3(0, 9.4, 157), Vector3(76, 96, 70), 11],
		[Vector3(0, 9.4, 194), Vector3(26, 90, 20), 12],
	]
	var mi_idx: int = 0
	for mdef in massifs:
		# Each massif top sits a few cm lower than its neighbour so overlapping clamped tops never z-fight.
		var top: Vector3 = (mdef[0] as Vector3) + Vector3(0, -0.035 * float(mi_idx % 5), 0)
		var rk: MeshInstance3D = _rock(_scenery, "Massif", top, mdef[1], int(mdef[2]), rock_m, 1.0, 0.14, 14, false, true)
		rk.remove_meta("gj_batch")
		mi_idx += 1

	# Crags and spires around the route for parallax depth (4 shared meshes, MultiMesh batched).
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var variants: Array = []
	for v in range(4):
		variants.append(_with_lods(ProcMesh.rock_mesh(Vector3(1, 1, 1), 900 + v, 0.24, 12, 1.0, 0.55)))
	var buckets: Array = [[], [], [], []]
	var placed: int = 0
	var guard: int = 0
	var sun_h: Vector3 = SUN_HEADING.normalized()
	while placed < 40 and guard < 2000:
		guard += 1
		var ang: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(70.0, 300.0)
		var center := Vector3(sin(ang) * dist, 0, 60.0 + cos(ang) * dist * 1.3)
		# Keep a clear corridor around the route, and keep the sunset side (west/north-west) open for vistas.
		if absf(center.x) < 45.0 and center.z > -90.0 and center.z < 230.0:
			continue
		var from_route := Vector3(center.x, 0, center.z - clampf(center.z, -60.0, 200.0)).normalized()
		if center.x < 0.0 and from_route.dot(sun_h) > -0.2:
			continue
		var h: float = rng.randf_range(55.0, 115.0)
		var w: float = h * rng.randf_range(0.22, 0.4)
		var b := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3(w, h, w * rng.randf_range(0.7, 1.3)))
		# Bottoms well below the cloud deck (Y -32) so nothing reads as floating.
		buckets[placed % 4].append(Transform3D(b, center + Vector3(0, -45.0 + h * rng.randf_range(0.2, 0.42), 0)))
		placed += 1
	for v in range(4):
		var mmi := _multimesh(_scenery, "Crags%d" % v, variants[v], rock_m, buckets[v], false)
		mmi.visibility_range_end = 900.0

	# Distant mountain ranges (aerial-perspective silhouettes through fog).
	var far_m: ShaderMaterial = _m_rock_far()
	for i in range(18):
		var ang: float = TAU * float(i) / 18.0 + rng.randf_range(-0.1, 0.1)
		var dist: float = rng.randf_range(1200.0, 2300.0)
		var mesh: ArrayMesh = _with_lods(ProcMesh.mountain_mesh(rng.randf_range(420.0, 700.0), rng.randf_range(260.0, 520.0), 700 + i))
		_mesh(_scenery, "Mountain", mesh, far_m, Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)), Vector3(sin(ang) * dist, -70.0, 60.0 + cos(ang) * dist)), false, 0.0, false)

	# Sea of clouds
	var cloud := PlaneMesh.new()
	cloud.size = Vector2(9000, 9000)
	var cm := ShaderMaterial.new()
	if ResourceLoader.exists(CLOUD_SHADER):
		cm.shader = load(CLOUD_SHADER) as Shader
	_mesh(_scenery, "CloudSea", cloud, cm, Transform3D(Basis.IDENTITY, Vector3(0, -32.0, 60.0)), false)

	# Mirror-only floating isles with crystal crowns drifting around the summit.
	var isles: Array[Node3D] = _zone("Zone_SkyIsles")
	var isle_mesh: ArrayMesh = ProcMesh.rock_mesh(Vector3(1, 1, 1), 555, 0.3, 8, 0.0)
	for i in range(10):
		var ang: float = TAU * float(i) / 10.0
		var pos := Vector3(sin(ang) * rng.randf_range(45.0, 90.0), rng.randf_range(18.0, 55.0), 120.0 + cos(ang) * rng.randf_range(50.0, 95.0))
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
	var kz := _make_pit_kill_zone("PitKillZone_World", Vector3(0.0, -25.0, 70.0), Vector3(700.0, 19.0, 700.0))
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
	# Gatehouse piers (facade x ±2.3..±11, z 4.5..7.5, y 0..15).
	for sx in [-1.0, 1.0]:
		_occluder(occ, "GatehousePier", Vector3(sx * 6.65, 7.3, 6.0), Vector3(8.3, 14.2, 2.6))
	# Rampart curtain wall.
	_occluder(occ, "CurtainWall", Vector3(3.6, Y_HALL + 3.0, 53.0), Vector3(1.0, 11.4, 12.4))
	# Hall corner towers.
	for cx in [-12.0, 12.0]:
		for cz in [22.0, 46.0]:
			_occluder(occ, "HallTower", Vector3(cx, Y_HALL + 6.0, cz), Vector3(3.6, 23.4, 3.6))
	# Clock tower: four walls + upper block.
	var ty: float = Y_GALLERY
	_occluder(occ, "TowerWallW", Vector3(-6.75, ty + 9.0, 94.0), Vector3(1.2, 17.4, 13.0))
	_occluder(occ, "TowerWallE", Vector3(6.75, ty + 9.0, 94.0), Vector3(1.2, 17.4, 13.0))
	for sx in [-1.0, 1.0]:
		_occluder(occ, "TowerWallS", Vector3(sx * 4.0, ty + 9.0, 87.4), Vector3(3.6, 17.4, 0.9))
		_occluder(occ, "TowerWallN", Vector3(sx * 4.0, ty + 9.0, 100.6), Vector3(3.6, 17.4, 0.9))
	_occluder(occ, "TowerUpper", Vector3(0, ty + 26.0, 94.0), Vector3(14.4, 13.4, 14.4))
	# Colosseum: portal-tower piers beside both tunnels, and the solid facade podium ring (as chords).
	var c: Vector3 = ARENA_CENTER
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
	# Rock massif cores (well inside the noisy hulls).
	for mdef in [[Vector3(0, -12, -10.5), Vector3(16, 20, 10)], [Vector3(0, -8, 35), Vector3(18, 20, 16)], [Vector3(0, -6, 92), Vector3(14, 20, 16)],
			[Vector3(0, -6, 112), Vector3(18, 20, 14)], [Vector3(0, -6, 157), Vector3(50, 24, 46)], [Vector3(0, -6, 194), Vector3(16, 20, 12)]]:
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
		sun.shadow_blur = 1.2
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
	env.ssao_intensity = 1.8
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.82, 0.66, 0.5)
	env.fog_density = 0.00075
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.08
	env.fog_sun_scatter = 0.25
	env.fog_height = -18.0
	env.fog_height_density = 0.012
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0035
	env.volumetric_fog_albedo = Color(1.0, 0.93, 0.85)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 80.0
	env.volumetric_fog_ambient_inject = 0.12
	env.volumetric_fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	# Let the realm controller re-apply palette + sky blend onto the new sky.
	var rec: Node = main.get_node_or_null("RealmEnvironmentController")
	if rec != null and rec.has_method("apply_state_immediate"):
		rec.call("apply_state_immediate", String(rec.get("active_palette_state")))
	# Re-apply user graphics settings (they may disable fog/volumetrics/SSAO on lower presets).
	var store: Node = get_tree().root.get_node_or_null("LeaderboardStore") if get_tree() != null else null
	if store != null and store.has_method("apply_settings"):
		store.call("apply_settings")
