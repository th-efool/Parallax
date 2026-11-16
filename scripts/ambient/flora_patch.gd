@tool
class_name FloraPatch
extends Node3D
## Drop-in scatterer for reactive plants. Place it, choose kind / count / radius; at runtime it
## scatters `AmbientFlora` onto the floor with a minimum spacing (grass optionally in clumps).
## Plants are cosmetic only (no collision).

const FloraScript := preload("res://scripts/ambient/ambient_flora.gd")
const WORLD_MASK: int = 4 | 8 | 16

@export var kind: AmbientFlora.Kind = AmbientFlora.Kind.SWAY_GRASS
@export_range(1, 200) var count: int = 24
@export_range(0.3, 30.0) var radius: float = 3.0:
	set(v):
		radius = v
		_update_preview()
@export_range(0.0, 2.0) var min_spacing: float = 0.25
## Grass: spawn in clumps of this many tufts.
@export_range(1, 8) var clump_size: int = 3
@export var realm_presence: AmbientFlora.RealmPresence = AmbientFlora.RealmPresence.BOTH
## -1 = random per plant.
@export_range(-1.0, 1.0) var shyness: float = -1.0
@export var size_min: float = 0.85
@export var size_max: float = 1.2
@export var spawn_on_ready: bool = true
@export var random_seed: int = 0

var spawned: Array[Node3D] = []
var _preview: MeshInstance3D = null


func _ready() -> void:
	if Engine.is_editor_hint():
		_update_preview()
		return
	if spawn_on_ready:
		_spawn_deferred.call_deferred()


func _spawn_deferred() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	spawn()


func spawn() -> void:
	for c in spawned:
		if is_instance_valid(c):
			c.queue_free()
	spawned.clear()
	var rng := RandomNumberGenerator.new()
	if random_seed != 0:
		rng.seed = random_seed
	else:
		rng.randomize()
	var placed: Array[Vector3] = []
	var w: World3D = get_world_3d()
	var attempts: int = 0
	var per_clump: int = clump_size if kind == AmbientFlora.Kind.SWAY_GRASS else 1
	var clump_center := Vector3.ZERO
	var in_clump: int = per_clump
	while placed.size() < count and attempts < count * 12:
		attempts += 1
		var p: Vector3
		if in_clump >= per_clump:
			var a: float = rng.randf() * TAU
			var r: float = sqrt(rng.randf()) * radius
			clump_center = global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
			in_clump = 0
		var ca: float = rng.randf() * TAU
		p = clump_center + Vector3(cos(ca), 0.0, sin(ca)) * rng.randf_range(0.0, 0.3 if per_clump > 1 else 0.0)
		var ok: bool = true
		for q in placed:
			if Vector2(q.x - p.x, q.z - p.z).length() < min_spacing:
				ok = false
				break
		if not ok:
			continue
		if w != null and w.direct_space_state != null:
			var ray := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 8.0, WORLD_MASK)
			var hit: Dictionary = w.direct_space_state.intersect_ray(ray)
			if hit.is_empty():
				continue
			if (hit["normal"] as Vector3).dot(Vector3.UP) < 0.8:
				continue  # too steep
			p.y = (hit["position"] as Vector3).y
		in_clump += 1
		placed.append(p)
		var f: Node3D = FloraScript.new() as Node3D
		f.set("kind", kind)
		f.set("realm_presence", realm_presence)
		f.set("shyness", shyness)
		f.set("size_scale", rng.randf_range(size_min, size_max))
		f.name = "Flora_%d" % placed.size()
		add_child(f)
		f.global_position = p
		spawned.append(f)


func _update_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _preview == null:
		_preview = MeshInstance3D.new()
		_preview.name = "_EditorRadiusPreview"
		add_child(_preview)
	var t := TorusMesh.new()
	t.inner_radius = maxf(0.05, radius - 0.03)
	t.outer_radius = radius
	t.rings = 48
	t.ring_segments = 4
	_preview.mesh = t
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.4, 0.9, 0.4)
	_preview.material_override = m
