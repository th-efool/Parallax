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
signal player_damaged(amount: int)
signal jumped()
signal player_died()
signal state_changed(new_state: int)
signal attack_executed(attack_name: String, combo_step: int, damage: int, is_heavy: bool)
signal dodge_started(direction: Vector3, duration: float)
signal landing_slam_triggered(impact_position: Vector3, radius: float, damage: int)
signal interact_requested()

@export_group("Health & Survival")
@export var max_health: int = 100

@export_group("Locomotion")
@export var run_speed: float = 5.5
@export var acceleration: float = 32.0
@export var friction: float = 28.0
@export var jump_velocity: float = 7.8
@export var gravity_scale: float = 1.6

@export_group("Dodge")
@export var dodge_duration: float = 0.48
@export var dodge_speed: float = 9.5
@export var dodge_iframe_start: float = 0.04
@export var dodge_iframe_duration: float = 0.24
@export var dodge_cooldown: float = 0.16

@export_group("Combat Tuning")
@export var light_combo_damages: PackedInt32Array = PackedInt32Array([25, 25, 35])
@export var light_attack_durations: PackedFloat32Array = PackedFloat32Array([0.42, 0.44, 0.54])
@export var light_combo_reset_window: float = 0.90
@export var heavy_attack_damage: int = 60
@export var heavy_attack_duration: float = 0.72
@export var landing_attack_damage: int = 60
@export var landing_attack_radius: float = 2.6
@export var landing_plunge_speed: float = 20.0
@export var landing_leap_velocity: float = 8.5
@export var landing_recovery_duration: float = 0.28

@export_group("Node References")
@export var camera_pivot_path: NodePath = NodePath("CameraPivot")
@export var sword_hitbox_path: NodePath = NodePath("SwordHitbox")
@export var hurtbox_path: NodePath = NodePath("Hurtbox3D")
@export var visual_root_path: NodePath = NodePath("VisualRoot")

@export_group("Camera & Facing")
@export var pitch_min_degrees: float = -45.0
@export var pitch_max_degrees: float = 60.0
@export var character_turn_speed: float = 14.0

@export_group("Game Feel")
@export var hit_stop_time_scale: float = 0.05
@export var hit_stop_duration: float = 0.06
@export var trauma_decay_per_sec: float = 1.8
@export var shake_max_pitch_deg: float = 2.4
@export var shake_max_yaw_deg: float = 2.8
@export var shake_max_roll_deg: float = 3.6
@export var shake_noise_speed: float = 38.0
@export var heavy_hit_stagger_threshold: int = 20
@export var heavy_hit_stagger_duration: float = 0.25
@export var stagger_knockback_speed: float = 3.2

const CombatVFXScript := preload("res://scripts/core/combat_vfx.gd")
const SLASH_TRAIL_SHADER_PATH: String = "res://assets/shaders/sword_slash_trail.gdshader"
const TRAUMA_HEAVY_HIT: float = 0.35
const TRAUMA_LANDING_SLAM: float = 0.60
const TRAUMA_PILLAR_COLLAPSE: float = 0.75
const TRAUMA_DAMAGE_TAKEN: float = 0.40
const TRAUMA_LIGHT_HIT: float = 0.06

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
var _coyote_timer: float = 0.0
var _pending_ground_slam: bool = false
var _pending_ground_slam_timer: float = 0.0
var _landing_recover_timer: float = 0.0
var _last_move_input_dir: Vector3 = Vector3.ZERO

var camera_trauma: float = 0.0
var _shake_offset: Vector3 = Vector3.ZERO
var _shake_time: float = 0.0
var _shake_noise: FastNoiseLite = null
var _hit_stop_active: bool = false
var _hit_stop_serial: int = 0
var _slash_shader: Shader = null


func _ready() -> void:
	add_to_group("player")
	health = max_health
	camera_yaw = global_rotation.y
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 0.001:
		set_facing_direction(fwd.normalized())
	_update_camera_pivot()
	if RealmManager.instance != null:
		RealmManager.instance.register_player(self)
	_load_mouse_settings_from_store()
	_update_mouse_capture_state()
	var sword: Hitbox3D = get_sword_hitbox()
	if sword != null and not sword.hit_landed.is_connected(_on_sword_hit_landed):
		sword.hit_landed.connect(_on_sword_hit_landed)
	health_changed.emit(health, max_health)


func _exit_tree() -> void:
	if _hit_stop_active:
		_hit_stop_active = false
		Engine.time_scale = 1.0
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _load_mouse_settings_from_store() -> void:
	var store: Node = _get_leaderboard_store()
	if store != null and store.has_method("get_settings"):
		var s: Dictionary = store.call("get_settings")
		mouse_sensitivity = float(s.get("mouse_sensitivity", 0.0025))
		invert_y = bool(s.get("invert_y", false))
		camera_shake_intensity = float(s.get("camera_shake_intensity", 1.0))
		hit_stop_enabled = bool(s.get("hit_stop_enabled", true))


func _process(delta: float) -> void:
	_update_mouse_capture_state()
	_update_camera_shake(delta)


func _unhandled_input(event: InputEvent) -> void:
	if current_state == State.DEAD:
		return
	if event is InputEventMouseButton and event.is_pressed():
		if DisplayServer.get_name() != "headless" and not _should_release_mouse():
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
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
	_update_camera_pivot()


func _update_camera_pivot() -> void:
	var cam_pivot: Node3D = get_node_or_null(camera_pivot_path) as Node3D
	if cam_pivot != null:
		if cam_pivot.is_inside_tree():
			cam_pivot.global_rotation = Vector3(camera_pitch + _shake_offset.x, camera_yaw + _shake_offset.y, _shake_offset.z)
		else:
			cam_pivot.rotation = Vector3(camera_pitch, wrapf(camera_yaw - global_rotation.y, -PI, PI), 0.0)


func _should_release_mouse() -> bool:
	if not is_inside_tree() or get_tree() == null:
		return false
	if get_tree().paused:
		return true
	for grp in ["title_screen", "pause_menu", "options_screen", "leaderboard_screen", "results_screen"]:
		for n in get_tree().get_nodes_in_group(grp):
			if n is CanvasItem and (n as CanvasItem).visible:
				return true
	return false


func _update_mouse_capture_state() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _should_release_mouse() or current_state == State.DEAD:
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func get_facing_direction() -> Vector3:
	if facing_direction.length_squared() > 0.001:
		return facing_direction.normalized()
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	return fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD


func set_facing_direction(dir: Vector3, delta: float = -1.0) -> void:
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() <= 0.0001:
		return
	facing_direction = flat.normalized()
	var target_world_yaw: float = atan2(-facing_direction.x, -facing_direction.z)
	var parent_yaw: float = global_rotation.y if is_inside_tree() else rotation.y
	var target_local_yaw: float = wrapf(target_world_yaw - parent_yaw, -PI, PI)

	var vis: Node3D = get_node_or_null(visual_root_path) as Node3D
	if vis != null:
		if delta > 0.0:
			vis.rotation.y = lerp_angle(vis.rotation.y, target_local_yaw, clampf(character_turn_speed * delta, 0.0, 1.0))
		else:
			vis.rotation.y = target_local_yaw
	var hb: Hitbox3D = get_sword_hitbox()
	if hb != null and hb.get_parent() == self:
		hb.rotation.y = target_local_yaw


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
	if current_state != State.LOCOMOTION or (is_currently_airborne() and _coyote_timer <= 0.0):
		return false
	_coyote_timer = 0.0
	velocity.y = jump_velocity
	jumped.emit()
	return true


func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return

	_update_camera_pivot()

	if _dodge_cooldown_timer > 0.0:
		_dodge_cooldown_timer = maxf(0.0, _dodge_cooldown_timer - delta)

	if _landing_recover_timer > 0.0:
		_landing_recover_timer = maxf(0.0, _landing_recover_timer - delta)

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
		State.STAGGER:
			_process_stagger_state(delta)
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

	if _last_move_input_dir.length_squared() > 0.001:
		set_facing_direction(_last_move_input_dir)

	var step_idx: int = clampi(combo_step, 0, light_combo_damages.size() - 1)
	var dmg: int = int(light_combo_damages[step_idx])
	var dur: float = float(light_attack_durations[step_idx])

	combo_step = (step_idx + 1) % light_combo_damages.size()
	_combo_window_timer = light_combo_reset_window
	_set_state(State.LIGHT_ATTACK, dur)

	var lunge_spd: float = 3.8 if step_idx < 2 else 5.2
	var fwd: Vector3 = get_facing_direction()
	velocity.x = fwd.x * lunge_spd
	velocity.z = fwd.z * lunge_spd

	var hb: Hitbox3D = get_sword_hitbox()
	if hb != null:
		hb.begin_swing(dmg, false, "player_light")

	_spawn_slash_arc_vfx(false, step_idx + 1)
	attack_executed.emit("light_" + str(step_idx + 1), step_idx + 1, dmg, false)
	return true


func start_heavy_attack() -> bool:
	if current_state != State.LOCOMOTION or is_currently_airborne():
		return false

	if _last_move_input_dir.length_squared() > 0.001:
		set_facing_direction(_last_move_input_dir)

	combo_step = 0
	_set_state(State.HEAVY_ATTACK, heavy_attack_duration)

	var fwd: Vector3 = get_facing_direction()
	velocity.x = fwd.x * 6.0
	velocity.z = fwd.z * 6.0

	var hb: Hitbox3D = get_sword_hitbox()
	if hb != null:
		hb.begin_swing(heavy_attack_damage, true, "player_heavy")

	_spawn_slash_arc_vfx(true, 0)
	attack_executed.emit("heavy", 0, heavy_attack_damage, true)
	return true


func start_dodge(input_dir: Vector3 = Vector3.ZERO) -> bool:
	if current_state != State.LOCOMOTION or (is_currently_airborne() and _coyote_timer <= 0.0) or _dodge_cooldown_timer > 0.0:
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

	_pending_ground_slam = false
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
	_pending_ground_slam = false
	_landing_recover_timer = landing_recovery_duration
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

	_spawn_landing_shockwave_vfx(global_position, landing_attack_radius)
	add_camera_trauma(TRAUMA_LANDING_SLAM)
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
	player_damaged.emit(amount)
	health_changed.emit(health, max_health)

	var run_state: Node = _get_run_state()
	if run_state != null and run_state.has_method("on_player_damaged"):
		run_state.call("on_player_damaged")

	add_camera_trauma(TRAUMA_DAMAGE_TAKEN)
	var is_heavy_strike: bool = amount > heavy_hit_stagger_threshold
	if is_heavy_strike or (_source != null and _source is WardenBoss):
		trigger_hit_stop()

	if health <= 0:
		_on_death()
	elif is_heavy_strike:
		_enter_stagger(_source)
	return true


func _enter_stagger(source: Node = null) -> void:
	## QA-A04: heavy incoming hits (> 20 HP) briefly flinch the player; light hits never lock locomotion.
	if current_state == State.DEAD or current_state == State.LANDING_PLUNGE:
		return
	var hb: Hitbox3D = get_sword_hitbox()
	if hb != null:
		hb.end_swing()
	_update_hurtbox_invulnerability(false)
	combo_step = 0
	_combo_window_timer = 0.0
	var push: Vector3 = -get_facing_direction()
	if source != null and source is Node3D and is_inside_tree() and (source as Node3D).is_inside_tree():
		var away: Vector3 = global_position - (source as Node3D).global_position
		away.y = 0.0
		if away.length_squared() > 0.0001:
			push = away.normalized()
	velocity.x = push.x * stagger_knockback_speed
	velocity.z = push.z * stagger_knockback_speed
	_set_state(State.STAGGER, heavy_hit_stagger_duration)


func _process_stagger_state(delta: float) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	if not is_on_floor():
		var grav: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * gravity_scale
		velocity.y -= grav * delta
	velocity.x = move_toward(velocity.x, 0.0, friction * 0.6 * delta)
	velocity.z = move_toward(velocity.z, 0.0, friction * 0.6 * delta)
	if is_inside_tree():
		move_and_slide()
	if _state_timer <= 0.0:
		_set_state(State.LOCOMOTION, 0.0)


# --- Game feel: hit-stop & trauma camera shake (QA-A02 / QA-A03) ---

func trigger_hit_stop(duration: float = -1.0) -> void:
	_load_mouse_settings_from_store()
	if not hit_stop_enabled or not is_inside_tree() or get_tree() == null:
		return
	var dur: float = hit_stop_duration if duration < 0.0 else duration
	if dur <= 0.0:
		return
	_hit_stop_serial += 1
	_hit_stop_active = true
	Engine.time_scale = hit_stop_time_scale
	# process_always = true, ignore_time_scale = true -> restores in real time even while paused / frozen.
	var t: SceneTreeTimer = get_tree().create_timer(dur, true, false, true)
	t.timeout.connect(_release_hit_stop.bind(_hit_stop_serial))


func _release_hit_stop(serial: int) -> void:
	if serial != _hit_stop_serial:
		return
	_hit_stop_active = false
	Engine.time_scale = 1.0


func is_hit_stop_active() -> bool:
	return _hit_stop_active


func add_camera_trauma(amount: float) -> void:
	if amount <= 0.0:
		return
	camera_trauma = clampf(camera_trauma + amount, 0.0, 1.0)


func _update_camera_shake(delta: float) -> void:
	if camera_trauma <= 0.0 and _shake_offset == Vector3.ZERO:
		return
	# Shake runs on real time so it keeps reading during hit-stop micro-freezes.
	var real_dt: float = minf(delta / maxf(Engine.time_scale, 0.01), 0.1)
	camera_trauma = maxf(0.0, camera_trauma - trauma_decay_per_sec * real_dt)
	if camera_trauma <= 0.0 or camera_shake_intensity <= 0.0:
		_shake_offset = Vector3.ZERO
		_update_camera_pivot()
		return
	if _shake_noise == null:
		_shake_noise = FastNoiseLite.new()
		_shake_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_shake_noise.seed = 1337
		_shake_noise.frequency = 0.08
	_shake_time += real_dt * shake_noise_speed
	var t2: float = camera_trauma * camera_trauma
	var t3: float = t2 * camera_trauma
	var k: float = clampf(camera_shake_intensity, 0.0, 1.0)
	_shake_offset = Vector3(
		deg_to_rad(shake_max_pitch_deg) * k * t2 * _shake_noise.get_noise_2d(_shake_time, 11.0),
		deg_to_rad(shake_max_yaw_deg) * k * t2 * _shake_noise.get_noise_2d(_shake_time, 47.0),
		deg_to_rad(shake_max_roll_deg) * k * t3 * _shake_noise.get_noise_2d(_shake_time, 91.0)
	)
	_update_camera_pivot()


func _on_sword_hit_landed(target: Node, _damage_dealt: int, is_heavy_hit: bool, source_type: String) -> void:
	var in_mirror: bool = RealmManager.instance != null and RealmManager.instance.current_realm == RealmManager.Realm.MIRROR and not RealmManager.instance.is_merged
	var rune_strike: bool = target is WardenBoss and (target as WardenBoss).is_chest_rune_exposed
	var hit_pos: Vector3 = global_position + Vector3(0.0, 1.0, 0.0) + get_facing_direction() * 0.9
	if target is Node3D and (target as Node3D).is_inside_tree():
		var t3d: Node3D = target as Node3D
		hit_pos = t3d.global_position + Vector3(0.0, 1.0, 0.0)
		var to_me: Vector3 = global_position - t3d.global_position
		to_me.y = 0.0
		if to_me.length_squared() > 0.0001:
			hit_pos += to_me.normalized() * 0.35
	var host: Node = get_parent() if get_parent() != null else self
	CombatVFXScript.spawn_impact_burst(host, hit_pos, in_mirror or rune_strike, is_heavy_hit)

	match source_type:
		"player_heavy":
			add_camera_trauma(TRAUMA_HEAVY_HIT)
			trigger_hit_stop()
		"player_landing":
			trigger_hit_stop()
		_:
			add_camera_trauma(TRAUMA_LIGHT_HIT)


func respawn_at(spawn_transform: Transform3D) -> void:
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	health = max_health
	combo_step = 0
	_combo_window_timer = 0.0
	_dodge_elapsed = 0.0
	_coyote_timer = 0.0
	_pending_ground_slam = false
	_landing_recover_timer = 0.0
	_simulated_airborne = false
	camera_yaw = global_rotation.y
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 0.001:
		set_facing_direction(fwd.normalized())
	_update_camera_pivot()
	_update_hurtbox_invulnerability(false)
	var hb: Hitbox3D = get_sword_hitbox()
	if hb != null:
		hb.end_swing()
	camera_trauma = 0.0
	_shake_offset = Vector3.ZERO
	_set_state(State.LOCOMOTION, 0.0)
	health_changed.emit(health, max_health)


func get_sword_hitbox() -> Hitbox3D:
	return get_node_or_null(sword_hitbox_path) as Hitbox3D


func get_hurtbox() -> Hurtbox3D:
	return get_node_or_null(hurtbox_path) as Hurtbox3D


func _process_locomotion_state(delta: float) -> void:
	var grav: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * gravity_scale
	if is_on_floor():
		_coyote_timer = 0.12
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)
		velocity.y -= grav * delta

	if _pending_ground_slam:
		_pending_ground_slam_timer = maxf(0.0, _pending_ground_slam_timer - delta)
		if _pending_ground_slam_timer <= 0.0 and is_currently_airborne():
			start_landing_attack()
			return
		elif _pending_ground_slam_timer <= 0.0:
			_pending_ground_slam = false

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
	_last_move_input_dir = move_dir
	var move_accel: float = acceleration if is_on_floor() else (acceleration * 0.55)
	var move_fric: float = friction if is_on_floor() else (friction * 0.20)

	if move_dir.length_squared() > 0.001 and _landing_recover_timer <= 0.0:
		set_facing_direction(move_dir, delta)
		velocity.x = move_toward(velocity.x, move_dir.x * run_speed, move_accel * delta)
		velocity.z = move_toward(velocity.z, move_dir.z * run_speed, move_accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_fric * delta)
		velocity.z = move_toward(velocity.z, 0.0, move_fric * delta)

	if Input.is_action_just_pressed("landing_attack"):
		if is_currently_airborne():
			start_landing_attack()
			return
		elif is_on_floor():
			velocity.y = landing_leap_velocity
			_pending_ground_slam = true
			_pending_ground_slam_timer = 0.14
			jumped.emit()
	if Input.is_action_just_pressed("light_attack") and _landing_recover_timer <= 0.0:
		if start_light_attack():
			return
	if Input.is_action_just_pressed("heavy_attack") and _landing_recover_timer <= 0.0:
		if start_heavy_attack():
			return

	var dodge_pressed: bool = Input.is_action_just_pressed("dodge")
	var jump_pressed: bool = Input.is_action_just_pressed("jump")
	if dodge_pressed and (is_on_floor() or _coyote_timer > 0.0):
		var d_dir: Vector3 = move_dir if move_dir.length_squared() > 0.001 else get_facing_direction()
		if start_dodge(d_dir):
			return
	if jump_pressed and (is_on_floor() or _coyote_timer > 0.0):
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

	if not is_on_floor():
		var grav: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * gravity_scale
		velocity.y -= grav * 0.65 * delta

	var dur: float = maxf(0.01, dodge_duration)
	var t_norm: float = clampf(_dodge_elapsed / dur, 0.0, 1.0)
	var cur_speed: float = dodge_speed * 1.22
	if t_norm > 0.55:
		var ease_out: float = (t_norm - 0.55) / 0.45
		cur_speed = lerpf(dodge_speed * 1.22, run_speed * 0.85, ease_out)

	velocity.x = _dodge_direction.x * cur_speed
	velocity.z = _dodge_direction.z * cur_speed
	if is_inside_tree():
		move_and_slide()

	if _state_timer <= 0.0:
		_update_hurtbox_invulnerability(false)
		_dodge_cooldown_timer = dodge_cooldown
		_set_state(State.LOCOMOTION, 0.0)


func _process_attack_state(delta: float) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	if not is_on_floor():
		var grav: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * gravity_scale
		velocity.y -= grav * delta
	velocity.x = move_toward(velocity.x, 0.0, friction * 0.55 * delta)
	velocity.z = move_toward(velocity.z, 0.0, friction * 0.55 * delta)
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


func _spawn_slash_arc_vfx(is_heavy: bool, step_num: int) -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	var vis: Node3D = get_node_or_null(visual_root_path) as Node3D
	if vis == null:
		return

	var in_mirror: bool = (RealmManager.instance != null and RealmManager.instance.current_realm == RealmManager.Realm.MIRROR)
	var slash_col: Color = Color(0.28, 0.82, 1.0, 0.9) if in_mirror else Color(1.0, 0.62, 0.18, 0.9)
	if is_heavy:
		slash_col = Color(0.38, 0.92, 1.0, 1.0) if in_mirror else Color(1.0, 0.40, 0.12, 1.0)

	# Ribbon sweep: angle 0 = straight ahead (-Z). Step 1 sweeps right->left, step 2 left->right,
	# step 3 / heavy are rolled into an overhead/diagonal chop.
	var inner_r: float = 0.55 if not is_heavy else 0.60
	var outer_r: float = 1.45 if not is_heavy else 1.95
	var start_deg: float = 80.0
	var end_deg: float = -80.0
	var roll_deg: float = -8.0
	match step_num:
		1:
			pass
		2:
			start_deg = -80.0
			end_deg = 80.0
			roll_deg = 28.0
		3:
			roll_deg = 78.0
		_:
			start_deg = 110.0
			end_deg = -110.0
			roll_deg = 62.0

	var arc := MeshInstance3D.new()
	arc.name = "SlashArcVFX"
	arc.mesh = CombatVFXScript.build_arc_ribbon_mesh(inner_r, outer_r, start_deg, end_deg, 32)
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arc.position = Vector3(0.0, 1.05, 0.0)
	arc.rotation = Vector3(0.06, 0.0, deg_to_rad(roll_deg))

	var sweep_time: float = 0.20 if is_heavy else 0.14
	var fade_time: float = 0.14 if is_heavy else 0.10
	if _slash_shader == null and ResourceLoader.exists(SLASH_TRAIL_SHADER_PATH):
		_slash_shader = load(SLASH_TRAIL_SHADER_PATH) as Shader

	var tw := create_tween()
	if _slash_shader != null:
		var smat := ShaderMaterial.new()
		smat.shader = _slash_shader
		smat.set_shader_parameter("slash_color", slash_col)
		smat.set_shader_parameter("intensity", 2.8 if is_heavy else 2.2)
		smat.set_shader_parameter("trail_length", 0.70 if is_heavy else 0.55)
		smat.set_shader_parameter("progress", 0.0)
		smat.set_shader_parameter("fade", 1.0)
		arc.material_override = smat
		vis.add_child(arc)
		var end_progress: float = 1.0 + (0.70 if is_heavy else 0.55)
		tw.tween_property(smat, "shader_parameter/progress", end_progress, sweep_time + fade_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(smat, "shader_parameter/fade", 0.0, fade_time).set_delay(sweep_time)
	else:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = slash_col
		arc.material_override = mat
		vis.add_child(arc)
		tw.tween_property(mat, "albedo_color:a", 0.0, sweep_time + fade_time)
	tw.tween_callback(arc.queue_free)


func _spawn_landing_shockwave_vfx(impact_pos: Vector3, radius: float) -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	var host: Node = get_parent() if get_parent() != null else get_tree().current_scene
	if host == null:
		return

	var ring := MeshInstance3D.new()
	ring.name = "LandingShockwaveVFX"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.65
	torus.outer_radius = 0.95
	torus.rings = 32
	torus.ring_segments = 10
	ring.mesh = torus

	var in_mirror: bool = (RealmManager.instance != null and RealmManager.instance.current_realm == RealmManager.Realm.MIRROR)
	var col: Color = Color(0.28, 0.85, 1.0, 0.92) if in_mirror else Color(1.0, 0.68, 0.22, 0.92)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.8
	ring.material_override = mat
	ring.scale = Vector3(0.4, 0.16, 0.4)
	host.add_child(ring)
	ring.global_position = Vector3(impact_pos.x, impact_pos.y + 0.10, impact_pos.z)

	var target_scale: float = maxf(1.5, radius)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(target_scale, 0.05, target_scale), 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.36)
	tw.chain().tween_callback(ring.queue_free)
