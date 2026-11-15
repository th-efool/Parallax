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


func _process(_delta: float) -> void:
	if _actor == null or not is_instance_valid(_actor):
		return
	if _actor is PlayerController:
		var pc: PlayerController = _actor as PlayerController
		if pc.current_state == PlayerController.State.LOCOMOTION:
			if pc.is_currently_airborne():
				play_candidates(["Jump_Idle", "Jump_Start", "Idle"])
			else:
				var horiz_speed: float = Vector2(pc.velocity.x, pc.velocity.z).length()
				if horiz_speed > 0.25:
					play_candidates(["Running_A", "Walking_A", "Idle"])
				else:
					play_candidates(["Idle", "Idle_A"])


func bind_actor(custom_actor: Node = null) -> void:
	_actor = custom_actor if custom_actor != null else get_node_or_null(actor_path)
	if _actor == null:
		_actor = get_parent()

	var model_root: Node3D = get_node_or_null(model_root_path) as Node3D
	if model_root != null:
		if enforce_model_180_y_rotation:
			model_root.rotation.y = PI
		_anim_player = _find_animation_player(model_root)
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
		if not pc.player_died.is_connected(_on_player_died):
			pc.player_died.connect(_on_player_died)
		if not pc.interact_requested.is_connected(_on_player_interact):
			pc.interact_requested.connect(_on_player_interact)
		play_candidates(["Idle", "Idle_A"])
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


func play_candidates(candidates: Array[String]) -> bool:
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

	if current_clip_name == chosen and _anim_player != null and _anim_player.is_playing():
		return true

	current_clip_name = chosen
	if _anim_player != null and _anim_player.has_animation(chosen) and DisplayServer.get_name() != "headless":
		_anim_player.play(chosen)

	animation_triggered.emit(current_clip_name)
	return true


func _on_player_state_changed(new_state: int) -> void:
	match new_state:
		PlayerController.State.DODGE:
			play_candidates(["Dodge_Forward", "Dodge_Right", "Running_A"])
		PlayerController.State.LANDING_PLUNGE:
			play_candidates(["1H_Melee_Attack_Jump_Chop", "2H_Melee_Attack_Chop"])
		PlayerController.State.STAGGER:
			play_candidates(["Hit_A", "Hit_B"])
		PlayerController.State.DEAD:
			play_candidates(["Death_A", "Death_B"])
		PlayerController.State.LOCOMOTION:
			play_candidates(["Idle", "Idle_A"])


func _on_player_attack_executed(attack_name: String, combo_step: int, _damage: int, is_heavy: bool) -> void:
	if attack_name == "landing_plunge":
		play_candidates(["1H_Melee_Attack_Jump_Chop", "2H_Melee_Attack_Chop"])
	elif is_heavy:
		play_candidates(["2H_Melee_Attack_Chop", "1H_Melee_Attack_Chop"])
	else:
		match combo_step:
			1:
				play_candidates(["1H_Melee_Attack_Slice_Horizontal", "1H_Melee_Attack_Chop"])
			2:
				play_candidates(["1H_Melee_Attack_Slice_Diagonal", "1H_Melee_Attack_Slice_Horizontal"])
			_:
				play_candidates(["1H_Melee_Attack_Chop", "1H_Melee_Attack_Stab"])


func _on_player_dodge_started(_dir: Vector3, _dur: float) -> void:
	play_candidates(["Dodge_Forward", "Dodge_Right"])


func _on_player_died() -> void:
	play_candidates(["Death_A", "Death_B"])


func _on_player_interact() -> void:
	play_candidates(["Interact", "Use_Item", "Idle"])


func _on_enemy_state_changed(new_state: int) -> void:
	match new_state:
		EnemyAI.State.IDLE:
			if _actor is ShieldedGuard and (_actor as ShieldedGuard).is_shield_raised():
				play_candidates(["Block", "Idle_Combat", "Idle"])
			else:
				play_candidates(["Idle_Combat", "Idle", "Idle_A"])
		EnemyAI.State.CHASE:
			play_candidates(["Running_A", "Walking_A", "Running_B"])
		EnemyAI.State.WINDUP:
			play_candidates(["2H_Melee_Attack_Spin", "1H_Melee_Attack_Slice_Diagonal", "Taunt"])
		EnemyAI.State.ATTACK:
			play_candidates(["1H_Melee_Attack_Chop", "2H_Melee_Attack_Chop", "Block_Attack"])
		EnemyAI.State.RECOVER:
			play_candidates(["Idle_Combat", "Idle", "Idle_A"])
		EnemyAI.State.STAGGER:
			play_candidates(["Hit_A", "Hit_B"])
		EnemyAI.State.DEAD:
			play_candidates(["Death_A", "Death_B"])


func _on_enemy_attack_telegraphed(_attack_name: String, _windup_sec: float) -> void:
	play_candidates(["2H_Melee_Attack_Spin", "1H_Melee_Attack_Slice_Diagonal", "Taunt"])


func _on_enemy_attack_started(attack_name: String, _damage: int) -> void:
	if attack_name == "shield_bash":
		play_candidates(["Block_Attack", "1H_Melee_Attack_Chop"])
	elif attack_name.contains("lunge"):
		play_candidates(["1H_Melee_Attack_Stab", "1H_Melee_Attack_Chop"])
	else:
		play_candidates(["2H_Melee_Attack_Chop", "1H_Melee_Attack_Chop"])


func _on_enemy_staggered(_dur: float) -> void:
	play_candidates(["Hit_A", "Hit_B"])


func _on_enemy_died(_enemy: Node, _ctx: Dictionary) -> void:
	play_candidates(["Death_A", "Death_B"])


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
