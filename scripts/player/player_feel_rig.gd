class_name PlayerFeelRig
extends Node
## Presentation layer for `PlayerController` (added automatically as a child at runtime).
## Owns everything that makes movement and attacks *read*: trauma camera shake, FOV punches,
## spring-arm zoom, vertical camera lag, procedural body lean / twist / squash-and-stretch on
## `ModelRoot`, the real-blade sword trail, footstep / skid / land dust, dodge afterimages,
## and layered procedural swing / impact sounds. Gameplay never depends on this node.

const GameFeelScript := preload("res://scripts/core/game_feel.gd")
const GoreFXScript := preload("res://scripts/core/gore_fx.gd")
const SwordTrailScript := preload("res://scripts/player/sword_trail.gd")
const LoadoutScript := preload("res://scripts/core/character_loadout.gd")

@export var camera_path: NodePath = NodePath("../CameraPivot/SpringArm3D/Camera3D")
@export var spring_arm_path: NodePath = NodePath("../CameraPivot/SpringArm3D")
@export var camera_pivot_path: NodePath = NodePath("../CameraPivot")
@export var model_root_path: NodePath = NodePath("../VisualRoot/ModelRoot")

@export_group("Camera")
@export var trauma_decay: float = 1.9
@export var shake_pitch_deg: float = 3.0
@export var shake_yaw_deg: float = 3.2
@export var shake_roll_deg: float = 4.5
@export var shake_offset_m: float = 0.10
@export var sprint_fov_bonus: float = 7.0
@export var sprint_arm_bonus: float = 0.45
@export var vertical_lag_air: float = 4.5
@export var vertical_lag_ground: float = 14.0

@export_group("Body")
@export var lean_per_speed: float = 0.022
@export var bank_per_yaw_rate: float = 0.055
@export var max_bank: float = 0.32

var trauma: float = 0.0

var _pc: PlayerController = null
var _camera: Camera3D = null
var _arm: SpringArm3D = null
var _pivot: Node3D = null
var _model: Node3D = null
var _model_base_scale: Vector3 = Vector3.ONE
var _trail: SwordTrail = null
var _noise := FastNoiseLite.new()
var _noise_t: float = 0.0

var _base_fov: float = 65.0
var _fov_smoothed: float = 65.0
var _base_arm: float = 4.0
var _base_pivot_y: float = 1.55
var _fov_kick: float = 0.0
var _fov_kick_vel: float = 0.0
var _arm_kick: float = 0.0
var _smooth_y: float = 0.0

# Springs: value + velocity
var _lean: float = 0.0
var _lean_v: float = 0.0
var _bank: float = 0.0
var _bank_v: float = 0.0
var _twist: float = 0.0
var _twist_v: float = 0.0
var _squash: float = 0.0  # +stretch / -squash
var _squash_v: float = 0.0
var _prev_yaw: float = 0.0
var _prev_hvel: Vector3 = Vector3.ZERO

var _step_timer: float = 0.0
var _ghost_timer: float = 0.0
var _ghosts_left: int = 0
var _ghost_color: Color = Color.WHITE
var _rng := RandomNumberGenerator.new()

# Heavy-charge aura: a slightly enlarged additive copy of the blade mesh + light + embers, grown by the hold ratio.
const AURA_MIN_SCALE: float = 1.10
const AURA_GROW: float = 0.40
var _aura: MeshInstance3D = null
var _aura_mat: StandardMaterial3D = null
var _aura_light: OmniLight3D = null
var _aura_embers: CPUParticles3D = null
var _aura_embers_mat: StandardMaterial3D = null
var _aura_center: Vector3 = Vector3.ZERO
var _charge_full_fired: bool = false


func _ready() -> void:
	add_to_group(GameFeelScript.GROUP_CAMERA_RIG)
	_pc = get_parent() as PlayerController
	_camera = get_node_or_null(camera_path) as Camera3D
	_arm = get_node_or_null(spring_arm_path) as SpringArm3D
	_pivot = get_node_or_null(camera_pivot_path) as Node3D
	_model = get_node_or_null(model_root_path) as Node3D
	if _camera != null:
		_base_fov = _camera.fov
		_fov_smoothed = _base_fov
	if _arm != null:
		_base_arm = _arm.spring_length
	if _pivot != null:
		_base_pivot_y = _pivot.position.y
	if _model != null:
		_model_base_scale = _model.scale
		LoadoutScript.apply_default_for(_model, "player")
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.9
	_noise.seed = 4242
	if _pc != null:
		_smooth_y = _pc.global_position.y if _pc.is_inside_tree() else 0.0
		_prev_yaw = _pc.get_visual_yaw()
		_connect_player()
	_setup_trail.call_deferred()


func _connect_player() -> void:
	_pc.attack_started.connect(_on_attack_started)
	_pc.attack_phase_changed.connect(_on_attack_phase)
	_pc.hit_confirmed.connect(_on_hit_confirmed)
	_pc.attack_deflected.connect(_on_attack_deflected)
	_pc.dodge_started.connect(_on_dodge_started)
	_pc.perfect_dodge.connect(_on_perfect_dodge)
	_pc.landed.connect(_on_landed)
	_pc.jumped.connect(_on_jumped)
	_pc.skidded.connect(_on_skidded)
	_pc.landing_slam_triggered.connect(_on_landing_slam)
	_pc.player_damaged.connect(_on_player_damaged)


func _setup_trail() -> void:
	if _model == null or _pc == null:
		return
	var blade: Node3D = null
	for n in ["1H_Sword", "2H_Sword", "1H_Axe", "2H_Axe"]:
		var f: MeshInstance3D = LoadoutScript.find_prop_mesh(_model, n)
		if f != null and f.is_visible_in_tree():
			blade = f
			break
	_trail = SwordTrailScript.new()
	_trail.name = "SwordTrail"
	_pc.add_child(_trail)
	if blade != null:
		_trail.bind_blade(blade)
		_build_charge_aura(blade as MeshInstance3D)


func add_trauma(amount: float) -> void:
	var k: float = 1.0
	if _pc != null:
		k = clampf(_pc.camera_shake_intensity, 0.0, 1.5)
	trauma = clampf(trauma + amount * k, 0.0, 1.0)


func kick_fov(amount: float) -> void:
	_fov_kick_vel += amount * 28.0


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if _pc == null or not _pc.is_inside_tree():
		return
	# Camera reads in real time so it keeps living through hit-stop; the body uses game time.
	var real_dt: float = minf(delta / maxf(Engine.time_scale, 0.01), 0.1)
	_update_camera(real_dt)
	_update_body(delta)
	_update_dust(delta)
	_update_ghosts(delta)
	_update_trail_state()
	_update_charge_vfx(_pc.get_heavy_charge_ratio())


func _update_camera(dt: float) -> void:
	trauma = maxf(0.0, trauma - trauma_decay * dt)
	# Holding a heavy: a continuous shake floor that rises with the charge (quadratic in the shader: subtle at the
	# start, clearly rumbling at full charge).
	var charge_k: float = _pc.get_heavy_charge_ratio()
	if charge_k > 0.0:
		trauma = maxf(trauma, 0.10 + 0.45 * charge_k * charge_k)
	_noise_t += dt * 32.0
	var hvel: Vector3 = Vector3(_pc.velocity.x, 0.0, _pc.velocity.z)
	var speed_k: float = clampf((hvel.length() - _pc.run_speed * 0.9) / maxf(0.1, _pc.sprint_speed - _pc.run_speed * 0.9), 0.0, 1.0)
	if _pc.current_state != PlayerController.State.LOCOMOTION:
		speed_k *= 0.6

	# FOV: underdamped spring kick on top of the sprint widening.
	var fov_spring: Vector2 = _spring(_fov_kick, _fov_kick_vel, 0.0, 160.0, 16.0, dt)
	_fov_kick = fov_spring.x
	_fov_kick_vel = fov_spring.y
	if _camera != null:
		var target_fov: float = _base_fov + sprint_fov_bonus * speed_k
		_fov_smoothed = lerpf(_fov_smoothed, target_fov, clampf(5.0 * dt, 0.0, 1.0))
		_camera.fov = clampf(_fov_smoothed + _fov_kick, 40.0, 110.0)
		var t2: float = trauma * trauma
		_camera.rotation = Vector3(
			deg_to_rad(shake_pitch_deg) * t2 * _noise.get_noise_2d(_noise_t, 3.0),
			deg_to_rad(shake_yaw_deg) * t2 * _noise.get_noise_2d(_noise_t, 41.0),
			deg_to_rad(shake_roll_deg) * t2 * trauma * _noise.get_noise_2d(_noise_t, 97.0)
		)
		_camera.h_offset = shake_offset_m * t2 * _noise.get_noise_2d(_noise_t, 151.0)
		_camera.v_offset = shake_offset_m * t2 * _noise.get_noise_2d(_noise_t, 211.0)

	if _arm != null:
		_arm_kick = lerpf(_arm_kick, 0.0, clampf(6.0 * dt, 0.0, 1.0))
		_arm.spring_length = _base_arm + sprint_arm_bonus * speed_k + _arm_kick

	# Vertical lag: the camera rides jumps loosely and snaps back on the ground.
	if _pivot != null:
		var py: float = _pc.global_position.y
		var rate: float = vertical_lag_ground if _pc.is_on_floor() else vertical_lag_air
		_smooth_y = lerpf(_smooth_y, py, clampf(rate * dt, 0.0, 1.0))
		_smooth_y = clampf(_smooth_y, py - 1.6, py + 1.2)
		_pivot.position.y = _base_pivot_y + (_smooth_y - py)


## Damped spring, sub-stepped at <= 1/120 s. A single explicit step is unstable once dt > ~2/sqrt(k)
## (~0.11 s for the twist spring): a load hitch or a heavy combat frame made the twist angle diverge and the
## character spin in place. Sub-stepping keeps it stable for any frame time; NaN/inf resets to rest.
func _spring(value: float, vel: float, target: float, stiffness: float, damping: float, dt: float) -> Vector2:
	var remaining: float = minf(dt, 0.1)
	while remaining > 0.0:
		var h: float = minf(remaining, 1.0 / 120.0)
		vel += ((target - value) * stiffness - vel * damping) * h
		value += vel * h
		remaining -= h
	if is_nan(value) or is_inf(value) or is_nan(vel) or is_inf(vel):
		return Vector2(target, 0.0)
	return Vector2(value, vel)


func _update_body(delta: float) -> void:
	if _model == null or delta <= 0.0:
		return
	var st: int = int(_pc.current_state)
	var hvel: Vector3 = Vector3(_pc.velocity.x, 0.0, _pc.velocity.z)
	var fwd: Vector3 = _pc.get_facing_direction()
	# Derivatives over a floored dt: hit-stop frames (time_scale 0.03) would otherwise turn tiny deltas into
	# enormous accelerations / yaw rates.
	var safe_dt: float = maxf(delta, 1.0 / 240.0)
	var accel: Vector3 = (hvel - _prev_hvel) / safe_dt
	_prev_hvel = hvel

	var yaw: float = _pc.get_visual_yaw()
	var yaw_rate: float = clampf(wrapf(yaw - _prev_yaw, -PI, PI) / safe_dt, -20.0, 20.0)
	_prev_yaw = yaw

	var lean_t: float = 0.0
	var bank_t: float = 0.0
	var twist_t: float = 0.0
	match st:
		PlayerController.State.LOCOMOTION:
			var fwd_speed: float = hvel.dot(fwd)
			lean_t = clampf(fwd_speed * lean_per_speed + accel.dot(fwd) * 0.006, -0.12, 0.26)
			if _pc.is_on_floor():
				bank_t = clampf(-yaw_rate * bank_per_yaw_rate * clampf(hvel.length() / maxf(1.0, _pc.run_speed), 0.0, 1.3), -max_bank, max_bank)
		PlayerController.State.DODGE:
			lean_t = 0.32
		PlayerController.State.LIGHT_ATTACK, PlayerController.State.HEAVY_ATTACK:
			var def: Dictionary = _pc.current_attack
			var tw: float = float(def.get("twist", 0.0))
			var heavy: bool = st == PlayerController.State.HEAVY_ATTACK
			match int(_pc.attack_phase):
				PlayerController.AttackPhase.WINDUP:
					lean_t = -0.10 if not heavy else -0.22
					twist_t = -tw * 0.45
				PlayerController.AttackPhase.ACTIVE:
					lean_t = 0.20 if not heavy else 0.34
					twist_t = tw * 0.55
				_:
					lean_t = 0.10 if not heavy else 0.16
					twist_t = tw * 0.15
		PlayerController.State.LANDING_PLUNGE:
			lean_t = 0.45
		PlayerController.State.STAGGER:
			lean_t = -0.30

	# Heavy charge: the body strains back and trembles harder the longer RMB is held.
	var charge: float = _pc.get_heavy_charge_ratio()
	if charge > 0.0:
		var tremble: float = _noise.get_noise_2d(float(Time.get_ticks_msec()) * 0.02, 7.0)
		lean_t -= 0.04 * charge
		twist_t += tremble * (0.015 + 0.06 * charge)
	var r: Vector2 = _spring(_lean, _lean_v, lean_t, 170.0, 15.0, delta)
	_lean = r.x
	_lean_v = r.y
	r = _spring(_bank, _bank_v, bank_t, 120.0, 14.0, delta)
	_bank = r.x
	_bank_v = r.y
	r = _spring(_twist, _twist_v, twist_t, 260.0, 17.0, delta)
	_twist = r.x
	_twist_v = r.y
	# Hard limits: procedural body motion is a flourish, never a full turn.
	_lean = clampf(_lean, -0.7, 0.8)
	_bank = clampf(_bank, -0.6, 0.6)
	_twist = clampf(_twist, -1.0, 1.0)
	r = _spring(_squash, _squash_v, 0.0, 260.0, 11.0, delta)
	_squash = clampf(r.x, -0.38, 0.32)
	_squash_v = r.y
	# Airborne stretch tracks vertical speed (rising long, apex round, falling long).
	if not _pc.is_on_floor() and st == PlayerController.State.LOCOMOTION:
		_squash = lerpf(_squash, clampf(absf(_pc.velocity.y) * 0.012, 0.0, 0.12), clampf(10.0 * delta, 0.0, 1.0))

	var sy: float = 1.0 + _squash
	var sxz: float = 1.0 / sqrt(maxf(0.3, sy))
	var b := Basis.from_euler(Vector3(_lean, PI + _twist, _bank))
	_model.transform.basis = b * Basis.from_scale(Vector3(sxz, sy, sxz) * _model_base_scale)


func _update_dust(delta: float) -> void:
	if _pc.current_state != PlayerController.State.LOCOMOTION or not _pc.is_on_floor():
		_step_timer = 0.0
		return
	var speed: float = Vector2(_pc.velocity.x, _pc.velocity.z).length()
	if speed < 3.0:
		return
	_step_timer += delta
	var interval: float = clampf(1.9 / speed, 0.22, 0.42)
	if _step_timer >= interval:
		_step_timer = 0.0
		var sprinting: bool = speed > (_pc.run_speed + _pc.sprint_speed) * 0.5
		GoreFXScript.dust_puff(_pc, _pc.global_position - _pc.get_facing_direction() * 0.15, 0.18, 4 if not sprinting else 7, Color(0.62, 0.56, 0.48, 0.35 if not sprinting else 0.5), 0.8)


func _update_trail_state() -> void:
	if _trail == null:
		return
	var attacking: bool = _pc.current_state == PlayerController.State.LIGHT_ATTACK or _pc.current_state == PlayerController.State.HEAVY_ATTACK
	var on: bool = false
	if attacking:
		var def: Dictionary = _pc.current_attack
		var w: float = float(def.get("windup", 0.1))
		var a: float = float(def.get("active", 0.1))
		var e: float = _pc.get_attack_elapsed()
		on = e >= w * 0.55 and e <= w + a + 0.07
	elif _pc.current_state == PlayerController.State.LANDING_PLUNGE:
		on = true
	if _pc.is_heavy_charging():
		on = false
	_trail.emitting = on


func _build_charge_aura(blade: MeshInstance3D) -> void:
	if blade == null or blade.mesh == null:
		return
	_aura_center = blade.mesh.get_aabb().get_center()
	_aura_mat = StandardMaterial3D.new()
	_aura_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aura_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aura_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_aura_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_aura_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	_aura = MeshInstance3D.new()
	_aura.name = "ChargeAura"
	_aura.mesh = blade.mesh
	_aura.material_override = _aura_mat
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura.visible = false
	blade.add_child(_aura)

	_aura_light = OmniLight3D.new()
	_aura_light.name = "ChargeAuraLight"
	_aura_light.position = _aura_center
	_aura_light.omni_range = 2.0
	_aura_light.light_energy = 0.0
	_aura_light.shadow_enabled = false
	blade.add_child(_aura_light)

	var ember_mesh := SphereMesh.new()
	ember_mesh.radius = 0.025
	ember_mesh.height = 0.05
	ember_mesh.radial_segments = 6
	ember_mesh.rings = 3
	_aura_embers_mat = StandardMaterial3D.new()
	_aura_embers_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aura_embers_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_aura_embers_mat.vertex_color_use_as_albedo = true
	ember_mesh.material = _aura_embers_mat
	_aura_embers = CPUParticles3D.new()
	_aura_embers.name = "ChargeEmbers"
	_aura_embers.emitting = false
	_aura_embers.amount = 28
	_aura_embers.lifetime = 0.55
	_aura_embers.local_coords = false
	_aura_embers.position = _aura_center
	_aura_embers.direction = Vector3.UP
	_aura_embers.spread = 70.0
	_aura_embers.gravity = Vector3(0.0, 1.2, 0.0)
	_aura_embers.initial_velocity_min = 0.3
	_aura_embers.initial_velocity_max = 1.1
	_aura_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_aura_embers.emission_sphere_radius = 0.22
	_aura_embers.mesh = ember_mesh
	blade.add_child(_aura_embers)


## ratio 0..1 from PlayerController.get_heavy_charge_ratio(): aura grows, brightens and pulses faster; at 1.0 it
## "pops" once (flash + ring + chime) so the player knows the guaranteed crit is armed.
func _update_charge_vfx(ratio: float) -> void:
	if _aura == null or not is_instance_valid(_aura):
		return
	var show: bool = ratio > 0.0
	_aura.visible = show
	if _aura_embers != null:
		_aura_embers.emitting = show
	if not show:
		_aura_light.light_energy = 0.0
		_charge_full_fired = false
		return
	var col: Color = _realm_color()
	var full: bool = ratio >= 0.999
	var core: Color = col.lerp(Color(1.0, 1.0, 1.0), 0.35 + 0.65 * ratio)
	var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * (0.012 + 0.02 * ratio))
	var s: float = AURA_MIN_SCALE + AURA_GROW * ratio + (0.10 * pulse if full else 0.03 * pulse)
	_aura.scale = Vector3.ONE * s
	_aura.position = -_aura_center * (s - 1.0) # scale about the blade's own centre, not its origin
	_aura_mat.albedo_color = Color(core.r, core.g, core.b, 0.18 + 0.55 * ratio)
	_aura_light.light_color = col
	_aura_light.light_energy = 0.5 + 4.0 * ratio + (1.5 * pulse if full else 0.0)
	_aura_light.omni_range = 2.0 + 2.0 * ratio
	if _aura_embers != null:
		_aura_embers.speed_scale = 1.0 + 1.5 * ratio
		_aura_embers.color = core
	if full and not _charge_full_fired:
		_charge_full_fired = true
		kick_fov(-4.0)
		add_trauma(0.30)
		GoreFXScript.flash_light(_pc, _pc.global_position + Vector3.UP * 1.2, col, 6.0, 0.25, 6.0)
		GoreFXScript.shockwave_ring(_pc, _pc.global_position, 1.8, Color(col.r, col.g, col.b, 0.8), 0.3, 0.12)
		GameFeelScript.play_sound(_pc, "clang", _pc.global_position + Vector3.UP * 1.2, -6.0, 1.5)


func _realm_color() -> Color:
	var in_mirror: bool = RealmManager.instance != null and RealmManager.instance.current_realm == RealmManager.Realm.MIRROR and not RealmManager.instance.is_merged
	return Color(0.35, 0.85, 1.0) if in_mirror else Color(1.0, 0.62, 0.22)


# ------------------------------------------------------------------ events

func _on_attack_started(attack_name: String, timing: Dictionary) -> void:
	if _trail != null:
		_trail.color = _realm_color()
		_trail.width_boost = float(timing.get("trail", 1.0))
		_trail.max_age = 0.12 if not attack_name.begins_with("heavy") else 0.18
	# Wind-up: weight shifts back, slight crouch.
	_squash_v -= 1.6 if attack_name.begins_with("heavy") else 0.7
	if attack_name.begins_with("heavy"):
		_arm_kick = -0.25


func _on_attack_phase(phase: int, attack_name: String) -> void:
	if phase != PlayerController.AttackPhase.ACTIVE:
		return
	var def: Dictionary = _pc.current_attack
	var heavy: bool = attack_name.begins_with("heavy")
	var finisher: bool = bool(def.get("finisher", false))
	kick_fov(float(def.get("fov_kick", 1.5)))
	_squash_v += 2.4 if heavy else 1.2
	GameFeelScript.add_trauma(_pc, 0.10 if heavy else 0.04)
	var pos: Vector3 = _pc.global_position + Vector3.UP * 1.1
	GameFeelScript.play_sound(_pc, "whoosh_heavy" if (heavy or finisher) else "whoosh_light", pos, -3.0 if heavy else -6.0, 0.9 if heavy else 1.1)
	if heavy and attack_name == "heavy":
		GameFeelScript.play_sound(_pc, "thud", _pc.global_position + _pc.get_facing_direction() * 1.5, -2.0, 0.8)
		GoreFXScript.flash_light(_pc, _pc.global_position + _pc.get_facing_direction() * 1.2 + Vector3.UP * 0.4, _realm_color(), 5.0, 0.18, 6.0)
	if finisher:
		_arm_kick = -0.35 if heavy else -0.2


func _on_hit_confirmed(target: Node, attack_name: String, killed: bool) -> void:
	var def: Dictionary = _pc.get_attack_def(attack_name)
	kick_fov(-1.5 if not killed else -3.5)
	var at: Vector3 = _pc.global_position + Vector3.UP * 1.1
	if target is Node3D:
		at = (target as Node3D).global_position + Vector3.UP * 1.1
	GameFeelScript.play_sound(_pc, "slash_flesh", at, -1.0 if not def.is_empty() else 0.0, 1.0 if not killed else 0.85)
	if killed:
		_arm_kick = minf(_arm_kick, -0.3)


func _on_attack_deflected(_is_heavy: bool) -> void:
	var tip: Vector3 = _trail.get_tip_world() if _trail != null and _trail.has_blade() else _pc.global_position + _pc.get_facing_direction() + Vector3.UP
	GoreFXScript.sparks(_pc, tip, -_pc.get_facing_direction(), Color(1.0, 0.85, 0.45), 34)
	GameFeelScript.play_sound(_pc, "clang", tip, 0.0, 1.0)
	_lean_v -= 6.0


func _on_dodge_started(_dir: Vector3, _dur: float) -> void:
	kick_fov(5.0)
	_squash_v -= 2.0
	_ghosts_left = 4
	_ghost_timer = 0.0
	_ghost_color = _realm_color()
	_ghost_color.a = 0.45
	GoreFXScript.dust_puff(_pc, _pc.global_position, 0.35, 10, Color(0.62, 0.56, 0.48, 0.55), 1.4)
	GameFeelScript.play_sound(_pc, "whoosh_light", _pc.global_position + Vector3.UP, -8.0, 0.75)


func _on_perfect_dodge() -> void:
	kick_fov(9.0)
	add_trauma(0.15)
	_ghosts_left = 6
	_ghost_color = Color(0.85, 0.95, 1.0, 0.65)
	GoreFXScript.flash_light(_pc, _pc.global_position + Vector3.UP, Color(0.6, 0.85, 1.0), 6.0, 0.35, 7.0)
	GoreFXScript.shockwave_ring(_pc, _pc.global_position, 2.2, Color(0.6, 0.9, 1.0, 0.7), 0.35, 0.12)
	GameFeelScript.play_sound(_pc, "whoosh_heavy", _pc.global_position + Vector3.UP, -2.0, 0.6)


func _on_jumped() -> void:
	_squash_v += 3.6
	GoreFXScript.dust_puff(_pc, _pc.global_position, 0.25, 8, Color(0.62, 0.56, 0.48, 0.5), 1.0)


func _on_landed(impact: float) -> void:
	var k: float = clampf(impact / 14.0, 0.15, 1.3)
	_squash_v -= 4.0 * k
	_lean_v += 2.0 * k
	GoreFXScript.dust_puff(_pc, _pc.global_position, 0.3 + 0.35 * k, int(6 + 10 * k), Color(0.62, 0.56, 0.48, 0.55), 1.2 + k)
	if impact > 9.0:
		add_trauma(0.12 * k)
		kick_fov(-1.5 * k)
		GameFeelScript.play_sound(_pc, "land_heavy", _pc.global_position, -10.0 + 6.0 * k, 1.1)


func _on_skidded() -> void:
	GoreFXScript.dust_puff(_pc, _pc.global_position + _pc.get_facing_direction() * -0.3, 0.4, 12, Color(0.62, 0.56, 0.48, 0.6), 1.6)
	_lean_v -= 4.0


func _on_landing_slam(pos: Vector3, radius: float, _dmg: int) -> void:
	var c: Color = _realm_color()
	_squash_v -= 6.0
	kick_fov(9.0)
	_arm_kick = 0.6
	GoreFXScript.shockwave_ring(_pc, pos, radius * 1.25, Color(c.r, c.g, c.b, 0.95), 0.42, 0.35)
	GoreFXScript.shockwave_ring(_pc, pos, radius * 0.7, Color(1, 1, 1, 0.8), 0.22, 0.2)
	GoreFXScript.dust_puff(_pc, pos, radius * 0.6, 26, Color(0.6, 0.54, 0.46, 0.65), 3.0)
	GoreFXScript.flash_light(_pc, pos + Vector3.UP * 0.5, c, 8.0, 0.3, radius * 3.0)
	for i in range(6):
		var ang: float = TAU * float(i) / 6.0 + _rng.randf_range(-0.3, 0.3)
		GoreFXScript.ground_crack(_pc, pos, Vector3(cos(ang), 0.0, sin(ang)), radius * 0.9, c)
	GameFeelScript.play_sound(_pc, "land_heavy", pos, 2.0, 0.8)


func _on_player_damaged(amount: int) -> void:
	kick_fov(-2.0 - float(amount) * 0.05)
	_lean_v -= 5.0
	GoreFXScript.blood_burst(_pc, _pc.global_position + Vector3.UP * 1.1, -_pc.get_facing_direction(), clampf(float(amount) / 20.0, 0.4, 1.4), GoreFXScript.BLOOD_RED, false)


# ------------------------------------------------------------------ afterimages

func _update_ghosts(delta: float) -> void:
	if _ghosts_left <= 0 or _model == null:
		return
	_ghost_timer -= delta
	if _ghost_timer > 0.0:
		return
	_ghost_timer = 0.045
	_ghosts_left -= 1
	_spawn_ghost(_ghost_color)


## Frozen, tinted copy of the character in its exact current animation pose.
func _spawn_ghost(color: Color) -> void:
	var host: Node = GoreFXScript.host_for(_pc)
	if host == null:
		return
	var src_ap: AnimationPlayer = _find_anim_player(_model)
	var ghost: Node3D = _model.duplicate() as Node3D
	if ghost == null:
		return
	host.add_child(ghost)
	ghost.global_transform = _model.global_transform
	var ap: AnimationPlayer = _find_anim_player(ghost)
	if ap != null and src_ap != null and src_ap.current_animation != "":
		ap.play(src_ap.current_animation)
		ap.seek(src_ap.current_animation_position, true)
		ap.pause()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	_apply_ghost_material(ghost, mat)
	var tw := ghost.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.28).set_ease(Tween.EASE_IN)
	tw.tween_property(ghost, "scale", ghost.scale * 1.04, 0.28)
	tw.set_parallel(false)
	tw.tween_callback(ghost.queue_free)


func _apply_ghost_material(node: Node, mat: Material) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).material_override = mat
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		_apply_ghost_material(c, mat)


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c in node.get_children():
		var f: AnimationPlayer = _find_anim_player(c)
		if f != null:
			return f
	return null
