class_name AmbientCreature
extends Node3D
## Base "brain + body" for non-combat ambient life. Neither enemy nor friend: no collision, no damage,
## never blocks the player, never counts toward encounters (Golden Collision Rule is trivially kept).
##
## Brain: utility AI ticked at ~8 Hz (staggered). Every instance rolls its own *personality* from its
## species baseline + archetype (curious / skittish / mischievous / loner / social / lazy):
##   bold, curiosity, sociability, mischief, energy  (0..1)
## Behaviours each get a score from perception (player, enemies, flockmates, FaunaDirector disturbances,
## points of interest) x personality; the best one wins with inertia so they don't flicker.
## Shared behaviours: idle, wander, flock, flee, curious (approach + circle someone), play (poke-and-chase
## games with a flockmate, role swaps = bickering), seek_interest (souls / scraps after fights), return.
## Species add their own (perch, land, hide, sniff, follow-the-leader...).

const WORLD_MASK: int = 4 | 8 | 16

enum Archetype { RANDOM, CURIOUS, SKITTISH, MISCHIEVOUS, LONER, SOCIAL, LAZY }
enum RealmPresence { BOTH, REALITY_ONLY, MIRROR_ONLY }

signal behaviour_changed(new_behaviour: String)
signal played_with(partner: Node3D, role: String)

@export var archetype: Archetype = Archetype.RANDOM
@export var realm_presence: RealmPresence = RealmPresence.BOTH
@export var home_radius: float = 8.0
## Set by AmbientHabitat; -1 = loner with no group.
@export var group_id: int = -1
@export var lod_distance: float = 48.0
@export var think_hz: float = 8.0
@export var debug_label: bool = false

var species: String = "creature"
var traits: Dictionary = {"bold": 0.5, "curiosity": 0.5, "sociability": 0.5, "mischief": 0.3, "energy": 0.5}
var archetype_name: String = ""
var home: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var behaviour: String = "idle"
var behaviour_time: float = 0.0
var focus: Node3D = null
var focus_pos: Vector3 = Vector3.ZERO
var fear: float = 0.0
var fear_source: Vector3 = Vector3.ZERO
var is_present: bool = true
## Species this creature hunts (prey within range feel threatened). Set by predator species.
var hunts: Array = []

# Kinematics (species set these in _configure)
var max_speed: float = 2.0
var accel: float = 8.0
var flies: bool = false
var ground_offset: float = 0.0
var min_altitude: float = 0.4
var max_altitude: float = 6.0
var turn_speed: float = 8.0

var _director: FaunaDirector = null
var _rng := RandomNumberGenerator.new()
var _think_acc: float = 0.0
var _wander_heading: float = 0.0
var _wander_alt: float = 1.5
var _ground_y: float = 0.0
var _ground_timer: float = 0.0
var _has_ground: bool = true
var _lod_timer: float = 0.0
var _body: Node3D = null
var _label: Label3D = null

var _play_partner: Node3D = null
var _play_role: String = ""
var _play_swaps: int = 0
var _play_until: float = 0.0
var _play_cooldown: float = 0.0
var _pending_fear: Array[Vector2] = []  # (amount, fire_time)
var _scores: Dictionary = {}
var _mates_cache: Array[Node3D] = []
var _cam_dist: float = 0.0


# ------------------------------------------------------------------ lifecycle

func _ready() -> void:
	add_to_group("ambient_creature")
	_rng.randomize()
	home = global_position
	_ground_y = global_position.y
	_wander_heading = _rng.randf_range(0.0, TAU)
	_think_acc = _rng.randf_range(0.0, 1.0 / think_hz)
	_configure()
	_roll_personality()
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_build_body(_body)
	var look: String = _realm_look_profile()
	if not look.is_empty():
		RealmLook.apply(_body, look)  # moonlit / luminous variant in Mirror
	# GPU distance culling for every body part (no per-frame script cost).
	for gi in _body.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).visibility_range_end = lod_distance
		(gi as GeometryInstance3D).visibility_range_end_margin = 4.0
	_director = FaunaDirector.get_for(self)
	if _director != null:
		_director.register_creature(self)
		_director.realm_shifted.connect(_on_realm_shifted)
	if debug_label:
		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.font_size = 28
		_label.position = Vector3.UP * 0.6
		_label.no_depth_test = true
		add_child(_label)
	_refresh_presence()


func _exit_tree() -> void:
	if _director != null and is_instance_valid(_director):
		_director.unregister_creature(self)
	_on_despawn()


# ------------------------------------------------------------------ virtuals for species

## Set species name, kinematics and the species' personality baseline here.
func _configure() -> void:
	pass


## Species personality baseline (0..1). Archetype modifiers are applied on top.
func _species_traits() -> Dictionary:
	return {"bold": 0.5, "curiosity": 0.5, "sociability": 0.5, "mischief": 0.3, "energy": 0.5}


func _build_body(_root: Node3D) -> void:
	pass


## RealmLook profile applied to the procedural body ("" = species handles its own realm look).
func _realm_look_profile() -> String:
	return "fur"


## Return {behaviour_name: score}. Base scores are filled first; species add or override.
func _score_extra(_scores_in: Dictionary) -> void:
	pass


## Desired velocity for species-specific behaviours. Return null to fall back to the base.
func _act_extra(_b: String, _delta: float) -> Variant:
	return null


func _animate(_delta: float) -> void:
	pass


func _on_behaviour_entered(_b: String) -> void:
	pass


func _on_play_event(_kind: String) -> void:
	pass


func _on_despawn() -> void:
	pass


# ------------------------------------------------------------------ personality

func _roll_personality() -> void:
	var base: Dictionary = _species_traits()
	var a: Archetype = archetype
	if a == Archetype.RANDOM:
		var pool: Array[Archetype] = [Archetype.CURIOUS, Archetype.SKITTISH, Archetype.MISCHIEVOUS, Archetype.LONER, Archetype.SOCIAL, Archetype.SOCIAL, Archetype.LAZY]
		a = pool[_rng.randi_range(0, pool.size() - 1)]
	archetype = a
	var mods: Dictionary = {}
	match a:
		Archetype.CURIOUS:
			archetype_name = "curious"
			mods = {"curiosity": 0.4, "bold": 0.25}
		Archetype.SKITTISH:
			archetype_name = "skittish"
			mods = {"bold": -0.4, "curiosity": -0.2, "energy": 0.15}
		Archetype.MISCHIEVOUS:
			archetype_name = "mischievous"
			mods = {"mischief": 0.5, "energy": 0.25, "bold": 0.1}
		Archetype.LONER:
			archetype_name = "loner"
			mods = {"sociability": -0.5, "bold": 0.1}
		Archetype.SOCIAL:
			archetype_name = "social"
			mods = {"sociability": 0.35, "mischief": 0.1}
		Archetype.LAZY:
			archetype_name = "lazy"
			mods = {"energy": -0.4, "curiosity": -0.1}
	for k in base.keys():
		traits[k] = clampf(float(base[k]) + float(mods.get(k, 0.0)) + _rng.randf_range(-0.12, 0.12), 0.0, 1.0)
	if group_id < 0:
		traits["sociability"] = minf(float(traits["sociability"]), 0.3)


func trait_value(t: String) -> float:
	return float(traits.get(t, 0.5))


# ------------------------------------------------------------------ main loop

func _process(delta: float) -> void:
	if not _update_lod(delta):
		return
	_think_acc += delta
	# Distant creatures think slower (still animate and move smoothly).
	var hz: float = think_hz if _cam_dist < 22.0 else think_hz * 0.3
	if _think_acc >= 1.0 / hz:
		think(_think_acc)
		_think_acc = 0.0
	behaviour_time += delta
	_play_cooldown = maxf(0.0, _play_cooldown - delta)
	fear = maxf(0.0, fear - delta * (0.18 + trait_value("bold") * 0.3))
	_process_pending_fear()

	var desired: Variant = _act_extra(behaviour, delta)
	if desired == null:
		desired = _act_base(behaviour, delta)
	var dv: Vector3 = desired as Vector3
	if dv.length() > max_speed * 1.6:
		dv = dv.normalized() * max_speed * 1.6
	velocity = velocity.move_toward(dv, accel * delta)
	global_position += velocity * delta
	_post_move(delta)
	_face_velocity(delta)
	_animate(delta)
	if _label != null:
		_label.text = "%s\n%s %s f%.1f" % [species, archetype_name, behaviour, fear]


func _update_lod(delta: float) -> bool:
	if not is_present:
		return false
	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_lod_timer = 0.5
		var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
		_cam_dist = cam.global_position.distance_to(global_position) if cam != null else 0.0
		var near: bool = cam == null or _cam_dist <= lod_distance
		if _body != null:
			_body.visible = near
		set_meta("lod_far", not near)
	return not bool(get_meta("lod_far", false))


func think(_dt: float) -> void:
	if _director != null and group_id >= 0:
		_mates_cache = _director.flockmates(self, species, 6.0, group_id)
	_perceive()
	_scores = {}
	_score_base(_scores)
	_score_extra(_scores)
	var best: String = behaviour
	var best_s: float = -INF
	for k in _scores.keys():
		var s: float = float(_scores[k])
		if k == behaviour:
			s += 0.12 if behaviour_time > 0.6 else 0.6  # inertia + minimum hold
		if s > best_s:
			best_s = s
			best = String(k)
	if best != behaviour:
		set_behaviour(best)


func set_behaviour(b: String) -> void:
	if b == behaviour:
		return
	if behaviour == "play" and b != "play":
		_play_partner = null
		_play_role = ""
	behaviour = b
	behaviour_time = 0.0
	_on_behaviour_entered(b)
	behaviour_changed.emit(b)


# ------------------------------------------------------------------ perception

func get_player() -> Node3D:
	return _director.get_player() if _director != null else null


func _player_speed(p: Node3D) -> float:
	if p is CharacterBody3D:
		var v: Vector3 = (p as CharacterBody3D).velocity
		return Vector2(v.x, v.z).length()
	return 0.0


func _player_is_violent(p: Node3D) -> bool:
	if p is PlayerController:
		var st: int = int((p as PlayerController).current_state)
		return st == PlayerController.State.LIGHT_ATTACK or st == PlayerController.State.HEAVY_ATTACK or st == PlayerController.State.LANDING_PLUNGE
	return false


func nearest_enemy(radius: float) -> Node3D:
	var best: Node3D = null
	var best_d: float = radius
	if _director == null:
		return null
	for e in _director.get_enemies():
		var eb: EnemyBase = e as EnemyBase
		if eb == null or not is_instance_valid(eb) or eb.is_dead or not eb.is_active:
			continue
		var d: float = eb.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = eb
	return best


func _perceive() -> void:
	var bold: float = trait_value("bold")
	var threat: float = 0.0
	var src: Vector3 = fear_source
	var p: Node3D = get_player()
	if p != null and p.is_inside_tree():
		var d: float = p.global_position.distance_to(global_position)
		var scare_r: float = 1.8 + 4.5 * (1.0 - bold)
		if d < scare_r:
			var k: float = (1.0 - d / scare_r) * (0.35 + _player_speed(p) / 7.0)
			if _player_is_violent(p):
				k *= 1.8
			if k > threat:
				threat = k
				src = p.global_position
	var e: Node3D = nearest_enemy(5.0)
	if e != null:
		var de: float = e.global_position.distance_to(global_position)
		var ke: float = (1.0 - de / 5.0) * 0.55 * (1.2 - bold)
		if e is EnemyAI and int((e as EnemyAI).current_state) in [EnemyAI.State.WINDUP, EnemyAI.State.ATTACK]:
			ke *= 2.0
		if ke > threat:
			threat = ke
			src = e.global_position
	if _director != null:
		var dist: Dictionary = _director.sample_disturbance(global_position)
		var ds: float = float(dist["strength"]) * (1.25 - bold) * _disturbance_sensitivity(String(dist["kind"]))
		if ds > threat:
			threat = ds
			src = dist["pos"] as Vector3
	# Prey sense predators that hunt their species (e.g. foxes stalking rats / pigeons / scurriers).
	if _director != null:
		for c in _director.hunters:
			if not is_instance_valid(c) or c == self:
				continue
			if not (c.get("hunts") as Array).has(species):
				continue
			var dp: float = (c as Node3D).global_position.distance_to(global_position)
			var hunting: bool = String(c.get("behaviour")) == "hunt"
			var rp: float = 6.0 if hunting else 3.0
			if dp < rp:
				var tp: float = (1.0 - dp / rp) * (1.1 if hunting else 0.6) * (1.2 - bold)
				if tp > threat:
					threat = tp
					src = (c as Node3D).global_position
	threat = clampf(threat, 0.0, 1.5)
	if threat > fear:
		var jumped: bool = threat > 0.6 and fear < 0.6
		fear = threat
		fear_source = src
		if jumped:
			_spread_fear()


## Species may shrug off (or love) certain disturbance kinds.
func _disturbance_sensitivity(_kind: String) -> float:
	return 1.0


## Panic is contagious: nearby flockmates startle a beat later (staggered = looks orchestrated).
func _spread_fear() -> void:
	if _director == null or group_id < 0:
		return
	for m in _director.flockmates(self, species, 6.0, group_id):
		if m.has_method("receive_fear"):
			m.call("receive_fear", fear * 0.75, fear_source, _rng.randf_range(0.05, 0.3))


func receive_fear(amount: float, source: Vector3, delay: float) -> void:
	_pending_fear.append(Vector2(amount, FaunaDirector.now() + delay))
	fear_source = source


func _process_pending_fear() -> void:
	if _pending_fear.is_empty():
		return
	var t: float = FaunaDirector.now()
	var i: int = _pending_fear.size() - 1
	while i >= 0:
		if t >= _pending_fear[i].y:
			if _pending_fear[i].x > fear:
				fear = _pending_fear[i].x
				if fear > 0.55 and behaviour != "flee":
					think(0.0)
			_pending_fear.remove_at(i)
		i -= 1


# ------------------------------------------------------------------ base scoring

func _score_base(s: Dictionary) -> void:
	var energy: float = trait_value("energy")
	var social: float = trait_value("sociability")
	var curious: float = trait_value("curiosity")
	var mischief: float = trait_value("mischief")
	s["idle"] = 0.15 + (1.0 - energy) * 0.25
	s["wander"] = 0.25 + energy * 0.2
	if group_id >= 0 and _director != null:
		var mates: int = _director.flockmates(self, species, 9.0, group_id).size()
		if mates > 0:
			s["flock"] = 0.2 + social * 0.45
	if fear > 0.25:
		s["flee"] = fear * 1.2
	var dh: float = Vector2(global_position.x - home.x, global_position.z - home.z).length()
	if dh > home_radius:
		s["return"] = 0.3 + (dh - home_radius) / maxf(1.0, home_radius) * 0.6
	# Curiosity: the player, or an enemy if bold enough.
	var p: Node3D = get_player()
	if p != null and fear < 0.35:
		var d: float = p.global_position.distance_to(global_position)
		if d < 10.0 and d > 1.0:
			var calm: float = 1.0 - clampf(_player_speed(p) / 7.0, 0.0, 1.0)
			s["curious"] = curious * (0.35 + 0.45 * calm) * (1.0 - d / 12.0) + (0.1 if archetype == Archetype.CURIOUS else 0.0)
			if behaviour != "curious":
				focus = p
	if fear < 0.25 and curious > 0.55 and trait_value("bold") > 0.5:
		var e: Node3D = nearest_enemy(9.0)
		if e != null and float(s.get("curious", 0.0)) < 0.35:
			s["curious"] = curious * 0.4
			if behaviour != "curious":
				focus = e
	# Play: mischievous creatures start poke-and-chase games with flockmates.
	if behaviour == "play":
		s["play"] = 0.95
	elif mischief > 0.45 and _play_cooldown <= 0.0 and fear < 0.15 and group_id >= 0 and _rng.randf() < 0.08 * mischief:
		var mate: Node3D = _director.find_playmate(self, species, 7.0) if _director != null else null
		if mate != null:
			_start_play_as_poker(mate)
			s["play"] = 1.0


# ------------------------------------------------------------------ base behaviours

func _act_base(b: String, delta: float) -> Vector3:
	match b:
		"idle":
			return Vector3.ZERO
		"wander":
			return wander(max_speed * (0.35 + trait_value("energy") * 0.4), delta)
		"flock":
			return flock(delta)
		"flee":
			return flee_from(fear_source, max_speed * (1.0 + fear * 0.6))
		"return":
			return steer_to(home, max_speed * 0.8, 1.0)
		"curious":
			if not is_instance_valid(focus):
				return Vector3.ZERO
			return orbit(focus.global_position, 1.8 + (1.0 - trait_value("bold")) * 1.6, 0.6 * (1.0 if get_instance_id() % 2 == 0 else -1.0), max_speed * 0.6)
		"play":
			return _act_play(delta)
		"seek_interest":
			return steer_to(focus_pos, max_speed * 0.7, 0.6)
	return Vector3.ZERO


# ------------------------------------------------------------------ steering helpers

func steer_to(target: Vector3, speed: float, arrive_r: float = 0.5) -> Vector3:
	var to: Vector3 = target - global_position
	if not flies:
		to.y = 0.0
	var d: float = to.length()
	if d < 0.01:
		return Vector3.ZERO
	var k: float = clampf(d / maxf(0.01, arrive_r), 0.0, 1.0)
	return to / d * speed * k


func flee_from(src: Vector3, speed: float) -> Vector3:
	var away: Vector3 = global_position - src
	if not flies:
		away.y = 0.0
	else:
		away.y = absf(away.y) + 1.0
	if away.length_squared() < 0.001:
		away = Vector3(_rng.randf_range(-1, 1), 0.5 if flies else 0.0, _rng.randf_range(-1, 1))
	var dir: Vector3 = away.normalized()
	# Bias toward home so panicked creatures don't run off the map forever.
	var to_home: Vector3 = home - global_position
	to_home.y = 0.0
	if to_home.length() > home_radius * 1.4:
		dir = (dir + to_home.normalized() * 0.8).normalized()
	return dir * speed


func wander(speed: float, delta: float) -> Vector3:
	_wander_heading += _rng.randf_range(-2.4, 2.4) * delta
	var to_home: Vector3 = home - global_position
	to_home.y = 0.0
	var pull: float = clampf(to_home.length() / maxf(0.1, home_radius), 0.0, 1.0)
	var dir := Vector3(cos(_wander_heading), 0.0, sin(_wander_heading))
	if pull > 0.6:
		dir = dir.lerp(to_home.normalized(), (pull - 0.6) * 2.0).normalized()
		_wander_heading = atan2(dir.z, dir.x)
	var v: Vector3 = dir * speed
	if flies:
		if _rng.randf() < delta * 0.3:
			_wander_alt = _rng.randf_range(min_altitude + 0.3, minf(max_altitude, min_altitude + 3.0))
		v.y = clampf((_ground_y + _wander_alt - global_position.y) * 1.5, -speed, speed)
	return v


## Circles a point at `radius`, `dir` = +1/-1 and angular blend. Flyers circle at head height.
func orbit(center: Vector3, radius: float, dir: float, speed: float) -> Vector3:
	var rel: Vector3 = global_position - center
	rel.y = 0.0
	var d: float = rel.length()
	if d < 0.01:
		rel = Vector3(1, 0, 0)
		d = 1.0
	var radial: Vector3 = rel / d
	var tangent := Vector3(-radial.z, 0.0, radial.x) * signf(dir if dir != 0.0 else 1.0)
	var v: Vector3 = tangent * speed + radial * (radius - d) * 2.0
	if flies:
		v.y = clampf((center.y + 1.5 - global_position.y) * 2.0, -speed, speed)
	return v


## Boids: cohesion + alignment + separation + gentle home pull.
func flock(delta: float) -> Vector3:
	if _director == null:
		return wander(max_speed * 0.5, delta)
	var mates: Array[Node3D] = _mates_cache  # refreshed at think rate, not per frame
	if mates.is_empty():
		return wander(max_speed * 0.5, delta)
	var center := Vector3.ZERO
	var align := Vector3.ZERO
	var sep := Vector3.ZERO
	for m in mates:
		center += m.global_position
		var mv: Variant = m.get("velocity")
		if mv is Vector3:
			align += mv as Vector3
		var off: Vector3 = global_position - m.global_position
		var l: float = off.length()
		if l < 0.8 and l > 0.001:
			sep += off / l * (0.8 - l) * 4.0
	center /= float(mates.size())
	align /= float(mates.size())
	var v: Vector3 = (center - global_position) * 0.8 + align * 0.6 + sep
	v += wander(max_speed * 0.3, delta) * 0.6
	if not flies:
		v.y = 0.0
	return v.limit_length(max_speed * 0.75)


func _post_move(delta: float) -> void:
	_ground_timer -= delta
	if _ground_timer <= 0.0:
		_ground_timer = 0.15 + _rng.randf_range(0.0, 0.05)
		_probe_ground()
	if flies:
		var min_y: float = _ground_y + min_altitude
		if global_position.y < min_y:
			global_position.y = lerpf(global_position.y, min_y, clampf(6.0 * delta, 0.0, 1.0))
			velocity.y = maxf(velocity.y, 0.0)
		elif global_position.y > _ground_y + max_altitude:
			velocity.y = minf(velocity.y, -0.5)
	else:
		global_position.y = lerpf(global_position.y, _ground_y + ground_offset, clampf(18.0 * delta, 0.0, 1.0))


func _probe_ground() -> void:
	var w: World3D = get_world_3d()
	if w == null or w.direct_space_state == null:
		return
	var space: PhysicsDirectSpaceState3D = w.direct_space_state
	var from: Vector3 = global_position + Vector3.UP * (0.6 if not flies else 0.2)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (6.0 if not flies else 14.0), WORLD_MASK)
	var hit: Dictionary = space.intersect_ray(q)
	_has_ground = not hit.is_empty()
	if _has_ground:
		_ground_y = (hit["position"] as Vector3).y
	elif not flies:
		# Walked off a ledge / over a chasm: step back toward home.
		velocity = (home - global_position).normalized() * max_speed
		velocity.y = 0.0
	# Walkers: don't run face-first into walls.
	if not flies and velocity.length_squared() > 0.04:
		var ahead := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.15, global_position + Vector3.UP * 0.15 + velocity.normalized() * 0.5, WORLD_MASK)
		if not space.intersect_ray(ahead).is_empty():
			_wander_heading += PI * 0.6
			velocity = velocity.rotated(Vector3.UP, PI * 0.5) * 0.5


func _face_velocity(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var look: Vector3 = flat
	if behaviour == "curious" and is_instance_valid(focus) and flat.length() < 0.6:
		look = focus.global_position - global_position
		look.y = 0.0
	if look.length_squared() < 0.0004:
		return
	var target_yaw: float = atan2(-look.x, -look.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


# ------------------------------------------------------------------ play (poke & chase)

func can_play() -> bool:
	return is_present and _play_cooldown <= 0.0 and fear < 0.2 and behaviour in ["idle", "wander", "flock", "rest", "perch"]


func _start_play_as_poker(mate: Node3D) -> void:
	_play_partner = mate
	_play_role = "poker"
	_play_swaps = 0
	_play_until = FaunaDirector.now() + 7.0
	if mate.has_method("_join_play"):
		mate.call("_join_play", self)
	if behaviour != "play":
		set_behaviour("play")


## Partner is now "it" — it doesn't know yet; it just keeps doing its thing until poked.
func _join_play(by: Node3D) -> void:
	_play_partner = by
	_play_role = "target"
	_play_swaps = 0
	_play_until = FaunaDirector.now() + 7.0


func on_poked(by: Node3D) -> void:
	_play_partner = by
	_play_role = "chaser"
	_play_until = FaunaDirector.now() + _rng.randf_range(2.5, 4.0)
	_on_play_event("poked")
	if behaviour != "play":
		set_behaviour("play")
	played_with.emit(by, "chaser")


func _caught_by(by: Node3D) -> void:
	# Bicker: role swap. After a couple of swaps, both lose interest and drift back to the group.
	_play_swaps += 1
	_on_play_event("caught")
	if _play_swaps >= 2 + int(trait_value("mischief") * 2.0) or _rng.randf() < 0.25:
		_end_play(true)
		if by.has_method("_end_play"):
			by.call("_end_play", true)
		return
	_play_role = "chaser"
	_play_partner = by
	_play_until = FaunaDirector.now() + _rng.randf_range(2.0, 3.5)


func _act_play(_delta: float) -> Vector3:
	if not is_instance_valid(_play_partner) or FaunaDirector.now() > _play_until:
		_end_play(true)
		return Vector3.ZERO
	var p: Vector3 = _play_partner.global_position
	var d: float = p.distance_to(global_position)
	match _play_role:
		"poker", "chaser":
			if d < 0.4:
				_on_play_event("poke")
				if _play_partner.has_method("on_poked") and _play_role == "poker":
					_play_partner.call("on_poked", self)
				elif _play_partner.has_method("_caught_by"):
					_play_partner.call("_caught_by", self)
				_play_role = "runner"
				_play_until = FaunaDirector.now() + _rng.randf_range(2.5, 4.0)
				played_with.emit(_play_partner, "runner")
				return flee_from(p, max_speed * 1.3)
			# Sneak up from behind, then dash.
			var speed: float = max_speed * (0.55 if d > 2.5 and _play_role == "poker" else 1.25)
			var aim: Vector3 = p
			var pv: Variant = _play_partner.get("velocity")
			if pv is Vector3:
				aim += (pv as Vector3) * 0.3
			return steer_to(aim, speed, 0.1)
		"runner":
			# Zig-zag escape that loops around home so the chase stays on screen.
			var away: Vector3 = flee_from(p, max_speed * 1.15)
			var side := Vector3(-away.z, 0.0, away.x) * sin(behaviour_time * 5.0) * 0.6
			var v: Vector3 = away + side + (home - global_position) * 0.25
			if not flies:
				v.y = 0.0
			return v
	return Vector3.ZERO


func _end_play(cooldown: bool) -> void:
	_play_partner = null
	_play_role = ""
	if cooldown:
		_play_cooldown = _rng.randf_range(10.0, 22.0) * (1.4 - trait_value("mischief"))
	if behaviour == "play":
		behaviour = "flock" if group_id >= 0 else "wander"
		behaviour_time = 0.0
		_on_behaviour_entered(behaviour)
		behaviour_changed.emit(behaviour)


# ------------------------------------------------------------------ realm

func _on_realm_shifted(_new_realm: int) -> void:
	_refresh_presence()


func _refresh_presence() -> void:
	var present: bool = true
	if RealmManager.instance != null and realm_presence != RealmPresence.BOTH:
		var merged: bool = RealmManager.instance.is_merged
		var mirror: bool = RealmManager.instance.current_realm == RealmManager.Realm.MIRROR
		present = merged or (mirror if realm_presence == RealmPresence.MIRROR_ONLY else not mirror)
	is_present = present
	visible = present


func in_mirror() -> bool:
	return RealmManager.instance != null and RealmManager.instance.current_realm == RealmManager.Realm.MIRROR and not RealmManager.instance.is_merged
