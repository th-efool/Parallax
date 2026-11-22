class_name Vegetation
extends Node3D
## One plant from the CC0 Quaternius Stylized Nature MegaKit (assets/models/flora/megakit), made
## realm-aware and alive. Purely cosmetic (no collision).
##  - Realm rule per kind: Reality-only (flowers, clover), Mirror-only spirit growth (spirit ferns,
##    crystal mushrooms, ghost pines), or both — with RealmLook turning foliage moonlit and luminous in
##    Mirror in sync with the level's realm transition.
##  - Wind sway (per-plant phase), bends away from the player / enemies / walking critters, and rustles
##    (shake + falling leaf/petal motes) when a fight, slam or sprint happens nearby.

const KitScript := preload("res://scripts/ambient/fauna_mesh_kit.gd")
const BASE: String = "res://assets/models/flora/megakit/"

enum Kind {
	TREE_COMMON, PINE, BUSH, BUSH_FLOWERS, FERN, CLOVER, PLANT_BIG, MUSHROOM, FLOWER_CLUMP, GRASS_CLUMP,
	SPIRIT_FERN, CRYSTAL_MUSHROOM, GHOST_PINE,
	WISPY_GRASS, WISPY_GRASS_TALL, GARDEN_ROCK,
}
enum RealmPresence { BOTH, REALITY_ONLY, MIRROR_ONLY }

## models, height range (m), realm (0 both / 1 reality / 2 mirror), sway, bendable, look profile, motes colour
const KINDS: Dictionary = {
	Kind.TREE_COMMON: {"models": ["tree_common_1", "tree_common_2", "tree_common_3"], "h": [4.5, 6.5], "realm": 0, "sway": 0.012, "bend": false, "look": "auto", "motes": Color(0.9, 1.0, 0.7)},
	Kind.PINE: {"models": ["pine_1", "pine_2", "pine_3", "pine_4", "pine_5"], "h": [5.0, 8.0], "realm": 0, "sway": 0.01, "bend": false, "look": "auto", "motes": Color(0.8, 1.0, 0.8)},
	Kind.BUSH: {"models": ["bush_common"], "h": [0.8, 1.3], "realm": 0, "sway": 0.03, "bend": true, "look": "auto", "motes": Color(0.8, 1.0, 0.6)},
	Kind.BUSH_FLOWERS: {"models": ["bush_common_flowers"], "h": [0.8, 1.3], "realm": 1, "sway": 0.03, "bend": true, "look": "auto", "motes": Color(1.0, 0.75, 0.85)},
	Kind.FERN: {"models": ["fern_1"], "h": [0.5, 0.9], "realm": 0, "sway": 0.05, "bend": true, "look": "leaves", "motes": Color(0.8, 1.0, 0.6)},
	Kind.CLOVER: {"models": ["clover_1", "clover_2"], "h": [0.15, 0.3], "realm": 1, "sway": 0.06, "bend": true, "look": "grass", "motes": Color(0.8, 1.0, 0.6)},
	Kind.PLANT_BIG: {"models": ["plant_big"], "h": [0.3, 0.55], "realm": 0, "sway": 0.05, "bend": true, "look": "leaves", "motes": Color(0.8, 1.0, 0.6)},
	Kind.MUSHROOM: {"models": ["mushroom_common"], "h": [0.15, 0.3], "realm": 0, "sway": 0.0, "bend": false, "look": "mushroom", "motes": Color(1.0, 0.9, 0.7)},
	Kind.FLOWER_CLUMP: {"models": ["flower_clumps"], "h": [0.25, 0.45], "realm": 1, "sway": 0.08, "bend": true, "look": "flower", "motes": Color(1.0, 0.85, 0.5)},
	Kind.GRASS_CLUMP: {"models": ["grass_clumps"], "h": [0.25, 0.5], "realm": 0, "sway": 0.09, "bend": true, "look": "grass", "motes": Color(0.8, 1.0, 0.6)},
	Kind.SPIRIT_FERN: {"models": ["fern_1"], "h": [0.7, 1.1], "realm": 2, "sway": 0.06, "bend": true, "look": "leaves", "motes": Color(0.45, 0.95, 1.0), "glow_motes": true},
	Kind.CRYSTAL_MUSHROOM: {"models": ["mushroom_common"], "h": [0.3, 0.6], "realm": 2, "sway": 0.0, "bend": false, "look": "mushroom", "motes": Color(0.6, 0.8, 1.0), "glow_motes": true},
	Kind.GHOST_PINE: {"models": ["pine_1", "pine_3", "pine_5"], "h": [5.5, 8.5], "realm": 2, "sway": 0.008, "bend": false, "look": "spectral", "motes": Color(0.5, 0.85, 1.0), "glow_motes": true},
	# Castle-appropriate growth: sun-dried wispy grass for wall bases, cracks and parapets.
	Kind.WISPY_GRASS: {"models": ["grass_wispy_short"], "h": [0.25, 0.45], "realm": 0, "sway": 0.1, "bend": true, "look": "grass", "motes": Color(0.95, 0.85, 0.55)},
	Kind.WISPY_GRASS_TALL: {"models": ["grass_wispy_tall"], "h": [0.5, 0.85], "realm": 0, "sway": 0.1, "bend": true, "look": "grass", "motes": Color(0.95, 0.85, 0.55)},
	Kind.GARDEN_ROCK: {"models": ["rock_medium_1", "rock_medium_3"], "h": [0.4, 1.0], "realm": 0, "sway": 0.0, "bend": false, "look": "stone", "motes": Color(0.7, 0.7, 0.7)},
}

static var _scene_cache: Dictionary = {}


static func clear_caches() -> void:
	_scene_cache.clear()
	_green_leaf_mats.clear()

@export var kind: Kind = Kind.BUSH
## -1 = use the kind's realm rule.
@export var presence_override: int = -1
@export var height_scale: float = 1.0
@export var lod_distance: float = 45.0

var _spec: Dictionary = {}
var _model: Node3D = null
var _sway: Node3D = null
var _rng := RandomNumberGenerator.new()
var _t: float = 0.0
var _sense_t: float = 0.0
var _push := Vector3.ZERO
var _tilt := Vector2.ZERO
var _tilt_v := Vector2.ZERO
var _rustle: float = 0.0
var _presence: int = 0
var _director: FaunaDirector = null
var _far: bool = false


func _ready() -> void:
	_rng.randomize()
	_spec = KINDS[kind]
	_presence = int(_spec["realm"]) if presence_override < 0 else presence_override
	_t = _rng.randf() * 20.0
	_sense_t = _rng.randf() * 0.2
	rotation.y = _rng.randf() * TAU
	_build()
	add_to_group("ambient_flora")
	if kind in [Kind.BUSH_FLOWERS, Kind.FLOWER_CLUMP]:
		add_to_group("flora_bloom")
		set_meta("landing_height", 0.0)
	_director = FaunaDirector.get_for(self)
	if _director != null:
		_director.register_flora(self)
		if not _director.realm_shifted.is_connected(_on_realm_shifted):
			_director.realm_shifted.connect(_on_realm_shifted)
		if not _director.disturbance.is_connected(_on_disturbance):
			_director.disturbance.connect(_on_disturbance)
	_refresh_presence()


func _on_realm_shifted(_r: int) -> void:
	_refresh_presence()


func _exit_tree() -> void:
	if _director != null and is_instance_valid(_director):
		if _director.realm_shifted.is_connected(_on_realm_shifted):
			_director.realm_shifted.disconnect(_on_realm_shifted)
		if _director.disturbance.is_connected(_on_disturbance):
			_director.disturbance.disconnect(_on_disturbance)
		_director.unregister_flora(self)


func _build() -> void:
	var names: Array = _spec["models"]
	var path: String = BASE + String(names[_rng.randi_range(0, names.size() - 1)]) + ".glb"
	var ps: PackedScene = _scene_cache.get(path, null) as PackedScene
	if ps == null and ResourceLoader.exists(path):
		ps = load(path) as PackedScene
		_scene_cache[path] = ps
	if ps == null:
		return
	_model = ps.instantiate() as Node3D
	_sway = Node3D.new()
	_sway.name = "Sway"  # pivot at the plant's base so it bends from the root
	add_child(_sway)
	_sway.add_child(_model)
	_greenify_autumn_leaves()
	var hr: Array = _spec["h"]
	_normalize(_rng.randf_range(float(hr[0]), float(hr[1])) * height_scale)
	if String(_spec["look"]) == "spectral":
		RealmLook.apply_spectral(_model, Color(0.35, 0.8, 1.0))
	else:
		RealmLook.apply(_model, String(_spec["look"]))
	# GPU distance culling scaled to plant size (grass vanishes early, trees stay on the skyline).
	var cull: float = clampf(14.0 + float(hr[1]) * 18.0, 22.0, 160.0)
	lod_distance = minf(lod_distance, cull)
	for mi in RealmLook._meshes(_model):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if float(hr[1]) > 1.5 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = cull
		mi.visibility_range_end_margin = 3.0
	if bool(_spec.get("glow_motes", false)):
		_add_motes(Color(_spec["motes"]), float(hr[1]) * height_scale)


## The MegaKit bushes ship with red "TwistedTree" autumn leaves; this level wants evergreen Mediterranean
## scrub, so swap in the common-tree leaf texture (same leaf-card layout).
static var _green_leaf_mats: Dictionary = {}

func _greenify_autumn_leaves() -> void:
	for mi in RealmLook._meshes(_model):
		for s in range(mi.mesh.get_surface_count()):
			var m: Material = mi.get_active_material(s)
			if not (m is StandardMaterial3D) or not String(m.resource_name).contains("TwistedTree"):
				continue
			var key: int = m.get_instance_id()
			if not _green_leaf_mats.has(key):
				var green_tex: Texture2D = _common_leaf_texture()
				var nm: StandardMaterial3D = (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				if green_tex != null:
					nm.albedo_texture = green_tex
				else:
					nm.albedo_color = Color(0.45, 0.7, 0.35)
				nm.resource_name = "Leaves_NormalTree_Bush"
				_green_leaf_mats[key] = nm
			mi.set_surface_override_material(s, _green_leaf_mats[key])


static func _common_leaf_texture() -> Texture2D:
	if _green_leaf_mats.has("tex"):
		return _green_leaf_mats["tex"] as Texture2D
	var tex: Texture2D = null
	var path: String = BASE + "tree_common_1.glb"
	if ResourceLoader.exists(path):
		var inst: Node = (load(path) as PackedScene).instantiate()
		for mi in RealmLook._meshes(inst):
			for s in range(mi.mesh.get_surface_count()):
				var m: Material = mi.mesh.surface_get_material(s)
				if m is StandardMaterial3D and String(m.resource_name).contains("Leaves"):
					tex = (m as StandardMaterial3D).albedo_texture
		inst.free()
	_green_leaf_mats["tex"] = tex
	return tex


func _normalize(target_h: float) -> void:
	var aabb := AABB()
	var first: bool = true
	var inv: Transform3D = _model.global_transform.affine_inverse()
	for mi in RealmLook._meshes(_model):
		var b: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	if first or aabb.size.y < 0.0001:
		return
	var k: float = target_h / aabb.size.y
	_model.scale = Vector3.ONE * k
	_model.position = Vector3(-aabb.get_center().x * k, -aabb.position.y * k, -aabb.get_center().z * k)


func _add_motes(c: Color, h: float) -> void:
	var p := CPUParticles3D.new()
	p.amount = 6 if h < 2.0 else 14
	p.lifetime = 3.5
	p.local_coords = false
	p.mesh = KitScript.glow_billboard(Color(c.r, c.g, c.b, 0.8), 0.07, 2.0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(h * 0.25, h * 0.4, h * 0.25)
	p.position = Vector3.UP * h * 0.45
	p.direction = Vector3.UP
	p.spread = 30.0
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.2
	p.gravity = Vector3(0.0, 0.05, 0.0)
	add_child(p)
	p.emitting = true


func _process(delta: float) -> void:
	if not visible or _model == null:
		return
	_t += delta
	_sense_t -= delta
	if _sense_t <= 0.0:
		_sense_t = 0.12
		var cam: Camera3D = get_viewport().get_camera_3d()
		_far = cam != null and cam.global_position.distance_to(global_position) > lod_distance
		if not _far and bool(_spec["bend"]):
			_sense_push()
	if _far:
		return
	var sway: float = float(_spec["sway"])
	var wind := Vector2(sin(_t * 1.3 + global_position.x * 0.3), sin(_t * 1.7 + global_position.z * 0.4)) * sway
	# Spring the bend toward the push target; rustle adds a quick shiver.
	var target := Vector2(_push.z, -_push.x) * 0.6
	_tilt_v += ((target - _tilt) * 55.0 - _tilt_v * 7.0) * delta
	_tilt += _tilt_v * delta
	_rustle = maxf(0.0, _rustle - delta * 1.8)
	var shiver := Vector2(sin(_t * 31.0), cos(_t * 27.0)) * _rustle * 0.06
	var r: Vector2 = wind + _tilt + shiver
	_sway.rotation.x = r.x
	_sway.rotation.z = r.y


func _sense_push() -> void:
	var push := Vector3.ZERO
	var actors: Array[Node3D] = []
	var reach: float = 0.5 + float(KINDS[kind]["h"][1]) * 0.5
	var reach2: float = (reach + 0.5) * (reach + 0.5)
	if _director != null:
		var p: Node3D = _director.get_player()
		if p != null and p.global_position.distance_squared_to(global_position) < reach2:
			actors.append(p)
		for e in _director.get_enemies():
			if is_instance_valid(e) and e.global_position.distance_squared_to(global_position) < reach2:
				actors.append(e)
	if actors.is_empty():
		if _push != Vector3.ZERO:
			_push = Vector3.ZERO
		return
	for a in actors:
		var rel: Vector3 = global_position - a.global_position
		rel.y = 0.0
		var d: float = rel.length()
		if d < reach and d > 0.001:
			push += rel / d * (reach - d) / reach
			var av: Variant = a.get("velocity")
			if av is Vector3 and (av as Vector3).length() > 2.0:
				_rustle = maxf(_rustle, 0.6)
	_push = global_transform.basis.inverse() * push.limit_length(1.0) if push != Vector3.ZERO else Vector3.ZERO


func _on_disturbance(pos: Vector3, radius: float, strength: float, _kind: String) -> void:
	if not visible or _far:
		return
	var d: float = pos.distance_to(global_position)
	if d > radius:
		return
	var felt: float = strength * (1.0 - d / radius)
	if felt > 0.25:
		_rustle = maxf(_rustle, felt)
		if felt > 0.6 and _rng.randf() < 0.5:
			_shed(Color(_spec["motes"]))


## A few leaves / petals / spores shaken loose.
func _shed(c: Color) -> void:
	var host: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	var h: float = float(KINDS[kind]["h"][1]) * height_scale
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.7
	p.amount = 8 if h < 2.0 else 18
	p.lifetime = 2.2
	p.local_coords = false
	var leaf := KitScript.box(Vector3(0.05, 0.005, 0.035))
	leaf.material = KitScript.mat(c.darkened(0.25), 0.6 if RealmLook.blend > 0.5 else 0.0)
	p.mesh = leaf
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(h * 0.3, h * 0.2, h * 0.3)
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.0
	p.gravity = Vector3(0.0, -1.2, 0.0)
	p.angular_velocity_min = -200.0
	p.angular_velocity_max = 200.0
	p.damping_min = 0.5
	p.damping_max = 1.2
	host.add_child(p)
	p.global_position = global_position + Vector3.UP * h * 0.7
	p.emitting = true
	get_tree().create_timer(2.6, false).timeout.connect(p.queue_free)


func _refresh_presence() -> void:
	var present: bool = true
	if RealmManager.instance != null and _presence != RealmPresence.BOTH:
		var merged: bool = RealmManager.instance.is_merged
		var mirror: bool = RealmManager.instance.current_realm == RealmManager.Realm.MIRROR
		present = merged or (mirror if _presence == RealmPresence.MIRROR_ONLY else not mirror)
	visible = present
