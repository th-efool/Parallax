class_name SunLizard
extends AmbientCreature
## Wall lizard of the sun-baked ruins (Reality only — cold-blooded, nowhere to be seen in moonlit Mirror).
## Basks flat on warm stone, does territorial push-ups, darts between sunny spots in lightning bursts
## and freezes mid-dash; when spooked it bolts for cover (`fauna_cover`) or away and goes motionless.
## Curious ones creep up to a still player and display (push-ups + throat flick); mischievous ones
## chase rivals off "their" stone.

const KitScript := preload("res://scripts/ambient/fauna_mesh_kit.gd")

@export var skin_base: Color = Color(0.52, 0.5, 0.32)
@export var skin_accent: Color = Color(0.25, 0.42, 0.22)

var _head: Node3D = null
var _tail: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _dewlap: MeshInstance3D = null
var _gait: float = 0.0
var _dart_t: float = 0.0
var _frozen: bool = false
var _pushup_t: float = 0.0
var _bask_spot: Vector3 = Vector3.ZERO


func _configure() -> void:
	species = "lizard"
	flies = false
	max_speed = 4.8
	accel = 40.0
	turn_speed = 18.0
	realm_presence = RealmPresence.REALITY_ONLY
	home_radius = maxf(home_radius, 4.0)
	lod_distance = 25.0


func _species_traits() -> Dictionary:
	return {"bold": 0.3, "curiosity": 0.55, "sociability": 0.15, "mischief": 0.5, "energy": 0.5}


func _build_body(root: Node3D) -> void:
	var s: float = randf_range(1.0, 1.35)
	root.scale = Vector3.ONE * s
	var hue: float = randf_range(-0.06, 0.06)
	var base_c: Color = skin_base.lerp(Color(0.35, 0.33, 0.28), randf() * 0.5)
	base_c.h = wrapf(base_c.h + hue, 0.0, 1.0)
	var skin := KitScript.mat(base_c)
	var accent := KitScript.mat(skin_accent.lerp(base_c, randf() * 0.4))
	var belly := KitScript.mat(base_c.lightened(0.3))
	KitScript.part(root, KitScript.sphere(0.05, 8, 5), skin, Vector3(0, 0.035, 0), Vector3(0.75, 0.45, 2.0), Vector3.ZERO, "Body")
	# Dorsal pattern: a row of darker scale patches.
	# Dorsal stripe (one stretched patch instead of many: fewer draw calls).
	KitScript.part(root, KitScript.sphere(0.012, 5, 3), accent, Vector3(0, 0.056, 0.0), Vector3(1.4, 0.5, 8.0))
	_head = KitScript.pivot(root, Vector3(0, 0.04, -0.1), "Head")
	KitScript.part(_head, KitScript.sphere(0.028, 7, 4), skin, Vector3(0, 0, -0.02), Vector3(0.9, 0.6, 1.5))
	var eye := KitScript.mat(Color(0.9, 0.7, 0.2), 0.6)
	KitScript.part(_head, KitScript.sphere(0.006, 5, 3), eye, Vector3(0.018, 0.008, -0.025))
	KitScript.part(_head, KitScript.sphere(0.006, 5, 3), eye, Vector3(-0.018, 0.008, -0.025))
	_dewlap = KitScript.part(_head, KitScript.sphere(0.015, 6, 3), KitScript.mat(Color(0.95, 0.55, 0.2)), Vector3(0, -0.015, -0.015), Vector3(0.6, 0.2, 1.0))
	var parent: Node3D = KitScript.pivot(root, Vector3(0, 0.03, 0.09), "Tail0")
	_tail.append(parent)
	for i in range(3):
		var seg_len: float = 0.075 - i * 0.012
		KitScript.part(parent, KitScript.cone(0.006 - i * 0.001, 0.012 - i * 0.0015, seg_len, 5), skin if i % 2 == 0 else accent, Vector3(0, 0, seg_len * 0.5), Vector3.ONE, Vector3(PI * 0.5, 0, 0))
		var nxt: Node3D = KitScript.pivot(parent, Vector3(0, 0, seg_len), "Tail%d" % (i + 1))
		_tail.append(nxt)
		parent = nxt
	for corner in [Vector3(0.035, 0.03, -0.05), Vector3(-0.035, 0.03, -0.05), Vector3(0.035, 0.03, 0.05), Vector3(-0.035, 0.03, 0.05)]:
		var hip: Node3D = KitScript.pivot(root, corner, "Leg")
		KitScript.part(hip, KitScript.box(Vector3(0.045, 0.008, 0.01)), skin, Vector3(signf(corner.x) * 0.022, -0.012, 0), Vector3.ONE, Vector3(0, 0, signf(corner.x) * -0.5))
		_legs.append(hip)
	_body.position.y = 0.0


func _realm_look_profile() -> String:
	return ""  # Reality-only


func _disturbance_sensitivity(kind: String) -> float:
	return 1.5 if kind in ["footsteps", "swing", "slam"] else 1.0


func _score_extra(s: Dictionary) -> void:
	s.erase("flock")
	s["bask"] = 0.45 + (1.0 - trait_value("energy")) * 0.25
	# No basking in the rain: shelter under cover until it clears.
	var wet: float = _director.get_wetness() if _director != null else 0.0
	if wet > 0.25:
		s["hide"] = maxf(float(s.get("hide", 0.0)), 0.6 + wet)
		s.erase("bask")
	if fear > 0.3:
		s["hide"] = fear * 1.4
		s.erase("flee")
	if behaviour == "hide":
		s["hide"] = maxf(float(s.get("hide", 0.0)), 0.8 if behaviour_time < 3.0 else 0.0)
	if s.has("curious"):
		s["curious"] = float(s["curious"]) * 0.8


func _on_behaviour_entered(b: String) -> void:
	match b:
		"bask":
			var a: float = randf() * TAU
			_bask_spot = global_position + Vector3(cos(a), 0, sin(a)) * randf_range(0.5, 2.5)
			if Vector2(_bask_spot.x - home.x, _bask_spot.z - home.z).length() > home_radius:
				_bask_spot = home
			_pushup_t = randf_range(1.0, 4.0)
		"hide":
			_frozen = false


func _act_extra(b: String, delta: float) -> Variant:
	match b:
		"bask", "wander":
			return _dart(_bask_spot if b == "bask" else global_position + wander(1.0, delta), delta)
		"hide":
			var cover: Node3D = _nearest_cover()
			if cover != null and cover.global_position.distance_to(global_position) > 0.25:
				return steer_to(cover.global_position, max_speed, 0.2)
			if cover == null and behaviour_time < 0.5:
				return flee_from(fear_source, max_speed)
			return Vector3.ZERO  # motionless
		"curious":
			if not is_instance_valid(focus):
				return null
			var d: float = focus.global_position.distance_to(global_position)
			if d > 1.3:
				return _dart(focus.global_position, delta)
			return Vector3.ZERO
	return null


## Lizard locomotion: lightning dash, sudden freeze, dash again.
func _dart(target: Vector3, delta: float) -> Vector3:
	_dart_t -= delta
	if _dart_t <= 0.0:
		_frozen = not _frozen
		_dart_t = randf_range(0.6, 2.4) if _frozen else randf_range(0.15, 0.4)
	var to: Vector3 = target - global_position
	to.y = 0.0
	if _frozen or to.length() < 0.15:
		return Vector3.ZERO
	return to.normalized() * max_speed


func _nearest_cover() -> Node3D:
	var best: Node3D = null
	var best_d: float = 6.0
	for c in get_tree().get_nodes_in_group("fauna_cover"):
		if c is Node3D:
			var d: float = (c as Node3D).global_position.distance_to(global_position)
			if d < best_d:
				best_d = d
				best = c as Node3D
	return best


func _animate(delta: float) -> void:
	var speed: float = Vector2(velocity.x, velocity.z).length()
	_gait += delta * (8.0 + speed * 14.0)
	var moving: bool = speed > 0.2
	# Sprawled gait: diagonal legs swing together, body S-curves through the tail.
	for i in range(_legs.size()):
		var phase: float = _gait + (PI if i in [1, 2] else 0.0)
		_legs[i].rotation.y = sin(phase) * (0.7 if moving else 0.0)
	for i in range(_tail.size()):
		var w: float = sin(_gait * 0.5 - i * 0.8) * (0.35 if moving else 0.08)
		if behaviour == "hide" and not moving:
			w = 0.25  # curled
		_tail[i].rotation.y = w
	# Push-ups + throat flick while basking or displaying to the player.
	var lift: float = 0.0
	if not moving and behaviour in ["bask", "curious"]:
		_pushup_t -= delta
		if _pushup_t < 0.0:
			lift = maxf(0.0, sin(-_pushup_t * 12.0)) * 0.02
			if _pushup_t < -0.8:
				_pushup_t = randf_range(2.0, 6.0)
	if _body != null:
		_body.position.y = lift
		_body.rotation.x = -lift * 6.0
	if _dewlap != null:
		_dewlap.scale = Vector3(0.6, 0.2 + lift * 40.0, 1.0)
	if _head != null:
		_head.rotation.y = sin(_gait * 0.13) * 0.3 if not moving else 0.0
