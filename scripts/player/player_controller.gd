class_name PlayerController
extends CharacterBody3D
## Third-person player: weighty locomotion (momentum sprint, variable-height jump, apex hang, fast fall,
## jump buffer, coyote time, one air-dash), phase-based melee (anticipation -> strike -> recovery) with
## input buffering, cancel windows, target magnetism, a 3-hit Light chain, Heavy Cleave / Whirlwind
## branch, Landing Plunge, perfect-dodge slow-mo, and shield-deflect recoil.
## Visual juice (camera, trail, squash/stretch, dust) lives in `PlayerFeelRig`; gore lives on enemies.

const GameFeelScript := preload("res://scripts/core/game_feel.gd")
const GoreFXScript := preload("res://scripts/core/gore_fx.gd")
const SquadCoordinatorScript := preload("res://scripts/enemies/squad_coordinator.gd")
const PlayerFeelRigScript := preload("res://scripts/player/player_feel_rig.gd")

enum State {
	LOCOMOTION = 0,
	DODGE = 1,
	LIGHT_ATTACK = 2,
	HEAVY_ATTACK = 3,
	LANDING_PLUNGE = 4,
	STAGGER = 5,
	DEAD = 6,
}

enum AttackPhase {
	NONE = 0,
	WINDUP = 1,
	ACTIVE = 2,
	RECOVERY = 3,
}

signal health_changed(current_hp: int, max_hp: int)
signal player_damaged(amount: int)
signal jumped()
signal player_died()
signal state_changed(new_state: int)
## Emitted on the strike frame (hitbox goes live) so swing SFX line up with the blade.
signal attack_executed(attack_name: String, combo_step: int, damage: int, is_heavy: bool)
## Emitted on button press / chain with the full timing dictionary (animation + feel rig use it).
signal attack_started(attack_name: String, timing: Dictionary)
signal attack_phase_changed(phase: int, attack_name: String)
signal hit_confirmed(target: Node, attack_name: String, killed: bool)
signal attack_deflected(is_heavy: bool)
signal dodge_started(direction: Vector3, duration: float)
signal perfect_dodge()
signal landed(impact_speed: float)
signal skidded()
signal landing_slam_triggered(impact_position: Vector3, radius: float, damage: int)
signal interact_requested()

## Per-attack timing & feel. Clip times are seconds into the KayKit clip (contact = blade peak speed,
## measured from the rig's hand.r velocity). `lunge` = metres travelled when no target is magnetised.
const ATTACK_DEFS: Dictionary = {
	"light_1": {
		"clip": "1H_Melee_Attack_Slice_Horizontal", "clip_start": 0.04, "clip_contact": 0.28, "clip_end": 0.80,
		"windup": 0.11, "active": 0.10, "recovery": 0.26, "cancel": 0.30,
		"lunge": 1.0, "reach": 2.35, "arc": 120.0, "knockback": 3.2,
		"hitstop": 0.050, "trauma": 0.16, "twist": -0.6, "fov_kick": 1.5, "trail": 1.0,
	},
	"light_2": {
		"clip": "1H_Melee_Attack_Slice_Diagonal", "clip_start": 0.10, "clip_contact": 0.42, "clip_end": 0.82,
		"windup": 0.11, "active": 0.10, "recovery": 0.26, "cancel": 0.30,
		"lunge": 1.1, "reach": 2.35, "arc": 120.0, "knockback": 3.6,
		"hitstop": 0.055, "trauma": 0.18, "twist": 0.6, "fov_kick": 1.5, "trail": 1.0,
	},
	"light_3": {
		"clip": "1H_Melee_Attack_Chop", "clip_start": 0.16, "clip_contact": 0.50, "clip_end": 0.98,
		"windup": 0.17, "active": 0.10, "recovery": 0.36, "cancel": 0.40,
		"lunge": 1.7, "reach": 2.6, "arc": 90.0, "knockback": 7.5,
		"hitstop": 0.090, "trauma": 0.42, "twist": 0.0, "fov_kick": -3.0, "trail": 1.25,
		"finisher": true, "crack": 2.2,
	},
	"heavy": {
		"clip": "2H_Melee_Attack_Chop", "clip_start": 0.22, "clip_contact": 0.75, "clip_end": 1.40,
		"windup": 0.30, "active": 0.12, "recovery": 0.42, "cancel": 0.45,
		"lunge": 1.9, "reach": 3.0, "arc": 70.0, "line": 4.2, "knockback": 9.5,
		"hitstop": 0.120, "trauma": 0.62, "twist": 0.0, "fov_kick": -5.0, "trail": 1.5,
		"finisher": true, "crack": 4.2,
	},
	"heavy_spin": {
		"clip": "2H_Melee_Attack_Spin", "clip_start": 0.42, "clip_contact": 0.98, "clip_end": 1.80,
		"windup": 0.15, "active": 0.30, "recovery": 0.34, "cancel": 0.45,
		"lunge": 0.9, "reach": 2.8, "arc": 360.0, "knockback": 8.0,
		"hitstop": 0.085, "trauma": 0.50, "twist": 0.0, "fov_kick": 4.0, "trail": 1.4,
		"finisher": true, "ring": 2.8,
	},
}

@export_group("Health & Survival")
@export var max_health: int = 100

@export_group("Locomotion")
@export var run_speed: float = 6.0
@export var sprint_speed: float = 7.6
@export var sprint_ramp_time: float = 1.1
@export var acceleration: float = 46.0
@export var friction: float = 40.0
@export var air_acceleration: float = 20.0
@export var jump_velocity: float = 7.8
@export var gravity_scale: float = 1.6
@export var fall_gravity_mult: float = 1.75
@export var jump_cut_gravity_mult: float = 2.3
@export var apex_hang_gravity_mult: float = 0.55
@export var apex_hang_threshold: float = 1.3
@export var max_fall_speed: float = 26.0
@export var jump_buffer_time: float = 0.13
@export var coyote_time: float = 0.12

@export_group("Dodge")
@export var dodge_duration: float = 0.42
@export var dodge_speed: float = 10.5
@export var dodge_iframe_start: float = 0.03
@export var dodge_iframe_duration: float = 0.26
@export var dodge_cooldown: float = 0.14
@export var allow_air_dash: bool = true
@export var perfect_dodge_slowmo_scale: float = 0.3
@export var perfect_dodge_slowmo_time: float = 0.55

@export_group("Combat Tuning")
@export var light_combo_damages: PackedInt32Array = PackedInt32Array([25, 25, 35])
@export var light_combo_reset_window: float = 0.90
@export var heavy_attack_damage: int = 60
@export var landing_attack_damage: int = 60
@export var landing_attack_radius: float = 2.6
@export var landing_plunge_speed: float = 22.0
@export var landing_leap_velocity: float = 8.5
@export var landing_recovery_duration: float = 0.28
@export var input_buffer_time: float = 0.24
@export var magnet_range: float = 4.8
@export var magnet_half_angle_deg: float = 75.0
@export var magnet_stop_distance: float = 1.25

@export_group("Node References")
@export var camera_pivot_path: NodePath = NodePath("CameraPivot")
@export var sword_hitbox_path: NodePath = NodePath("SwordHitbox")
@export var hurtbox_path: NodePath = NodePath("Hurtbox3D")
@export var visual_root_path: NodePath = NodePath("VisualRoot")

@export_group("Camera & Facing")
@export var pitch_min_degrees: float = -45.0
@export var pitch_max_degrees: float = 60.0
@export var character_turn_speed: float = 18.0

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
var attack_phase: AttackPhase = AttackPhase.NONE
var current_attack_name: String = ""
var current_attack: Dictionary = {}
var current_target: Node3D = null
var run_time: float = 0.0

var _combo_window_timer: float = 0.0
var _state_timer: float = 0.0
var _attack_elapsed: float = 0.0
var _attack_damage: int = 0
var _attack_heavy: bool = false
var _attack_hits: int = 0
var _lunge_distance: float = 0.0
var _dodge_elapsed: float = 0.0
var _dodge_cooldown_timer: float = 0.0
var _dodge_direction: Vector3 = Vector3.BACK
var _perfect_dodge_spent: bool = false
var _air_dash_used: bool = false
var _simulated_airborne: bool = false
var _force_jump_context: bool = false
var _jump_zone_overlaps: int = 0
var _nearby_interactables: Array[Node] = []
var _coyote_timer: float = 0.0
var _jump_held: bool = false
var _was_on_floor: bool = true
var _last_air_vy: float = 0.0
var _pending_ground_slam: bool = false
var _pending_ground_slam_timer: float = 0.0
var _plunge_hang_timer: float = 0.0
var _landing_recover_timer: float = 0.0
var _last_move_input_dir: Vector3 = Vector3.ZERO
var _buffer_action: String = ""
var _buffer_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _prev_move_dir: Vector3 = Vector3.ZERO


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
	var hurt: Hurtbox3D = get_hurtbox()
	if hurt != null and not hurt.hit_blocked_invulnerable.is_connected(_on_hit_dodged):
		hurt.hit_blocked_invulnerable.connect(_on_hit_dodged)
	if get_node_or_null("PlayerFeelRig") == null:
		var rig: Node = PlayerFeelRigScript.new()
		rig.name = "PlayerFeelRig"
		add_child(rig)
	health_changed.emit(health, max_health)


func _exit_tree() -> void:
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


func _process(_delta: float) -> void:
	_update_mouse_capture_state()


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
	camera_yaw -= relative_motion.x * mouse_sensitivity
	var y_sign: float = 1.0 if invert_y else -1.0
	camera_pitch = clampf(
		camera_pitch + relative_motion.y * mouse_sensitivity * y_sign,
		deg_to_rad(pitch_min_degrees),
		deg_to_rad(pitch_max_degrees)
	)
	_update_camera_pivot()


func _update_camera_pivot() -> void:
	var cam_pivot: Node3D = get_node_or_null(camera_pivot_path) as Node3D
	if cam_pivot != null:
		if cam_pivot.is_inside_tree():
			cam_pivot.global_rotation = Vector3(camera_pitch, camera_yaw, 0.0)
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


func get_visual_yaw() -> float:
	var vis: Node3D = get_node_or_null(visual_root_path) as Node3D
	return vis.global_rotation.y if vis != null and vis.is_inside_tree() else rotation.y


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
		var step_origin: Vector3 = global_position + Vector3(0.0, 0.55, 0.0)
		var step_end: Vector3 = step_origin + flat_dir * 1.45
		var step_q := PhysicsRayQueryParameters3D.create(step_origin, step_end, mask, [get_rid()])
		if not space.intersect_ray(step_q).is_empty():
			return true
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
	_jump_buffer_timer = 0.0
	_jump_held = true
	velocity.y = jump_velocity
	# Carry sprint momentum into the jump so long jumps feel earned.
	jumped.emit()
	return true


# ------------------------------------------------------------------ main loop

func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return

	_update_camera_pivot()
	_poll_action_inputs(delta)

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

	_track_landing()


## Every press is buffered so inputs during an attack/dodge chain the moment a cancel window opens.
func _poll_action_inputs(delta: float) -> void:
	if _buffer_timer > 0.0:
		_buffer_timer = maxf(0.0, _buffer_timer - delta)
		if _buffer_timer <= 0.0:
			_buffer_action = ""
	if _jump_buffer_timer > 0.0:
		_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - delta)
	if not InputMap.has_action("light_attack"):
		return
	if Input.is_action_just_pressed("light_attack"):
		_buffer("light")
	if Input.is_action_just_pressed("heavy_attack"):
		_buffer("heavy")
	if Input.is_action_just_pressed("dodge"):
		_buffer("dodge")
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
		if current_state != State.LOCOMOTION:
			_buffer("jump")
	if Input.is_action_just_pressed("landing_attack"):
		_buffer("plunge")
	if not Input.is_action_pressed("jump"):
		_jump_held = false


func _buffer(action: String) -> void:
	_buffer_action = action
	_buffer_timer = input_buffer_time


func _consume_buffer() -> String:
	var a: String = _buffer_action
	_buffer_action = ""
	_buffer_timer = 0.0
	return a


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


# ------------------------------------------------------------------ attacks

func get_attack_def(attack_name: String) -> Dictionary:
	return ATTACK_DEFS.get(attack_name, {}) as Dictionary


func get_attack_elapsed() -> float:
	return _attack_elapsed


func get_attack_total_duration(attack_name: String) -> float:
	var d: Dictionary = get_attack_def(attack_name)
	return float(d.get("windup", 0.1)) + float(d.get("active", 0.1)) + float(d.get("recovery", 0.2))


func start_light_attack() -> bool:
	if not _can_start_attack():
		return false
	var step_idx: int = clampi(combo_step, 0, light_combo_damages.size() - 1)
	var attack_name: String = "light_%d" % (step_idx + 1)
	combo_step = (step_idx + 1) % light_combo_damages.size()
	_combo_window_timer = light_combo_reset_window
	_begin_attack(attack_name, int(light_combo_damages[step_idx]), false, State.LIGHT_ATTACK)
	return true


func start_heavy_attack() -> bool:
	if not _can_start_attack():
		return false
	# Heavy pressed mid-chain branches into the Whirlwind; from neutral it is the overhead Cleave.
	var chained: bool = combo_step > 0 and (current_state != State.LOCOMOTION or _combo_window_timer > 0.0)
	combo_step = 0
	_combo_window_timer = 0.0
	_begin_attack("heavy_spin" if chained else "heavy", heavy_attack_damage, true, State.HEAVY_ATTACK)
	return true


func _can_start_attack() -> bool:
	if is_currently_airborne():
		return false
	if current_state == State.LOCOMOTION:
		return _landing_recover_timer <= 0.0
	# Chaining from an attack's cancel window
	return (current_state == State.LIGHT_ATTACK or current_state == State.HEAVY_ATTACK) and _in_cancel_window()


func _begin_attack(attack_name: String, damage: int, heavy: bool, state: State) -> void:
	var hb: Hitbox3D = get_sword_hitbox()
	if hb != null:
		hb.end_swing()
	current_attack_name = attack_name
	current_attack = get_attack_def(attack_name)
	_attack_damage = damage
	_attack_heavy = heavy
	_attack_elapsed = 0.0
	_attack_hits = 0

	var has_input: bool = _last_move_input_dir.length_squared() > 0.001
	var dir_hint: Vector3 = _last_move_input_dir if has_input else get_facing_direction()
	current_target = _acquire_target(dir_hint, magnet_range * (1.15 if heavy else 1.0))
	if current_target == null and not has_input:
		# Stick neutral: swing at whoever is crowding us, even from behind.
		current_target = _acquire_target(dir_hint, 2.8, true)
	if current_target != null:
		var to_t: Vector3 = current_target.global_position - global_position
		to_t.y = 0.0
		set_facing_direction(to_t)
		_lunge_distance = clampf(to_t.length() - magnet_stop_distance, 0.0, float(current_attack.get("lunge", 1.0)) * 1.8)
	else:
		set_facing_direction(dir_hint)
		_lunge_distance = float(current_attack.get("lunge", 1.0)) * 0.7
	velocity.x = 0.0
	velocity.z = 0.0

	var total: float = get_attack_total_duration(attack_name)
	_set_state(state, total)
	_set_attack_phase(AttackPhase.WINDUP)
	var timing: Dictionary = current_attack.duplicate()
	timing["total"] = total
	timing["name"] = attack_name
	attack_started.emit(attack_name, timing)
	SquadCoordinatorScript.notify_player_attack(self, heavy, float(current_attack.get("windup", 0.1)))


func _set_attack_phase(phase: AttackPhase) -> void:
	if attack_phase == phase:
		return
	attack_phase = phase
	attack_phase_changed.emit(int(phase), current_attack_name)


func _in_cancel_window() -> bool:
	if current_attack.is_empty():
		return true
	var w: float = float(current_attack.get("windup", 0.1))
	var a: float = float(current_attack.get("active", 0.1))
	var r: float = float(current_attack.get("recovery", 0.2))
	return _attack_elapsed >= w + a + r * float(current_attack.get("cancel", 0.35))


func _process_attack_state(delta: float) -> void:
	_attack_elapsed += delta
	_state_timer = maxf(0.0, _state_timer - delta)
	var w: float = float(current_attack.get("windup", 0.1))
	var a: float = float(current_attack.get("active", 0.1))

	# Track the magnetised target through the wind-up (souls-like "tracking" that ends at the strike).
	if attack_phase == AttackPhase.WINDUP and is_instance_valid(current_target):
		var to_t: Vector3 = current_target.global_position - global_position
		to_t.y = 0.0
		if to_t.length_squared() > 0.01:
			set_facing_direction(get_facing_direction().slerp(to_t.normalized(), clampf(12.0 * delta, 0.0, 1.0)))

	var fwd: Vector3 = get_facing_direction()
	if _attack_elapsed < w:
		# Anticipation: plant feet, a small creep forward.
		var v_w: float = (_lunge_distance * 0.18) / maxf(0.01, w)
		velocity.x = fwd.x * v_w
		velocity.z = fwd.z * v_w
	elif _attack_elapsed < w + a:
		if attack_phase != AttackPhase.ACTIVE:
			_enter_strike()
		var v_a: float = (_lunge_distance * 0.82) / maxf(0.01, a)
		if is_instance_valid(current_target):
			var gap: float = Vector2(current_target.global_position.x - global_position.x, current_target.global_position.z - global_position.z).length()
			if gap <= magnet_stop_distance:
				v_a = 0.0
		velocity.x = fwd.x * v_a
		velocity.z = fwd.z * v_a
		_sweep_strike_targets()
	else:
		if attack_phase == AttackPhase.ACTIVE or attack_phase == AttackPhase.WINDUP:
			if attack_phase == AttackPhase.WINDUP:
				_enter_strike()
				_sweep_strike_targets()
			_enter_recovery()
		velocity.x = move_toward(velocity.x, 0.0, friction * 1.2 * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * 1.2 * delta)

	if not is_on_floor():
		velocity.y = maxf(velocity.y - _base_gravity() * delta, -max_fall_speed)
	if is_inside_tree():
		move_and_slide()

	# Cancels: dodge any time outside the strike frames, attacks/jump inside the recovery cancel window.
	if _buffer_action == "dodge" and attack_phase != AttackPhase.ACTIVE:
		_consume_buffer()
		_abort_attack()
		_set_state(State.LOCOMOTION, 0.0)
		var cancel_dir: Vector3 = _read_move_dir()
		start_dodge(cancel_dir if cancel_dir.length_squared() > 0.001 else -get_facing_direction())
		return
	if _in_cancel_window() and not _buffer_action.is_empty():
		var act: String = _consume_buffer()
		match act:
			"light":
				_finish_attack_cleanup()
				if start_light_attack():
					return
			"heavy":
				_finish_attack_cleanup()
				if start_heavy_attack():
					return
			"jump":
				_abort_attack()
				_set_state(State.LOCOMOTION, 0.0)
				start_jump()
				return

	if _state_timer <= 0.0:
		_abort_attack()
		_combo_window_timer = light_combo_reset_window if current_state == State.LIGHT_ATTACK else 0.0
		if current_attack_name == "light_3" or current_state == State.HEAVY_ATTACK:
			combo_step = 0
		_set_state(State.LOCOMOTION, 0.0)


func _enter_strike() -> void:
	_set_attack_phase(AttackPhase.ACTIVE)
	var hb: Hitbox3D = get_sword_hitbox()
	if hb != null:
		var src: String = "player_heavy" if _attack_heavy else "player_light"
		hb.begin_swing(_attack_damage, _attack_heavy, src)
	var step_num: int = 0
	if current_attack_name.begins_with("light_"):
		step_num = int(current_attack_name.substr(6))
	attack_executed.emit(current_attack_name, step_num, _attack_damage, _attack_heavy)
	if current_attack.has("crack"):
		_spawn_ground_crack(float(current_attack["crack"]))
	if current_attack.has("ring"):
		GoreFXScript.shockwave_ring(self, global_position, float(current_attack["ring"]), _realm_color(0.9), 0.32, 0.22)


func _enter_recovery() -> void:
	_set_attack_phase(AttackPhase.RECOVERY)
	var hb: Hitbox3D = get_sword_hitbox()
	if hb != null:
		hb.end_swing()


func _finish_attack_cleanup() -> void:
	var hb: Hitbox3D = get_sword_hitbox()
	if hb != null:
		hb.end_swing()


func _abort_attack() -> void:
	_finish_attack_cleanup()
	_set_attack_phase(AttackPhase.NONE)
	current_target = null


## Manual strike-shape query every active frame, in addition to Area3D overlap signals, so fast lunges
## never tunnel past enemies and shape (arc / line / 360 ring) matches what the trail shows.
func _sweep_strike_targets() -> void:
	var hb: Hitbox3D = get_sword_hitbox()
	if hb == null or not hb.is_swing_active or not is_inside_tree():
		return
	var my_hurt: Hurtbox3D = get_hurtbox()
	var fwd: Vector3 = get_facing_direction()
	var reach: float = float(current_attack.get("reach", 2.3))
	var half_arc: float = deg_to_rad(float(current_attack.get("arc", 110.0)) * 0.5)
	var line_len: float = float(current_attack.get("line", 0.0))
	for n in get_tree().get_nodes_in_group("hurtbox"):
		var h: Hurtbox3D = n as Hurtbox3D
		if h == null or h == my_hurt or h.is_player_hurtbox or h.is_invulnerable or not h.monitorable:
			continue
		var actor: Node3D = h.get_owner_actor() as Node3D
		if actor == null or not actor.is_inside_tree():
			continue
		var rel: Vector3 = actor.global_position - global_position
		if absf(rel.y) > 2.2:
			continue
		rel.y = 0.0
		var dist: float = rel.length()
		var inside: bool = false
		if dist < 0.9:
			inside = true
		elif dist <= reach + 0.35:
			inside = fwd.angle_to(rel / dist) <= half_arc
		if not inside and line_len > 0.0:
			var along: float = rel.dot(fwd)
			var lateral: float = (rel - fwd * along).length()
			inside = along > 0.0 and along <= line_len and lateral <= 1.0
		if inside:
			hb.try_hit_target(h)


## Best enemy to swing at: in range, inside the cone around the stick / facing, nearest-and-most-centred.
func _acquire_target(dir_hint: Vector3, max_range: float, any_direction: bool = false) -> Node3D:
	if not is_inside_tree():
		return null
	var hint: Vector3 = Vector3(dir_hint.x, 0.0, dir_hint.z)
	hint = hint.normalized() if hint.length_squared() > 0.001 else get_facing_direction()
	var best: Node3D = null
	var best_score: float = INF
	var cos_limit: float = -1.01 if any_direction else cos(deg_to_rad(magnet_half_angle_deg))
	for n in get_tree().get_nodes_in_group("enemy"):
		var e: EnemyBase = n as EnemyBase
		if e == null or e.is_dead or not e.is_active or not e.is_inside_tree():
			continue
		var rel: Vector3 = e.global_position - global_position
		if absf(rel.y) > 2.0:
			continue
		rel.y = 0.0
		var dist: float = rel.length()
		if dist > max_range or dist < 0.01:
			continue
		var c: float = hint.dot(rel / dist)
		if c < cos_limit:
			continue
		var score: float = dist + (1.0 - c) * 4.0
		if score < best_score:
			best_score = score
			best = e
	return best


func _on_sword_hit_landed(target: Node, _damage_dealt: int, _is_heavy_hit: bool, source_type: String) -> void:
	_attack_hits += 1
	var killed: bool = target is EnemyBase and (target as EnemyBase).is_dead
	var stop: float = float(current_attack.get("hitstop", 0.05))
	var trauma: float = float(current_attack.get("trauma", 0.15))
	if source_type == "player_landing":
		stop = 0.11
		trauma = 0.0  # slam already shakes
	if killed:
		stop = maxf(stop, 0.10) + 0.03
		trauma += 0.15
	# Multi-hit swings shouldn't stack freeze length.
	if _attack_hits <= 1 or killed:
		GameFeelScript.hitstop(self, stop)
	if trauma > 0.0:
		GameFeelScript.add_trauma(self, trauma)
	if killed:
		_maybe_kill_cam()
	hit_confirmed.emit(target, current_attack_name if source_type != "player_landing" else "landing_plunge", killed)


## Last enemy of a fight dies -> brief dramatic slow motion.
func _maybe_kill_cam() -> void:
	if not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group("enemy"):
		var e: EnemyBase = n as EnemyBase
		if e != null and not e.is_dead and e.is_active and e.global_position.distance_to(global_position) < 22.0:
			return
	GameFeelScript.slowmo(self, 0.22, 0.42)


## Compatibility API (used by BreakableProp pillar collapse and older callers): routed into GameFeel.
func add_camera_trauma(amount: float) -> void:
	GameFeelScript.add_trauma(self, amount)


func trigger_hit_stop(duration: float = -1.0) -> void:
	GameFeelScript.hitstop(self, 0.06 if duration < 0.0 else duration)


func is_hit_stop_active() -> bool:
	return Engine.time_scale < 0.99


## Called by a shield (EnemyBase) that fully blocked this swing: bounce the blade off.
func on_attack_deflected(is_heavy: bool, _contact: Vector3 = Vector3.ZERO) -> void:
	if current_state != State.LIGHT_ATTACK and current_state != State.HEAVY_ATTACK:
		return
	if is_heavy:
		GameFeelScript.hitstop(self, 0.07)
		GameFeelScript.add_trauma(self, 0.3)
		attack_deflected.emit(true)
		return
	_enter_recovery()
	var w: float = float(current_attack.get("windup", 0.1))
	var a: float = float(current_attack.get("active", 0.1))
	_attack_elapsed = maxf(_attack_elapsed, w + a)
	_state_timer = maxf(_state_timer, 0.32)
	var back: Vector3 = -get_facing_direction() * 4.5
	velocity.x = back.x
	velocity.z = back.z
	combo_step = 0
	GameFeelScript.hitstop(self, 0.06)
	GameFeelScript.add_trauma(self, 0.25)
	attack_deflected.emit(false)


# ------------------------------------------------------------------ dodge / plunge

func start_dodge(input_dir: Vector3 = Vector3.ZERO) -> bool:
	if _dodge_cooldown_timer > 0.0:
		return false
	if current_state != State.LOCOMOTION:
		return false
	var airborne: bool = is_currently_airborne() and _coyote_timer <= 0.0
	if airborne:
		if not allow_air_dash or _air_dash_used:
			return false
		_air_dash_used = true

	if input_dir.length_squared() > 0.001:
		set_facing_direction(input_dir)
		_dodge_direction = Vector3(input_dir.x, 0.0, input_dir.z).normalized()
	else:
		_dodge_direction = get_facing_direction()
	velocity.y = 0.0 if airborne else minf(velocity.y, 0.0)
	_dodge_elapsed = 0.0
	_perfect_dodge_spent = false
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
	_plunge_hang_timer = 0.10
	_set_state(State.LANDING_PLUNGE, 2.0)
	velocity = Vector3(0.0, 2.2, 0.0)
	attack_executed.emit("landing_plunge", 0, landing_attack_damage, true)
	attack_started.emit("landing_plunge", {"name": "landing_plunge", "total": 0.45})
	return true


func complete_landing_slam(candidates: Array[Node] = []) -> int:
	if current_state != State.LANDING_PLUNGE:
		return 0

	_simulated_airborne = false
	_pending_ground_slam = false
	_landing_recover_timer = landing_recovery_duration
	_last_air_vy = 0.0
	_was_on_floor = true
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

	GameFeelScript.add_trauma(self, 0.7)
	if hits == 0:
		GameFeelScript.hitstop(self, 0.06)
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


# ------------------------------------------------------------------ damage

func apply_damage(amount: int, _source: Node = null) -> bool:
	if amount <= 0 or current_state == State.DEAD:
		return false
	if is_invulnerable():
		_on_hit_dodged(_source)
		return false

	health = maxi(0, health - amount)
	player_damaged.emit(amount)
	health_changed.emit(health, max_health)

	var run_state: Node = _get_run_state()
	if run_state != null and run_state.has_method("on_player_damaged"):
		run_state.call("on_player_damaged")

	GameFeelScript.add_trauma(self, clampf(0.25 + float(amount) / 40.0, 0.3, 0.75))
	GameFeelScript.hitstop(self, 0.05 if amount < 20 else 0.08)

	if health <= 0:
		_on_death()
	elif amount >= 20 and current_state != State.LANDING_PLUNGE:
		_enter_stagger(_source, amount)
	return true


func _on_hit_dodged(_attacker: Node) -> void:
	if current_state != State.DODGE or _perfect_dodge_spent:
		return
	_perfect_dodge_spent = true
	GameFeelScript.slowmo(self, perfect_dodge_slowmo_scale, perfect_dodge_slowmo_time)
	perfect_dodge.emit()


func _enter_stagger(source: Node, amount: int) -> void:
	_abort_attack()
	_update_hurtbox_invulnerability(false)
	combo_step = 0
	_combo_window_timer = 0.0
	var push: Vector3 = -get_facing_direction()
	if source is Node3D and (source as Node3D).is_inside_tree():
		var away: Vector3 = global_position - (source as Node3D).global_position
		away.y = 0.0
		if away.length_squared() > 0.0001:
			push = away.normalized()
	var kb: float = 3.0 + float(amount) * 0.08
	velocity.x = push.x * kb
	velocity.z = push.z * kb
	_set_state(State.STAGGER, 0.22 if amount < 22 else 0.34)


func _process_stagger_state(delta: float) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	if not is_on_floor():
		velocity.y = maxf(velocity.y - _base_gravity() * delta, -max_fall_speed)
	velocity.x = move_toward(velocity.x, 0.0, friction * 0.5 * delta)
	velocity.z = move_toward(velocity.z, 0.0, friction * 0.5 * delta)
	if is_inside_tree():
		move_and_slide()
	if _state_timer <= 0.0:
		_set_state(State.LOCOMOTION, 0.0)
		if _buffer_action == "dodge":
			_consume_buffer()
			start_dodge(_read_move_dir())


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
	_air_dash_used = false
	_buffer_action = ""
	run_time = 0.0
	camera_yaw = global_rotation.y
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 0.001:
		set_facing_direction(fwd.normalized())
	_update_camera_pivot()
	_update_hurtbox_invulnerability(false)
	_abort_attack()
	_set_state(State.LOCOMOTION, 0.0)
	health_changed.emit(health, max_health)


func get_sword_hitbox() -> Hitbox3D:
	return get_node_or_null(sword_hitbox_path) as Hitbox3D


func get_hurtbox() -> Hurtbox3D:
	return get_node_or_null(hurtbox_path) as Hurtbox3D


# ------------------------------------------------------------------ locomotion

func _base_gravity() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * gravity_scale


## Gravity shaped for feel: full arc while the button is held, heavy cut when released early,
## floaty apex hang, and a faster fall so jumps read as committed and land with weight.
func _shaped_gravity() -> float:
	var g: float = _base_gravity()
	if velocity.y > 0.0:
		if not _jump_held:
			return g * jump_cut_gravity_mult
		if velocity.y < apex_hang_threshold:
			return g * apex_hang_gravity_mult
		return g
	if velocity.y > -apex_hang_threshold and _jump_held:
		return g * apex_hang_gravity_mult
	return g * fall_gravity_mult


func _read_move_dir() -> Vector3:
	if not InputMap.has_action("move_left"):
		return Vector3.ZERO
	var input_vec: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis_ref: Basis = global_transform.basis
	var cam_pivot: Node3D = get_node_or_null(camera_pivot_path) as Node3D
	if cam_pivot != null and cam_pivot.is_inside_tree():
		basis_ref = cam_pivot.global_transform.basis
	var forward: Vector3 = -basis_ref.z
	forward.y = 0.0
	forward = forward.normalized()
	var right: Vector3 = basis_ref.x
	right.y = 0.0
	right = right.normalized()
	var v: Vector3 = right * input_vec.x + forward * (-input_vec.y)
	# Keep analogue magnitude (walk vs run) but never exceed 1.
	return v if v.length() <= 1.0 else v.normalized()


func _process_locomotion_state(delta: float) -> void:
	var on_floor: bool = is_on_floor()
	if on_floor:
		_coyote_timer = coyote_time
		_air_dash_used = false
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)
		velocity.y = maxf(velocity.y - _shaped_gravity() * delta, -max_fall_speed)

	if _pending_ground_slam:
		_pending_ground_slam_timer = maxf(0.0, _pending_ground_slam_timer - delta)
		if _pending_ground_slam_timer <= 0.0 and is_currently_airborne():
			start_landing_attack()
			return
		elif _pending_ground_slam_timer <= 0.0:
			_pending_ground_slam = false

	var move_dir: Vector3 = _read_move_dir()
	_last_move_input_dir = move_dir.normalized() if move_dir.length_squared() > 0.001 else Vector3.ZERO
	var input_mag: float = clampf(move_dir.length(), 0.0, 1.0)

	# Momentum sprint: holding a direction ramps toward sprint speed; sharp reversals skid.
	if on_floor and input_mag > 0.6 and _landing_recover_timer <= 0.0:
		if _prev_move_dir.length_squared() > 0.001 and _prev_move_dir.dot(_last_move_input_dir) < -0.35 and run_time > 0.45:
			run_time = 0.0
			skidded.emit()
		else:
			run_time += delta
	elif on_floor:
		run_time = maxf(0.0, run_time - delta * 3.0)
	if input_mag > 0.001:
		_prev_move_dir = _last_move_input_dir
	var sprint_k: float = smoothstep(0.35, sprint_ramp_time, run_time)
	var target_speed: float = lerpf(run_speed, sprint_speed, sprint_k) * input_mag

	var accel: float = acceleration if on_floor else air_acceleration
	var decel: float = friction if on_floor else air_acceleration * 0.35
	if input_mag > 0.001 and _landing_recover_timer <= 0.0:
		set_facing_direction(_last_move_input_dir, delta)
		var target_v: Vector3 = _last_move_input_dir * target_speed
		var cur: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
		# Turning against current momentum uses friction-strength accel so direction changes snap.
		var a: float = accel if cur.dot(target_v) >= 0.0 else maxf(accel, friction * 1.4)
		cur = cur.move_toward(target_v, a * delta)
		velocity.x = cur.x
		velocity.z = cur.z
	else:
		var cur2: Vector3 = Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, decel * delta)
		velocity.x = cur2.x
		velocity.z = cur2.z

	# Consume buffered actions (buffer is filled in _poll_action_inputs)
	var act: String = _buffer_action
	if act == "plunge":
		_consume_buffer()
		if is_currently_airborne():
			start_landing_attack()
			return
		elif on_floor:
			velocity.y = landing_leap_velocity
			_jump_held = true
			_pending_ground_slam = true
			_pending_ground_slam_timer = 0.14
			jumped.emit()
	elif act == "light" and _landing_recover_timer <= 0.0 and not is_currently_airborne():
		_consume_buffer()
		if start_light_attack():
			return
	elif act == "heavy" and _landing_recover_timer <= 0.0 and not is_currently_airborne():
		_consume_buffer()
		if start_heavy_attack():
			return
	elif act == "dodge":
		_consume_buffer()
		var d_dir: Vector3 = _last_move_input_dir if _last_move_input_dir.length_squared() > 0.001 else get_facing_direction()
		if start_dodge(d_dir):
			return
	elif act == "jump":
		_consume_buffer()
		_jump_buffer_timer = jump_buffer_time

	if _jump_buffer_timer > 0.0 and (on_floor or _coyote_timer > 0.0) and _landing_recover_timer <= 0.0:
		start_jump()

	if InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
		try_interact()

	if is_inside_tree():
		move_and_slide()


func _track_landing() -> void:
	if not is_inside_tree():
		return
	var on_floor: bool = is_on_floor()
	if not on_floor:
		_last_air_vy = velocity.y
	elif not _was_on_floor:
		var impact: float = -_last_air_vy
		if impact > 2.0 and current_state != State.LANDING_PLUNGE:
			landed.emit(impact)
			if impact > 13.0:
				_landing_recover_timer = maxf(_landing_recover_timer, 0.12)
		_last_air_vy = 0.0
	_was_on_floor = on_floor


func _process_dodge_state(delta: float) -> void:
	_dodge_elapsed += delta
	_state_timer = maxf(0.0, _state_timer - delta)
	var in_iframes: bool = _dodge_elapsed >= dodge_iframe_start and _dodge_elapsed <= (dodge_iframe_start + dodge_iframe_duration)
	_update_hurtbox_invulnerability(in_iframes)

	var dur: float = maxf(0.01, dodge_duration)
	var t_norm: float = clampf(_dodge_elapsed / dur, 0.0, 1.0)
	if not is_on_floor():
		# Air-dash holds altitude for the burst, then gravity returns.
		if t_norm > 0.6:
			velocity.y = maxf(velocity.y - _base_gravity() * 0.8 * delta, -max_fall_speed)
		else:
			velocity.y = 0.0

	# Explosive start, long ease-out into a run so the dodge flows into movement.
	var burst: float = dodge_speed * 1.3
	var cur_speed: float = burst
	if t_norm > 0.45:
		var ease_out: float = (t_norm - 0.45) / 0.55
		cur_speed = lerpf(burst, run_speed * 0.95, ease_out * ease_out * (3.0 - 2.0 * ease_out))
	velocity.x = _dodge_direction.x * cur_speed
	velocity.z = _dodge_direction.z * cur_speed
	if is_inside_tree():
		move_and_slide()

	# Attack out of a dodge late in the roll (dodge-attack chain).
	if t_norm > 0.6 and (_buffer_action == "light" or _buffer_action == "heavy") and is_on_floor():
		_update_hurtbox_invulnerability(false)
		_set_state(State.LOCOMOTION, 0.0)
		run_time = sprint_ramp_time
		var act: String = _consume_buffer()
		if act == "light":
			start_light_attack()
		else:
			start_heavy_attack()
		return

	if _state_timer <= 0.0:
		_update_hurtbox_invulnerability(false)
		_dodge_cooldown_timer = dodge_cooldown
		run_time = sprint_ramp_time * 0.8  # come out of a roll already moving fast
		_set_state(State.LOCOMOTION, 0.0)


func _process_landing_plunge_state(delta: float) -> void:
	if _plunge_hang_timer > 0.0:
		# Brief hang at the top: the "wind-up" before the drop.
		_plunge_hang_timer -= delta
		velocity.y = maxf(0.0, velocity.y - 20.0 * delta)
	else:
		velocity.y = -landing_plunge_speed
	if is_inside_tree():
		move_and_slide()
		if _plunge_hang_timer <= 0.0 and is_on_floor():
			complete_landing_slam()
			return

	_state_timer = maxf(0.0, _state_timer - delta)
	if _state_timer <= 0.0:
		complete_landing_slam()


func _set_state(next_state: State, duration: float) -> void:
	current_state = next_state
	_state_timer = duration
	if next_state != State.LIGHT_ATTACK and next_state != State.HEAVY_ATTACK:
		if attack_phase != AttackPhase.NONE:
			_set_attack_phase(AttackPhase.NONE)
	state_changed.emit(current_state)


func _update_hurtbox_invulnerability(invuln: bool) -> void:
	var hb: Hurtbox3D = get_hurtbox()
	if hb != null:
		hb.is_invulnerable = invuln


func _on_death() -> void:
	_abort_attack()
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


func _realm_color(alpha: float = 1.0) -> Color:
	var in_mirror: bool = RealmManager.instance != null and RealmManager.instance.current_realm == RealmManager.Realm.MIRROR and not RealmManager.instance.is_merged
	var c: Color = Color(0.30, 0.85, 1.0) if in_mirror else Color(1.0, 0.55, 0.18)
	c.a = alpha
	return c


func _spawn_ground_crack(length: float) -> void:
	var fwd: Vector3 = get_facing_direction()
	GoreFXScript.ground_crack(self, global_position + fwd * 0.6, fwd, length, _realm_color())
