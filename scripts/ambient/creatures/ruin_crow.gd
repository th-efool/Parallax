class_name RuinCrow
extends AmbientCreature
## Ground-and-sky flock bird of the ruins. On the ground: hops, pecks, glances around, caws.
## Startle one and the whole murder bursts into the air (staggered contagion), circles overhead until
## things calm down, then drifts back down to the ground or to `fauna_perch` markers.
## Bold ones hop up to inspect the player; mischievous ones peck a flockmate from behind and hop off,
## starting a cawing, wing-flapping squabble; after a fight they come to pick at the scraps.
## Loners are bigger ravens; mischievous birds wear a red crest.

const KitScript := preload("res://scripts/ambient/fauna_mesh_kit.gd")
const GameFeelScript := preload("res://scripts/core/game_feel.gd")

@export var circle_altitude: float = 6.0
@export var ground_speed: float = 1.5
@export var air_speed: float = 5.2

var airborne: bool = false
var _head: Node3D = null
var _beak_low: Node3D = null
var _wing_l: Node3D = null
var _wing_r: Node3D = null
var _tail: Node3D = null
var _hop_phase: float = 0.0
var _flap: float = 0.0
var _peck: float = 0.0
var _caw_t: float = 0.0
var _caw_cd: float = 0.0
var _look_t: float = 0.0
var _head_yaw: float = 0.0
var _head_yaw_target: float = 0.0
var _perch: Node3D = null
var _land_pos: Vector3 = Vector3.ZERO
var _calm_time: float = 0.0
var _circle_dir: float = 1.0


func _configure() -> void:
	species = "crow"
	flies = false
	max_speed = ground_speed
	accel = 7.0
	min_altitude = 1.0
	max_altitude = 12.0
	turn_speed = 9.0
	_circle_dir = 1.0 if randf() < 0.5 else -1.0


func _species_traits() -> Dictionary:
	return {"bold": 0.55, "curiosity": 0.6, "sociability": 0.65, "mischief": 0.5, "energy": 0.5}


func _build_body(root: Node3D) -> void:
	var s: float = randf_range(0.9, 1.08)
	if archetype == Archetype.LONER:
		s *= 1.3  # raven
	root.scale = Vector3.ONE * s
	var black := KitScript.mat(Color(0.06, 0.06, 0.08))
	var sheen := KitScript.mat(Color(0.1, 0.12, 0.2))
	var beak := KitScript.mat(Color(0.18, 0.17, 0.16))
	KitScript.part(root, KitScript.sphere(0.12, 8, 5), black, Vector3(0, 0.17, 0.02), Vector3(0.8, 0.85, 1.35), Vector3.ZERO, "Torso")
	_head = KitScript.pivot(root, Vector3(0, 0.28, -0.13), "Head")
	KitScript.part(_head, KitScript.sphere(0.075, 8, 5), sheen, Vector3.ZERO)
	KitScript.part(_head, KitScript.prism(Vector3(0.045, 0.1, 0.035)), beak, Vector3(0, 0.0, -0.1), Vector3.ONE, Vector3(-PI * 0.5, 0, 0))
	_beak_low = KitScript.pivot(_head, Vector3(0, -0.012, -0.05), "BeakLow")
	KitScript.part(_beak_low, KitScript.box(Vector3(0.03, 0.01, 0.07)), beak, Vector3(0, -0.005, -0.03))
	var eye := KitScript.mat(Color(0.95, 0.85, 0.5), 1.5, true)
	KitScript.part(_head, KitScript.sphere(0.012, 6, 4), eye, Vector3(0.055, 0.02, -0.03))
	KitScript.part(_head, KitScript.sphere(0.012, 6, 4), eye, Vector3(-0.055, 0.02, -0.03))
	if archetype == Archetype.MISCHIEVOUS:
		KitScript.part(_head, KitScript.prism(Vector3(0.02, 0.06, 0.05)), KitScript.mat(Color(0.8, 0.1, 0.08)), Vector3(0, 0.08, 0.0))
	_tail = KitScript.pivot(root, Vector3(0, 0.17, 0.17), "Tail")
	KitScript.part(_tail, KitScript.box(Vector3(0.11, 0.015, 0.2)), black, Vector3(0, 0, 0.09))
	# Rounded inner wing + swept primary-feather tip so the silhouette reads as a bird, not a board.
	var inner := KitScript.sphere(0.5, 8, 4)
	var tip := KitScript.prism(Vector3(0.1, 0.012, 0.16))
	_wing_r = KitScript.pivot(root, Vector3(0.07, 0.22, 0.0), "WingR")
	KitScript.part(_wing_r, inner, black, Vector3(0.1, 0, 0.03), Vector3(0.22, 0.02, 0.13))
	KitScript.part(_wing_r, tip, sheen, Vector3(0.24, 0, 0.07), Vector3.ONE, Vector3(PI * 0.5, 0.0, -0.35))
	_wing_l = KitScript.pivot(root, Vector3(-0.07, 0.22, 0.0), "WingL")
	KitScript.part(_wing_l, inner, black, Vector3(-0.1, 0, 0.03), Vector3(0.22, 0.02, 0.13))
	KitScript.part(_wing_l, tip, sheen, Vector3(-0.24, 0, 0.07), Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.35))
	var leg := KitScript.box(Vector3(0.012, 0.09, 0.012))
	KitScript.part(root, leg, beak, Vector3(0.035, 0.045, 0.02))
	KitScript.part(root, leg, beak, Vector3(-0.035, 0.045, 0.02))


func _set_airborne(on: bool) -> void:
	if airborne == on:
		return
	airborne = on
	flies = on
	max_speed = air_speed if on else ground_speed
	accel = 6.0 if on else 7.0
	if on:
		velocity.y = 3.5
		_caw(true)
		GameFeelScript.play_sound(self, "flutter", global_position, -16.0, 0.8)


func _disturbance_sensitivity(kind: String) -> float:
	return 0.6 if kind == "death" else 1.0


func _score_extra(s: Dictionary) -> void:
	_caw_cd = maxf(0.0, _caw_cd - 1.0 / think_hz)
	if airborne:
		# In the air: keep circling while scared, then come down.
		s.erase("idle")
		s.erase("curious")
		s.erase("play")
		s["circle"] = 0.5 + fear
		if fear < 0.15:
			_calm_time += 1.0 / think_hz
		else:
			_calm_time = 0.0
		if _calm_time > 2.5 + (1.0 - trait_value("bold")) * 3.0:
			s["descend"] = 0.95
		if behaviour == "descend":
			s["descend"] = 1.0
		s["flee"] = fear * 0.6  # prefer circling over fleeing once up
		return
	if fear > 0.45:
		s["takeoff"] = fear * 1.3
	s["peck"] = 0.28 + (1.0 - trait_value("energy")) * 0.2
	if _director != null and fear < 0.3 and trait_value("bold") > 0.4:
		var scraps: Dictionary = _director.nearest_interest(global_position, "scraps", 14.0)
		if not scraps.is_empty():
			s["scavenge"] = 0.5 + trait_value("bold") * 0.3
			if behaviour != "scavenge":
				focus_pos = scraps["pos"] as Vector3
	# Curious crows keep a respectful hop-distance from the player.
	if s.has("curious"):
		s["curious"] = float(s["curious"]) * 0.9


func _on_behaviour_entered(b: String) -> void:
	match b:
		"takeoff":
			_set_airborne(true)
		"descend":
			_choose_landing()
			min_altitude = 0.0  # allow touching down
		"circle", "takeoff":
			min_altitude = 1.0
		"peck":
			_peck = 0.0
	if randf() < 0.2:
		_caw(false)


func _choose_landing() -> void:
	_perch = null
	var best_d: float = 14.0
	for n in get_tree().get_nodes_in_group("fauna_perch"):
		if n is Node3D and not bool(n.get_meta("occupied", false)):
			var d: float = (n as Node3D).global_position.distance_to(home)
			if d < best_d and randf() < 0.7:
				best_d = d
				_perch = n as Node3D
	if _perch != null:
		_perch.set_meta("occupied", true)
		_land_pos = _perch.global_position
	else:
		var a: float = randf() * TAU
		var r: float = randf() * home_radius * 0.7
		_land_pos = Vector3(home.x + cos(a) * r, home.y, home.z + sin(a) * r)


func _act_extra(b: String, delta: float) -> Variant:
	match b:
		"takeoff":
			var up: Vector3 = flee_from(fear_source, max_speed * 0.6)
			up.y = 3.5
			return up
		"circle":
			var c: Vector3 = home + Vector3.UP * (circle_altitude + float(get_instance_id() % 5) * 0.4)
			var v: Vector3 = orbit(c, 3.5 + float(get_instance_id() % 3), _circle_dir, max_speed * 0.8)
			v.y = clampf((c.y - global_position.y) * 1.2, -2.0, 3.0)
			return v
		"descend":
			var to: Vector3 = _land_pos - global_position
			if to.length() < 0.35 or (to.y > -0.4 and Vector2(to.x, to.z).length() < 0.5):
				global_position = _land_pos
				_ground_y = _land_pos.y
				_set_airborne(false)
				home = _land_pos if _perch == null else home
				set_behaviour("idle")
				return Vector3.ZERO
			return to.normalized() * minf(max_speed * 0.7, to.length() * 1.5 + 0.8)
		"peck":
			return Vector3.ZERO
		"scavenge":
			var d: float = Vector2(focus_pos.x - global_position.x, focus_pos.z - global_position.z).length()
			if d < 0.5:
				return Vector3.ZERO
			return steer_to(focus_pos, max_speed, 0.4)
		"flee":
			if not airborne:
				_set_airborne(true)
			var away: Vector3 = flee_from(fear_source, max_speed)
			away.y = 2.5
			return away
	if not airborne and _perch != null and b in ["idle", "peck"]:
		# Perched birds stay put on their ledge.
		global_position = global_position.lerp(_perch.global_position, clampf(5.0 * delta, 0.0, 1.0))
		_ground_y = _perch.global_position.y
		return Vector3.ZERO
	if not airborne and _perch != null and b not in ["idle", "peck"]:
		_perch.set_meta("occupied", false)
		_perch = null
	return null


func _post_move(delta: float) -> void:
	if _perch != null and not airborne:
		return
	super._post_move(delta)


func _on_play_event(kind: String) -> void:
	_caw(true)
	if kind == "poke":
		_peck = 0.0
		_flap = 0.0


func _caw(force: bool) -> void:
	if _caw_cd > 0.0 and not force:
		return
	_caw_cd = randf_range(2.5, 6.0)
	_caw_t = 0.35
	GameFeelScript.play_sound(self, "caw", global_position, -11.0 if force else -14.0, randf_range(0.85, 1.15) / (1.2 if archetype == Archetype.LONER else 1.0), 0.06)


func _animate(delta: float) -> void:
	var speed: float = Vector2(velocity.x, velocity.z).length()
	_caw_t = maxf(0.0, _caw_t - delta)
	if _beak_low != null:
		_beak_low.rotation.x = 0.45 if _caw_t > 0.0 else 0.0
	if not airborne and randf() < delta * 0.08:
		_caw(false)
	# Head: quick bird glances, peck bobs, tilt toward focus when curious.
	_look_t -= delta
	if _look_t <= 0.0:
		_look_t = randf_range(0.3, 1.4)
		_head_yaw_target = randf_range(-1.0, 1.0)
	_head_yaw = lerpf(_head_yaw, _head_yaw_target, clampf(25.0 * delta, 0.0, 1.0))  # snappy, bird-like
	var head_pitch: float = 0.0
	if behaviour in ["peck", "scavenge"] and speed < 0.2:
		_peck += delta * 7.0
		head_pitch = maxf(0.0, sin(_peck)) * 1.1
	if _head != null:
		_head.rotation = Vector3(head_pitch, _head_yaw, 0.35 * sin(_look_t * 3.0) if behaviour == "curious" else 0.0)
	# Body: hops on the ground, flaps / glides in the air.
	if airborne:
		_flap += delta * (11.0 if velocity.y > 0.3 or fear > 0.3 else 5.0)
		var glide: bool = velocity.y < -0.2 and fear < 0.3
		var a: float = 0.15 if glide else sin(_flap) * 1.0
		if _wing_r != null:
			_wing_r.rotation.z = a
			_wing_l.rotation.z = -a
		if _body != null:
			_body.position.y = 0.0
			_body.rotation.x = clampf(-velocity.y * 0.12, -0.4, 0.4)
	else:
		if speed > 0.15:
			_hop_phase += delta * 9.0
		else:
			_hop_phase = 0.0
		var hop: float = absf(sin(_hop_phase)) * 0.08
		var flap_ground: float = 0.0
		if behaviour == "play" or (fear > 0.3 and fear < 0.45):
			_flap += delta * 14.0
			flap_ground = (0.5 + 0.5 * sin(_flap)) * 0.9  # squabble flaps
		if _wing_r != null:
			_wing_r.rotation.z = -0.15 + flap_ground
			_wing_l.rotation.z = 0.15 - flap_ground
		if _body != null:
			_body.position.y = hop
			_body.rotation.x = 0.0
	if _tail != null:
		_tail.rotation.x = 0.2 * sin(_hop_phase * 0.5) + (0.3 if airborne else 0.0)
