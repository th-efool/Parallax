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
signal thralls_summoned(count: int)

const WardenLookScript := preload("res://scripts/enemies/warden_look.gd")

@export_group("Warden Tuning")
@export var cleave_damage: int = 28
@export var lunge_damage: int = 35
@export var cleave_range: float = 3.3
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

@export_group("Summons")
## Every `summon_interval` seconds of the fight the Warden stops, casts (chest rune exposed in Phase 1) and raises
## `summon_min..summon_max` bone thralls. Phase 1: they step out of the Central Mirror Plane — skeletons (fight in
## either realm) on its west face, phantoms (fight only in the Mirror) on its east face. Phase 2 (plane shattered):
## they rise from the sand anywhere.
@export var summon_enabled: bool = true
@export var summon_interval: float = 20.0
@export var summon_min: int = 3
@export var summon_max: int = 7
## Hard cap on living thralls so an ignored wave can't snowball into an unwinnable arena.
@export var summon_max_alive: int = 10
@export var summon_cast_duration: float = 1.4
## Base HP before EnemyBase.HEALTH_SCALE (52 -> 130): thralls die to a short combo.
@export var summon_thrall_health: int = 52

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

## Set by the level builder: func(kind: String, global_pos: Vector3, face_toward: Vector3) -> EnemyBase.
var summon_factory: Callable = Callable()
var _summon_timer: float = 0.0
var _summon_cast_timer: float = 0.0
var _summons: Array[EnemyBase] = []
var _pending_summons: Array = []   # [kind, global_pos]
var _sigils: Array[Node3D] = []


func _ready() -> void:
	_health_scaled = true
	_damage_scaled = true
	super._ready()
	select_next_move(BossMove.CLEAVE)
	_summon_timer = summon_interval
	var model: Node3D = get_node_or_null(NodePath(String(visual_root_path) + "/ModelRoot")) as Node3D
	if model != null and not model.has_meta("warden_dressed"):
		model.set_meta("warden_dressed", true)
		WardenLookScript.dress(model)

func _init() -> void:
	realm_affinity = RealmReactive.Affinity.BOTH_STATEFUL
	award_standard_kill_score = false
	max_health = 1500
	health = 1500
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
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity_and_slide(delta)
		_transition_timer = maxf(0.0, _transition_timer - delta)
		if _transition_timer <= 0.0:
			complete_phase2_transition_now()
		return

	if _summon_cast_timer > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity_and_slide(delta)
		_summon_cast_timer = maxf(0.0, _summon_cast_timer - delta)
		if _summon_cast_timer <= 0.0:
			_finish_summon()
		return

	_tick_summons(delta)
	super.step_ai(delta)


# --- Summons ---------------------------------------------------------------------------------------------

func _fight_engaged() -> bool:
	var ed: EncounterDirector = EncounterDirector.instance as EncounterDirector
	return ed != null and ed.current_encounter_id == encounter_id and get_current_target() != null


func get_alive_summon_count() -> int:
	var n: int = 0
	for s in _summons:
		if is_instance_valid(s) and not s.is_dead:
			n += 1
	return n


func _tick_summons(delta: float) -> void:
	if not summon_enabled or summon_factory.is_null() or not _fight_engaged():
		return
	_summon_timer -= delta
	if _summon_timer > 0.0:
		return
	# Wait for a neutral moment: never cut into a wind-up, strike or recovery.
	if current_state != State.CHASE and current_state != State.IDLE:
		return
	begin_summon()


## Starts the summon cast now (also used by tests). Returns the number of thralls that will appear.
func begin_summon() -> int:
	_summon_timer = summon_interval
	var live: Array[EnemyBase] = []
	for s in _summons:
		if is_instance_valid(s):
			live.append(s)
	_summons = live
	var room: int = summon_max_alive - get_alive_summon_count()
	var n: int = mini(randi_range(summon_min, summon_max), room)
	if n <= 0:
		return 0
	_pending_summons = _pick_summon_points(n)
	_summon_cast_timer = summon_cast_duration
	velocity.x = 0.0
	velocity.z = 0.0
	_clear_telegraph_flash()
	var target: Node3D = get_current_target()
	if target != null:
		set_facing_direction(target.global_position - global_position)
	var bridge: CharacterAnimationBridge = get_node_or_null("CharacterAnimationBridge") as CharacterAnimationBridge
	if bridge != null:
		bridge.play_candidates(["Spellcast_Summon", "Spellcast_Raise", "Taunt"], summon_cast_duration, true, false)
	if AudioManager.instance != null:
		AudioManager.instance.play_sfx("enemy/warden_roar", -2.0)
	for entry in _pending_summons:
		_sigils.append(_spawn_sigil(entry[1] as Vector3, String(entry[0]) == "phantom"))
	# Phase 1: the cast is an opening — the chest rune is exposed exactly like a recovery window.
	if current_phase == Phase.PHASE_1_SPLIT:
		is_chest_rune_exposed = true
		_update_rune_glow()
		chest_rune_exposed_changed.emit(true, summon_cast_duration)
	return n


func _finish_summon() -> void:
	_summon_cast_timer = 0.0
	_clear_chest_rune_exposure()
	var count: int = 0
	if not is_dead and summon_factory.is_valid():
		var face: Vector3 = global_position
		for entry in _pending_summons:
			var e: EnemyBase = summon_factory.call(String(entry[0]), entry[1] as Vector3, face) as EnemyBase
			if e != null:
				_register_summon(e)
				count += 1
	_pending_summons.clear()
	_clear_sigils()
	if count > 0:
		thralls_summoned.emit(count)


func _pick_summon_points(n: int) -> Array:
	var plane: BreakableProp = get_node_or_null(mirror_plane_prop_path) as BreakableProp if not mirror_plane_prop_path.is_empty() else null
	var centre: Vector3 = plane.global_position if plane != null else get_home_position()
	var ax: Vector3 = plane.global_transform.basis.x.normalized() if plane != null else Vector3.RIGHT
	var az: Vector3 = plane.global_transform.basis.z.normalized() if plane != null else Vector3.BACK
	var from_plane: bool = current_phase == Phase.PHASE_1_SPLIT and plane != null and plane.current_state == BreakableProp.PropState.INTACT
	var target: Node3D = get_current_target()
	var out: Array = []
	for i in range(n):
		var best: Array = []
		for attempt in range(10):
			var kind: String
			var p: Vector3
			if from_plane:
				var side: float = -1.0 if i % 2 == 0 else 1.0
				p = centre + ax * side * randf_range(1.3, 2.3) + az * randf_range(-8.5, 8.5)
				kind = "skeleton" if side < 0.0 else "phantom"
			else:
				var a: float = randf() * TAU
				var r: float = randf_range(5.5, 11.0)
				p = centre + ax * cos(a) * r + az * sin(a) * r
				kind = "skeleton" if randf() < 0.6 else "phantom"
			best = [kind, p]
			var ok: bool = Vector2(p.x - global_position.x, p.z - global_position.z).length() > 2.5
			if ok and target != null:
				ok = Vector2(p.x - target.global_position.x, p.z - target.global_position.z).length() > 3.0
			for prev in out:
				var q: Vector3 = prev[1] as Vector3
				if Vector2(p.x - q.x, p.z - q.z).length() < 1.6:
					ok = false
			if ok:
				break
		out.append(best)
	return out


func _register_summon(e: EnemyBase) -> void:
	_summons.append(e)
	e.set_meta("warden_thrall", true)
	e.died.connect(func(_enemy, _ctx) -> void:
		if is_instance_valid(e) and e.is_inside_tree():
			get_tree().create_timer(2.5).timeout.connect(func() -> void:
				if is_instance_valid(e):
					e.queue_free()))
	e.tree_exiting.connect(func() -> void:
		var ed: EncounterDirector = EncounterDirector.instance as EncounterDirector
		if ed != null:
			ed.unregister_section_enemy(e.section_id as EncounterDirector.Section, e))
	if e is EnemyAI:
		(e as EnemyAI).receive_alert(get_current_target(), self, true)
	# Rise: scale the visual up from the floor with a dust puff.
	var vr: Node3D = e.get_node_or_null(e.visual_root_path) as Node3D
	if vr != null:
		var final_scale: Vector3 = vr.scale
		vr.scale = final_scale * 0.15
		var tw: Tween = vr.create_tween()
		tw.tween_property(vr, "scale", final_scale, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var bridge: CharacterAnimationBridge = e.get_node_or_null("CharacterAnimationBridge") as CharacterAnimationBridge
	if bridge != null:
		bridge.play_candidates(["Spawn_Ground_Skeletons", "Skeletons_Awaken_Standing", "Spawn_Ground"], 0.9, true, false)
	GameFeel.play_sound(self, "thud", e.global_position, -4.0, 0.8)


func _spawn_sigil(at: Vector3, mirror: bool) -> Node3D:
	var host: Node = get_parent() if get_parent() != null else self
	var root := Node3D.new()
	root.name = "ThrallSigil"
	host.add_child(root)
	root.global_position = at + Vector3(0, 0.04, 0)
	var col: Color = Color(0.25, 0.72, 1.0) if mirror else Color(1.0, 0.62, 0.25)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.55
	tor.outer_radius = 0.75
	tor.rings = 32
	tor.ring_segments = 6
	ring.mesh = tor
	ring.scale = Vector3(1.0, 0.08, 1.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(col.r, col.g, col.b, 0.9)
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 0.0
	light.omni_range = 2.4
	light.position = Vector3(0, 0.4, 0)
	root.add_child(light)
	root.scale = Vector3.ONE * 0.2
	var tw: Tween = root.create_tween().set_parallel(true)
	tw.tween_property(root, "scale", Vector3.ONE, summon_cast_duration * 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(light, "light_energy", 2.2, summon_cast_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(ring, "rotation:y", TAU, summon_cast_duration)
	return root


func _clear_sigils() -> void:
	for s in _sigils:
		if is_instance_valid(s):
			s.queue_free()
	_sigils.clear()


## Removes every thrall (player death / section reset). `crumble` plays their death (no score) instead.
func _dismiss_summons(crumble: bool) -> void:
	_summon_cast_timer = 0.0
	_pending_summons.clear()
	_clear_sigils()
	for s in _summons:
		if not is_instance_valid(s):
			continue
		if crumble and not s.is_dead and s.is_inside_tree():
			s.award_standard_kill_score = false
			s._die("warden_bond")
		else:
			s.queue_free()
	if not crumble:
		_summons.clear()


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


func _queue_next_move() -> void:
	_move_counter += 1
	select_next_move(BossMove.CLEAVE if _move_counter % 2 == 0 else BossMove.LUNGE)


func start_windup(custom_windup: float = -1.0) -> void:
	if current_phase == Phase.PHASE_2_TRANSITION or is_dead or not is_active:
		return

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
		var lunge_vel: Vector3 = get_facing_direction() * lunge_speed
		velocity.x = lunge_vel.x
		velocity.z = lunge_vel.z
	else:
		velocity.x = 0.0
		velocity.z = 0.0


func _clear_chest_rune_exposure() -> void:
	if is_chest_rune_exposed:
		is_chest_rune_exposed = false
		_update_rune_glow()
		chest_rune_exposed_changed.emit(false, 0.0)


func _transition_to(next_state: State, duration: float) -> void:
	# A stagger (heavy hit on the exposed rune) cuts the summon cast short: the thralls arrive early.
	# Deferred: staggers arrive from a sword hitbox's area_entered (physics flush); adding thrall bodies there is illegal.
	if _summon_cast_timer > 0.0 and next_state == State.STAGGER:
		_summon_cast_timer = 0.0
		_finish_summon.call_deferred()
	if next_state != State.RECOVER:
		_clear_chest_rune_exposure()
	super._transition_to(next_state, duration)


func _enter_recover(custom_recover: float = -1.0) -> void:
	if phase2_chain_enabled and custom_recover < 0.0 and current_phase == Phase.PHASE_2_MERGED and current_move == BossMove.CLEAVE and not is_dead:
		var hb: Hitbox3D = get_attack_hitbox()
		if hb != null:
			hb.end_swing()
		velocity.x = 0.0
		velocity.z = 0.0
		_queue_next_move()
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
	_queue_next_move()


func _on_recover_finished() -> void:
	_clear_chest_rune_exposure()


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
	return int(round(float(max_health) * 0.666))


func _should_stagger_on_hit(is_heavy: bool, _source_type: String) -> bool:
	return is_heavy and is_vulnerable_to_full_damage() and current_state != State.STAGGER


func _on_damage_taken(_final_damage: int, _is_heavy: bool, _source_type: String) -> void:
	if current_phase == Phase.PHASE_1_SPLIT and health <= _phase2_threshold():
		health = maxi(health, _phase2_threshold())
		_trigger_phase2_transition()


func _trigger_phase2_transition() -> void:
	_clear_telegraph_flash()
	_release_token()
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.end_swing()

	current_phase = Phase.PHASE_2_TRANSITION
	_transition_timer = phase2_transition_duration
	velocity.x = 0.0
	velocity.z = 0.0
	_transition_to(State.STAGGER, phase2_transition_duration)

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
	_dismiss_summons(false)
	_summon_timer = summon_interval
	current_phase = Phase.PHASE_1_SPLIT
	_transition_timer = 0.0
	_move_counter = 0
	select_next_move(BossMove.CLEAVE)
	is_chest_rune_exposed = false
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
	_clear_chest_rune_exposure()
	_update_rune_glow()
	# His thralls crumble with him (no score for them).
	_dismiss_summons(true)
	super._die(source_type)
	if auto_finalize_run_on_death:
		var run_state: Node = _get_run_state()
		if run_state != null and run_state.has_method("finalize_run"):
			run_state.call("finalize_run", true)
	boss_defeated.emit()
