class_name SquadCoordinator
extends Node
## Lightweight "co-op brain" shared by every EnemyAI (lazy singleton, no autoload needed).
##  - Attack tokens: only N enemies may commit to an attack at once; the rest hold a ring around the
##    player, circling and spacing themselves out instead of queueing in a line.
##  - Rhythm: a minimum gap between attack starts so pressure comes in alternating beats, not a pile-on.
##  - Pincer priority: enemies behind / beside the player win the next token, so they flank.
##  - Alerts: the first enemy to spot the player calls the others in.
##  - Threat reads: when the player winds up, nearby uncommitted enemies may side-step out of the arc.
##  - Last stand: when a squad is whittled down to one, the survivor becomes enraged.

const MAX_TOKEN_HOLD_SEC: float = 4.0

static var _instance: Node = null

var max_attackers: int = 2
var min_attack_gap: float = 0.42
var alert_radius: float = 14.0
var engage_radius: float = 11.0

var _members: Array[Node] = []
var _tokens: Dictionary = {}       # enemy instance_id -> grant time (sec)
var _waiting_since: Dictionary = {} # enemy instance_id -> first request time
var _last_attack_start: float = -10.0
var _peak_engaged: int = 0


static func get_for(context: Node) -> SquadCoordinator:
	if _instance != null and is_instance_valid(_instance):
		return _instance as SquadCoordinator
	if context == null or not context.is_inside_tree():
		return null
	var sc: SquadCoordinator = (load("res://scripts/enemies/squad_coordinator.gd") as GDScript).new() as SquadCoordinator
	sc.name = "SquadCoordinator"
	context.get_tree().root.add_child.call_deferred(sc)
	_instance = sc
	return sc


static func notify_player_attack(player: Node3D, is_heavy: bool, windup: float) -> void:
	if _instance == null or not is_instance_valid(_instance):
		return
	(_instance as SquadCoordinator)._on_player_attack(player, is_heavy, windup)


static func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func register(e: Node) -> void:
	if e != null and not _members.has(e):
		_members.append(e)


func unregister(e: Node) -> void:
	_members.erase(e)
	release_token(e)


func _prune() -> void:
	var i: int = _members.size() - 1
	while i >= 0:
		if not is_instance_valid(_members[i]):
			_members.remove_at(i)
		i -= 1
	var now: float = _now()
	for id in _tokens.keys():
		var obj: Object = instance_from_id(int(id))
		if obj == null or not is_instance_valid(obj) or now - float(_tokens[id]) > MAX_TOKEN_HOLD_SEC:
			_tokens.erase(id)
		elif obj is EnemyBase and ((obj as EnemyBase).is_dead or not (obj as EnemyBase).is_active):
			_tokens.erase(id)


## Enemies currently fighting (active, alive, chasing/attacking near the player).
func get_engaged(player: Node3D) -> Array[EnemyAI]:
	var out: Array[EnemyAI] = []
	for m in _members:
		var e: EnemyAI = m as EnemyAI
		if e == null or not is_instance_valid(e) or e.is_dead or not e.is_active or not e.is_inside_tree():
			continue
		if e.current_state == EnemyAI.State.IDLE:
			continue
		if player != null and e.global_position.distance_to(player.global_position) > engage_radius:
			continue
		out.append(e)
	return out


func has_token(e: Node) -> bool:
	return _tokens.has(e.get_instance_id())


func release_token(e: Node) -> void:
	if e == null:
		return
	_tokens.erase(e.get_instance_id())
	_waiting_since.erase(e.get_instance_id())


## Called every frame by an enemy that is in range and ready to swing. Returns true when it may commit.
func request_attack_token(e: EnemyAI, player: Node3D) -> bool:
	_prune()
	var id: int = e.get_instance_id()
	if _tokens.has(id):
		return true
	var now: float = _now()
	if not _waiting_since.has(id):
		_waiting_since[id] = now
	var engaged: Array[EnemyAI] = get_engaged(player)
	var cap: int = max_attackers if engaged.size() >= 3 else maxi(1, mini(max_attackers, engaged.size()))
	if _tokens.size() >= cap:
		return false
	if now - _last_attack_start < min_attack_gap and not _tokens.is_empty():
		return false
	# Fairness + flanking: highest priority waiter wins.
	var my_p: float = _priority(e, player, now)
	for other_id in _waiting_since.keys():
		if int(other_id) == id or _tokens.has(other_id):
			continue
		var o: Object = instance_from_id(int(other_id))
		if o == null or not is_instance_valid(o) or not (o is EnemyAI):
			_waiting_since.erase(other_id)
			continue
		var oe: EnemyAI = o as EnemyAI
		var stale: bool = now - float(_waiting_since[other_id]) > 2.5 and oe.current_state != EnemyAI.State.CHASE
		if oe.is_dead or not oe.is_active or stale:
			_waiting_since.erase(other_id)
			continue
		if _priority(oe, player, now) > my_p + 0.05:
			return false
	_tokens[id] = now
	_waiting_since.erase(id)
	_last_attack_start = now
	return true


func _priority(e: EnemyAI, player: Node3D, now: float) -> float:
	var wait: float = now - float(_waiting_since.get(e.get_instance_id(), now))
	var p: float = wait
	if player != null and player.has_method("get_facing_direction"):
		var pf: Vector3 = player.call("get_facing_direction")
		var to_e: Vector3 = e.global_position - player.global_position
		to_e.y = 0.0
		if to_e.length_squared() > 0.001:
			# Behind the player (dot < 0) scores up to +1.2 s of "virtual waiting".
			p += clampf(-pf.dot(to_e.normalized()), 0.0, 1.0) * 1.2
	return p


## Point on the holding ring for a non-attacking enemy: spaced from squad-mates, drifting to flank.
func get_ring_position(e: EnemyAI, player: Node3D, radius: float, orbit_sign: float) -> Vector3:
	var center: Vector3 = player.global_position
	var rel: Vector3 = e.global_position - center
	rel.y = 0.0
	if rel.length_squared() < 0.01:
		rel = Vector3(1.0, 0.0, 0.0)
	var my_ang: float = atan2(rel.z, rel.x)
	var push: float = 0.0
	var spacing: float = deg_to_rad(62.0)
	for m in get_engaged(player):
		if m == e:
			continue
		var r2: Vector3 = m.global_position - center
		r2.y = 0.0
		if r2.length_squared() < 0.01:
			continue
		var d: float = wrapf(my_ang - atan2(r2.z, r2.x), -PI, PI)
		if absf(d) < spacing:
			push += (spacing - absf(d)) * (1.0 if d >= 0.0 else -1.0) * 1.6
	# Drift toward the player's flank/back when standing in front of them.
	if player.has_method("get_facing_direction"):
		var pf: Vector3 = player.call("get_facing_direction")
		var front: float = pf.dot(rel.normalized())
		if front > 0.3:
			var side: float = signf(pf.cross(rel.normalized()).y)
			if side == 0.0:
				side = orbit_sign
			push += -side * 0.6 * front
	push += orbit_sign * 0.28
	# Look-ahead target on the ring; the enemy steers toward it every frame so it keeps circling.
	var ang: float = my_ang + clampf(push, -1.2, 1.2) * 0.5
	return center + Vector3(cos(ang), 0.0, sin(ang)) * radius


## Separation steering from nearby squad-mates (prevents clumping / overlapping).
func get_separation(e: EnemyAI, radius: float = 1.6) -> Vector3:
	var push := Vector3.ZERO
	for m in _members:
		var o: EnemyAI = m as EnemyAI
		if o == null or o == e or not is_instance_valid(o) or o.is_dead or not o.is_active:
			continue
		var d: Vector3 = e.global_position - o.global_position
		d.y = 0.0
		var l: float = d.length()
		if l < radius and l > 0.001:
			push += d / l * (radius - l) / radius
	return push


## The first enemy to see the player calls nearby idle squad-mates into the fight.
func alert(source: EnemyAI, player: Node3D) -> void:
	for m in _members:
		var e: EnemyAI = m as EnemyAI
		if e == null or e == source or not is_instance_valid(e) or e.is_dead or not e.is_active:
			continue
		if e.current_state != EnemyAI.State.IDLE:
			continue
		var same_encounter: bool = not source.encounter_id.is_empty() and e.encounter_id == source.encounter_id
		if same_encounter or e.global_position.distance_to(source.global_position) <= alert_radius:
			e.receive_alert(player, source)


func is_last_standing(e: EnemyAI, player: Node3D) -> bool:
	var engaged: Array[EnemyAI] = get_engaged(player)
	_peak_engaged = maxi(_peak_engaged, engaged.size())
	if engaged.is_empty():
		_peak_engaged = 0
	return _peak_engaged >= 2 and engaged.size() == 1 and engaged[0] == e


func _on_player_attack(player: Node3D, is_heavy: bool, windup: float) -> void:
	if player == null or not player.is_inside_tree():
		return
	var pf: Vector3 = Vector3.FORWARD
	if player.has_method("get_facing_direction"):
		pf = player.call("get_facing_direction")
	for m in _members:
		var e: EnemyAI = m as EnemyAI
		if e == null or not is_instance_valid(e) or e.is_dead or not e.is_active:
			continue
		var rel: Vector3 = e.global_position - player.global_position
		rel.y = 0.0
		var dist: float = rel.length()
		if dist > 3.4 or dist < 0.01:
			continue
		if pf.dot(rel / dist) < 0.35:
			continue
		e.consider_evade(player, is_heavy, windup)
