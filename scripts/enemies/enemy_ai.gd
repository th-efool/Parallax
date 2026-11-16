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

@export_group("Telegraph Feedback")
@export var telegraph_color: Color = Color(1.0, 0.12, 0.06, 1.0)
@export var telegraph_overlay_peak_alpha: float = 0.42
@export var telegraph_light_height: float = 1.55
@export var telegraph_light_energy: float = 2.4

var current_state: State = State.IDLE
var _state_timer: float = 0.0
var target_player: Node3D = null
var _telegraph_mat: StandardMaterial3D = null
var _telegraph_light: OmniLight3D = null
var _telegraph_tween: Tween = null
var _telegraph_meshes: Array[MeshInstance3D] = []


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
	var p: Node3D = _resolve_target_player()
	if p != null:
		set_facing_direction(p.global_position - global_position)
	var dur: float = windup_duration if custom_windup < 0.0 else custom_windup
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
		set_facing_direction(dir)
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
	if is_inside_tree():
		move_and_slide()


func _process_windup(delta: float, _player: Node3D) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
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
	_clear_telegraph_flash()
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.end_swing()
	_transition_to(State.IDLE, 0.0)


func _die(source_type: String) -> void:
	_clear_telegraph_flash()
	_transition_to(State.DEAD, 0.0)
	super._die(source_type)


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
