class_name CharacterAnimationBridge
extends Node
## Bridges `PlayerController` and `EnemyAI` state machines to the 95 baked animations inside
## the imported KayKit `.glb` character rigs (`Knight.glb`, `Barbarian.glb`, `Skeleton_Warrior.glb`, `Skeleton_Rogue.glb`).
## Also enforces the 180-degree Y rotation (`PI`) on `ModelRoot` (+Z model forward -> -Z Godot forward)
## and applies `mirror_spectral.gdshader` to Mirror-only spectral actors (`PhantomTwin`).

signal animation_triggered(clip_name: String)

const SPECTRAL_SHADER_PATH: String = "res://assets/shaders/mirror_spectral.gdshader"

@export var actor_path: NodePath = NodePath("..")
@export var model_root_path: NodePath = NodePath("../VisualRoot/ModelRoot")
@export var enforce_model_180_y_rotation: bool = true
@export var apply_spectral_shader: bool = false

var current_clip_name: String = ""
var current_speed_scale: float = 1.0
var _action_lock_timer: float = 0.0
var _actor: Node = null
var _anim_player: AnimationPlayer = null
var _spectral_mat: ShaderMaterial = null


func _exit_tree() -> void:
	_actor = null
	_anim_player = null
	_spectral_mat = null


func _ready() -> void:
	add_to_group("animation_bridge")
	bind_actor()


func _process(delta: float) -> void:
	if _action_lock_timer > 0.0:
		_action_lock_timer = maxf(0.0, _action_lock_timer - delta)
	if _actor == null or not is_instance_valid(_actor):
		return
	if _actor is PlayerController:
		var pc: PlayerController = _actor as PlayerController
		if pc.current_state == PlayerController.State.LOCOMOTION and _action_lock_timer <= 0.0:
			if pc.is_currently_airborne():
				play_candidates(["Jump_Idle", "Jump_Start", "Idle"], -1.0, false, true)
			else:
				var horiz_speed: float = Vector2(pc.velocity.x, pc.velocity.z).length()
				if horiz_speed > 0.25:
					var run_scale: float = clampf(horiz_speed / maxf(1.0, pc.run_speed), 0.75, 1.35)
					play_candidates(["Running_A", "Walking_A", "Idle"], -1.0, false, true, run_scale)
				else:
					play_candidates(["Idle", "Idle_A"], -1.0, false, true)


func bind_actor(custom_actor: Node = null) -> void:
	_actor = custom_actor if custom_actor != null else get_node_or_null(actor_path)
	if _actor == null:
		_actor = get_parent()

	var model_root: Node3D = get_node_or_null(model_root_path) as Node3D
	if model_root != null:
		if enforce_model_180_y_rotation:
			model_root.rotation.y = PI
		_anim_player = _find_animation_player(model_root)
		if _anim_player != null:
			_configure_animation_loops()
		if apply_spectral_shader or (_actor != null and _actor is PhantomTwin):
			_apply_spectral_material_recursive(model_root)

	if _actor is PlayerController:
		var pc: PlayerController = _actor as PlayerController
		if not pc.state_changed.is_connected(_on_player_state_changed):
			pc.state_changed.connect(_on_player_state_changed)
		if not pc.attack_executed.is_connected(_on_player_attack_executed):
			pc.attack_executed.connect(_on_player_attack_executed)
		if not pc.dodge_started.is_connected(_on_player_dodge_started):
			pc.dodge_started.connect(_on_player_dodge_started)
		if not pc.jumped.is_connected(_on_player_jumped):
			pc.jumped.connect(_on_player_jumped)
		if not pc.landing_slam_triggered.is_connected(_on_player_landing_slam):
			pc.landing_slam_triggered.connect(_on_player_landing_slam)
		if not pc.player_died.is_connected(_on_player_died):
			pc.player_died.connect(_on_player_died)
		if not pc.interact_requested.is_connected(_on_player_interact):
			pc.interact_requested.connect(_on_player_interact)
		play_candidates(["Idle", "Idle_A"], -1.0, false, true)
	elif _actor is EnemyAI:
		var ai: EnemyAI = _actor as EnemyAI
		if not ai.state_changed.is_connected(_on_enemy_state_changed):
			ai.state_changed.connect(_on_enemy_state_changed)
		if not ai.attack_telegraphed.is_connected(_on_enemy_attack_telegraphed):
			ai.attack_telegraphed.connect(_on_enemy_attack_telegraphed)
		if not ai.attack_started.is_connected(_on_enemy_attack_started):
			ai.attack_started.connect(_on_enemy_attack_started)
		if not ai.staggered.is_connected(_on_enemy_staggered):
			ai.staggered.connect(_on_enemy_staggered)
		if not ai.died.is_connected(_on_enemy_died):
			ai.died.connect(_on_enemy_died)
		_on_enemy_state_changed(ai.current_state)


func get_animation_player() -> AnimationPlayer:
	return _anim_player


func play_candidates(
	candidates: Array[String],
	target_duration: float = -1.0,
	force_restart: bool = false,
	is_looping: bool = false,
	explicit_speed: float = 1.0
) -> bool:
	if candidates.is_empty():
		return false

	var chosen: String = candidates[0]
	if _anim_player != null:
		for c in candidates:
			if _anim_player.has_animation(c):
				chosen = c
				break
			elif _anim_player.has_animation("Animations/" + c):
				chosen = "Animations/" + c
				break

	var computed_speed: float = explicit_speed
	if _anim_player != null and _anim_player.has_animation(chosen):
		var anim_res: Animation = _anim_player.get_animation(chosen)
		if anim_res != null:
			anim_res.loop_mode = Animation.LOOP_LINEAR if is_looping else Animation.LOOP_NONE
			if target_duration > 0.0 and anim_res.length > 0.05:
				computed_speed = clampf((anim_res.length * 0.90) / target_duration, 1.0, 2.85)

	if not force_restart and current_clip_name == chosen and _anim_player != null and _anim_player.is_playing():
		_anim_player.speed_scale = computed_speed
		current_speed_scale = computed_speed
		return true

	current_clip_name = chosen
	current_speed_scale = computed_speed
	if _anim_player != null and _anim_player.has_animation(chosen):
		var blend_time: float = 0.12 if is_looping else 0.06
		_anim_player.speed_scale = computed_speed
		_anim_player.play(chosen, blend_time, 1.0)
		if force_restart:
			_anim_player.seek(0.0, true)

	animation_triggered.emit(current_clip_name)
	return true


func _configure_animation_loops() -> void:
	if _anim_player == null:
		return
	var loop_names: Array[String] = [
		"Idle", "Idle_A", "Idle_B", "Idle_Combat",
		"Running_A", "Running_B", "Walking_A", "Walking_B",
		"Jump_Idle", "Block",
	]
	for base_name in loop_names:
		for cand in [base_name, "Animations/" + base_name]:
			if _anim_player.has_animation(cand):
				var anim_res: Animation = _anim_player.get_animation(cand)
				if anim_res != null:
					anim_res.loop_mode = Animation.LOOP_LINEAR


func _on_player_state_changed(new_state: int) -> void:
	match new_state:
		PlayerController.State.DODGE:
			var d_dur: float = 0.48
			if _actor is PlayerController:
				d_dur = (_actor as PlayerController).dodge_duration
			play_candidates(["Dodge_Forward", "Dodge_Right", "Running_A"], d_dur, true, false)
		PlayerController.State.LANDING_PLUNGE:
			play_candidates(["1H_Melee_Attack_Jump_Chop", "2H_Melee_Attack_Chop", "1H_Melee_Attack_Chop"], 0.45, true, false)
		PlayerController.State.STAGGER:
			_action_lock_timer = 0.25
			play_candidates(["Hit_A", "Hit_B"], 0.30, true, false)
		PlayerController.State.DEAD:
			_action_lock_timer = 1.5
			play_candidates(["Death_A", "Death_B"], -1.0, true, false)
		PlayerController.State.LOCOMOTION:
			if _action_lock_timer <= 0.0:
				play_candidates(["Idle", "Idle_A"], -1.0, false, true)


func _on_player_attack_executed(attack_name: String, combo_step: int, _damage: int, is_heavy: bool) -> void:
	var pc: PlayerController = _actor as PlayerController
	if attack_name == "landing_plunge":
		play_candidates(["1H_Melee_Attack_Jump_Chop", "2H_Melee_Attack_Chop", "1H_Melee_Attack_Chop"], 0.45, true, false)
	elif is_heavy:
		var h_dur: float = pc.heavy_attack_duration if pc != null else 0.72
		play_candidates(["2H_Melee_Attack_Chop", "1H_Melee_Attack_Chop"], h_dur, true, false)
	else:
		var idx: int = clampi(combo_step - 1, 0, 2)
		var l_dur: float = float(pc.light_attack_durations[idx]) if (pc != null and idx < pc.light_attack_durations.size()) else 0.44
		match combo_step:
			1:
				play_candidates(["1H_Melee_Attack_Slice_Horizontal", "1H_Melee_Attack_Chop"], l_dur, true, false)
			2:
				play_candidates(["1H_Melee_Attack_Slice_Diagonal", "1H_Melee_Attack_Slice_Horizontal"], l_dur, true, false)
			_:
				play_candidates(["1H_Melee_Attack_Chop", "1H_Melee_Attack_Stab"], l_dur, true, false)


func _on_player_dodge_started(_dir: Vector3, dur: float) -> void:
	play_candidates(["Dodge_Forward", "Dodge_Right"], dur, true, false)


func _on_player_jumped() -> void:
	play_candidates(["Jump_Start", "Jump_Idle"], 0.28, true, false)


func _on_player_landing_slam(_impact_pos: Vector3, _radius: float, _dmg: int) -> void:
	var rec_dur: float = 0.28
	if _actor is PlayerController:
		rec_dur = (_actor as PlayerController).landing_recovery_duration
	_action_lock_timer = rec_dur
	play_candidates(["Jump_Land", "1H_Melee_Attack_Chop"], rec_dur, true, false)


func _on_player_died() -> void:
	_action_lock_timer = 1.5
	play_candidates(["Death_A", "Death_B"], -1.0, true, false)


func _on_player_interact() -> void:
	_action_lock_timer = 0.28
	play_candidates(["Interact", "Use_Item", "Idle"], 0.30, true, false)


func _on_enemy_state_changed(new_state: int) -> void:
	match new_state:
		EnemyAI.State.IDLE:
			if _actor is ShieldedGuard and (_actor as ShieldedGuard).is_shield_raised():
				play_candidates(["Block", "Idle_Combat", "Idle"], -1.0, false, true)
			else:
				play_candidates(["Idle_Combat", "Idle", "Idle_A"], -1.0, false, true)
		EnemyAI.State.CHASE:
			play_candidates(["Running_A", "Walking_A", "Running_B"], -1.0, false, true)
		EnemyAI.State.WINDUP:
			var w_dur: float = (_actor as EnemyAI).windup_duration if _actor is EnemyAI else 0.55
			play_candidates(["2H_Melee_Attack_Spin", "1H_Melee_Attack_Slice_Diagonal", "Taunt"], w_dur, true, false)
		EnemyAI.State.ATTACK:
			var a_dur: float = (_actor as EnemyAI).attack_active_duration if _actor is EnemyAI else 0.25
			play_candidates(["1H_Melee_Attack_Chop", "2H_Melee_Attack_Chop", "Block_Attack"], maxf(0.32, a_dur), true, false)
		EnemyAI.State.RECOVER:
			play_candidates(["Idle_Combat", "Idle", "Idle_A"], -1.0, false, true)
		EnemyAI.State.STAGGER:
			var s_dur: float = (_actor as EnemyAI).stagger_duration if _actor is EnemyAI else 0.65
			play_candidates(["Hit_A", "Hit_B"], s_dur, true, false)
		EnemyAI.State.DEAD:
			play_candidates(["Death_A", "Death_B"], -1.0, true, false)


func _on_enemy_attack_telegraphed(_attack_name: String, windup_sec: float) -> void:
	play_candidates(["2H_Melee_Attack_Spin", "1H_Melee_Attack_Slice_Diagonal", "Taunt"], windup_sec, true, false)


func _on_enemy_attack_started(attack_name: String, _damage: int) -> void:
	if attack_name == "shield_bash":
		play_candidates(["Block_Attack", "1H_Melee_Attack_Chop"], 0.35, true, false)
	elif attack_name.contains("lunge"):
		play_candidates(["1H_Melee_Attack_Stab", "1H_Melee_Attack_Chop"], 0.38, true, false)
	else:
		play_candidates(["2H_Melee_Attack_Chop", "1H_Melee_Attack_Chop"], 0.40, true, false)


func _on_enemy_staggered(dur: float) -> void:
	play_candidates(["Hit_A", "Hit_B"], dur, true, false)


func _on_enemy_died(_enemy: Node, _ctx: Dictionary) -> void:
	play_candidates(["Death_A", "Death_B"], -1.0, true, false)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null


func _apply_spectral_material_recursive(node: Node) -> void:
	if _spectral_mat == null and ResourceLoader.exists(SPECTRAL_SHADER_PATH):
		var sh: Shader = load(SPECTRAL_SHADER_PATH) as Shader
		if sh != null:
			_spectral_mat = ShaderMaterial.new()
			_spectral_mat.shader = sh

	if _spectral_mat != null and node is MeshInstance3D:
		(node as MeshInstance3D).material_override = _spectral_mat

	for child in node.get_children():
		_apply_spectral_material_recursive(child)
