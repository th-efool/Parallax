@tool
class_name WallIvy
extends Node3D
## Procedural ivy for castle walls. Place the node in front of a wall with its -Z axis pointing at the
## wall (the editor shows a preview frame). At runtime it ray-casts to find the wall face and grows
## branching vine strands across it — climbing from the base (`hanging = false`) or cascading down from a
## ledge (`hanging = true`) — with leaf cards that reuse the Stylized Nature MegaKit leaf texture so it
## matches the garden trees. RealmLook turns it moonlit and faintly luminous in Mirror. No collision.

const WORLD_MASK: int = 4 | 8 | 16
const LEAF_SOURCE: String = "res://assets/models/flora/megakit/tree_common_1.glb"

@export var width: float = 3.0:
	set(v):
		width = v
		_preview()
@export var height: float = 3.5:
	set(v):
		height = v
		_preview()
@export var hanging: bool = false
@export_range(1, 24) var strands: int = 7
@export_range(0.2, 3.0) var leaf_density: float = 1.0
@export var leaf_size: float = 0.16
@export var random_seed: int = 0
@export var max_wall_distance: float = 2.0

static var _leaf_mat: StandardMaterial3D = null
static var _stem_mat: StandardMaterial3D = null

var _mesh_instance: MeshInstance3D = null
var _rng := RandomNumberGenerator.new()


static func clear_caches() -> void:
	_leaf_mat = null
	_stem_mat = null


func _ready() -> void:
	if Engine.is_editor_hint():
		_preview()
		return
	add_to_group("ambient_flora")
	_grow_deferred.call_deferred()


func _grow_deferred() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	grow()


func grow() -> void:
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.seed = hash(global_position.snapped(Vector3.ONE * 0.1))
	# Find the wall face straight ahead (-Z).
	var origin: Vector3 = global_position
	var fwd: Vector3 = -global_transform.basis.z.normalized()
	var normal: Vector3 = -fwd
	var surface: Vector3 = origin + fwd * 0.3
	var w: World3D = get_world_3d()
	if w != null and w.direct_space_state != null:
		# Probe at knee height (a ray along the floor plane hits the floor), accept only wall-like faces.
		var probe: Vector3 = origin + Vector3.UP * 0.6
		var q := PhysicsRayQueryParameters3D.create(probe, probe + fwd * max_wall_distance, WORLD_MASK)
		var hit: Dictionary = w.direct_space_state.intersect_ray(q)
		if not hit.is_empty() and absf((hit["normal"] as Vector3).y) < 0.5:
			surface = (hit["position"] as Vector3) - Vector3.UP * 0.6
			normal = (hit["normal"] as Vector3).normalized()
	normal.y = 0.0
	normal = normal.normalized() if normal.length_squared() > 0.001 else -fwd
	var right: Vector3 = Vector3.UP.cross(normal).normalized()
	if right.length_squared() < 0.01:
		right = global_transform.basis.x
	var up: Vector3 = normal.cross(right).normalized()

	var stems := SurfaceTool.new()
	stems.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inv: Transform3D = global_transform.affine_inverse()
	var base: Vector3 = surface + normal * 0.03
	for s in range(strands):
		var u: float = _rng.randf_range(-width * 0.5, width * 0.5)
		var v: float = height if hanging else 0.0
		var dir_v: float = -1.0 if hanging else 1.0
		var length: float = height * _rng.randf_range(0.55, 1.0)
		_grow_strand(stems, leaves, inv, base, right, up, normal, u, v, dir_v, length, 0)
	var mesh := ArrayMesh.new()
	var arr_s: Array = stems.commit_to_arrays()
	if (arr_s[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr_s)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _get_stem_mat())
	leaves.generate_normals()
	var arr_l: Array = leaves.commit_to_arrays()
	if (arr_l[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr_l)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _get_leaf_mat())
	if _mesh_instance != null:
		_mesh_instance.queue_free()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Ivy"
	_mesh_instance.mesh = mesh
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.visibility_range_end = 60.0
	add_child(_mesh_instance)
	RealmLook.apply(_mesh_instance, "leaves")


## Random-walk vine across the wall plane, sprouting leaves and the odd side branch.
func _grow_strand(stems: SurfaceTool, leaves: SurfaceTool, inv: Transform3D, base: Vector3, right: Vector3, up: Vector3, normal: Vector3, u: float, v: float, dir_v: float, length: float, depth: int) -> void:
	var step: float = 0.12
	var drift: float = _rng.randf_range(-0.4, 0.4)
	var prev: Vector3 = base + right * u + up * v
	var travelled: float = 0.0
	var thickness: float = 0.022 if depth == 0 else 0.014
	while travelled < length:
		drift = clampf(drift + _rng.randf_range(-0.35, 0.35), -0.9, 0.9)
		u = clampf(u + drift * step, -width * 0.6, width * 0.6)
		v += dir_v * step * _rng.randf_range(0.7, 1.0)
		if v < -0.1 or v > height + 0.1:
			break
		var cur: Vector3 = base + right * u + up * v + normal * (0.01 * sin(travelled * 9.0))
		_quad_strip(stems, inv, prev, cur, normal, thickness * (1.0 - travelled / length * 0.6))
		# Leaves along the stem (density tapers toward the growing tip).
		var n_leaves: int = int(round(leaf_density * _rng.randf_range(0.8, 2.2)))
		for i in range(n_leaves):
			var side: float = -1.0 if (i % 2 == 0) else 1.0
			var lp: Vector3 = cur + right * side * _rng.randf_range(0.03, 0.09) + up * _rng.randf_range(-0.04, 0.04)
			_leaf(leaves, inv, lp, right, up, normal, leaf_size * _rng.randf_range(0.7, 1.25))
		if depth < 2 and _rng.randf() < 0.07:
			_grow_strand(stems, leaves, inv, base, right, up, normal, u, v, dir_v, (length - travelled) * 0.6, depth + 1)
		prev = cur
		travelled += step


func _quad_strip(st: SurfaceTool, inv: Transform3D, a: Vector3, b: Vector3, normal: Vector3, t: float) -> void:
	var along: Vector3 = (b - a).normalized()
	var side: Vector3 = along.cross(normal).normalized() * t
	var p0: Vector3 = inv * (a - side)
	var p1: Vector3 = inv * (a + side)
	var p2: Vector3 = inv * (b + side)
	var p3: Vector3 = inv * (b - side)
	var n: Vector3 = (inv.basis * normal).normalized()
	for p in [p0, p1, p2, p0, p2, p3]:
		st.set_normal(n)
		st.add_vertex(p)


func _leaf(st: SurfaceTool, inv: Transform3D, center: Vector3, right: Vector3, up: Vector3, normal: Vector3, size: float) -> void:
	# Leaf card tilted off the wall a little, random roll, so ivy reads as a 3D mat, not a decal.
	var roll: float = _rng.randf() * TAU
	var r: Vector3 = (right * cos(roll) + up * sin(roll)) * size * 0.5
	var u2: Vector3 = (up * cos(roll) - right * sin(roll)) * size * 0.5
	var tilt: Vector3 = normal * size * _rng.randf_range(0.15, 0.45)
	var c: Vector3 = center + normal * 0.02
	var v0: Vector3 = inv * (c - r - u2)
	var v1: Vector3 = inv * (c + r - u2)
	var v2: Vector3 = inv * (c + r + u2 + tilt)
	var v3: Vector3 = inv * (c - r + u2 + tilt)
	var uvs: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	var vs: Array[Vector3] = [v0, v1, v2, v3]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uvs[idx])
		st.add_vertex(vs[idx])


static func _get_leaf_mat() -> StandardMaterial3D:
	if _leaf_mat != null:
		return _leaf_mat
	_leaf_mat = StandardMaterial3D.new()
	_leaf_mat.resource_name = "Leaves_Ivy"
	_leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_leaf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_leaf_mat.alpha_scissor_threshold = 0.45
	_leaf_mat.roughness = 0.8
	_leaf_mat.albedo_color = Color(0.72, 0.85, 0.62)  # a touch darker/cooler than tree canopy: shaded ivy
	if ResourceLoader.exists(LEAF_SOURCE):
		var inst: Node = (load(LEAF_SOURCE) as PackedScene).instantiate()
		for mi in RealmLook._meshes(inst):
			for s in range(mi.mesh.get_surface_count()):
				var m: Material = mi.mesh.surface_get_material(s)
				if m is StandardMaterial3D and String(m.resource_name).contains("Leaves"):
					_leaf_mat.albedo_texture = (m as StandardMaterial3D).albedo_texture
		inst.free()
	if _leaf_mat.albedo_texture == null:
		_leaf_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		_leaf_mat.albedo_color = Color(0.25, 0.42, 0.2)
	return _leaf_mat


static func _get_stem_mat() -> StandardMaterial3D:
	if _stem_mat == null:
		_stem_mat = StandardMaterial3D.new()
		_stem_mat.resource_name = "Bark_Ivy"
		_stem_mat.albedo_color = Color(0.3, 0.24, 0.16)
		_stem_mat.roughness = 0.95
	return _stem_mat


func _preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var p: MeshInstance3D = get_node_or_null("_EditorPreview") as MeshInstance3D
	if p == null:
		p = MeshInstance3D.new()
		p.name = "_EditorPreview"
		add_child(p)
	var q := QuadMesh.new()
	q.size = Vector2(width, height)
	p.mesh = q
	p.position = Vector3(0, height * 0.5, -0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.3, 0.8, 0.3, 0.25)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	p.material_override = m
