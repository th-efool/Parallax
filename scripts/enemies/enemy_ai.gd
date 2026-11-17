class_name EnemyAI
extends EnemyBase
## Finite State Machine shared by every standard enemy and extended by The Warden.
##   IDLE (patrol) -> CHASE (engage) -> WINDUP -> ATTACK -> RECOVER, plus STAGGER, DEAD and the aggro states
##   ALERT (investigate a noise / squad call), STUNNED (knocked down), FLEEING (low-HP break) and RETURNING
##   (leashed back home after exceeding `max_chase_distance`). TAUNTED is a *modifier* (a target lock timer),
##   not a state.
##
## Threat table: every enemy keeps `instance_id -> threat` for each entity that hurt it, taunted it or stood
## close to it (the player and every `squad_ally`). Threat decays exponentially; proximity adds a trickle;
## damage adds damage x multiplier (backstabs multiply further). The current target is the highest-threat
## valid entity (with hysteresis), unless a taunt lock pins it. `SquadCoordinator` soft-caps how many enemies
## may pile onto one entity and hands out attack tokens per target.

const SquadCoordinatorScript := preload("res://scripts/enemies/squad_coordinator.gd")

enum State {
	IDLE = 0,
	CHASE = 1,
	WINDUP = 2,
	ATTACK = 3,
	RECOVER = 4,
	STAGGER = 5,
	DEAD = 6,
	ALERT = 7,
	STUNNED = 8,
	FLEEING = 9,
	RETURNING = 10,
}

## Damage sources that knock an enemy down (-> STUNNED) instead of a plain stagger.
const KNOCKDOWN_SOURCES: Array[String] = ["player_landing", "fin_sunder", "ally_charge", "ally_nuke", "ally_detonate"]

signal state_changed(new_state: int)
signal attack_telegraphed(attack_name: String, windup_sec: float)
signal attack_started(attack_name: String, damage: int)
signal recovery_started(recover_sec: float)
signal alerted(by: Node)
signal evaded(direction: Vector3)
signal target_changed(new_target: Node)
signal taunted(by: Node, lock_sec: float)
signal backstabbed(by: Node)
signal knocked_down(duration: float)
signal fleeing_started()
signal returning_home()

@export_group("AI & Combat Tuning")
@export var detection_range: float = 9.0
@export var attack_range: float = 1.85
@export var move_speed: float = 3.2
@export var windup_duration: float = 0.55
@export var attack_active_duration: float = 0.22
@export var recover_duration: float = 0.80
@export var stagger_duration: float = 0.65
@export var attack_damage: int = 15
@export var attack_name: String = "melee_slash"

@export_group("Telegraph Feedback")
@export var telegraph_color: Color = Color(1.0, 0.12, 0.06, 1.0)
@export var telegraph_overlay_peak_alpha: float = 0.42
@export var telegraph_light_height: float = 1.55
@export var telegraph_light_energy: float = 2.4

@export_group("Squad Tactics")
@export var use_squad_tactics: bool = true
@export var ring_margin: float = 1.7
@export var evade_skill: float = 0.45
@export var flinch_duration: float = 0.26
@export var max_flinch_chain: int = 2
@export var poise_duration: float = 1.6
@export var counter_attack_chance: float = 0.7
@export var attack_lunge_speed: float = 3.2

@export_group("Threat & Aggro")
## Fraction of threat lost per second (exponential decay).
@export var threat_decay_per_sec: float = 0.10
@export var proximity_threat_radius: float = 4.5
@export var proximity_threat_per_sec: float = 7.0
@export var damage_threat_mult: float = 1.0
@export var backstab_threat_mult: float = 1.8
@export var backstab_damage_mult: float = 1.25
@export var backstab_stagger: float = 0.55
@export var backstab_staggers: bool = true
@export var taunt_threat_bonus: float = 60.0
@export var default_taunt_lock: float = 3.0
@export var retarget_interval: float = 0.3
## A challenger must beat the current target's threat by this factor to steal aggro.
@export var retarget_hysteresis: float = 1.15
## Distance from home (spawn) after which the enemy gives up and walks back to its patrol.
@export var max_chase_distance: float = 22.0
@export var alert_investigate_duration: float = 4.0
@export var knockdown_immune: bool = false
@export var stun_duration: float = 1.6
@export var stunned_damage_mult: float = 1.35
## Health ratio below which the enemy breaks and flees once per life (0 disables).
@export var flee_health_ratio: float = 0.0
@export var flee_duration: float = 3.0
@export var patrol_radius: float = 0.0
@export var show_state_icon: bool = true

var current_state: State = State.IDLE
var _state_timer: float = 0.0
var _state_duration: float = 0.0
var _state_elapsed: float = 0.0
## Current target (player or a squad ally). Name kept for compatibility with subclasses/tests.
var target_player: Node3D = null

var _squad: SquadCoordinator = null
var _orbit_sign: float = 1.0
var _orbit_flip_timer: float = 0.0
var _ring_jitter: float = 0.0
var _taunt_timer: float = 0.0
var _evade_timer: float = 0.0
var _evade_cooldown: float = 0.0
var _evade_dir: Vector3 = Vector3.ZERO
var _evade_clip: String = "Dodge_Backward"
var _flinch_chain: int = 0
var _flinch_chain_timer: float = 0.0
var _poise_timer: float = 0.0
var _knockback: Vector3 = Vector3.ZERO
var _lean: Vector2 = Vector2.ZERO
var _lean_v: Vector2 = Vector2.ZERO
var _model_base_scale: Vector3 = Vector3.ZERO
var _enraged: bool = false
var _rng := RandomNumberGenerator.new()
var _telegraph_mat: StandardMaterial3D = null
var _telegraph_light: OmniLight3D = null
var _telegraph_tween: Tween = null
var _telegraph_meshes: Array[MeshInstance3D] = []

# Threat / aggro bookkeeping.
var _threat: Dictionary = {}          # target instance_id -> float
var _taunt_lock_id: int = 0
var _taunt_lock_timer: float = 0.0
var _retarget_timer: float = 0.0
var _home: Vector3 = Vector3.ZERO
var _alert_pos: Vector3 = Vector3.ZERO
var _reaggro_block: float = 0.0
var _has_fled: bool = false
var _turn_to_id: int = 0
var _patrol_goal: Vector3 = Vector3.ZERO
var _patrol_timer: float = 0.0
var _state_icon: Label3D = null


func _ready() -> void:
	super._ready()
	_rng.randomize()
	_home = global_position
	_patrol_goal = _home
	_orbit_sign = 1.0 if _rng.randf() < 0.5 else -1.0
	_ring_jitter = _rng.randf_range(-0.35, 0.35)
	_orbit_flip_timer = _rng.randf_range(1.8, 3.5)
	if use_squad_tactics:
		_squad = SquadCoordinatorScript.get_for(self)
		if _squad != null:
			_squad.register(self)


func _exit_tree() -> void:
	if _squad != null and is_instance_valid(_squad):
		_squad.unregister(self)


func _physics_process(delta: float) -> void:
	if not is_active or is_dead:
		return
	_tick_timers(delta)
	_update_threat(delta)
	step_ai(delta)
	_apply_knockback(delta)


func _process(delta: float) -> void:
	_update_hit_lean(delta)
	_update_state_icon()


func step_ai(delta: float) -> void:
	if is_dead:
		if current_state != State.DEAD:
			_transition_to(State.DEAD, 0.0)
		return

	_state_elapsed += delta
	var target: Node3D = _resolve_target_player()
	match current_state:
		State.IDLE:
			_process_idle(delta, target)
		State.CHASE:
			_process_chase(delta, target)
		State.WINDUP:
			_process_windup(delta, target)
		State.ATTACK:
			_process_attack(delta, target)
		State.RECOVER:
			_process_recover(delta, target)
		State.STAGGER:
			_process_stagger(delta)
		State.ALERT:
			_process_alert(delta)
		State.STUNNED:
			_process_stunned(delta)
		State.FLEEING:
			_process_fleeing(delta, target)
		State.RETURNING:
			_process_returning(delta)


func _tick_timers(delta: float) -> void:
	_taunt_timer = maxf(0.0, _taunt_timer - delta)
	_evade_cooldown = maxf(0.0, _evade_cooldown - delta)
	_poise_timer = maxf(0.0, _poise_timer - delta)
	_reaggro_block = maxf(0.0, _reaggro_block - delta)
	if _taunt_lock_timer > 0.0:
		_taunt_lock_timer -= delta
		if _taunt_lock_timer <= 0.0:
			_taunt_lock_id = 0
	if _flinch_chain_timer > 0.0:
		_flinch_chain_timer -= delta
		if _flinch_chain_timer <= 0.0:
			_flinch_chain = 0
	_orbit_flip_timer -= delta
	if _orbit_flip_timer <= 0.0:
		_orbit_flip_timer = _rng.randf_range(2.0, 4.5)
		if _rng.randf() < 0.45:
			_orbit_sign = -_orbit_sign


# ------------------------------------------------------------------ public queries (animation bridge, HUD, allies)

func get_state_elapsed() -> float:
	return _state_elapsed


func get_state_duration() -> float:
	return _state_duration


func is_taunting() -> bool:
	return _taunt_timer > 0.0


func is_evading() -> bool:
	return _evade_timer > 0.0


func get_evade_clip() -> String:
	return _evade_clip


func is_enraged() -> bool:
	return _enraged


## TAUNTED modifier: a taunt lock is pinning this enemy's target.
func is_taunted() -> bool:
	return _taunt_lock_timer > 0.0 and _taunt_lock_id != 0


func is_stunned() -> bool:
	return current_state == State.STUNNED


func is_aggroed() -> bool:
	return current_state != State.IDLE and current_state != State.ALERT and current_state != State.RETURNING and current_state != State.DEAD


func get_current_target() -> Node3D:
	if is_instance_valid(target_player) and _is_valid_target(target_player):
		return target_player
	return null


func get_home_position() -> Vector3:
	return _home


func get_threat(source: Node) -> float:
	if source == null:
		return 0.0
	return float(_threat.get(source.get_instance_id(), 0.0))


## Readable copy of the threat table: [{ "node": Node, "name": String, "threat": float }] sorted desc.
func get_threat_table() -> Array:
	var out: Array = []
	for id in _threat.keys():
		var o: Object = instance_from_id(int(id))
		if o == null or not is_instance_valid(o):
			continue
		out.append({"node": o, "name": _display_name(o as Node), "threat": float(_threat[id])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["threat"]) > float(b["threat"]))
	return out


func add_threat(source: Node, amount: float) -> void:
	if source == null or not (source is Node3D) or amount == 0.0 or is_dead:
		return
	if not _is_valid_target(source as Node3D):
		return
	var id: int = source.get_instance_id()
	_threat[id] = maxf(0.0, float(_threat.get(id, 0.0)) + amount)


## Taunt: flat threat bonus plus a target lock. Pulls an idle/alert/returning enemy straight into the fight.
func apply_taunt(source: Node3D, bonus: float = -1.0, lock_sec: float = -1.0) -> void:
	if is_dead or not is_active or source == null or not _is_valid_target(source):
		return
	var b: float = taunt_threat_bonus if bonus < 0.0 else bonus
	var lock: float = default_taunt_lock if lock_sec < 0.0 else lock_sec
	add_threat(source, b)
	_taunt_lock_id = source.get_instance_id()
	_taunt_lock_timer = lock
	_reaggro_block = 0.0
	_set_target(source)
	if current_state == State.IDLE or current_state == State.ALERT or current_state == State.RETURNING:
		_transition_to(State.CHASE, 0.0)
	taunted.emit(source, lock)


## Knockdown (charges, landing slams, detonations). Leaves the enemy STUNNED and taking bonus damage.
func knock_down(duration: float = -1.0, source: Node = null) -> void:
	if is_dead or not is_active or knockdown_immune:
		return
	if source != null:
		add_threat(source, 8.0)
	enter_stunned(duration)


# ------------------------------------------------------------------ actions

func start_windup(custom_windup: float = -1.0) -> void:
	if is_dead or not is_active:
		return
	var p: Node3D = _resolve_target_player()
	if p != null:
		set_facing_direction(p.global_position - global_position)
	var dur: float = windup_duration if custom_windup < 0.0 else custom_windup
	if _enraged:
		dur *= 0.8
	velocity = Vector3.ZERO
	_transition_to(State.WINDUP, dur)
	_begin_telegraph_flash(dur)
	attack_telegraphed.emit(attack_name, dur)


func enter_stagger(custom_duration: float = -1.0) -> void:
	if is_dead:
		return
	_clear_telegraph_flash()
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.end_swing()
	_release_token()
	var dur: float = stagger_duration if custom_duration < 0.0 else custom_duration
	velocity = Vector3.ZERO
	_transition_to(State.STAGGER, dur)
	staggered.emit(dur)


func enter_stunned(custom_duration: float = -1.0) -> void:
	if is_dead or knockdown_immune:
		return
	_clear_telegraph_flash()
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.end_swing()
	_release_token()
	var dur: float = stun_duration if custom_duration < 0.0 else custom_duration
	velocity = Vector3.ZERO
	_transition_to(State.STUNNED, dur)
	knocked_down.emit(dur)
	staggered.emit(dur)


## Squad call from an ally that spotted a target. Close squad-mates join the fight; farther ones investigate.
func receive_alert(target: Node3D, by: Node, join_fight: bool = true) -> void:
	if is_dead or not is_active:
		return
	if current_state != State.IDLE and current_state != State.ALERT:
		return
	if join_fight and target != null and _is_valid_target(target):
		add_threat(target, 12.0)
		_set_target(target)
		_taunt_timer = _rng.randf_range(0.0, 0.25)
		_transition_to(State.CHASE, 0.0)
	else:
		_alert_pos = (by as Node3D).global_position if by is Node3D else (target.global_position if target != null else global_position)
		_transition_to(State.ALERT, alert_investigate_duration)
	alerted.emit(by)


## A noise (combat, an ally's taunt shout) heard from afar: investigate it.
func hear_noise(at: Vector3) -> void:
	if is_dead or not is_active or current_state != State.IDLE:
		return
	_alert_pos = at
	_transition_to(State.ALERT, alert_investigate_duration)


## Player is winding up a swing that covers us: maybe side-step out of it.
func consider_evade(player: Node3D, is_heavy: bool, windup: float) -> void:
	if is_dead or not is_active or _evade_cooldown > 0.0 or evade_skill <= 0.0:
		return
	if current_state != State.CHASE and current_state != State.RECOVER and current_state != State.IDLE:
		return
	if _squad != null and _squad.has_token(self) and current_state == State.CHASE:
		return
	var chance: float = evade_skill * (1.0 if is_heavy else 0.45)
	if windup < 0.12:
		chance *= 0.6
	if _rng.randf() > chance:
		_evade_cooldown = 0.8
		return
	var away: Vector3 = global_position - player.global_position
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.001 else -get_facing_direction()
	var side: Vector3 = Vector3(-away.z, 0.0, away.x) * (1.0 if _rng.randf() < 0.5 else -1.0)
	_evade_dir = (away * 0.55 + side * 0.85).normalized()
	_evade_timer = 0.32
	_evade_cooldown = _rng.randf_range(2.2, 3.4)
	set_facing_direction(player.global_position - global_position)
	var f: Vector3 = get_facing_direction()
	var r: Vector3 = Vector3(-f.z, 0.0, f.x)
	if absf(_evade_dir.dot(r)) > absf(_evade_dir.dot(f)):
		_evade_clip = "Dodge_Right" if _evade_dir.dot(r) > 0.0 else "Dodge_Left"
	else:
		_evade_clip = "Dodge_Backward"
	if current_state != State.CHASE:
		_transition_to(State.CHASE, 0.0)
	evaded.emit(_evade_dir)


# ------------------------------------------------------------------ damage hooks (threat, backstab, stun)

func apply_damage(amount: int, is_heavy: bool = false, source_type: String = "", attacker: Node = null) -> bool:
	if is_dead or not is_active or amount <= 0:
		return false
	var backstab: bool = _is_backstab(attacker, source_type)
	var amt: float = float(amount)
	if current_state == State.STUNNED and source_type != "environmental":
		amt *= stunned_damage_mult
	if backstab:
		amt *= backstab_damage_mult
	var was_idle: bool = not is_aggroed()
	var ok: bool = super.apply_damage(int(round(amt)), is_heavy, source_type, attacker)
	if not ok or is_dead:
		return ok
	if attacker is Node3D:
		add_threat(attacker, amt * damage_threat_mult * (backstab_threat_mult if backstab else 1.0))
	if source_type in KNOCKDOWN_SOURCES and not knockdown_immune:
		enter_stunned()
	elif backstab:
		_on_backstabbed(attacker)
	if _should_flee():
		_start_flee()
	elif was_idle and attacker is Node3D and _is_valid_target(attacker as Node3D) and current_state != State.STUNNED and current_state != State.STAGGER:
		_set_target(attacker as Node3D)
		_reaggro_block = 0.0
		_transition_to(State.CHASE, 0.0)
		if _squad != null:
			_squad.alert(self, attacker as Node3D)
	return ok


func _is_backstab(attacker: Node, source_type: String) -> bool:
	if attacker == null or not (attacker is Node3D) or source_type == "environmental":
		return false
	if current_state == State.STUNNED or current_state == State.DEAD:
		return false
	var to_a: Vector3 = (attacker as Node3D).global_position - global_position
	to_a.y = 0.0
	if to_a.length_squared() < 0.0001:
		return false
	return get_facing_direction().dot(to_a.normalized()) < -0.35


func _on_backstabbed(attacker: Node) -> void:
	backstabbed.emit(attacker)
	_turn_to_id = attacker.get_instance_id() if attacker != null else 0
	if backstab_staggers and current_state != State.ATTACK:
		enter_stagger(backstab_stagger)
	elif attacker is Node3D:
		set_facing_direction((attacker as Node3D).global_position - global_position)


# ------------------------------------------------------------------ threat table

func _update_threat(delta: float) -> void:
	var decay: float = exp(-threat_decay_per_sec * delta)
	for id in _threat.keys():
		var o: Object = instance_from_id(int(id))
		if o == null or not is_instance_valid(o) or not _is_valid_target(o as Node3D):
			_threat.erase(id)
			continue
		var v: float = float(_threat[id]) * decay
		if v < 0.25 and int(id) != _taunt_lock_id:
			_threat.erase(id)
		else:
			_threat[id] = v
	if not is_aggroed():
		return
	# Proximity trickle: whoever stands close draws attention.
	for c in _gather_candidates():
		var d: float = global_position.distance_to(c.global_position)
		if d < proximity_threat_radius:
			add_threat(c, (1.0 - d / proximity_threat_radius) * proximity_threat_per_sec * delta)
	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = retarget_interval
		_select_target()


func _select_target() -> void:
	if is_taunted():
		var lock_o: Object = instance_from_id(_taunt_lock_id)
		if lock_o != null and is_instance_valid(lock_o) and _is_valid_target(lock_o as Node3D):
			_set_target(lock_o as Node3D)
			return
		_taunt_lock_id = 0
		_taunt_lock_timer = 0.0
	var cur: Node3D = get_current_target()
	var cur_score: float = _target_score(cur) if cur != null else -1.0
	var best: Node3D = cur
	var best_score: float = cur_score
	for id in _threat.keys():
		var o: Object = instance_from_id(int(id))
		if o == null or not is_instance_valid(o) or o == cur:
			continue
		var n: Node3D = o as Node3D
		if not _is_valid_target(n):
			continue
		var s: float = _target_score(n)
		if s > maxf(best_score, cur_score * retarget_hysteresis) + 0.01:
			best = n
			best_score = s
	if best != null:
		_set_target(best)


## Threat x soft-cap penalty: an entity already swarmed by enough enemies is less attractive.
func _target_score(n: Node3D) -> float:
	if n == null:
		return -1.0
	var s: float = float(_threat.get(n.get_instance_id(), 0.0))
	if _squad != null and _squad.is_target_saturated(n, self):
		s *= 0.45
	return s


func _set_target(n: Node3D) -> void:
	if n == target_player:
		return
	target_player = n
	if _squad != null:
		_squad.set_enemy_target(self, n)
		_squad.release_token(self)
	target_changed.emit(n)


func _clear_threat() -> void:
	_threat.clear()
	_taunt_lock_id = 0
	_taunt_lock_timer = 0.0
	target_player = null
	if _squad != null:
		_squad.set_enemy_target(self, null)


func _gather_candidates() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if not is_inside_tree():
		return out
	var p: Node = get_tree().get_first_node_in_group("player")
	if p is Node3D and _is_valid_target(p as Node3D):
		out.append(p as Node3D)
	for a in get_tree().get_nodes_in_group("squad_ally"):
		if a is Node3D and _is_valid_target(a as Node3D):
			out.append(a as Node3D)
	return out


func _is_valid_target(n: Node3D) -> bool:
	if n == null or not is_instance_valid(n) or not n.is_inside_tree():
		return false
	if n is PlayerController:
		return (n as PlayerController).current_state != PlayerController.State.DEAD
	if n.has_method("is_targetable"):
		return bool(n.call("is_targetable"))
	return false


func _nearest_visible_candidate(range_m: float) -> Node3D:
	var best: Node3D = null
	var best_d: float = range_m
	for c in _gather_candidates():
		var d: float = global_position.distance_to(c.global_position)
		if d <= best_d and absf(c.global_position.y - global_position.y) < 4.0:
			best = c
			best_d = d
	return best


func _display_name(n: Node) -> String:
	if n == null:
		return "?"
	if n.has_method("get_display_name"):
		return String(n.call("get_display_name"))
	if n is PlayerController:
		return "Player"
	return String(n.name)


# ------------------------------------------------------------------ states

func _process_idle(delta: float, _target: Node3D) -> void:
	if _reaggro_block <= 0.0:
		var seen: Node3D = _nearest_visible_candidate(detection_range)
		if seen != null:
			_aggro_on(seen, true)
			return
	_patrol(delta)


func _aggro_on(seen: Node3D, roar: bool) -> void:
	add_threat(seen, 10.0)
	_set_target(seen)
	# First to spot the target roars and calls the squad in.
	_taunt_timer = 0.55 if roar and _squad != null and _squad.get_engaged(seen).is_empty() else 0.0
	_transition_to(State.CHASE, 0.0)
	if _squad != null:
		_squad.alert(self, seen)
	alerted.emit(self)


func _patrol(delta: float) -> void:
	if patrol_radius <= 0.05:
		velocity = Vector3.ZERO
		return
	_patrol_timer -= delta
	var to_goal: Vector3 = _patrol_goal - global_position
	to_goal.y = 0.0
	if _patrol_timer <= 0.0 or to_goal.length() < 0.35:
		if _patrol_timer <= 0.0:
			_patrol_timer = _rng.randf_range(3.0, 6.0)
			var ang: float = _rng.randf() * TAU
			_patrol_goal = _home + Vector3(cos(ang), 0.0, sin(ang)) * _rng.randf_range(0.5, patrol_radius)
		velocity = Vector3.ZERO
		return
	_steer_toward(to_goal.normalized() * move_speed * 0.42, delta, true)


func _process_alert(delta: float) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	var seen: Node3D = _nearest_visible_candidate(detection_range * 1.25)
	if seen != null:
		_aggro_on(seen, false)
		return
	var to_p: Vector3 = _alert_pos - global_position
	to_p.y = 0.0
	if to_p.length() > 1.2 and global_position.distance_to(_home) < max_chase_distance:
		_steer_toward(to_p.normalized() * move_speed * 0.75, delta, true)
		set_facing_direction(to_p)
	else:
		velocity = Vector3.ZERO
		# Look around.
		set_facing_direction(get_facing_direction().rotated(Vector3.UP, sin(_state_elapsed * 2.2) * 2.4 * delta))
	if _state_timer <= 0.0:
		if global_position.distance_to(_home) > 1.5:
			_begin_return()
		else:
			_transition_to(State.IDLE, 0.0)


func _process_chase(delta: float, target: Node3D) -> void:
	if target == null:
		_lose_target()
		return

	var to_p: Vector3 = target.global_position - global_position
	to_p.y = 0.0
	var dist: float = to_p.length()
	# Leash: chased too far from home -> give up and walk back to the patrol.
	if global_position.distance_to(_home) > max_chase_distance and dist > attack_range * 1.5 and not is_taunted():
		_begin_return()
		return
	if dist > detection_range * 2.2 and not is_taunted():
		_threat.erase(target.get_instance_id())
		_lose_target()
		return
	var dir_to_p: Vector3 = to_p / dist if dist > 0.001 else get_facing_direction()

	if _taunt_timer > 0.0:
		set_facing_direction(dir_to_p)
		velocity = Vector3.ZERO
		return

	if _evade_timer > 0.0:
		_evade_timer -= delta
		var k: float = clampf(_evade_timer / 0.32, 0.0, 1.0)
		velocity = _evade_dir * lerpf(2.0, 8.5, k)
		set_facing_direction(dir_to_p)
		if is_inside_tree():
			move_and_slide()
		return

	if _squad != null:
		_enraged = _squad.is_last_standing(self, target)
	var speed: float = move_speed * (1.25 if _enraged else 1.0)
	var desired: Vector3
	var has_token: bool = _squad == null or _squad.request_attack_token(self, target)

	if has_token:
		if dist <= attack_range:
			start_windup()
			return
		desired = dir_to_p * speed * 1.15
	else:
		# Hold a spaced ring just outside reach, circling to find a flank.
		var ring_r: float = attack_range + ring_margin + _ring_jitter
		if health < max_health * 0.3:
			ring_r += 1.2
		var goal: Vector3 = _squad.get_ring_position(self, target, ring_r, _orbit_sign)
		var to_goal: Vector3 = goal - global_position
		to_goal.y = 0.0
		var g_len: float = to_goal.length()
		var strafe_speed: float = speed * 0.62
		desired = to_goal / g_len * minf(strafe_speed, g_len * 3.0) if g_len > 0.05 else Vector3.ZERO
		# Too close while not attacking: back off.
		if dist < attack_range + 0.4:
			desired += -dir_to_p * speed * 0.8

	if _squad != null:
		desired += _squad.get_separation(self) * speed * 1.4
	set_facing_direction(dir_to_p)
	var dv: Vector3 = Vector3(desired.x, 0.0, desired.z)
	var cur: Vector3 = Vector3(velocity.x, 0.0, velocity.z).move_toward(dv, 22.0 * delta)
	velocity.x = cur.x
	velocity.z = cur.z
	if is_inside_tree():
		move_and_slide()


## Current target lost: switch to the next one on the table, else investigate where it was last seen.
func _lose_target() -> void:
	_release_token()
	var last_pos: Vector3 = target_player.global_position if is_instance_valid(target_player) else global_position
	target_player = null
	if _squad != null:
		_squad.set_enemy_target(self, null)
	_select_target()
	if get_current_target() != null:
		return
	_alert_pos = last_pos
	_transition_to(State.ALERT, alert_investigate_duration)


func _begin_return() -> void:
	_release_token()
	_clear_threat()
	_reaggro_block = 1.5
	_transition_to(State.RETURNING, 0.0)
	returning_home.emit()


func _process_returning(delta: float) -> void:
	var to_h: Vector3 = _home - global_position
	to_h.y = 0.0
	if to_h.length() < 0.6:
		velocity = Vector3.ZERO
		_patrol_goal = _home
		_transition_to(State.IDLE, 0.0)
		return
	if _reaggro_block <= 0.0:
		var seen: Node3D = _nearest_visible_candidate(detection_range * 0.6)
		if seen != null and seen.global_position.distance_to(_home) < max_chase_distance:
			_aggro_on(seen, false)
			return
	set_facing_direction(to_h)
	_steer_toward(to_h.normalized() * move_speed * 0.95, delta, false)
	# Hopelessly stuck (e.g. dropped down a level): snap home once the timer runs long.
	if _state_elapsed > 14.0:
		global_position = _home
		velocity = Vector3.ZERO


func _should_flee() -> bool:
	return flee_health_ratio > 0.0 and not _has_fled and not is_dead and float(health) / float(maxi(1, max_health)) <= flee_health_ratio \
		and current_state != State.STUNNED


func _start_flee() -> void:
	_has_fled = true
	_clear_telegraph_flash()
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.end_swing()
	_release_token()
	_transition_to(State.FLEEING, flee_duration)
	fleeing_started.emit()


func _process_fleeing(delta: float, target: Node3D) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	var away: Vector3 = -get_facing_direction()
	if target != null:
		away = global_position - target.global_position
		away.y = 0.0
	# Bias toward home so fleeing never drags the enemy out of its arena.
	var to_h: Vector3 = _home - global_position
	to_h.y = 0.0
	if to_h.length() > max_chase_distance * 0.6:
		away = away.normalized() * 0.4 + to_h.normalized()
	if away.length_squared() < 0.001:
		away = Vector3.FORWARD
	set_facing_direction(away)
	_steer_toward(away.normalized() * move_speed * 1.15, delta, true)
	if _state_timer <= 0.0:
		# Cornered courage: turn and fight again.
		_taunt_timer = 0.35
		_transition_to(State.CHASE, 0.0)


func _process_windup(delta: float, target: Node3D) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	# Track the target through the first half of the wind-up, then commit (dodgeable).
	if target != null and _state_elapsed < _state_duration * 0.55:
		var to_p: Vector3 = target.global_position - global_position
		to_p.y = 0.0
		if to_p.length_squared() > 0.01:
			set_facing_direction(get_facing_direction().slerp(to_p.normalized(), clampf(8.0 * delta, 0.0, 1.0)))
	if _state_timer <= 0.0:
		_begin_attack_strike()


func _begin_attack_strike() -> void:
	_release_telegraph_flash()
	_transition_to(State.ATTACK, attack_active_duration)
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.affects_player = true
		hb.affects_enemies = false
		hb.begin_swing(attack_damage, false, "enemy_" + attack_name)
	# Step into the swing so strikes carry weight (subclasses with real lunges override velocity).
	velocity = get_facing_direction() * attack_lunge_speed
	attack_started.emit(attack_name, attack_damage)


func _process_attack(delta: float, _target: Node3D) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	if is_inside_tree() and velocity.length_squared() > 0.001:
		move_and_slide()
	if _state_timer <= 0.0:
		_enter_recover()


func _enter_recover(custom_recover: float = -1.0) -> void:
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.end_swing()
	velocity = Vector3.ZERO
	_release_token()
	var dur: float = recover_duration if custom_recover < 0.0 else custom_recover
	if _enraged:
		dur *= 0.7
	_transition_to(State.RECOVER, dur)
	recovery_started.emit(dur)


func _process_recover(delta: float, _target: Node3D) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	if _state_timer <= 0.0:
		_on_recover_finished()
		_transition_to(State.CHASE, 0.0)


func _process_stagger(delta: float) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	if _state_timer <= 0.0:
		_finish_turn_around()
		_transition_to(State.CHASE, 0.0)


func _process_stunned(delta: float) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	velocity = Vector3.ZERO
	if _state_timer <= 0.0:
		_finish_turn_around()
		_transition_to(State.CHASE, 0.0)


## Backstab reaction: whip around to face whoever stabbed us (and make them the target).
func _finish_turn_around() -> void:
	if _turn_to_id == 0:
		return
	var o: Object = instance_from_id(_turn_to_id)
	_turn_to_id = 0
	if o is Node3D and is_instance_valid(o) and _is_valid_target(o as Node3D):
		set_facing_direction((o as Node3D).global_position - global_position)
		_set_target(o as Node3D)
		_taunt_timer = 0.2


func _on_recover_finished() -> void:
	pass


func _on_stagger_triggered() -> void:
	enter_stagger()


## Steering helper with an edge probe so wandering / fleeing never walks off a ledge.
func _steer_toward(desired: Vector3, delta: float, probe_edges: bool) -> void:
	var dv: Vector3 = Vector3(desired.x, 0.0, desired.z)
	if probe_edges and dv.length_squared() > 0.01 and not _has_floor_ahead(dv.normalized()):
		var side := Vector3(-dv.z, 0.0, dv.x)
		dv = side if _has_floor_ahead(side.normalized()) else Vector3.ZERO
	if _squad != null:
		dv += _squad.get_separation(self) * move_speed
	var cur: Vector3 = Vector3(velocity.x, 0.0, velocity.z).move_toward(dv, 18.0 * delta)
	velocity.x = cur.x
	velocity.z = cur.z
	if not is_on_floor():
		velocity.y = maxf(velocity.y - 20.0 * delta, -20.0)
	else:
		velocity.y = 0.0
	if is_inside_tree():
		move_and_slide()


func _has_floor_ahead(dir: Vector3, dist: float = 0.9) -> bool:
	if not is_inside_tree() or get_world_3d() == null:
		return true
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return true
	var from: Vector3 = global_position + dir * dist + Vector3.UP * 0.6
	var mask: int = collision_mask & (RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_REALITY | RealmManager.LAYER_WORLD_MIRROR)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.2, mask, [get_rid()])
	return not space.intersect_ray(q).is_empty()


# ------------------------------------------------------------------ hit reactions

func _on_hit_reaction(final_damage: int, is_heavy: bool, source_type: String, staggered_now: bool) -> void:
	var kb: float = 2.6 + float(final_damage) * 0.05
	if is_heavy:
		kb = 6.5
	if source_type == "player_landing":
		kb = 7.5
	_knockback += last_hit_direction * kb * knockback_scale
	# Hit lean: tilt away from the blow (local to facing).
	var f: Vector3 = get_facing_direction()
	var r: Vector3 = Vector3(-f.z, 0.0, f.x)
	var push: float = (5.0 if is_heavy else 3.0) * clampf(knockback_scale * 1.5, 0.25, 1.0)
	_lean_v += Vector2(last_hit_direction.dot(f), last_hit_direction.dot(r)) * push * 1.3

	if staggered_now or is_heavy or not flinch_on_light_hits:
		return
	match current_state:
		State.ATTACK, State.DEAD, State.STUNNED, State.FLEEING:
			return
		State.WINDUP:
			if _state_elapsed > _state_duration * 0.5:
				return  # hyper-armour: the swing is coming
	if _poise_timer > 0.0:
		return
	_flinch_chain += 1
	_flinch_chain_timer = 1.4
	if _flinch_chain > max_flinch_chain:
		# Broke free of the stun-lock: brace, then punish the button-masher.
		_flinch_chain = 0
		_poise_timer = poise_duration
		if _rng.randf() < counter_attack_chance:
			var p: Node3D = _resolve_target_player()
			if p != null and global_position.distance_to(p.global_position) <= attack_range + 0.9:
				if _squad != null:
					_squad.release_token(self)
					_squad.request_attack_token(self, p)
				start_windup(windup_duration * 0.65)
		return
	enter_stagger(flinch_duration)


func _apply_knockback(delta: float) -> void:
	if _knockback.length_squared() < 0.01:
		_knockback = Vector3.ZERO
		return
	if is_inside_tree():
		move_and_collide(Vector3(_knockback.x, 0.0, _knockback.z) * delta)
	_knockback *= exp(-9.0 * delta)


## External shove (ally charge, detonation) on top of hit knockback.
func add_knockback(impulse: Vector3) -> void:
	_knockback += Vector3(impulse.x, 0.0, impulse.z) * knockback_scale


func _update_hit_lean(delta: float) -> void:
	if delta <= 0.0:
		return
	var model: Node3D = get_node_or_null(NodePath(String(visual_root_path) + "/ModelRoot")) as Node3D
	if model == null:
		return
	if _model_base_scale == Vector3.ZERO:
		_model_base_scale = model.scale
	# Critically-damped-ish spring back to upright.
	_lean_v += (-_lean * 150.0 - _lean_v * 13.0) * delta
	_lean += _lean_v * delta
	_lean = _lean.clamp(Vector2(-0.6, -0.5), Vector2(0.6, 0.5))
	var squash: float = 0.0
	if current_state == State.WINDUP:
		# Coil down during the wind-up so the telegraph reads in the silhouette.
		squash = -0.06 * clampf(_state_elapsed / maxf(0.05, _state_duration), 0.0, 1.0)
	elif current_state == State.ATTACK:
		squash = 0.05
	var sy: float = 1.0 + squash
	var sxz: float = 1.0 / sqrt(sy)
	# Euler x>0 tips the model forward, z>0 tips it to its right. A blow from the front gives
	# lean.x < 0 (head snaps back); a blow from the right gives lean.y < 0 (tips left).
	model.transform.basis = Basis.from_euler(Vector3(_lean.x, PI, _lean.y)) * Basis.from_scale(Vector3(sxz, sy, sxz) * _model_base_scale)


## Tiny readable glyph over the head: ? investigating, ! aggro, ** stunned, ~ fleeing, <- returning, lock when taunted.
func _update_state_icon() -> void:
	if not show_state_icon or not is_inside_tree():
		return
	if _state_icon == null or not is_instance_valid(_state_icon):
		_state_icon = Label3D.new()
		_state_icon.name = "StateIcon"
		_state_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_state_icon.no_depth_test = true
		_state_icon.pixel_size = 0.012
		_state_icon.font_size = 44
		_state_icon.outline_size = 10
		_state_icon.outline_modulate = Color(0.02, 0.02, 0.04, 0.9)
		_state_icon.position = Vector3(0.0, 2.75, 0.0)
		_state_icon.font = UITheme.display_font()
		add_child(_state_icon)
	var txt: String = ""
	var col := Color(1.0, 0.85, 0.35)
	match current_state:
		State.ALERT:
			txt = "?"
		State.STUNNED:
			txt = "✦ ✦"
			col = Color(1.0, 0.95, 0.55)
		State.FLEEING:
			txt = "!!"
			col = Color(0.6, 0.85, 1.0)
		State.RETURNING:
			txt = "↩"
			col = Color(0.7, 0.75, 0.8)
	if txt.is_empty() and is_taunted():
		txt = "⚔"
		col = Color(1.0, 0.45, 0.25)
	elif txt.is_empty() and current_state == State.CHASE and _taunt_timer > 0.0:
		txt = "!"
		col = Color(1.0, 0.3, 0.2)
	_state_icon.text = txt
	_state_icon.modulate = col
	_state_icon.visible = not txt.is_empty() and is_active and not is_dead


func _on_enemy_reset() -> void:
	_clear_telegraph_flash()
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.end_swing()
	_release_token()
	_clear_threat()
	_knockback = Vector3.ZERO
	_lean = Vector2.ZERO
	_lean_v = Vector2.ZERO
	_flinch_chain = 0
	_poise_timer = 0.0
	_taunt_timer = 0.0
	_evade_timer = 0.0
	_enraged = false
	_has_fled = false
	_turn_to_id = 0
	_reaggro_block = 0.0
	_patrol_goal = _home
	_transition_to(State.IDLE, 0.0)


func _die(source_type: String) -> void:
	_clear_telegraph_flash()
	_release_token()
	_transition_to(State.DEAD, 0.0)
	super._die(source_type)
	if _squad != null and is_instance_valid(_squad):
		_squad.set_enemy_target(self, null)


func _release_token() -> void:
	if _squad != null and is_instance_valid(_squad):
		_squad.release_token(self)


func _transition_to(next_state: State, duration: float) -> void:
	current_state = next_state
	_state_timer = duration
	_state_duration = duration
	_state_elapsed = 0.0
	state_changed.emit(current_state)


## Returns the current threat target (player or ally). Name kept for subclasses.
func _resolve_target_player() -> Node3D:
	return get_current_target()


# --- Telegraph clarity (Claude Pass A): red emissive overlay + eye-height glow during wind-up ---

func _begin_telegraph_flash(windup_sec: float) -> void:
	if not is_inside_tree():
		return
	_clear_telegraph_flash()
	var vis_root: Node3D = get_node_or_null(visual_root_path) as Node3D
	if vis_root == null:
		return
	if _telegraph_mat == null:
		_telegraph_mat = StandardMaterial3D.new()
		_telegraph_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_telegraph_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_telegraph_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_telegraph_mat.cull_mode = BaseMaterial3D.CULL_BACK
	_telegraph_mat.albedo_color = Color(telegraph_color.r, telegraph_color.g, telegraph_color.b, 0.0)

	_telegraph_meshes.clear()
	_collect_meshes(vis_root, _telegraph_meshes)
	for mi in _telegraph_meshes:
		mi.material_overlay = _telegraph_mat

	if _telegraph_light == null or not is_instance_valid(_telegraph_light):
		_telegraph_light = OmniLight3D.new()
		_telegraph_light.name = "TelegraphGlow"
		_telegraph_light.light_color = telegraph_color
		_telegraph_light.omni_range = 2.4
		_telegraph_light.shadow_enabled = false
		vis_root.add_child(_telegraph_light)
		_telegraph_light.position = Vector3(0.0, telegraph_light_height, -0.35)
	_telegraph_light.light_energy = 0.0
	_telegraph_light.visible = true

	var dur: float = maxf(0.05, windup_sec)
	_telegraph_tween = create_tween()
	_telegraph_tween.set_parallel(true)
	_telegraph_tween.tween_property(_telegraph_mat, "albedo_color:a", telegraph_overlay_peak_alpha, dur * 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_telegraph_tween.tween_property(_telegraph_light, "light_energy", telegraph_light_energy, dur * 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Final "glint" right before the strike lands.
	_telegraph_tween.chain().tween_property(_telegraph_mat, "albedo_color:a", minf(1.0, telegraph_overlay_peak_alpha * 1.6), dur * 0.25)
	_telegraph_tween.parallel().tween_property(_telegraph_light, "light_energy", telegraph_light_energy * 1.5, dur * 0.25)


func _release_telegraph_flash() -> void:
	## Strike started: let the glow fall off quickly instead of snapping.
	if _telegraph_mat == null or _telegraph_meshes.is_empty():
		_clear_telegraph_flash()
		return
	if _telegraph_tween != null and _telegraph_tween.is_valid():
		_telegraph_tween.kill()
	_telegraph_tween = create_tween()
	_telegraph_tween.set_parallel(true)
	_telegraph_tween.tween_property(_telegraph_mat, "albedo_color:a", 0.0, 0.12)
	if _telegraph_light != null and is_instance_valid(_telegraph_light):
		_telegraph_tween.tween_property(_telegraph_light, "light_energy", 0.0, 0.12)
	_telegraph_tween.chain().tween_callback(_clear_telegraph_flash)


func _clear_telegraph_flash() -> void:
	if _telegraph_tween != null and _telegraph_tween.is_valid():
		_telegraph_tween.kill()
	_telegraph_tween = null
	for mi in _telegraph_meshes:
		if is_instance_valid(mi) and mi.material_overlay == _telegraph_mat:
			mi.material_overlay = null
	_telegraph_meshes.clear()
	if _telegraph_light != null and is_instance_valid(_telegraph_light):
		_telegraph_light.light_energy = 0.0
		_telegraph_light.visible = false


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and not String(node.name).begins_with("ChestRune"):
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)
