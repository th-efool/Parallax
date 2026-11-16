class_name EnemyAI
extends EnemyBase
## Finite State Machine (`IDLE`, `CHASE`, `WINDUP`, `ATTACK`, `RECOVER`, `STAGGER`, `DEAD`)
## shared by Skeleton Guard, Phantom Twin, Shielded Guard, and extended by The Warden.
##
## Squad behaviour (via `SquadCoordinator`): CHASE is an *engage* state — an enemy only closes in and
## swings while holding an attack token; otherwise it circles the player on a spaced holding ring,
## drifting to flank. Spotting the player alerts nearby allies (with a short taunt). Uncommitted enemies
## can side-step a telegraphed player swing, flinch on light hits (with poise so they can't be stun-locked
## forever and will counter a button-masher), get knocked back, and the last survivor gets enraged.

const SquadCoordinatorScript := preload("res://scripts/enemies/squad_coordinator.gd")

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
signal alerted(by: Node)
signal evaded(direction: Vector3)

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

var current_state: State = State.IDLE
var _state_timer: float = 0.0
var _state_duration: float = 0.0
var _state_elapsed: float = 0.0
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


func _ready() -> void:
	super._ready()
	_rng.randomize()
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
	step_ai(delta)
	_apply_knockback(delta)


func _process(delta: float) -> void:
	_update_hit_lean(delta)


func step_ai(delta: float) -> void:
	if is_dead:
		if current_state != State.DEAD:
			_transition_to(State.DEAD, 0.0)
		return

	_state_elapsed += delta
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


func _tick_timers(delta: float) -> void:
	_taunt_timer = maxf(0.0, _taunt_timer - delta)
	_evade_cooldown = maxf(0.0, _evade_cooldown - delta)
	_poise_timer = maxf(0.0, _poise_timer - delta)
	if _flinch_chain_timer > 0.0:
		_flinch_chain_timer -= delta
		if _flinch_chain_timer <= 0.0:
			_flinch_chain = 0
	_orbit_flip_timer -= delta
	if _orbit_flip_timer <= 0.0:
		_orbit_flip_timer = _rng.randf_range(2.0, 4.5)
		if _rng.randf() < 0.45:
			_orbit_sign = -_orbit_sign


# ------------------------------------------------------------------ public queries (animation bridge)

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


## Squad alert from an ally that spotted the player.
func receive_alert(player: Node3D, by: Node) -> void:
	if is_dead or not is_active or current_state != State.IDLE:
		return
	target_player = player
	_taunt_timer = _rng.randf_range(0.0, 0.25)
	_transition_to(State.CHASE, 0.0)
	alerted.emit(by)


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


# ------------------------------------------------------------------ states

func _process_idle(_delta: float, player: Node3D) -> void:
	velocity = Vector3.ZERO
	if player != null and global_position.distance_to(player.global_position) <= detection_range:
		# First to spot the player roars and calls the squad in.
		_taunt_timer = 0.55 if _squad != null and _squad.get_engaged(player).is_empty() else 0.0
		_transition_to(State.CHASE, 0.0)
		if _squad != null:
			_squad.alert(self, player)
		alerted.emit(self)


func _process_chase(delta: float, player: Node3D) -> void:
	if player == null:
		_release_token()
		_transition_to(State.IDLE, 0.0)
		return

	var to_p: Vector3 = player.global_position - global_position
	to_p.y = 0.0
	var dist: float = to_p.length()
	if dist > detection_range * 1.6:
		_release_token()
		_transition_to(State.IDLE, 0.0)
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
		_enraged = _squad.is_last_standing(self, player)
	var speed: float = move_speed * (1.25 if _enraged else 1.0)
	var desired: Vector3
	var has_token: bool = _squad == null or _squad.request_attack_token(self, player)

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
		var goal: Vector3 = _squad.get_ring_position(self, player, ring_r, _orbit_sign)
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


func _process_windup(delta: float, player: Node3D) -> void:
	_state_timer = maxf(0.0, _state_timer - delta)
	# Track the player through the first half of the wind-up, then commit (dodgeable).
	if player != null and _state_elapsed < _state_duration * 0.55:
		var to_p: Vector3 = player.global_position - global_position
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
	_release_token()
	var dur: float = recover_duration if custom_recover < 0.0 else custom_recover
	if _enraged:
		dur *= 0.7
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
		State.ATTACK, State.DEAD:
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


func _on_enemy_reset() -> void:
	_clear_telegraph_flash()
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.end_swing()
	_release_token()
	_knockback = Vector3.ZERO
	_lean = Vector2.ZERO
	_lean_v = Vector2.ZERO
	_flinch_chain = 0
	_poise_timer = 0.0
	_taunt_timer = 0.0
	_evade_timer = 0.0
	_enraged = false
	_transition_to(State.IDLE, 0.0)


func _die(source_type: String) -> void:
	_clear_telegraph_flash()
	_release_token()
	_transition_to(State.DEAD, 0.0)
	super._die(source_type)


func _release_token() -> void:
	if _squad != null and is_instance_valid(_squad):
		_squad.release_token(self)


func _transition_to(next_state: State, duration: float) -> void:
	current_state = next_state
	_state_timer = duration
	_state_duration = duration
	_state_elapsed = 0.0
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
