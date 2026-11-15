class_name PlayerController
extends CharacterBody3D
## Third-person player locomotion, combat state machine (3-hit Light combo, Heavy, Dodge with i-frames,
## Airborne Landing Attack), interaction ray/area trigger, and checkpoint respawn contract.

enum State {
	LOCOMOTION = 0,
	DODGE = 1,
	LIGHT_ATTACK = 2,
	HEAVY_ATTACK = 3,
	LANDING_PLUNGE = 4,
	STAGGER = 5,
	DEAD = 6,
}

signal health_changed(current_hp: int, max_hp: int)
signal player_died()
signal state_changed(new_state: int)
signal attack_executed(attack_name: String, combo_step: int, damage: int, is_heavy: bool)
signal dodge_started(direction: Vector3, duration: float)
signal landing_slam_triggered(impact_position: Vector3, radius: float, damage: int)
signal interact_requested()

@export_group("Health & Survival")
@export var max_health: int = 100

@export_group("Locomotion")
@export var run_speed: float = 4.5
@export var acceleration: float = 28.0
@export var friction: float = 24.0
@export var jump_velocity: float = 7.2
@export var gravity_scale: float = 1.6

@export_group("Dodge")
@export var dodge_duration: float = 0.55
@export var dodge_speed: float = 8.2
@export var dodge_iframe_start: float = 0.10
@export var dodge_iframe_duration: float = 0.18
@export var dodge_cooldown: float = 0.20

@export_group("Combat Tuning")
@export var light_combo_damages: PackedInt32Array = PackedInt32Array([25, 25, 35])
@export var light_attack_durations: PackedFloat32Array = PackedFloat32Array([0.32, 0.34, 0.44])
@export var light_combo_reset_window: float = 0.85
@export var heavy_attack_damage: int = 60
@export var heavy_attack_duration: float = 0.68
@export var landing_attack_damage: int = 60
@export var landing_attack_radius: float = 2.2
@export var landing_plunge_speed: float = 18.0

@export_group("Node References")
@export var camera_pivot_path: NodePath = NodePath("CameraPivot")
@export var sword_hitbox_path: NodePath = NodePath("SwordHitbox")
@export var hurtbox_path: NodePath = NodePath("Hurtbox3D")

var health: int = 100
var current_state: State = State.LOCOMOTION

var combo_step: int = 0
var _combo_window_timer: float = 0.0
var _state_timer: float = 0.0
var _dodge_elapsed: float = 0.0
var _dodge_cooldown_timer: float = 0.0
var _dodge_direction: Vector3 = Vector3.BACK
var _simulated_airborne: bool = false
var _nearby_interactables: Array[Node] = []


func _ready() -> void:
	add_to_group("player")
	health = max_health
	if RealmManager.instance != null:
		RealmManager.instance.register_player(self)
	health_changed.emit(health, max_health)


func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return

	if _dodge_cooldown_timer > 0.0:
		_dodge_cooldown_timer = maxf(0.0, _dodge_cooldown_timer - delta)

	if _combo_window_timer > 0.0 and current_state == State.LOCOMOTION:
		_combo_window_timer = maxf(0.0, _combo_window_timer - delta)
		if _combo_window_timer <= 0.0:
			combo_step = 0

	match current_state:
		State.DODGE:
			_process_dodge_state(delta)
		State.LIGHT_ATTACK, State.HEAVY_ATTACK:
			_process_attack_state(delta)
		State.LANDING_PLUNGE:
			_process_landing_plunge_state(delta)
		State.LOCOMOTION:
			_process_locomotion_state(delta)


func is_currently_airborne() -> bool:
	return _simulated_airborne or (is_inside_tree() and not is_on_floor())


func set_simulated_airborne(airborne: bool) -> void:
	_simulated_airborne = airborne


func is_invulnerable() -> bool:
	var hb: Hurtbox3D = get_hurtbox()
	if hb != null and hb.is_invulnerable:
		return true
	if current_state == State.DODGE:
		return _dodge_elapsed >= dodge_iframe_start and _dodge_elapsed <= (dodge_iframe_start + dodge_iframe_duration)
	return false


func start_light_attack() -> bool:
	if current_state != State.LOCOMOTION or is_currently_airborne():
		return false

	var step_idx: int = clampi(combo_step, 0, light_combo_damages.size() - 1)
	var dmg: int = int(light_combo_damages[step_idx])
	var dur: float = float(light_attack_durations[step_idx])

	combo_step = (step_idx + 1) % light_combo_damages.size()
	_combo_window_timer = light_combo_reset_window
	_set_state(State.LIGHT_ATTACK, dur)

	var hb: Hitbox3D = get_sword_hitbox()
	if hb != null:
		hb.begin_swing(dmg, false, "player_light")

	attack_executed.emit("light_" + str(step_idx + 1), step_idx + 1, dmg, false)
	return true


func start_heavy_attack() -> bool:
	if current_state != State.LOCOMOTION or is_currently_airborne():
		return false

	combo_step = 0
	_set_state(State.HEAVY_ATTACK, heavy_attack_duration)

	var hb: Hitbox3D = get_sword_hitbox()
	if hb != null:
		hb.begin_swing(heavy_attack_damage, true, "player_heavy")

	attack_executed.emit("heavy", 0, heavy_attack_damage, true)
	return true


func start_dodge(input_dir: Vector3 = Vector3.ZERO) -> bool:
	if current_state != State.LOCOMOTION or is_currently_airborne() or _dodge_cooldown_timer > 0.0:
		return false

	_dodge_direction = input_dir.normalized() if input_dir.length_squared() > 0.001 else -global_transform.basis.z.normalized()
	_dodge_elapsed = 0.0
	_set_state(State.DODGE, dodge_duration)
	_update_hurtbox_invulnerability(false)
	dodge_started.emit(_dodge_direction, dodge_duration)
	return true


func start_landing_attack() -> bool:
	if not is_currently_airborne():
		return false
	if current_state != State.LOCOMOTION:
		return false

	_set_state(State.LANDING_PLUNGE, 2.0)
	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y = -landing_plunge_speed
	attack_executed.emit("landing_plunge", 0, landing_attack_damage, true)
	return true


func complete_landing_slam(candidates: Array[Node] = []) -> int:
	if current_state != State.LANDING_PLUNGE:
		return 0

	_simulated_airborne = false
	_set_state(State.LOCOMOTION, 0.0)
	var hits: int = 0
	var hb: Hitbox3D = get_sword_hitbox()
	if hb != null:
		if not candidates.is_empty():
			hits = hb.pulse_radial_targets(global_position, landing_attack_radius, candidates, landing_attack_damage, true, "player_landing")
		elif get_tree() != null:
			var tree_targets: Array[Node] = []
			for n in get_tree().get_nodes_in_group("enemy"):
				tree_targets.append(n)
			for n in get_tree().get_nodes_in_group("mechanism_target"):
				tree_targets.append(n)
			for n in get_tree().get_nodes_in_group("breakable"):
				tree_targets.append(n)
			hits = hb.pulse_radial_targets(global_position, landing_attack_radius, tree_targets, landing_attack_damage, true, "player_landing")

	landing_slam_triggered.emit(global_position, landing_attack_radius, landing_attack_damage)
	return hits


func try_interact() -> bool:
	if current_state == State.DEAD:
		return false
	interact_requested.emit()
	for item in _nearby_interactables:
		if is_instance_valid(item) and item.has_method("interact"):
			if bool(item.call("interact")):
				return true
	if get_tree() != null:
		for node in get_tree().get_nodes_in_group("interactable_switch"):
			if is_instance_valid(node) and node is Node3D:
				if (node as Node3D).global_position.distance_to(global_position) <= 2.6 and node.has_method("interact"):
					if bool(node.call("interact")):
						return true
	return false


func register_nearby_interactable(node: Node) -> void:
	if node != null and not _nearby_interactables.has(node):
		_nearby_interactables.append(node)


func unregister_nearby_interactable(node: Node) -> void:
	_nearby_interactables.erase(node)


func apply_damage(amount: int, _source: Node = null) -> bool:
	if amount <= 0 or current_state == State.DEAD or is_invulnerable():
		return false

	health = maxi(0, health - amount)
	health_changed.emit(health, max_health)

	var run_state: Node = _get_run_state()
	if run_state != null and run_state.has_method("on_player_damaged"):
		run_state.call("on_player_damaged")

	if health <= 0:
		_on_death()
	return true


func respawn_at(spawn_transform: Transform3D) -> void:
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	health = max_health
	combo_step = 0
	_combo_window_timer = 0.0
	_dodge_elapsed = 0.0
	_simulated_airborne = false
	_update_hurtbox_invulnerability(false)
	var hb: Hitbox3D = get_sword_hitbox()
	if hb != null:
		hb.end_swing()
	_set_state(State.LOCOMOTION, 0.0)
	health_changed.emit(health, max_health)


func get_sword_hitbox() -> Hitbox3D:
	return get_node_or_null(sword_hitbox_path) as Hitbox3D


func get_hurtbox() -> Hurtbox3D:
	return get_node_or_null(hurtbox_path) as Hurtbox3D


func _process_locomotion_state(delta: float) -> void:
	var grav: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * gravity_scale
	if not is_on_floor():
		velocity.y -= grav * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var input_vec: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis_ref: Basis = global_transform.basis
	var cam_pivot: Node3D = get_node_or_null(camera_pivot_path) as Node3D
	if cam_pivot != null:
		basis_ref = cam_pivot.global_transform.basis

	var forward: Vector3 = -basis_ref.z
	forward.y = 0.0
	forward = forward.normalized()
	var right: Vector3 = basis_ref.x
	right.y = 0.0
	right = right.normalized()

	var move_dir: Vector3 = (right * input_vec.x + forward * (-input_vec.y)).normalized()
	if move_dir.length_squared() > 0.001:
		velocity.x = move_toward(velocity.x, move_dir.x * run_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, move_dir.z * run_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)

	if Input.is_action_just_pressed("landing_attack") and is_currently_airborne():
		start_landing_attack()
		return
	if Input.is_action_just_pressed("light_attack"):
		start_light_attack()
		return
	if Input.is_action_just_pressed("heavy_attack"):
		start_heavy_attack()
		return
	if Input.is_action_just_pressed("dodge") and is_on_floor() and move_dir.length_squared() > 0.001:
		start_dodge(move_dir)
		return
	if Input.is_action_just_pressed("interact"):
		try_interact()

	if is_inside_tree():
		move_and_slide()


func _process_dodge_state(delta: float) -> void:
	_dodge_elapsed += delta
	_state_timer = maxf(0.0, _state_timer - delta)
	var in_iframes: bool = _dodge_elapsed >= dodge_iframe_start and _dodge_elapsed <= (dodge_iframe_start + dodge_iframe_duration)
	_update_hurtbox_invulnerability(in_iframes)

	velocity.x = _dodge_direction.x * dodge_speed
	velocity.z = _dodge_direction.z * dodge_speed
	if is_inside_tree():
		move_and_slide()

	if _state_timer <= 0.0:
		_update_hurtbox_invulnerability(false)
		_dodge_cooldown_timer = dodge_cooldown
		_set_state(State.LOCOMOTION, 0.0)


func _process_attack_state(delta: float) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	velocity.x = move_toward(velocity.x, 0.0, friction * delta)
	velocity.z = move_toward(velocity.z, 0.0, friction * delta)
	if is_inside_tree():
		move_and_slide()

	if _state_timer <= 0.0:
		var hb: Hitbox3D = get_sword_hitbox()
		if hb != null:
			hb.end_swing()
		_set_state(State.LOCOMOTION, 0.0)


func _process_landing_plunge_state(delta: float) -> void:
	velocity.y = -landing_plunge_speed
	if is_inside_tree():
		move_and_slide()
		if is_on_floor():
			complete_landing_slam()
			return

	_state_timer = maxf(0.0, _state_timer - delta)
	if _state_timer <= 0.0:
		complete_landing_slam()


func _set_state(next_state: State, duration: float) -> void:
	current_state = next_state
	_state_timer = duration
	state_changed.emit(current_state)


func _update_hurtbox_invulnerability(invuln: bool) -> void:
	var hb: Hurtbox3D = get_hurtbox()
	if hb != null:
		hb.is_invulnerable = invuln


func _on_death() -> void:
	var hb: Hitbox3D = get_sword_hitbox()
	if hb != null:
		hb.end_swing()
	_update_hurtbox_invulnerability(false)
	_set_state(State.DEAD, 0.0)
	player_died.emit()
	if EncounterDirector.instance != null:
		EncounterDirector.instance.handle_player_death(self)


func _get_run_state() -> Node:
	if get_tree() != null and get_tree().root != null:
		return get_tree().root.get_node_or_null("RunState")
	return null
