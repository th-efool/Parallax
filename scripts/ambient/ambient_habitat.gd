@tool
class_name AmbientHabitat
extends Node3D
## Drop-in spawner for ambient creatures. Place it in a room, pick a species, count and radius;
## at runtime it scatters the creatures onto the floor inside the radius, gives them a shared home,
## and organises them into a flock, several small groups, loners, or a mix.
## Child `Marker3D`s whose name starts with "Perch" become crow perches (`fauna_perch`), and
## "Cover" markers become rodent hiding spots (`fauna_cover`). Nothing here has collision.

enum Species { SPIRIT_WISP, BUTTERFLY, MIRROR_MOTH, RUIN_CROW, SCURRIER }
enum GroupMode { ONE_GROUP, SMALL_GROUPS, ALL_LONERS, MIXED }

const SCRIPTS: Dictionary = {
	Species.SPIRIT_WISP: "res://scripts/ambient/creatures/spirit_wisp.gd",
	Species.BUTTERFLY: "res://scripts/ambient/creatures/butterfly.gd",
	Species.MIRROR_MOTH: "res://scripts/ambient/creatures/butterfly.gd",
	Species.RUIN_CROW: "res://scripts/ambient/creatures/ruin_crow.gd",
	Species.SCURRIER: "res://scripts/ambient/creatures/scurrier.gd",
}
const WORLD_MASK: int = 4 | 8 | 16

static var _next_group_id: int = 1

@export var species: Species = Species.SPIRIT_WISP:
	set(v):
		species = v
		update_gizmo_hint()
@export_range(1, 40) var count: int = 6
@export_range(0.5, 30.0) var radius: float = 5.0:
	set(v):
		radius = v
		update_gizmo_hint()
@export var group_mode: GroupMode = GroupMode.MIXED
@export_range(0.0, 1.0) var loner_chance: float = 0.2
@export_range(2, 10) var small_group_size: int = 4
## RANDOM = every individual rolls its own personality.
@export var archetype_override: AmbientCreature.Archetype = AmbientCreature.Archetype.RANDOM
@export var realm_presence: AmbientCreature.RealmPresence = AmbientCreature.RealmPresence.BOTH
## Home wander radius = habitat radius x this.
@export var home_radius_scale: float = 1.4
@export var spawn_on_ready: bool = true
@export var debug_labels: bool = false
@export var random_seed: int = 0

var spawned: Array[Node3D] = []
var _preview: MeshInstance3D = null


func _ready() -> void:
	if Engine.is_editor_hint():
		update_gizmo_hint()
		return
	for c in get_children():
		if c is Marker3D:
			var n: String = String(c.name).to_lower()
			if n.begins_with("perch"):
				c.add_to_group("fauna_perch")
			elif n.begins_with("cover"):
				c.add_to_group("fauna_cover")
	if spawn_on_ready:
		_spawn_deferred.call_deferred()


func _spawn_deferred() -> void:
	# Wait for level collision to exist so floor probes hit.
	await get_tree().physics_frame
	await get_tree().physics_frame
	spawn()


func spawn() -> void:
	despawn()
	var rng := RandomNumberGenerator.new()
	if random_seed != 0:
		rng.seed = random_seed
	else:
		rng.randomize()
	var script: GDScript = load(String(SCRIPTS[species])) as GDScript
	if script == null:
		return
	var group_ids: Array[int] = _assign_groups(rng)
	for i in range(count):
		var c: Node3D = script.new() as Node3D
		c.name = "%s_%d" % [Species.keys()[species].capitalize().replace(" ", ""), i]
		c.set("group_id", group_ids[i])
		c.set("archetype", archetype_override)
		c.set("home_radius", radius * home_radius_scale)
		c.set("debug_label", debug_labels)
		var presence: int = realm_presence
		if species == Species.MIRROR_MOTH:
			presence = AmbientCreature.RealmPresence.MIRROR_ONLY
		c.set("realm_presence", presence)
		var pos: Vector3 = _random_floor_point(rng)
		add_child(c)
		c.global_position = pos
		c.set("home", global_position)
		spawned.append(c)


func despawn() -> void:
	for c in spawned:
		if is_instance_valid(c):
			c.queue_free()
	spawned.clear()


func _assign_groups(rng: RandomNumberGenerator) -> Array[int]:
	var ids: Array[int] = []
	var current: int = _next_group_id
	_next_group_id += 1
	var in_group: int = 0
	for i in range(count):
		var gid: int = current
		match group_mode:
			GroupMode.ALL_LONERS:
				gid = -1
			GroupMode.SMALL_GROUPS:
				if in_group >= small_group_size:
					current = _next_group_id
					_next_group_id += 1
					in_group = 0
				gid = current
				in_group += 1
			GroupMode.MIXED:
				gid = -1 if rng.randf() < loner_chance else current
		ids.append(gid)
	return ids


func _random_floor_point(rng: RandomNumberGenerator) -> Vector3:
	var flies: bool = species in [Species.SPIRIT_WISP, Species.BUTTERFLY, Species.MIRROR_MOTH]
	for attempt in range(10):
		var a: float = rng.randf() * TAU
		var r: float = sqrt(rng.randf()) * radius
		var p: Vector3 = global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var w: World3D = get_world_3d()
		if w == null or w.direct_space_state == null:
			return p
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 8.0, WORLD_MASK)
		var hit: Dictionary = w.direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var y: float = (hit["position"] as Vector3).y
			return Vector3(p.x, y + (rng.randf_range(0.8, 2.2) if flies else 0.02), p.z)
	return global_position + Vector3.UP * (1.5 if flies else 0.0)


# ------------------------------------------------------------------ editor preview

func update_gizmo_hint() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _preview == null:
		_preview = MeshInstance3D.new()
		_preview.name = "_EditorRadiusPreview"
		add_child(_preview)
	var t := TorusMesh.new()
	t.inner_radius = maxf(0.05, radius - 0.04)
	t.outer_radius = radius
	t.rings = 48
	t.ring_segments = 4
	_preview.mesh = t
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var colors: Array[Color] = [Color(1.0, 0.75, 0.3), Color(1.0, 0.5, 0.2), Color(0.4, 0.8, 1.0), Color(0.2, 0.2, 0.3), Color(0.6, 0.5, 0.4)]
	m.albedo_color = colors[int(species) % colors.size()]
	_preview.material_override = m
