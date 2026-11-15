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
@export var visual_root_path: NodePath = NodePath("VisualRoot")

@export_group("Camera & Facing")
@export var pitch_min_degrees: float = -45.0
@export var pitch_max_degrees: float = 60.0
@export var character_turn_speed: float = 14.0

var health: int = 100
var current_state: State = State.LOCOMOTION
var camera_yaw: float = 0.0
var camera_pitch: float = deg_to_rad(-15.0)
var facing_direction: Vector3 = Vector3.FORWARD
var mouse_sensitivity: float = 0.0025
var invert_y: bool = false
var camera_shake_intensity: float = 1.0
var hit_stop_enabled: bool = true

var combo_step: int = 0
var _combo_window_timer: float = 0.0
var _state_timer: float = 0.0
var _dodge_elapsed: float = 0.0
var _dodge_cooldown_timer: float = 0.0
var _dodge_direction: Vector3 = Vector3.BACK
var _simulated_airborne: bool = false
var _force_jump_context: bool = false
var _jump_zone_overlaps: int = 0
var _nearby_interactables: Array[Node] = []


func _ready() -> void:
	add_to_group("player")
	health = max_health
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 0.001:
		facing_direction = fwd.normalized()
	if RealmManager.instance != null:
		RealmManager.instance.register_player(self)
	_load_mouse_settings_from_store()
	health_changed.emit(health, max_health)


func _load_mouse_settings_from_store() -> void:
	var store: Node = _get_leaderboard_store()
	if store != null and store.has_method("get_settings"):
		var s: Dictionary = store.call("get_settings")
		mouse_sensitivity = float(s.get("mouse_sensitivity", 0.0025))
		invert_y = bool(s.get("invert_y", false))
		camera_shake_intensity = float(s.get("camera_shake_intensity", 1.0))
		hit_stop_enabled = bool(s.get("hit_stop_enabled", true))


func _unhandled_input(event: InputEvent) -> void:
	if current_state == State.DEAD:
		return
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		apply_look_delta(mm.relative)


func apply_look_delta(relative_motion: Vector2) -> void:
	_load_mouse_settings_from_store()
	var sens: float = mouse_sensitivity
	var inv_y: bool = invert_y

	camera_yaw -= relative_motion.x * sens
	var y_sign: float = 1.0 if inv_y else -1.0
	camera_pitch = clampf(
		camera_pitch + relative_motion.y * sens * y_sign,
		deg_to_rad(pitch_min_degrees),
		deg_to_rad(pitch_max_degrees)
	)
	var cam_pivot: Node3D = get_node_or_null(camera_pivot_path) as Node3D
	if cam_pivot != null:
		cam_pivot.rotation = Vector3(camera_pitch, camera_yaw, 0.0)


func get_facing_direction() -> Vector3:
	if facing_direction.length_squared() > 0.001:
		return facing_direction.normalized()
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	return fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD


func set_facing_direction(dir: Vector3) -> void:
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() <= 0.0001:
		return
	facing_direction = flat.normalized()
	var target_yaw: float = atan2(-facing_direction.x, -facing_direction.z)
	var vis: Node3D = get_node_or_null(visual_root_path) as Node3D
	if vis != null:
		vis.rotation.y = target_yaw
	var hb: Hitbox3D = get_sword_hitbox()
	if hb != null and hb.get_parent() == self:
		hb.rotation.y = target_yaw


func set_jump_context(enabled: bool) -> void:
	_force_jump_context = enabled


func enter_jump_zone() -> void:
	_jump_zone_overlaps += 1


func exit_jump_zone() -> void:
	_jump_zone_overlaps = maxi(0, _jump_zone_overlaps - 1)


func is_in_jump_context(move_dir: Vector3 = Vector3.ZERO) -> bool:
	if _force_jump_context or _jump_zone_overlaps > 0:
		return true
	if move_dir.length_squared() <= 0.001:
		return true
	if is_inside_tree() and get_world_3d() != null and get_world_3d().direct_space_state != null:
		var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var flat_dir: Vector3 = Vector3(move_dir.x, 0.0, move_dir.z).normalized()
		var mask: int = collision_mask & (RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_REALITY | RealmManager.LAYER_WORLD_MIRROR)
		if mask == 0:
			mask = RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_REALITY | RealmManager.LAYER_WORLD_MIRROR
		# Check for a raised step/dais ahead (knee-to-waist height)
		var step_origin: Vector3 = global_position + Vector3(0.0, 0.55, 0.0)
		var step_end: Vector3 = step_origin + flat_dir * 1.45
		var step_q := PhysicsRayQueryParameters3D.create(step_origin, step_end, mask, [get_rid()])
		if not space.intersect_ray(step_q).is_empty():
			return true
		# Check for a floor gap/chasm drop-off ahead
		var probe_origin: Vector3 = global_position + flat_dir * 1.35 + Vector3(0.0, 0.35, 0.0)
		var probe_end: Vector3 = probe_origin + Vector3.DOWN * 1.10
		var gap_q := PhysicsRayQueryParameters3D.create(probe_origin, probe_end, mask, [get_rid()])
		if space.intersect_ray(gap_q).is_empty():
			return true
	return false


func start_jump() -> bool:
	if current_state != State.LOCOMOTION or is_currently_airborne():
		return false
	velocity.y = jump_velocity
	return true


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
	if _simulated_airborne:
		return true
	if is_inside_tree() and _has_body_collider():
		return not is_on_floor()
	return false


func _has_body_collider() -> bool:
	for child in get_children():
		if child is CollisionShape3D and not (child as CollisionShape3D).disabled:
			return true
	return false


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

	if input_dir.length_squared() > 0.001:
		set_facing_direction(input_dir)
		_dodge_direction = input_dir.normalized()
	else:
		_dodge_direction = get_facing_direction()
	velocity.y = minf(velocity.y, 0.0)
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
		set_facing_direction(move_dir)
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

	var jump_pressed: bool = Input.is_action_just_pressed("jump")
	var dodge_pressed: bool = Input.is_action_just_pressed("dodge")
	if is_on_floor() and (jump_pressed or dodge_pressed):
		if jump_pressed and dodge_pressed:
			if is_in_jump_context(move_dir):
				start_jump()
			else:
				start_dodge(move_dir)
				return
		elif dodge_pressed:
			if start_dodge(move_dir):
				return
		elif jump_pressed:
			start_jump()

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
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		return get_tree().root.get_node_or_null("RunState")
	return null


func _get_leaderboard_store() -> Node:
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		return get_tree().root.get_node_or_null("LeaderboardStore")
	return null
