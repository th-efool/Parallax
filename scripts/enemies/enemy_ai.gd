class_name EnemyAI
extends EnemyBase
## Finite State Machine (`IDLE`, `CHASE`, `WINDUP`, `ATTACK`, `RECOVER`, `STAGGER`, `DEAD`)
## shared by Skeleton Guard, Phantom Twin, Shielded Guard, and extended by The Warden.

enum State {
	IDLE = 0,
	CHASE = 1,
	WINDUP = 2,
	ATTACK = 3,
	RECOVER = 4,
	STAGGER = 5,
	DEAD = 6,
}

signal state_changed(new_state: int)
signal attack_telegraphed(attack_name: String, windup_sec: float)
signal attack_started(attack_name: String, damage: int)
signal recovery_started(recover_sec: float)

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

var current_state: State = State.IDLE
var _state_timer: float = 0.0
var target_player: Node3D = null


func _physics_process(delta: float) -> void:
	if not is_active or is_dead:
		return
	step_ai(delta)


func step_ai(delta: float) -> void:
	if is_dead:
		if current_state != State.DEAD:
			_transition_to(State.DEAD, 0.0)
		return

	var player: Node3D = _resolve_target_player()
	match current_state:
		State.IDLE:
			_process_idle(delta, player)
		State.CHASE:
			_process_chase(delta, player)
		State.WINDUP:
			_process_windup(delta, player)
		State.ATTACK:
			_process_attack(delta, player)
		State.RECOVER:
			_process_recover(delta, player)
		State.STAGGER:
			_process_stagger(delta)


func start_windup(custom_windup: float = -1.0) -> void:
	if is_dead or not is_active:
		return
	var dur: float = windup_duration if custom_windup < 0.0 else custom_windup
	velocity = Vector3.ZERO
	_transition_to(State.WINDUP, dur)
	attack_telegraphed.emit(attack_name, dur)


func enter_stagger(custom_duration: float = -1.0) -> void:
	if is_dead:
		return
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.end_swing()
	var dur: float = stagger_duration if custom_duration < 0.0 else custom_duration
	velocity = Vector3.ZERO
	_transition_to(State.STAGGER, dur)
	staggered.emit(dur)


func _process_idle(_delta: float, player: Node3D) -> void:
	velocity = Vector3.ZERO
	if player != null and global_position.distance_to(player.global_position) <= detection_range:
		_transition_to(State.CHASE, 0.0)


func _process_chase(_delta: float, player: Node3D) -> void:
	if player == null:
		_transition_to(State.IDLE, 0.0)
		return

	var dist: float = global_position.distance_to(player.global_position)
	if dist > detection_range * 1.35:
		_transition_to(State.IDLE, 0.0)
		return
	if dist <= attack_range:
		start_windup()
		return

	var dir: Vector3 = (player.global_position - global_position)
	dir.y = 0.0
	if dir.length_squared() > 0.001:
		dir = dir.normalized()
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
	if is_inside_tree():
		move_and_slide()


func _process_windup(delta: float, _player: Node3D) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	if _state_timer <= 0.0:
		_begin_attack_strike()


func _begin_attack_strike() -> void:
	_transition_to(State.ATTACK, attack_active_duration)
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.affects_player = true
		hb.affects_enemies = false
		hb.begin_swing(attack_damage, false, "enemy_" + attack_name)
	attack_started.emit(attack_name, attack_damage)


func _process_attack(delta: float, _player: Node3D) -> void:
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
	var dur: float = recover_duration if custom_recover < 0.0 else custom_recover
	_transition_to(State.RECOVER, dur)
	recovery_started.emit(dur)


func _process_recover(delta: float, _player: Node3D) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	if _state_timer <= 0.0:
		_on_recover_finished()
		_transition_to(State.CHASE, 0.0)


func _process_stagger(delta: float) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	if _state_timer <= 0.0:
		_transition_to(State.CHASE, 0.0)


func _on_recover_finished() -> void:
	pass


func _on_stagger_triggered() -> void:
	enter_stagger()


func _on_enemy_reset() -> void:
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.end_swing()
	_transition_to(State.IDLE, 0.0)


func _die(source_type: String) -> void:
	_transition_to(State.DEAD, 0.0)
	super._die(source_type)


func _transition_to(next_state: State, duration: float) -> void:
	current_state = next_state
	_state_timer = duration
	state_changed.emit(current_state)


func _resolve_target_player() -> Node3D:
	if is_instance_valid(target_player):
		return target_player
	if is_inside_tree() and get_tree() != null:
		var p: Node = get_tree().get_first_node_in_group("player")
		if p is Node3D:
			target_player = p as Node3D
			return target_player
	return null
