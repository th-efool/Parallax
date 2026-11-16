class_name Scurrier
extends AmbientCreature
## Small ruin rodent. Moves in stop-and-go bursts with sniffing pauses. Groups travel as a
## follow-the-leader conga line (a different orchestration from the wisps' boids flock).
## Frightened, they bolt for the nearest `fauna_cover` marker (or away) and freeze; once calm they
## rear up on hind legs to peek before carrying on. Curious ones sniff around the player's or an
## enemy's feet; bold ones nibble post-fight scraps; mischievous ones nip a sibling and get chased.

const KitScript := preload("res://scripts/ambient/fauna_mesh_kit.gd")
const GameFeelScript := preload("res://scripts/core/game_feel.gd")

@export var fur_color: Color = Color(0.36, 0.3, 0.26)

var _head: Node3D = null
var _tail: Array[Node3D] = []
var _ears: Array[Node3D] = []
var _burst_t: float = 0.0
var _pausing: bool = false
var _sniff: float = 0.0
var _rear: float = 0.0
var _cover: Node3D = null
var _gait: float = 0.0
var _squeak_cd: float = 0.0


func _configure() -> void:
	species = "scurrier"
	flies = false
	max_speed = 3.4
	accel = 16.0
	turn_speed = 14.0
	ground_offset = 0.0
	lod_distance = 25.0


func _species_traits() -> Dictionary:
	return {"bold": 0.25, "curiosity": 0.5, "sociability": 0.6, "mischief": 0.45, "energy": 0.75}


func _build_body(root: Node3D) -> void:
	var fur: Color = fur_color.lerp(Color(0.55, 0.5, 0.45) if randf() < 0.3 else Color(0.2, 0.17, 0.15), randf() * 0.5)
	var m := KitScript.mat(fur)
	var pink := KitScript.mat(Color(0.85, 0.55, 0.55))
	var s: float = randf_range(1.2, 1.55)  # sized to read next to the chibi KayKit heroes
	root.scale = Vector3.ONE * s
	KitScript.part(root, KitScript.sphere(0.07, 8, 5), m, Vector3(0, 0.07, 0.01), Vector3(0.85, 0.75, 1.5), Vector3.ZERO, "Torso")
	_head = KitScript.pivot(root, Vector3(0, 0.085, -0.1), "Head")
	KitScript.part(_head, KitScript.cone(0.012, 0.045, 0.11, 6), m, Vector3(0, 0, -0.04), Vector3.ONE, Vector3(-PI * 0.5, 0, 0))
	KitScript.part(_head, KitScript.sphere(0.011, 6, 4), pink, Vector3(0, 0, -0.1))
	var eye := KitScript.mat(Color(0.02, 0.02, 0.02))
	KitScript.part(_head, KitScript.sphere(0.008, 5, 3), eye, Vector3(0.025, 0.018, -0.045))
	KitScript.part(_head, KitScript.sphere(0.008, 5, 3), eye, Vector3(-0.025, 0.018, -0.045))
	for x in [0.028, -0.028]:
		var ear: Node3D = KitScript.pivot(_head, Vector3(x, 0.035, -0.005), "Ear")
		KitScript.part(ear, KitScript.sphere(0.02, 6, 4), pink, Vector3(0, 0.012, 0), Vector3(1.0, 1.0, 0.35))
		_ears.append(ear)
	var parent: Node3D = KitScript.pivot(root, Vector3(0, 0.06, 0.1), "Tail0")
	_tail.append(parent)
	for i in range(4):
		KitScript.part(parent, KitScript.cone(0.006, 0.009, 0.07, 4), pink, Vector3(0, 0, 0.035), Vector3.ONE, Vector3(PI * 0.5, 0, 0))
		var nxt: Node3D = KitScript.pivot(parent, Vector3(0, 0, 0.07), "Tail%d" % (i + 1))
		_tail.append(nxt)
		parent = nxt


func _disturbance_sensitivity(kind: String) -> float:
	return 1.4 if kind in ["slam", "swing", "footsteps"] else 1.0


func _score_extra(s: Dictionary) -> void:
	_squeak_cd = maxf(0.0, _squeak_cd - 1.0 / think_hz)
	# Scared rodents hide rather than run in the open.
	if fear > 0.3:
		s["hide"] = fear * 1.35
		s.erase("flee")
	if behaviour == "hide":
		s["hide"] = maxf(float(s.get("hide", 0.0)), 0.75 if behaviour_time < 2.5 + (1.0 - trait_value("bold")) * 3.0 else 0.0)
	if behaviour == "peek":
		s["peek"] = 0.85 if behaviour_time < 1.6 else 0.0
	elif behaviour == "hide" and fear < 0.15 and behaviour_time > 2.0:
		s["peek"] = 0.9
	if group_id >= 0 and s.has("flock"):
		s["follow_leader"] = float(s["flock"]) + 0.05
		s.erase("flock")
	if _director != null and fear < 0.25 and trait_value("bold") > 0.3:
		var scraps: Dictionary = _director.nearest_interest(global_position, "scraps", 10.0)
		if not scraps.is_empty():
			s["scavenge"] = 0.45 + trait_value("bold") * 0.35
			if behaviour != "scavenge":
				focus_pos = scraps["pos"] as Vector3 + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))


func _on_behaviour_entered(b: String) -> void:
	match b:
		"hide":
			_cover = _find_cover()
			_squeak(true)
		"peek":
			_rear = 0.0


func _find_cover() -> Node3D:
	var best: Node3D = null
	var best_score: float = INF
	for c in get_tree().get_nodes_in_group("fauna_cover"):
		if not (c is Node3D):
			continue
		var cp: Vector3 = (c as Node3D).global_position
		var d: float = cp.distance_to(global_position)
		if d > 9.0:
			continue
		# Prefer cover that is away from the threat.
		var toward_threat: float = (cp - global_position).normalized().dot((fear_source - global_position).normalized())
		var score: float = d + toward_threat * 4.0
		if score < best_score:
			best_score = score
			best = c as Node3D
	return best


## Conga line: follow the flockmate directly ahead in the group order; the leader wanders.
func _leader_ahead() -> Node3D:
	if _director == null:
		return null
	var best: Node3D = null
	var best_id: int = -1
	var my_id: int = get_instance_id()
	for m in _director.flockmates(self, species, 10.0, group_id):
		var id: int = m.get_instance_id()
		if id < my_id and id > best_id and String(m.get("behaviour")) in ["follow_leader", "wander", "idle", "scavenge"]:
			best_id = id
			best = m
	return best


func _act_extra(b: String, delta: float) -> Variant:
	match b:
		"hide":
			if _cover != null and is_instance_valid(_cover):
				var d: float = _cover.global_position.distance_to(global_position)
				if d < 0.35:
					return Vector3.ZERO  # frozen, tucked in
				return steer_to(_cover.global_position, max_speed * 1.25, 0.3)
			if behaviour_time < 0.9:
				return flee_from(fear_source, max_speed * 1.25)
			return Vector3.ZERO  # froze in place
		"peek":
			return Vector3.ZERO
		"follow_leader":
			var lead: Node3D = _leader_ahead()
			if lead == null:
				return _burst(wander(max_speed * 0.7, delta), delta)
			var behind: Vector3 = lead.global_position
			var lv: Variant = lead.get("velocity")
			if lv is Vector3 and (lv as Vector3).length() > 0.1:
				behind -= (lv as Vector3).normalized() * 0.32
			if global_position.distance_to(behind) < 0.12:
				return Vector3.ZERO
			return steer_to(behind, max_speed * 1.1, 0.25)
		"wander":
			return _burst(wander(max_speed * 0.75, delta), delta)
		"scavenge":
			if Vector2(focus_pos.x - global_position.x, focus_pos.z - global_position.z).length() < 0.25:
				return Vector3.ZERO
			return _burst(steer_to(focus_pos, max_speed * 0.8, 0.3), delta)
		"curious":
			if not is_instance_valid(focus):
				return null
			# Sniff around the feet in short darts, never quite touching.
			var center: Vector3 = focus.global_position
			var r: float = 0.7 + (1.0 - trait_value("bold")) * 0.8
			return _burst(orbit(center, r, 1.0 if get_instance_id() % 2 == 0 else -1.0, max_speed * 0.5), delta)
	return null


## Stop-and-go: run bursts separated by sniffing pauses.
func _burst(v: Vector3, delta: float) -> Vector3:
	_burst_t -= delta
	if _burst_t <= 0.0:
		_pausing = not _pausing
		_burst_t = randf_range(0.25, 1.2) * (1.4 - trait_value("energy")) if _pausing else randf_range(0.3, 0.9)
	return Vector3.ZERO if _pausing else v


func _on_play_event(_kind: String) -> void:
	_squeak(true)


func _squeak(force: bool) -> void:
	if _squeak_cd > 0.0 and not force:
		return
	_squeak_cd = randf_range(2.0, 5.0)
	GameFeelScript.play_sound(self, "squeak", global_position, -18.0, randf_range(0.9, 1.3), 0.1)


func _animate(delta: float) -> void:
	var speed: float = Vector2(velocity.x, velocity.z).length()
	_gait += delta * (6.0 + speed * 9.0)
	var pausing: bool = speed < 0.15
	# Rear up on hind legs to peek / inspect.
	var rear_target: float = 0.0
	if behaviour == "peek" or (behaviour == "curious" and pausing):
		rear_target = 0.9
	_rear = lerpf(_rear, rear_target, clampf(8.0 * delta, 0.0, 1.0))
	if _body != null:
		_body.rotation.x = -_rear * 0.9
		_body.position.y = (absf(sin(_gait)) * 0.015 if not pausing else 0.0) + _rear * 0.04
		_body.rotation.z = sin(_gait * 0.5) * 0.06 * speed
	# Sniffing: fast little head twitches while paused.
	if _head != null:
		_sniff += delta * (22.0 if pausing else 6.0)
		_head.rotation = Vector3(0.12 * sin(_sniff) if pausing else 0.0, 0.25 * sin(_sniff * 0.31) if pausing else 0.0, 0.0)
	for i in range(_ears.size()):
		_ears[i].rotation.z = (0.4 if fear > 0.3 else 0.0) * (1.0 if i == 0 else -1.0)
	# Tail sways, whips when running, curls when frozen in hiding.
	for i in range(_tail.size()):
		var w: float = sin(_gait * 0.6 - i * 0.7) * (0.25 + speed * 0.08)
		if behaviour == "hide" and pausing:
			w = 0.45
		_tail[i].rotation.y = w
		_tail[i].rotation.x = 0.08 * i * (1.0 - _rear)
