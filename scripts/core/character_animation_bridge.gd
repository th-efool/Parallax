class_name CharacterAnimationBridge
extends Node
## Bridges `PlayerController` and `EnemyAI` state machines to the baked animations inside the imported
## KayKit `.glb` rigs (`Knight.glb`, `Barbarian.glb`, `Skeleton_Warrior.glb`, `Skeleton_Rogue.glb`).
## Also enforces the 180-degree Y rotation (`PI`) on `ModelRoot` (+Z model forward -> -Z Godot forward)
## and applies `mirror_spectral.gdshader` to Mirror-only spectral actors (`PhantomTwin`).
##
## Attacks are driven by an *attack timeline*: the clip is time-remapped so its anticipation stretches
## over the gameplay wind-up (slow, held backswing), the contact frames are crushed into the active
## window (a fast whip), and the follow-through eases out over recovery. This is where swing weight
## comes from — the same clip played at a constant speed reads as floaty.

signal animation_triggered(clip_name: String)

const SPECTRAL_SHADER_PATH: String = "res://assets/shaders/mirror_spectral.gdshader"
const LoadoutScript := preload("res://scripts/core/character_loadout.gd")

## Enemy attack clips: [clip, clip_start, clip_contact, clip_end] (contact = blade peak speed).
const ENEMY_ATTACK_CLIPS: Dictionary = {
	"skeleton_slash": ["1H_Melee_Attack_Chop", 0.05, 0.50, 1.00],
	"melee_slash": ["1H_Melee_Attack_Slice_Diagonal", 0.0, 0.42, 0.95],
	"phantom_lunge": ["1H_Melee_Attack_Stab", 0.0, 0.40, 1.10],
	"shield_bash": ["Block_Attack", 0.0, 0.45, 1.00],
	"warden_cleave": ["2H_Melee_Attack_Chop", 0.10, 0.75, 1.50],
	"warden_lunge": ["2H_Melee_Attack_Stab", 0.0, 0.40, 1.30],
	"hex_bolt": ["Spellcast_Shoot", 0.0, 0.42, 1.05],
	"grave_slam": ["2H_Melee_Attack_Chop", 0.10, 0.75, 1.50],
	"stalker_stab": ["Dualwield_Melee_Attack_Stab", 0.0, 0.38, 1.00],
}

@export var actor_path: NodePath = NodePath("..")
@export var model_root_path: NodePath = NodePath("../VisualRoot/ModelRoot")
@export var enforce_model_180_y_rotation: bool = true
@export var apply_spectral_shader: bool = false
@export var apply_default_loadout: bool = true

var current_clip_name: String = ""
var current_speed_scale: float = 1.0
var _action_lock_timer: float = 0.0
var _actor: Node = null
var _anim_player: AnimationPlayer = null
var _spectral_mat: ShaderMaterial = null

# Attack timeline (seconds into clip) + gameplay phase lengths.
var _tl_active: bool = false
var _tl_clip: String = ""
var _tl: Dictionary = {}
var _tl_elapsed: float = 0.0


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
	# Enemies asleep in another section (or realm) are hidden: don't animate them.
	if _actor is EnemyBase and not (_actor as EnemyBase).is_active and not (_actor as EnemyBase).is_dead:
		return
	if _actor is PlayerController:
		_process_player(_actor as PlayerController, delta)
	elif _actor is EnemyAI:
		_process_enemy(_actor as EnemyAI, delta)


# ------------------------------------------------------------------ player

func _process_player(pc: PlayerController, delta: float) -> void:
	if _tl_active:
		if pc.current_state == PlayerController.State.LIGHT_ATTACK or pc.current_state == PlayerController.State.HEAVY_ATTACK:
			_drive_timeline(pc.get_attack_elapsed(), delta)
			return
		_tl_active = false
	if pc.current_state != PlayerController.State.LOCOMOTION or _action_lock_timer > 0.0:
		return
	if pc.is_currently_airborne():
		if pc.velocity.y > 1.5:
			play_candidates(["Jump_Idle", "Jump_Start", "Idle"], -1.0, false, true, 1.0)
		else:
			play_candidates(["Jump_Idle", "Idle"], -1.0, false, true, 0.8)
		return
	var horiz_speed: float = Vector2(pc.velocity.x, pc.velocity.z).length()
	if horiz_speed > 3.2:
		var run_scale: float = clampf(horiz_speed / maxf(1.0, pc.run_speed), 0.8, 1.45)
		play_candidates(["Running_A", "Running_B", "Walking_A"], -1.0, false, true, run_scale)
	elif horiz_speed > 0.35:
		play_candidates(["Walking_A", "Walking_B", "Running_A"], -1.0, false, true, clampf(horiz_speed / 2.2, 0.6, 1.5))
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
		if apply_default_loadout and not (_actor is PlayerController):
			LoadoutScript.apply_default_for(model_root, "enemy")
			_apply_hostile_appearance(model_root)
		if apply_spectral_shader or (_actor != null and _actor is PhantomTwin):
			_apply_spectral_material_recursive(model_root)

	if _actor is PlayerController:
		var pc: PlayerController = _actor as PlayerController
		if not pc.state_changed.is_connected(_on_player_state_changed):
			pc.state_changed.connect(_on_player_state_changed)
		if not pc.attack_started.is_connected(_on_player_attack_started):
			pc.attack_started.connect(_on_player_attack_started)
		if not pc.dodge_started.is_connected(_on_player_dodge_started):
			pc.dodge_started.connect(_on_player_dodge_started)
		if not pc.jumped.is_connected(_on_player_jumped):
			pc.jumped.connect(_on_player_jumped)
		if not pc.landed.is_connected(_on_player_landed):
			pc.landed.connect(_on_player_landed)
		if not pc.attack_deflected.is_connected(_on_player_deflected):
			pc.attack_deflected.connect(_on_player_deflected)
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
		if not ai.died.is_connected(_on_enemy_died):
			ai.died.connect(_on_enemy_died)
		_on_enemy_state_changed(ai.current_state)


func get_animation_player() -> AnimationPlayer:
	return _anim_player


func _resolve_clip(candidates: Array[String]) -> String:
	if _anim_player == null:
		return candidates[0] if not candidates.is_empty() else ""
	for c in candidates:
		if _anim_player.has_animation(c):
			return c
		if _anim_player.has_animation("Animations/" + c):
			return "Animations/" + c
	return ""


func play_candidates(
	candidates: Array[String],
	target_duration: float = -1.0,
	force_restart: bool = false,
	is_looping: bool = false,
	explicit_speed: float = 1.0
) -> bool:
	if candidates.is_empty():
		return false

	var chosen: String = _resolve_clip(candidates)
	if chosen.is_empty():
		chosen = candidates[0]

	var computed_speed: float = explicit_speed
	if _anim_player != null and _anim_player.has_animation(chosen):
		var anim_res: Animation = _anim_player.get_animation(chosen)
		if anim_res != null:
			# Only touch loop_mode on change: every set emits 'changed' on an Animation shared by ALL instances of
			# the rig, forcing every AnimationPlayer to rebuild its caches (O(n^2) per frame with many enemies).
			var want_loop: Animation.LoopMode = Animation.LOOP_LINEAR if is_looping else Animation.LOOP_NONE
			if anim_res.loop_mode != want_loop:
				anim_res.loop_mode = want_loop
			if target_duration > 0.0 and anim_res.length > 0.05:
				computed_speed = clampf((anim_res.length * 0.90) / target_duration, 0.6, 3.2)

	if not force_restart and current_clip_name == chosen and _anim_player != null and _anim_player.is_playing():
		_anim_player.speed_scale = computed_speed
		current_speed_scale = computed_speed
		return true

	current_clip_name = chosen
	current_speed_scale = computed_speed
	if _anim_player != null and _anim_player.has_animation(chosen):
		var blend_time: float = 0.14 if is_looping else 0.07
		_anim_player.speed_scale = computed_speed
		_anim_player.play(chosen, blend_time, 1.0)
		if force_restart:
			_anim_player.seek(0.0, true)

	animation_triggered.emit(current_clip_name)
	return true


# ------------------------------------------------------------------ attack timeline

## Starts a remapped clip. `tl` needs clip_start, clip_contact, clip_end, windup, active, recovery.
func start_timeline(candidates: Array[String], tl: Dictionary) -> void:
	var clip: String = _resolve_clip(candidates)
	if clip.is_empty() or _anim_player == null:
		_tl_active = false
		return
	var anim_res: Animation = _anim_player.get_animation(clip)
	if anim_res != null and anim_res.loop_mode != Animation.LOOP_NONE:
		anim_res.loop_mode = Animation.LOOP_NONE
	_tl = tl
	_tl_clip = clip
	_tl_active = true
	_tl_elapsed = 0.0
	current_clip_name = clip
	_anim_player.speed_scale = 1.0
	_anim_player.play(clip, 0.05, 1.0)
	_anim_player.seek(float(tl.get("clip_start", 0.0)), true)
	animation_triggered.emit(clip)


func _timeline_target(e: float) -> float:
	var w: float = maxf(0.01, float(_tl.get("windup", 0.1)))
	var a: float = maxf(0.01, float(_tl.get("active", 0.1)))
	var r: float = maxf(0.01, float(_tl.get("recovery", 0.2)))
	var cs: float = float(_tl.get("clip_start", 0.0))
	var cc: float = float(_tl.get("clip_contact", 0.4))
	var ce: float = float(_tl.get("clip_end", cc + 0.5))
	var pre: float = maxf(cs, cc - 0.11)
	var post: float = cc + 0.10
	if e < w:
		# Ease-out into the backswing so the pose *hangs* at the top just before release.
		var u: float = e / w
		return lerpf(cs, pre, 1.0 - (1.0 - u) * (1.0 - u))
	if e < w + a:
		return lerpf(pre, post, (e - w) / a)
	var u3: float = clampf((e - w - a) / r, 0.0, 1.0)
	return lerpf(post, ce, 1.0 - pow(1.0 - u3, 3.0))


func _drive_timeline(elapsed: float, delta: float) -> void:
	if _anim_player == null or not _tl_active:
		return
	if _anim_player.current_animation != _tl_clip:
		_anim_player.play(_tl_clip, 0.0, 1.0)
	var target: float = _timeline_target(elapsed)
	var cur: float = _anim_player.current_animation_position
	var err: float = target - cur
	if absf(err) > 0.09 or delta <= 0.0:
		_anim_player.seek(target, true)
		# Predict next frame's rate from the remap slope.
		var ahead: float = _timeline_target(elapsed + maxf(delta, 0.001))
		_anim_player.speed_scale = clampf((ahead - target) / maxf(delta, 0.001), 0.0, 8.0)
	else:
		var ahead2: float = _timeline_target(elapsed + delta)
		_anim_player.speed_scale = clampf((ahead2 - cur) / delta, 0.0, 8.0)
	current_speed_scale = _anim_player.speed_scale


# ------------------------------------------------------------------ player events

func _on_player_state_changed(new_state: int) -> void:
	match new_state:
		PlayerController.State.DODGE:
			pass  # handled by dodge_started (needs direction)
		PlayerController.State.LANDING_PLUNGE:
			_tl_active = false
			play_candidates(["1H_Melee_Attack_Jump_Chop", "2H_Melee_Attack_Chop", "1H_Melee_Attack_Chop"], 0.45, true, false)
		PlayerController.State.STAGGER:
			_tl_active = false
			_action_lock_timer = 0.22
			play_candidates(["Hit_A", "Hit_B"], 0.30, true, false)
		PlayerController.State.DEAD:
			_tl_active = false
			_action_lock_timer = 1.5
			play_candidates(["Death_A", "Death_B"], -1.0, true, false)
		PlayerController.State.LOCOMOTION:
			_tl_active = false
			if _anim_player != null:
				_anim_player.speed_scale = 1.0
			if current_clip_name.contains("Death"):
				_action_lock_timer = 0.0
				play_candidates(["Idle", "Idle_A"], -1.0, true, true)


func _on_player_attack_started(attack_name: String, timing: Dictionary) -> void:
	if attack_name == "landing_plunge":
		return
	var clip: String = String(timing.get("clip", "1H_Melee_Attack_Chop"))
	start_timeline([clip, "1H_Melee_Attack_Chop", "1H_Melee_Attack_Slice_Diagonal"], timing)


func _on_player_dodge_started(dir: Vector3, dur: float) -> void:
	_tl_active = false
	var clip: Array[String] = ["Dodge_Forward", "Dodge_Right"]
	var pc: PlayerController = _actor as PlayerController
	if pc != null:
		var fwd: Vector3 = pc.get_facing_direction()
		if fwd.dot(dir) < -0.5:
			clip = ["Dodge_Backward", "Dodge_Forward"]
	play_candidates(clip, dur, true, false)


func _on_player_jumped() -> void:
	_tl_active = false
	_action_lock_timer = 0.14
	play_candidates(["Jump_Start", "Jump_Idle"], 0.22, true, false)


func _on_player_landed(impact: float) -> void:
	if impact > 9.0:
		_action_lock_timer = 0.16
		play_candidates(["Jump_Land", "Idle"], 0.22, true, false)


func _on_player_deflected(is_heavy: bool) -> void:
	if is_heavy:
		return
	_tl_active = false
	_action_lock_timer = 0.3
	play_candidates(["Block_Hit", "Hit_B", "Hit_A"], 0.32, true, false)


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


# ------------------------------------------------------------------ enemy

func _process_enemy(ai: EnemyAI, delta: float) -> void:
	if ai.is_dead:
		return
	match ai.current_state:
		EnemyAI.State.WINDUP:
			_drive_timeline(ai.get_state_elapsed(), delta)
		EnemyAI.State.ATTACK:
			_drive_timeline(float(_tl.get("windup", 0.5)) + ai.get_state_elapsed(), delta)
		EnemyAI.State.RECOVER:
			if _tl_active:
				var e: float = float(_tl.get("windup", 0.5)) + float(_tl.get("active", 0.2)) + ai.get_state_elapsed()
				if e < float(_tl.get("windup", 0.5)) + float(_tl.get("active", 0.2)) + float(_tl.get("recovery", 0.8)):
					_drive_timeline(e, delta)
				else:
					_tl_active = false
			if not _tl_active:
				play_candidates(["Idle_Combat", "Idle", "Idle_A"], -1.0, false, true)
		EnemyAI.State.CHASE:
			_tl_active = false
			if ai.is_taunting():
				play_candidates(["Taunt", "Cheer", "Idle_Combat"], -1.0, false, false)
				return
			if ai.is_evading():
				play_candidates([ai.get_evade_clip(), "Dodge_Backward", "Dodge_Forward"], 0.3, false, false)
				return
			_play_directional_locomotion(ai)
		EnemyAI.State.IDLE:
			_tl_active = false
			if Vector2(ai.velocity.x, ai.velocity.z).length() > 0.3:
				_play_directional_locomotion(ai)
			elif _actor is ShieldedGuard and (_actor as ShieldedGuard).is_shield_raised():
				play_candidates(["Blocking", "Block", "Idle_Combat"], -1.0, false, true)
			else:
				play_candidates(["Idle_Combat", "Idle", "Idle_A"], -1.0, false, true)
		EnemyAI.State.ALERT, EnemyAI.State.RETURNING, EnemyAI.State.FLEEING:
			_tl_active = false
			_play_directional_locomotion(ai)
		EnemyAI.State.STUNNED:
			_tl_active = false
			var el: float = ai.get_state_elapsed()
			var remain: float = ai.get_state_duration() - el
			if el < 0.5:
				play_candidates(["Lie_Down", "Hit_B"], 0.5, false, false)
			elif remain < 0.65:
				play_candidates(["Lie_StandUp", "Idle"], maxf(0.2, remain), false, false)
			else:
				play_candidates(["Lie_Idle", "Lie_Pose", "Hit_B"], -1.0, false, true)


## Strafe / back-pedal / run chosen from velocity relative to facing (enemies circle while waiting).
func _play_directional_locomotion(ai: EnemyAI) -> void:
	var v: Vector3 = Vector3(ai.velocity.x, 0.0, ai.velocity.z)
	var speed: float = v.length()
	if speed < 0.3:
		if _actor is ShieldedGuard and (_actor as ShieldedGuard).is_shield_raised():
			play_candidates(["Blocking", "Idle_Combat", "Idle"], -1.0, false, true)
		else:
			play_candidates(["Idle_Combat", "Idle", "Idle_A"], -1.0, false, true)
		return
	var f: Vector3 = ai.get_facing_direction()
	var right: Vector3 = Vector3(-f.z, 0.0, f.x)
	var fwd_c: float = v.dot(f) / speed
	var side_c: float = v.dot(right) / speed
	var rate: float = clampf(speed / maxf(1.0, ai.move_speed), 0.6, 1.6)
	if fwd_c > 0.55:
		if speed > ai.move_speed * 0.75:
			play_candidates(["Running_A", "Running_B", "Walking_A"], -1.0, false, true, rate)
		else:
			play_candidates(["Walking_A", "Walking_B", "Running_A"], -1.0, false, true, rate * 1.3)
	elif fwd_c < -0.55:
		play_candidates(["Walking_Backwards", "Walking_A"], -1.0, false, true, rate * 1.2)
	elif side_c > 0.0:
		play_candidates(["Running_Strafe_Right", "Walking_A"], -1.0, false, true, rate)
	else:
		play_candidates(["Running_Strafe_Left", "Walking_A"], -1.0, false, true, rate)


func _on_enemy_state_changed(new_state: int) -> void:
	match new_state:
		EnemyAI.State.IDLE:
			if _actor is ShieldedGuard and (_actor as ShieldedGuard).is_shield_raised():
				play_candidates(["Blocking", "Block", "Idle_Combat", "Idle"], -1.0, false, true)
			else:
				play_candidates(["Idle_Combat", "Idle", "Idle_A"], -1.0, false, true)
		EnemyAI.State.STAGGER:
			_tl_active = false
			var s_dur: float = (_actor as EnemyAI).get_state_duration() if _actor is EnemyAI else 0.4
			var hit_clips: Array[String] = ["Hit_A", "Hit_B"]
			if s_dur >= 0.4:
				hit_clips = ["Hit_B", "Hit_A"]
			play_candidates(hit_clips, s_dur, true, false)
		EnemyAI.State.DEAD:
			_tl_active = false
			play_candidates(["Death_A", "Death_B"], -1.0, true, false)
		EnemyAI.State.STUNNED:
			_tl_active = false
			play_candidates(["Lie_Down", "Hit_B"], 0.5, true, false)


func _on_enemy_attack_telegraphed(attack_name: String, windup_sec: float) -> void:
	var ai: EnemyAI = _actor as EnemyAI
	var spec: Array = ENEMY_ATTACK_CLIPS.get(attack_name, ENEMY_ATTACK_CLIPS["melee_slash"]) as Array
	var tl: Dictionary = {
		"clip_start": float(spec[1]),
		"clip_contact": float(spec[2]),
		"clip_end": float(spec[3]),
		"windup": windup_sec,
		"active": ai.attack_active_duration if ai != null else 0.22,
		"recovery": ai.recover_duration if ai != null else 0.8,
	}
	start_timeline([String(spec[0]), "1H_Melee_Attack_Chop", "2H_Melee_Attack_Chop"], tl)


func _on_enemy_died(_enemy: Node, _ctx: Dictionary) -> void:
	_tl_active = false
	play_candidates(["Death_A", "Death_B"], -1.0, true, false)


func _configure_animation_loops() -> void:
	if _anim_player == null:
		return
	var loop_names: Array[String] = [
		"Idle", "Idle_A", "Idle_B", "Idle_Combat",
		"Running_A", "Running_B", "Walking_A", "Walking_B", "Walking_Backwards",
		"Running_Strafe_Left", "Running_Strafe_Right",
		"Jump_Idle", "Block", "Blocking", "Lie_Idle", "Spellcasting", "2H_Melee_Idle",
	]
	for base_name in loop_names:
		for cand in [base_name, "Animations/" + base_name]:
			if _anim_player.has_animation(cand):
				var anim_res: Animation = _anim_player.get_animation(cand)
				if anim_res != null and anim_res.loop_mode != Animation.LOOP_LINEAR:
					anim_res.loop_mode = Animation.LOOP_LINEAR


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


## Hostile rigs keep their KayKit texture; they only get a slightly weathered, cooler tint so they read as
## enemies next to the (warm, saturated) squad. Never a flat material_override: that erased the texture and
## made every Skeleton Guard a solid red silhouette.
const HOSTILE_TINT := Color(0.84, 0.82, 0.80, 1.0)
const HOSTILE_KNIGHT_TINT := Color(0.56, 0.56, 0.64, 1.0)


func _apply_hostile_appearance(root: Node3D) -> void:
	# Spectral rigs (Phantom Twins) are fully covered by the spectral material_override instead.
	if _actor is EnemyBase and not apply_spectral_shader and not (_actor is PhantomTwin):
		# Hostile Knights (Shielded Guard) share the player's / Ivo's rig: blackened steel keeps them apart.
		var is_knight: bool = root.find_child("Knight_Body", true, false) != null
		_tint_surfaces_recursive(root, HOSTILE_KNIGHT_TINT if is_knight else HOSTILE_TINT)


func _tint_surfaces_recursive(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh != null and mi.material_override == null:
			for s in range(mi.mesh.get_surface_count()):
				var src: Material = mi.get_surface_override_material(s)
				if src == null:
					src = mi.mesh.surface_get_material(s)
				if src is StandardMaterial3D:
					var m: StandardMaterial3D = (src as StandardMaterial3D).duplicate() as StandardMaterial3D
					m.albedo_color = m.albedo_color * tint
					mi.set_surface_override_material(s, m)
	for child in node.get_children():
		_tint_surfaces_recursive(child, tint)
