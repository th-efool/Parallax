class_name SquadCoordinator
extends Node
## Lightweight "co-op brain" shared by every EnemyAI (lazy singleton, no autoload needed).
##  - Per-target bookkeeping: which entity (player or a squad ally) each enemy is hunting.
##  - Soft target cap: at most `max_enemies_per_target` enemies should pile onto one entity; extra enemies
##    see a threat penalty for saturated targets and spread onto others (taunts ignore the cap).
##  - Attack tokens (per target): only N enemies may commit to an attack on the same entity at once; the rest
##    hold a ring around it, circling and spacing themselves out instead of queueing in a line.
##  - Rhythm: a minimum gap between attack starts on the same target so pressure comes in beats.
##  - Pincer priority: enemies behind / beside the target win the next token, so they flank.
##  - Alert propagation: the first enemy to spot a target calls squad-mates within `join_radius` (or in the
##    same encounter) straight into the fight; those within `alert_radius` come to investigate (ALERT).
##  - Threat reads: when the player winds up, nearby uncommitted enemies may side-step out of the arc.
##  - Last stand: when a squad is whittled down to one, the survivor becomes enraged.

const MAX_TOKEN_HOLD_SEC: float = 4.0

static var _instance: Node = null

var max_attackers: int = 2
var max_enemies_per_target: int = 3
var min_attack_gap: float = 0.42
var join_radius: float = 9.0
var alert_radius: float = 18.0
var engage_radius: float = 11.0

var _members: Array[Node] = []
var _tokens: Dictionary = {}        # enemy instance_id -> grant time (sec)
var _token_target: Dictionary = {}  # enemy instance_id -> target instance_id
var _waiting_since: Dictionary = {} # enemy instance_id -> first request time
var _enemy_target: Dictionary = {}  # enemy instance_id -> target instance_id
var _last_attack_start: Dictionary = {} # target instance_id -> sec
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


static func get_instance() -> SquadCoordinator:
	if _instance != null and is_instance_valid(_instance):
		return _instance as SquadCoordinator
	return null


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
	if e != null:
		_enemy_target.erase(e.get_instance_id())


func get_members() -> Array[Node]:
	return _members


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
			_token_target.erase(id)
		elif obj is EnemyBase and ((obj as EnemyBase).is_dead or not (obj as EnemyBase).is_active):
			_tokens.erase(id)
			_token_target.erase(id)


# ------------------------------------------------------------------ per-target bookkeeping

func set_enemy_target(e: Node, target: Node) -> void:
	if e == null:
		return
	if target == null:
		_enemy_target.erase(e.get_instance_id())
	else:
		_enemy_target[e.get_instance_id()] = target.get_instance_id()


## Live enemies currently hunting `target` (optionally excluding one).
func count_targeting(target: Node, exclude: Node = null) -> int:
	if target == null:
		return 0
	var tid: int = target.get_instance_id()
	var n: int = 0
	for m in _members:
		if m == exclude or not is_instance_valid(m):
			continue
		var e: EnemyAI = m as EnemyAI
		if e == null or e.is_dead or not e.is_active:
			continue
		if int(_enemy_target.get(e.get_instance_id(), 0)) == tid and e.is_aggroed():
			n += 1
	return n


func is_target_saturated(target: Node, asker: Node) -> bool:
	return count_targeting(target, asker) >= max_enemies_per_target


## Enemies currently fighting `target` (active, alive, aggroed on it and nearby).
func get_engaged(target: Node3D) -> Array[EnemyAI]:
	var out: Array[EnemyAI] = []
	var tid: int = target.get_instance_id() if target != null else 0
	for m in _members:
		var e: EnemyAI = m as EnemyAI
		if e == null or not is_instance_valid(e) or e.is_dead or not e.is_active or not e.is_inside_tree():
			continue
		if not e.is_aggroed():
			continue
		if target != null:
			if int(_enemy_target.get(e.get_instance_id(), 0)) != tid:
				continue
			if e.global_position.distance_to(target.global_position) > engage_radius:
				continue
		out.append(e)
	return out


## Every aggroed enemy (any target) — used by allies and the squad HUD.
func get_aggroed_enemies() -> Array[EnemyAI]:
	return get_engaged(null)


func has_token(e: Node) -> bool:
	return _tokens.has(e.get_instance_id())


func release_token(e: Node) -> void:
	if e == null:
		return
	_tokens.erase(e.get_instance_id())
	_token_target.erase(e.get_instance_id())
	_waiting_since.erase(e.get_instance_id())


func _tokens_on(target_id: int) -> int:
	var n: int = 0
	for id in _tokens.keys():
		if int(_token_target.get(id, 0)) == target_id:
			n += 1
	return n


## Called every frame by an enemy that is in range and ready to swing. Returns true when it may commit.
func request_attack_token(e: EnemyAI, target: Node3D) -> bool:
	_prune()
	var id: int = e.get_instance_id()
	if _tokens.has(id):
		return true
	if target == null:
		return false
	var tid: int = target.get_instance_id()
	var now: float = _now()
	if not _waiting_since.has(id):
		_waiting_since[id] = now
	# Taunted enemies are locked on and never wait for a token.
	if e.is_taunted():
		_grant(id, tid, now)
		return true
	var engaged: Array[EnemyAI] = get_engaged(target)
	var cap: int = max_attackers if engaged.size() >= 3 else maxi(1, mini(max_attackers, engaged.size()))
	var on_target: int = _tokens_on(tid)
	if on_target >= cap:
		return false
	if now - float(_last_attack_start.get(tid, -10.0)) < min_attack_gap and on_target > 0:
		return false
	# Fairness + flanking: highest priority waiter on the same target wins.
	var my_p: float = _priority(e, target, now)
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
		if int(_enemy_target.get(int(other_id), 0)) != tid:
			continue
		if _priority(oe, target, now) > my_p + 0.05:
			return false
	_grant(id, tid, now)
	return true


func _grant(id: int, tid: int, now: float) -> void:
	_tokens[id] = now
	_token_target[id] = tid
	_waiting_since.erase(id)
	_last_attack_start[tid] = now


func _priority(e: EnemyAI, target: Node3D, now: float) -> float:
	var wait: float = now - float(_waiting_since.get(e.get_instance_id(), now))
	var p: float = wait
	if target != null and target.has_method("get_facing_direction"):
		var pf: Vector3 = target.call("get_facing_direction")
		var to_e: Vector3 = e.global_position - target.global_position
		to_e.y = 0.0
		if to_e.length_squared() > 0.001:
			# Behind the target (dot < 0) scores up to +1.2 s of "virtual waiting".
			p += clampf(-pf.dot(to_e.normalized()), 0.0, 1.0) * 1.2
	return p


## Point on the holding ring for a non-attacking enemy: spaced from squad-mates, drifting to flank.
func get_ring_position(e: EnemyAI, target: Node3D, radius: float, orbit_sign: float) -> Vector3:
	var center: Vector3 = target.global_position
	var rel: Vector3 = e.global_position - center
	rel.y = 0.0
	if rel.length_squared() < 0.01:
		rel = Vector3(1.0, 0.0, 0.0)
	var my_ang: float = atan2(rel.z, rel.x)
	var push: float = 0.0
	var spacing: float = deg_to_rad(62.0)
	for m in get_engaged(target):
		if m == e:
			continue
		var r2: Vector3 = m.global_position - center
		r2.y = 0.0
		if r2.length_squared() < 0.01:
			continue
		var d: float = wrapf(my_ang - atan2(r2.z, r2.x), -PI, PI)
		if absf(d) < spacing:
			push += (spacing - absf(d)) * (1.0 if d >= 0.0 else -1.0) * 1.6
	# Drift toward the target's flank/back when standing in front of it.
	if target.has_method("get_facing_direction"):
		var pf: Vector3 = target.call("get_facing_direction")
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


## The first enemy to see a target calls nearby squad-mates in (join) or over to investigate (alert).
func alert(source: EnemyAI, target: Node3D) -> void:
	for m in _members:
		var e: EnemyAI = m as EnemyAI
		if e == null or e == source or not is_instance_valid(e) or e.is_dead or not e.is_active:
			continue
		if e.current_state != EnemyAI.State.IDLE and e.current_state != EnemyAI.State.ALERT:
			continue
		var same_encounter: bool = not source.encounter_id.is_empty() and e.encounter_id == source.encounter_id
		var d: float = e.global_position.distance_to(source.global_position)
		if same_encounter or d <= join_radius:
			e.receive_alert(target, source, true)
		elif d <= alert_radius:
			e.receive_alert(target, source, false)


## A loud event (ally war-cry, detonation) makes idle enemies within `radius` investigate.
func broadcast_noise(at: Vector3, radius: float) -> void:
	for m in _members:
		var e: EnemyAI = m as EnemyAI
		if e == null or not is_instance_valid(e) or e.is_dead or not e.is_active:
			continue
		if e.global_position.distance_to(at) <= radius:
			e.hear_noise(at)


func is_last_standing(e: EnemyAI, target: Node3D) -> bool:
	var engaged: Array[EnemyAI] = get_engaged(null)
	_peak_engaged = maxi(_peak_engaged, engaged.size())
	if engaged.is_empty():
		_peak_engaged = 0
	return _peak_engaged >= 2 and engaged.size() == 1 and engaged[0] == e and target != null


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
