class_name AmbientFlora
extends Node3D
## Reactive plant life. Purely cosmetic: no collision, never blocks or damages anything.
##  GLOW_BLOOM — petals that open and glow; *shy* blooms fold shut when someone comes close or a fight
##               breaks out nearby and reopen once it's quiet. Drifting pollen motes. Butterflies land on
##               them and wisps hover over them (group `flora_bloom`). Brighter in Mirror.
##  SWAY_GRASS — wind-swept tuft (shader) that bends away from the player, enemies and critters
##               brushing through it, then springs back.
##  SPORE_POD  — a breathing bulb; startle it (fast movement, swings, slams) and it bursts a glowing
##               spore cloud that spooks nearby critters, deflates, and regrows.

const KitScript := preload("res://scripts/ambient/fauna_mesh_kit.gd")
const GameFeelScript := preload("res://scripts/core/game_feel.gd")

enum Kind { GLOW_BLOOM, SWAY_GRASS, SPORE_POD }
enum RealmPresence { BOTH, REALITY_ONLY, MIRROR_ONLY }

@export var kind: Kind = Kind.GLOW_BLOOM
@export var realm_presence: RealmPresence = RealmPresence.BOTH
## 0 = never closes, 1 = folds at the slightest movement. Negative = random per plant.
@export var shyness: float = -1.0
@export var reality_color: Color = Color(1.0, 0.55, 0.35)
@export var mirror_color: Color = Color(0.45, 0.8, 1.0)
@export var size_scale: float = 1.0
@export var lod_distance: float = 40.0

var _rng := RandomNumberGenerator.new()
var _director: FaunaDirector = null
var _t: float = 0.0
var _tick: float = 0.0
var _lod_far: bool = false

# bloom
var _petals: Array[Node3D] = []
var _bloom_head: Node3D = null
var _center: MeshInstance3D = null
var _pollen: CPUParticles3D = null
var _open: float = 1.0
var _open_target: float = 1.0
var _reopen_at: float = 0.0
var _petal_mat: StandardMaterial3D = null

# grass
var _grass: MeshInstance3D = null
var _push := Vector3.ZERO
var _push_v := Vector3.ZERO
var _push_cur := Vector3.ZERO

# pod
var _pod: Node3D = null
var _pod_mat: StandardMaterial3D = null
var _pod_size: float = 1.0
var _regrow_at: float = 0.0


func _ready() -> void:
	_rng.randomize()
	_t = _rng.randf() * 10.0
	_tick = _rng.randf() * 0.1
	if shyness < 0.0:
		shyness = _rng.randf_range(0.2, 0.95)
	scale = Vector3.ONE * size_scale * _rng.randf_range(0.85, 1.15)
	rotation.y = _rng.randf() * TAU
	match kind:
		Kind.GLOW_BLOOM:
			_build_bloom()
			add_to_group("flora_bloom")
			set_meta("landing_height", 0.42 * scale.y)
		Kind.SWAY_GRASS:
			_build_grass()
		Kind.SPORE_POD:
			_build_pod()
	add_to_group("ambient_flora")
	_director = FaunaDirector.get_for(self)
	if _director != null:
		_director.register_flora(self)
		_director.realm_shifted.connect(_on_realm_shifted)
		_director.disturbance.connect(_on_disturbance)
	_refresh_presence()


func _exit_tree() -> void:
	if _director != null and is_instance_valid(_director):
		_director.unregister_flora(self)


# ------------------------------------------------------------------ builders

func _build_bloom() -> void:
	var stem_mat := KitScript.mat(Color(0.25, 0.42, 0.2))
	KitScript.part(self, KitScript.cone(0.012, 0.02, 0.4, 5), stem_mat, Vector3(0, 0.2, 0))
	var leaf := KitScript.sphere(0.5, 6, 3)
	KitScript.part(self, leaf, stem_mat, Vector3(0.06, 0.1, 0), Vector3(0.14, 0.02, 0.06), Vector3(0, 0, 0.4))
	KitScript.part(self, leaf, stem_mat, Vector3(-0.05, 0.16, 0.02), Vector3(0.12, 0.02, 0.05), Vector3(0, 0.6, -0.4))
	_bloom_head = KitScript.pivot(self, Vector3(0, 0.4, 0), "Bloom")
	_petal_mat = StandardMaterial3D.new()
	_petal_mat.roughness = 0.6
	_petal_mat.emission_enabled = true
	_petal_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var count: int = _rng.randi_range(5, 7)
	for i in range(count):
		var hinge: Node3D = KitScript.pivot(_bloom_head, Vector3.ZERO, "Petal%d" % i)
		hinge.rotation.y = TAU * float(i) / count
		KitScript.part(hinge, KitScript.petal_mesh(), _petal_mat, Vector3(0, 0, -0.06), Vector3(0.07, 0.015, 0.13))
		_petals.append(hinge)
	_center = KitScript.part(_bloom_head, KitScript.sphere(0.03, 8, 5), KitScript.mat(Color(1.0, 0.9, 0.5), 2.5, true), Vector3(0, 0.01, 0))
	_pollen = CPUParticles3D.new()
	_pollen.amount = 6
	_pollen.lifetime = 3.0
	_pollen.local_coords = false
	_pollen.mesh = KitScript.glow_billboard(Color(1.0, 0.9, 0.55, 0.8), 0.05, 1.5)
	_pollen.direction = Vector3.UP
	_pollen.spread = 40.0
	_pollen.initial_velocity_min = 0.05
	_pollen.initial_velocity_max = 0.2
	_pollen.gravity = Vector3(0.05, 0.03, 0.0)
	_pollen.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_pollen.emission_sphere_radius = 0.08
	_bloom_head.add_child(_pollen)
	_pollen.emitting = true
	_apply_bloom_color()


func _build_grass() -> void:
	_grass = MeshInstance3D.new()
	var root_c := Color(0.18, 0.24, 0.12)
	var tip_c := Color(0.55, 0.6, 0.3).lerp(Color(0.7, 0.55, 0.3), _rng.randf() * 0.5)
	_grass.mesh = KitScript.grass_tuft_mesh(_rng.randi_range(9, 16), 0.45, 0.14, root_c, tip_c, _rng.randi())
	_grass.material_override = KitScript.grass_material()
	_grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_grass)


func _build_pod() -> void:
	var stalk := KitScript.mat(Color(0.32, 0.3, 0.2))
	KitScript.part(self, KitScript.cone(0.02, 0.035, 0.18, 5), stalk, Vector3(0, 0.09, 0))
	_pod = KitScript.pivot(self, Vector3(0, 0.26, 0), "Pod")
	_pod_mat = StandardMaterial3D.new()
	_pod_mat.albedo_color = Color(0.55, 0.45, 0.3)
	_pod_mat.emission_enabled = true
	_pod_mat.emission = Color(0.8, 0.9, 0.4)
	_pod_mat.emission_energy_multiplier = 0.5
	_pod_mat.roughness = 0.5
	KitScript.part(_pod, KitScript.sphere(0.1, 10, 6), _pod_mat, Vector3.ZERO, Vector3(1.0, 1.2, 1.0))
	for i in range(5):
		var a: float = TAU * i / 5.0
		KitScript.part(_pod, KitScript.sphere(0.018, 5, 3), KitScript.mat(Color(0.9, 1.0, 0.5), 2.0, true), Vector3(cos(a) * 0.085, 0.03 * sin(i * 2.0), sin(a) * 0.085))


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.1
		var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
		_lod_far = cam != null and cam.global_position.distance_to(global_position) > lod_distance
		if not _lod_far:
			_sense()
	if _lod_far:
		return
	match kind:
		Kind.GLOW_BLOOM:
			_animate_bloom(delta)
		Kind.SWAY_GRASS:
			_animate_grass(delta)
		Kind.SPORE_POD:
			_animate_pod(delta)


## Who is close and how fast are they moving? (player, enemies, ground critters)
func _sense() -> void:
	var close_motion: float = 0.0
	var push := Vector3.ZERO
	var actors: Array[Node3D] = []
	if _director != null:
		var p: Node3D = _director.get_player()
		if p != null:
			actors.append(p)
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is EnemyBase and (e as EnemyBase).is_active:
			actors.append(e as Node3D)
	if kind == Kind.SWAY_GRASS and _director != null:
		for c in _director.creatures:
			if is_instance_valid(c) and not bool(c.get("flies")) and (c as Node3D).global_position.distance_squared_to(global_position) < 1.0:
				actors.append(c as Node3D)
	for a in actors:
		var rel: Vector3 = global_position - a.global_position
		rel.y = 0.0
		var d: float = rel.length()
		var speed: float = 0.0
		var av: Variant = a.get("velocity")
		if av is Vector3:
			speed = Vector2((av as Vector3).x, (av as Vector3).z).length()
		if d < 3.0:
			close_motion = maxf(close_motion, (1.0 - d / 3.0) * (0.3 + speed / 5.0))
		if d < 0.85 and d > 0.001:
			push += rel / d * (0.85 - d) * 0.9
	match kind:
		Kind.GLOW_BLOOM:
			if close_motion > (1.0 - shyness) * 0.8:
				_close_bloom(1.5 + shyness * 2.5)
		Kind.SWAY_GRASS:
			_push = push.limit_length(0.45)
		Kind.SPORE_POD:
			if close_motion > 0.75:
				_burst_pod()


func _on_disturbance(pos: Vector3, radius: float, strength: float, _k: String) -> void:
	if not visible:
		return
	var d: float = pos.distance_to(global_position)
	if d > radius:
		return
	var felt: float = strength * (1.0 - d / radius)
	match kind:
		Kind.GLOW_BLOOM:
			if felt > (1.0 - shyness) * 0.6:
				_close_bloom(2.0 + shyness * 3.0)
		Kind.SPORE_POD:
			if felt > 0.45:
				_burst_pod()
		Kind.SWAY_GRASS:
			var away: Vector3 = global_position - pos
			away.y = 0.0
			if away.length_squared() > 0.001:
				_push_v += away.normalized() * felt * 1.8


# ------------------------------------------------------------------ bloom

func _close_bloom(hold: float) -> void:
	_open_target = 0.0
	_reopen_at = FaunaDirector.now() + hold


func _animate_bloom(delta: float) -> void:
	if _open_target < 0.5 and FaunaDirector.now() > _reopen_at:
		_open_target = 1.0
	# Close fast (a flinch), open slowly (cautious).
	var rate: float = 9.0 if _open_target < _open else 1.2
	_open = move_toward(_open, _open_target, rate * delta)
	var breathe: float = 0.05 * sin(_t * 1.3)
	for p in _petals:
		p.rotation.x = lerpf(1.3, -0.12, _open) + breathe  # +1.3 = tips folded up into a closed bud
	if _bloom_head != null:
		_bloom_head.rotation.z = 0.06 * sin(_t * 0.9)
		_bloom_head.rotation.x = 0.05 * sin(_t * 0.7 + 1.0)
	var mirror_k: float = 1.8 if _in_mirror() else 1.0
	_petal_mat.emission_energy_multiplier = (0.25 + 0.6 * _open) * mirror_k * (1.0 + 0.15 * sin(_t * 2.0))
	if _center != null:
		_center.visible = _open > 0.3
	if _pollen != null:
		_pollen.emitting = _open > 0.8


func _apply_bloom_color() -> void:
	if _petal_mat == null:
		return
	var c: Color = mirror_color if _in_mirror() else reality_color
	c = c.lerp(Color(1, 1, 1), _rng.randf() * 0.25)
	_petal_mat.albedo_color = c
	_petal_mat.emission = c


# ------------------------------------------------------------------ grass

func _animate_grass(delta: float) -> void:
	# Underdamped spring toward the current push, so tufts flick back with a little wobble;
	# disturbance impulses (shockwaves) ring out the same way.
	var acc: Vector3 = (_push - _push_cur) * 60.0 - _push_v * 7.0
	_push_v += acc * delta
	_push_cur += _push_v * delta
	_push_cur = _push_cur.limit_length(0.6)
	if _grass != null:
		var local: Vector3 = global_transform.basis.inverse() * _push_cur
		_grass.set_instance_shader_parameter("push", Vector3(local.x, 0.0, local.z) / maxf(0.01, scale.x))


# ------------------------------------------------------------------ spore pod

func _burst_pod() -> void:
	if _pod_size < 0.85:
		return
	_pod_size = 0.35
	_regrow_at = FaunaDirector.now() + _rng.randf_range(7.0, 12.0)
	var host: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = 40
	p.lifetime = 2.6
	p.local_coords = false
	var c: Color = Color(0.5, 0.95, 1.0) if _in_mirror() else Color(0.85, 1.0, 0.45)
	p.mesh = KitScript.glow_billboard(Color(c.r, c.g, c.b, 0.7), 0.09, 1.6)
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0.0, -0.15, 0.0)
	p.damping_min = 0.8
	p.damping_max = 1.6
	var fade := Curve.new()
	fade.add_point(Vector2(0, 0.6))
	fade.add_point(Vector2(0.2, 1.0))
	fade.add_point(Vector2(1, 0))
	p.scale_amount_curve = fade
	host.add_child(p)
	p.global_position = _pod.global_position
	p.emitting = true
	get_tree().create_timer(3.2, false).timeout.connect(p.queue_free)
	GameFeelScript.play_sound(self, "spore_puff", _pod.global_position, -14.0, _rng.randf_range(0.8, 1.2))
	if _director != null:
		_director.emit_disturbance(global_position, 2.5, 0.5, "spores")


func _animate_pod(delta: float) -> void:
	if _pod_size < 1.0 and FaunaDirector.now() > _regrow_at:
		_pod_size = move_toward(_pod_size, 1.0, delta * 0.25)
	var breathe: float = 1.0 + 0.06 * sin(_t * 1.6)
	if _pod != null:
		_pod.scale = Vector3.ONE * _pod_size * breathe
	if _pod_mat != null:
		_pod_mat.emission_energy_multiplier = (0.3 + 0.5 * (0.5 + 0.5 * sin(_t * 1.6))) * _pod_size * (1.8 if _in_mirror() else 1.0)


# ------------------------------------------------------------------ realm

func _on_realm_shifted(_r: int) -> void:
	_refresh_presence()
	if kind == Kind.GLOW_BLOOM:
		_apply_bloom_color()


func _refresh_presence() -> void:
	var present: bool = true
	if RealmManager.instance != null and realm_presence != RealmPresence.BOTH:
		var merged: bool = RealmManager.instance.is_merged
		var mirror: bool = RealmManager.instance.current_realm == RealmManager.Realm.MIRROR
		present = merged or (mirror if realm_presence == RealmPresence.MIRROR_ONLY else not mirror)
	visible = present


func _in_mirror() -> bool:
	return RealmManager.instance != null and RealmManager.instance.current_realm == RealmManager.Realm.MIRROR and not RealmManager.instance.is_merged
