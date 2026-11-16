class_name AmbientButterfly
extends AmbientCreature
## Erratic fluttering flyer with a unique procedurally painted wing pattern per individual.
## Lands on the ground or on glow-blooms to rest (slow wing breathing), flees from fast movement,
## courting pairs spiral up around each other, and a curious, bold one will land on the player's
## shoulder if they stand still — and flutter off the moment they move or swing.
## Mirror-realm variants (`realm_presence = MIRROR_ONLY`) are luminous spectral moths.

const KitScript := preload("res://scripts/ambient/fauna_mesh_kit.gd")

const REALITY_PALETTES: Array = [
	[Color(0.98, 0.52, 0.08), Color(0.12, 0.06, 0.03)],  # monarch
	[Color(0.98, 0.88, 0.25), Color(0.85, 0.55, 0.1)],   # sulphur
	[Color(0.75, 0.12, 0.12), Color(0.1, 0.05, 0.05)],   # crimson admiral
	[Color(0.95, 0.95, 0.9), Color(0.55, 0.6, 0.65)],    # cabbage white
	[Color(0.3, 0.55, 0.95), Color(0.08, 0.1, 0.25)],    # morpho
]
const MIRROR_PALETTES: Array = [
	[Color(0.35, 0.85, 1.0), Color(0.6, 0.35, 1.0)],
	[Color(0.75, 0.95, 1.0), Color(0.25, 0.5, 1.0)],
	[Color(0.9, 0.5, 1.0), Color(0.3, 0.9, 1.0)],
]

@export var shoulder_offset: Vector3 = Vector3(0.3, 1.05, 0.05)
@export var size_scale: float = 1.0

var _wing_l: Node3D = null
var _wing_r: Node3D = null
var _flap: float = 0.0
var _glide: float = 0.0
var _rest_until: float = 0.0
var _land_target: Vector3 = Vector3.ZERO
var _land_node: Node3D = null
var _dance_partner: Node3D = null
var _dance_center: Vector3 = Vector3.ZERO
var _still_timer: float = 0.0
var _jitter := Vector3.ZERO
var _dance_cd: float = 0.0
var _air_time: float = 0.0


func _configure() -> void:
	species = "butterfly"
	flies = true
	max_speed = 1.9
	accel = 4.5
	min_altitude = 0.25
	max_altitude = 3.2
	turn_speed = 6.0
	_wander_alt = randf_range(0.6, 1.8)


func _species_traits() -> Dictionary:
	return {"bold": 0.3, "curiosity": 0.55, "sociability": 0.35, "mischief": 0.25, "energy": 0.7}


func _build_body(root: Node3D) -> void:
	var spectral: bool = realm_presence == RealmPresence.MIRROR_ONLY
	var pals: Array = MIRROR_PALETTES if spectral else REALITY_PALETTES
	var pal: Array = pals[_rng.randi_range(0, pals.size() - 1)]
	var tex: Texture2D = KitScript.wing_texture(pal[0], pal[1], _rng.randi())
	var s: float = randf_range(0.8, 1.2) * size_scale
	root.scale = Vector3.ONE * s
	KitScript.part(root, KitScript.cone(0.012, 0.018, 0.12), KitScript.mat(Color(0.08, 0.06, 0.05)), Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0), "Thorax")
	var ant := KitScript.box(Vector3(0.004, 0.004, 0.07))
	KitScript.part(root, ant, KitScript.mat(Color(0.05, 0.05, 0.05)), Vector3(0.015, 0.02, -0.08), Vector3.ONE, Vector3(0.5, 0.3, 0))
	KitScript.part(root, ant, KitScript.mat(Color(0.05, 0.05, 0.05)), Vector3(-0.015, 0.02, -0.08), Vector3.ONE, Vector3(0.5, -0.3, 0))
	var wmesh: QuadMesh = KitScript.wing_mesh(0.16, tex, 1.6 if spectral else 0.0)
	_wing_r = KitScript.pivot(root, Vector3(0.01, 0.0, 0.0), "WingR")
	var wr := MeshInstance3D.new()
	wr.mesh = wmesh
	wr.rotation = Vector3(-PI * 0.5, 0.0, 0.0)  # lay the quad flat (XZ), hinge on +X edge of body
	wr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wing_r.add_child(wr)
	_wing_l = KitScript.pivot(root, Vector3(-0.01, 0.0, 0.0), "WingL")
	var wl := MeshInstance3D.new()
	wl.mesh = wmesh
	wl.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	wl.scale = Vector3(-1.0, 1.0, 1.0)
	wl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wing_l.add_child(wl)
	if spectral:
		var g := MeshInstance3D.new()
		g.mesh = KitScript.glow_billboard(pal[0], 0.45, 0.8)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(g)


func _disturbance_sensitivity(kind: String) -> float:
	return 1.3 if kind in ["swing", "slam", "footsteps"] else 1.0


func _score_extra(s: Dictionary) -> void:
	var t: float = FaunaDirector.now()
	_dance_cd = maxf(0.0, _dance_cd - 1.0 / think_hz)
	# Resting is sticky until its timer runs out (unless something scares it).
	if behaviour in ["rest", "shoulder"] and t < _rest_until and fear < 0.3:
		s[behaviour] = 0.9
	elif behaviour != "land":
		# The longer it has been flying, the more it wants to settle somewhere.
		s["land"] = 0.15 + (1.0 - trait_value("energy")) * 0.3 + minf(_air_time * 0.03, 0.55)
	if behaviour == "land":
		s["land"] = 0.85
	var p: Node3D = get_player()
	if p != null:
		var still: bool = _player_speed(p) < 0.4 and not _player_is_violent(p)
		var d: float = p.global_position.distance_to(global_position)
		if still and d < 5.0 and trait_value("bold") > 0.35 and trait_value("curiosity") > 0.55:
			s["shoulder_approach"] = 0.5 + trait_value("curiosity") * 0.4 if _still_timer > 1.5 else 0.0
		if behaviour == "shoulder":
			if not still or fear > 0.25:
				s["flee"] = 0.95
				fear = maxf(fear, 0.4)
				fear_source = p.global_position
			else:
				# Stays a good while, then wanders off on its own.
				s["shoulder"] = 1.0 if FaunaDirector.now() < _rest_until else 0.0
	# Courtship dance with a flockmate.
	if behaviour == "dance":
		s["dance"] = 0.9 if is_instance_valid(_dance_partner) and behaviour_time < 6.0 else 0.0
	elif group_id >= 0 and fear < 0.1 and _dance_cd <= 0.0 and trait_value("sociability") > 0.45 and _rng.randf() < 0.03:
		var mate: Node3D = _director.find_playmate(self, species, 3.0) if _director != null else null
		if mate != null and mate.has_method("begin_dance"):
			_dance_partner = mate
			mate.call("begin_dance", self)
			s["dance"] = 1.0


func begin_dance(partner: Node3D) -> void:
	_dance_partner = partner
	set_behaviour("dance")


func _on_behaviour_entered(b: String) -> void:
	match b:
		"land":
			_pick_landing_spot()
		"rest":
			_rest_until = FaunaDirector.now() + randf_range(3.0, 9.0) * (1.4 - trait_value("energy"))
		"shoulder":
			_rest_until = FaunaDirector.now() + randf_range(6.0, 16.0)
		"dance":
			_dance_cd = randf_range(15.0, 30.0)
			if is_instance_valid(_dance_partner):
				_dance_center = (global_position + _dance_partner.global_position) * 0.5


func _pick_landing_spot() -> void:
	_land_node = null
	var best_d: float = 5.0
	for b in get_tree().get_nodes_in_group("flora_bloom"):
		if b is Node3D and (b as Node3D).is_visible_in_tree():
			var d: float = (b as Node3D).global_position.distance_to(global_position)
			if d < best_d:
				best_d = d
				_land_node = b as Node3D
	if _land_node != null:
		_land_target = _land_node.global_position + Vector3.UP * float(_land_node.get_meta("landing_height", 0.4))
	else:
		var a: float = randf() * TAU
		_land_target = Vector3(global_position.x + cos(a) * 1.5, _ground_y + 0.03, global_position.z + sin(a) * 1.5)


func _act_extra(b: String, delta: float) -> Variant:
	var p: Node3D = get_player()
	match b:
		"land":
			var to: Vector3 = _land_target - global_position
			if to.length() < 0.06:
				global_position = _land_target
				set_behaviour("rest")
				return Vector3.ZERO
			return to.normalized() * minf(max_speed * 0.6, to.length() * 2.5)
		"rest":
			if _land_node != null and is_instance_valid(_land_node):
				global_position = global_position.lerp(_land_node.global_position + Vector3.UP * float(_land_node.get_meta("landing_height", 0.4)), clampf(4.0 * delta, 0.0, 1.0))
			velocity = Vector3.ZERO
			return Vector3.ZERO
		"shoulder_approach":
			if p == null:
				return null
			var sp: Vector3 = _shoulder_point(p)
			var gap: float = sp.distance_to(global_position)
			if gap < 0.18:
				# Final flutter-in: snap the last few centimetres and settle.
				global_position = sp
				velocity = Vector3.ZERO
				set_behaviour("shoulder")
				return Vector3.ZERO
			var approach: Vector3 = (sp - global_position).normalized() * minf(max_speed * 0.7, gap * 2.5 + 0.2)
			approach.y += sin(behaviour_time * 9.0) * 0.4  # still fluttery on the way in
			return approach
		"shoulder":
			if p == null:
				return null
			global_position = _shoulder_point(p)
			velocity = Vector3.ZERO
			return Vector3.ZERO
		"dance":
			if not is_instance_valid(_dance_partner):
				return null
			_dance_center += Vector3.UP * delta * (0.35 if behaviour_time < 3.5 else -0.4)
			var ang: float = behaviour_time * 4.0 + (0.0 if get_instance_id() < _dance_partner.get_instance_id() else PI)
			var tgt: Vector3 = _dance_center + Vector3(cos(ang), 0.0, sin(ang)) * 0.22
			return (tgt - global_position) * 6.0
	# Every free-flight behaviour gets the flutter: random vertical hops and sideways twitches.
	if flies and b in ["wander", "flock", "flee", "curious", "return", "play"]:
		_jitter = _jitter.lerp(Vector3(randf_range(-1, 1), randf_range(-1.2, 1.4), randf_range(-1, 1)) * 1.4, clampf(6.0 * delta, 0.0, 1.0))
		var base: Vector3 = _act_base(b, delta)
		return base + _jitter
	return null


func _shoulder_point(p: Node3D) -> Vector3:
	var f: Vector3 = Vector3.FORWARD
	if p.has_method("get_facing_direction"):
		f = p.call("get_facing_direction")
	var right := Vector3(-f.z, 0.0, f.x)
	return p.global_position + right * shoulder_offset.x + Vector3.UP * shoulder_offset.y + f * shoulder_offset.z


func _animate(delta: float) -> void:
	var p: Node3D = get_player()
	if p != null and _player_speed(p) < 0.4:
		_still_timer += delta
	else:
		_still_timer = 0.0
	var resting: bool = behaviour in ["rest", "shoulder"]
	_air_time = 0.0 if resting else _air_time + delta
	var speed: float = velocity.length()
	if not resting and _glide <= 0.0 and randf() < delta * 0.4 and speed > 0.6:
		_glide = randf_range(0.2, 0.5)
	_glide = maxf(0.0, _glide - delta)
	var rate: float = 0.7 if resting else (14.0 + speed * 3.0 + fear * 8.0)
	_flap += delta * rate
	var amp: float
	var open: float
	if resting:
		open = 0.25 + 0.55 * (0.5 + 0.5 * sin(_flap))
		amp = 0.0
	elif _glide > 0.0:
		open = 0.15
		amp = 0.05
	else:
		open = 0.35
		amp = 1.05
	var ang: float = open + sin(_flap * TAU * 0.16) * amp
	if _wing_r != null:
		_wing_r.rotation.z = ang
		_wing_l.rotation.z = -ang
	if _body != null:
		_body.rotation.x = 0.0 if resting else clampf(-velocity.y * 0.25, -0.5, 0.5)
		_body.position.y = 0.0 if resting else sin(_flap * TAU * 0.16) * 0.012

func _realm_look_profile() -> String:
	return "flower"  # wings turn to light in Mirror
