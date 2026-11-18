class_name WardenBoss
extends EnemyAI
## Stage 05 Execution Arena Final Boss — The Warden (1,000 shared HP).
## Phase 1 (1000 -> 501 HP): Armored in Reality; after Cleave (20 dmg) or Lunge (25 dmg), enters 1.4s recovery
## where Mirror reflection exposes glowing chest rune for full damage & stagger.
## Phase 2 Transition (<= 500 HP): Cancels attack, shatters Mirror Plane, forces RealmManager.force_merge_realms() (locks Q).
## Phase 2 (500 -> 0 HP): Directly vulnerable in Reality with faster Cleave/Lunge cadence.

enum Phase {
	PHASE_1_SPLIT = 1,
	PHASE_2_TRANSITION = 2,
	PHASE_2_MERGED = 3,
}

enum BossMove {
	CLEAVE = 0,
	LUNGE = 1,
}

signal boss_phase_changed(new_phase: int)
signal chest_rune_exposed_changed(is_exposed: bool, window_duration: float)
signal mirror_plane_shattered()
signal boss_defeated()

@export_group("Warden Tuning")
@export var cleave_damage: int = 28
@export var lunge_damage: int = 35
@export var cleave_range: float = 2.8
@export var lunge_range: float = 5.0
@export var lunge_speed: float = 11.0
@export var phase1_windup_duration: float = 0.90
@export var phase1_recovery_window: float = 1.40
@export var phase1_reality_armor_cap: int = 5
## Legacy absolute value (kept for the inspector). Phase 2 now starts at 50 % of max_health (see
## _phase2_threshold), so the global HEALTH_SCALE can't shift it.
@export var phase2_hp_threshold: int = 500
## Phase 2: max damage a single hit can deal (stops 3 allies + finishers deleting the second half in seconds).
@export var phase2_max_hit: int = 120
@export var phase2_transition_duration: float = 1.60
@export var phase2_windup_duration: float = 0.65
@export var phase2_recovery_window: float = 0.85
## Phase 2 chain: a Cleave flows straight into a Lunge with this (still red-telegraphed) wind-up, skipping recovery.
@export var phase2_chain_windup: float = 0.45
@export var phase2_chain_enabled: bool = true
@export var mirror_plane_prop_path: NodePath
@export var auto_finalize_run_on_death: bool = true

@export_group("Chest Rune Glow")
@export var rune_glow_color: Color = Color(0.22, 0.55, 1.0, 1.0)
@export var rune_glow_offset: Vector3 = Vector3(0.0, 1.55, -0.42)
@export var rune_glow_energy_mirror: float = 3.2
@export var rune_glow_energy_reality: float = 0.6

var current_phase: Phase = Phase.PHASE_1_SPLIT
var _rune_glow_root: Node3D = null
var _rune_glow_mat: StandardMaterial3D = null
var _rune_glow_light: OmniLight3D = null
var _rune_glow_tween: Tween = null
var current_move: BossMove = BossMove.CLEAVE
var is_chest_rune_exposed: bool = false
var _transition_timer: float = 0.0
var _move_counter: int = 0
var _lunge_dir: Vector3 = Vector3.BACK


func _ready() -> void:
	_health_scaled = true
	super._ready()

func _init() -> void:
	realm_affinity = RealmReactive.Affinity.BOTH_STATEFUL
	award_standard_kill_score = false
	max_health = 1000
	health = 1000
	detection_range = 24.0
	attack_range = 2.8
	move_speed = 3.5
	windup_duration = 0.90
	attack_active_duration = 0.30
	recover_duration = 1.40
	stagger_duration = 0.80
	attack_damage = 28
	attack_name = "warden_cleave"
	section_id = EncounterDirector.Section.EXECUTION_ARENA
	encounter_id = "the_warden"
	# Boss poise: light hits don't flinch, barely budges, never side-steps.
	flinch_on_light_hits = false
	knockback_scale = 0.15
	evade_skill = 0.0
	attack_lunge_speed = 0.0
	# Boss aggro: never knocked down, never turned by a backstab, never leashes out of its arena, never flees.
	knockdown_immune = true
	backstab_staggers = false
	max_chase_distance = 80.0
	flee_health_ratio = 0.0
	show_state_icon = false
	# The Warden has its own Mirror mechanic (chest rune) — no generic insight bonus.
	mirror_damage_mult = 1.0
	# Never executed by the player's Execution finisher.
	execute_immune = true


func step_ai(delta: float) -> void:
	if is_dead:
		return
	# Fall safety: knockback or a lunge off the arena edge must never kill the boss (world kill plane below
	# y ~ -6). Snap back to the spawn spot instead.
	if global_position.y < get_home_position().y - 4.0:
		global_position = get_home_position()
		velocity = Vector3.ZERO

	if current_phase == Phase.PHASE_2_TRANSITION:
		_transition_timer = maxf(0.0, _transition_timer - delta)
		if _transition_timer <= 0.0:
			complete_phase2_transition_now()
		return

	super.step_ai(delta)


func select_next_move(move: BossMove) -> void:
	current_move = move
	if current_move == BossMove.CLEAVE:
		attack_name = "warden_cleave"
		attack_damage = cleave_damage
		attack_range = cleave_range
	else:
		attack_name = "warden_lunge"
		attack_damage = lunge_damage
		attack_range = lunge_range


func start_windup(custom_windup: float = -1.0) -> void:
	if current_phase == Phase.PHASE_2_TRANSITION:
		return

	if _move_counter % 2 == 0:
		select_next_move(BossMove.CLEAVE)
	else:
		select_next_move(BossMove.LUNGE)
	_move_counter += 1

	var p: Node3D = _resolve_target_player()
	if p != null:
		var dir: Vector3 = p.global_position - global_position
		dir.y = 0.0
		if dir.length_squared() > 0.001:
			_lunge_dir = dir.normalized()

	var w_dur: float = phase1_windup_duration if current_phase == Phase.PHASE_1_SPLIT else phase2_windup_duration
	if custom_windup >= 0.0:
		w_dur = custom_windup
	super.start_windup(w_dur)


func complete_phase2_transition_now() -> void:
	if current_phase != Phase.PHASE_2_TRANSITION:
		return
	current_phase = Phase.PHASE_2_MERGED
	_transition_timer = 0.0
	windup_duration = phase2_windup_duration
	recover_duration = phase2_recovery_window
	_transition_to(State.CHASE, 0.0)
	boss_phase_changed.emit(current_phase)


func is_vulnerable_to_full_damage() -> bool:
	if current_phase == Phase.PHASE_2_MERGED:
		return true
	if current_phase == Phase.PHASE_2_TRANSITION:
		return false
	# Phase 1: vulnerable in Mirror during recovery chest-rune opening or stagger
	var in_mirror: bool = (RealmManager.instance != null and RealmManager.instance.current_realm == RealmManager.Realm.MIRROR)
	return in_mirror and (is_chest_rune_exposed or current_state == State.STAGGER)


func _begin_attack_strike() -> void:
	super._begin_attack_strike()
	if current_move == BossMove.LUNGE:
		velocity = _lunge_dir * lunge_speed
	else:
		velocity = Vector3.ZERO


func _enter_recover(custom_recover: float = -1.0) -> void:
	if phase2_chain_enabled and custom_recover < 0.0 and current_phase == Phase.PHASE_2_MERGED and current_move == BossMove.CLEAVE and not is_dead:
		var hb: Hitbox3D = get_attack_hitbox()
		if hb != null:
			hb.end_swing()
		velocity = Vector3.ZERO
		start_windup(phase2_chain_windup) # _move_counter alternation guarantees the follow-up is a Lunge
		return
	var r_dur: float = phase1_recovery_window if current_phase == Phase.PHASE_1_SPLIT else phase2_recovery_window
	if custom_recover >= 0.0:
		r_dur = custom_recover
	super._enter_recover(r_dur)
	if current_phase == Phase.PHASE_1_SPLIT:
		is_chest_rune_exposed = true
		_update_rune_glow()
		chest_rune_exposed_changed.emit(true, r_dur)


func _on_recover_finished() -> void:
	if is_chest_rune_exposed:
		is_chest_rune_exposed = false
		_update_rune_glow()
		chest_rune_exposed_changed.emit(false, 0.0)


func on_realm_changed(_active_realm: int) -> void:
	_update_rune_glow()


# --- Chest rune cobalt glow (Claude Pass A): bright in Mirror (vulnerable), faint hint in Reality ---

func _ensure_rune_glow() -> void:
	if _rune_glow_root != null and is_instance_valid(_rune_glow_root):
		return
	var vis_root: Node3D = get_node_or_null(visual_root_path) as Node3D
	if vis_root == null:
		return
	_rune_glow_root = Node3D.new()
	_rune_glow_root.name = "ChestRuneGlow"
	_rune_glow_root.position = rune_glow_offset
	_rune_glow_root.visible = false

	var core := MeshInstance3D.new()
	core.name = "ChestRuneCore"
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	sm.radial_segments = 16
	sm.rings = 8
	core.mesh = sm
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rune_glow_mat = StandardMaterial3D.new()
	_rune_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rune_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rune_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_rune_glow_mat.albedo_color = Color(rune_glow_color.r, rune_glow_color.g, rune_glow_color.b, 0.0)
	core.material_override = _rune_glow_mat
	_rune_glow_root.add_child(core)

	_rune_glow_light = OmniLight3D.new()
	_rune_glow_light.name = "ChestRuneLight"
	_rune_glow_light.light_color = rune_glow_color
	_rune_glow_light.omni_range = 3.6
	_rune_glow_light.light_energy = 0.0
	_rune_glow_light.shadow_enabled = false
	_rune_glow_root.add_child(_rune_glow_light)
	vis_root.add_child(_rune_glow_root)


func _update_rune_glow() -> void:
	if not is_inside_tree():
		return
	_ensure_rune_glow()
	if _rune_glow_root == null:
		return
	if _rune_glow_tween != null and _rune_glow_tween.is_valid():
		_rune_glow_tween.kill()
	var show_glow: bool = is_chest_rune_exposed and not is_dead
	if not show_glow:
		_rune_glow_root.visible = false
		_rune_glow_mat.albedo_color.a = 0.0
		_rune_glow_light.light_energy = 0.0
		return
	var in_mirror: bool = RealmManager.instance != null and RealmManager.instance.current_realm == RealmManager.Realm.MIRROR
	var energy: float = rune_glow_energy_mirror if in_mirror else rune_glow_energy_reality
	var alpha: float = 0.95 if in_mirror else 0.30
	_rune_glow_root.visible = true
	_rune_glow_root.scale = Vector3.ONE * (1.25 if in_mirror else 0.8)
	_rune_glow_tween = create_tween()
	_rune_glow_tween.set_parallel(true)
	_rune_glow_tween.tween_property(_rune_glow_mat, "albedo_color:a", alpha, 0.10)
	_rune_glow_tween.tween_property(_rune_glow_light, "light_energy", energy, 0.10)
	if in_mirror:
		# Heartbeat pulses across the 1.4s window.
		for _i in range(3):
			_rune_glow_tween.chain().tween_property(_rune_glow_root, "scale", Vector3.ONE * 1.05, 0.22).set_trans(Tween.TRANS_SINE)
			_rune_glow_tween.chain().tween_property(_rune_glow_root, "scale", Vector3.ONE * 1.3, 0.22).set_trans(Tween.TRANS_SINE)


func _modify_incoming_damage(amount: int, _is_heavy: bool, source_type: String) -> int:
	if current_phase == Phase.PHASE_2_TRANSITION:
		return 0
	if current_phase == Phase.PHASE_2_MERGED:
		return mini(amount, phase2_max_hit)
	var raw: int = amount
	if source_type != "environmental" and not is_vulnerable_to_full_damage():
		raw = mini(amount, phase1_reality_armor_cap)
	var cap_to_p2: int = maxi(1, health - _phase2_threshold())
	return mini(raw, cap_to_p2)


func _phase2_threshold() -> int:
	return int(round(float(max_health) * 0.5))


func _should_stagger_on_hit(is_heavy: bool, _source_type: String) -> bool:
	return is_heavy and is_vulnerable_to_full_damage()


func _on_damage_taken(_final_damage: int, _is_heavy: bool, _source_type: String) -> void:
	if current_phase == Phase.PHASE_1_SPLIT and health <= _phase2_threshold():
		health = maxi(health, _phase2_threshold())
		_trigger_phase2_transition()


func _trigger_phase2_transition() -> void:
	current_phase = Phase.PHASE_2_TRANSITION
	_transition_timer = phase2_transition_duration
	velocity = Vector3.ZERO

	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.end_swing()

	if is_chest_rune_exposed:
		is_chest_rune_exposed = false
		_update_rune_glow()
		chest_rune_exposed_changed.emit(false, 0.0)

	if not mirror_plane_prop_path.is_empty():
		var plane: BreakableProp = get_node_or_null(mirror_plane_prop_path) as BreakableProp
		if plane != null:
			plane.complete_break_now()

	if RealmManager.instance != null and not RealmManager.instance.is_merged:
		RealmManager.instance.force_merge_realms()

	mirror_plane_shattered.emit()
	boss_phase_changed.emit(current_phase)


func _on_enemy_reset() -> void:
	var was_phase1: bool = (current_phase == Phase.PHASE_1_SPLIT)
	var was_exposed: bool = is_chest_rune_exposed
	current_phase = Phase.PHASE_1_SPLIT
	current_move = BossMove.CLEAVE
	is_chest_rune_exposed = false
	_transition_timer = 0.0
	_move_counter = 0
	windup_duration = phase1_windup_duration
	recover_duration = phase1_recovery_window

	if not mirror_plane_prop_path.is_empty():
		var plane: BreakableProp = get_node_or_null(mirror_plane_prop_path) as BreakableProp
		if plane != null:
			plane.reset_prop()

	if RealmManager.instance != null and (RealmManager.instance.is_merged or RealmManager.instance.shift_locked):
		RealmManager.instance.force_realm(RealmManager.Realm.REALITY, false)

	_update_rune_glow()
	if was_exposed:
		chest_rune_exposed_changed.emit(false, 0.0)
	if not was_phase1:
		boss_phase_changed.emit(current_phase)

	super._on_enemy_reset()


func _die(source_type: String) -> void:
	print("[Warden] defeated by '%s' (phase %d, last attacker %s)" % [source_type, int(current_phase), str(_last_attacker)])
	if is_chest_rune_exposed:
		is_chest_rune_exposed = false
		chest_rune_exposed_changed.emit(false, 0.0)
	_update_rune_glow()
	super._die(source_type)
	if auto_finalize_run_on_death:
		var run_state: Node = _get_run_state()
		if run_state != null and run_state.has_method("finalize_run"):
			run_state.call("finalize_run", true)
	boss_defeated.emit()
