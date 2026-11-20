extends SceneTree
## Headless regression test for Guide 02 (ENM-01..ENM-26).
## Exercises all 26 Enemies & AI fixes without editor class-cache dependency.
## Run: godot --headless --path . -s res://tests/enemies_ai_bugfix_regression_test.gd

const SquadAIConfigScript := preload("res://addons/parallax_squad_ai/squad_ai_config.gd")
const EnemyBaseScript := preload("res://scripts/enemies/enemy_base.gd")
const EnemyAIScript := preload("res://scripts/enemies/enemy_ai.gd")
const ArchetypeEnemyScript := preload("res://scripts/enemies/archetype_enemy.gd")
const PhantomTwinScript := preload("res://scripts/enemies/phantom_twin.gd")
const ShieldedGuardScript := preload("res://scripts/enemies/shielded_guard.gd")
const SkeletonGuardScript := preload("res://scripts/enemies/skeleton_guard.gd")
const SquadCoordinatorScript := preload("res://scripts/enemies/squad_coordinator.gd")
const WardenBossScript := preload("res://scripts/enemies/warden_boss.gd")
const RealmManagerScript := preload("res://scripts/core/realm_manager.gd")
const EncounterDirectorScript := preload("res://scripts/core/encounter_director.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const AllySquadManagerScript := preload("res://scripts/allies/ally_squad_manager.gd")
const SquadAllyScript := preload("res://scripts/allies/squad_ally.gd")

var _results: Array[String] = []
var _main: Node = null
var _level: Node = null
var _player: Node3D = null
var _mgr: Node = null
var _coord: SquadCoordinator = null
var _spawned: Array[EnemyBase] = []
var _idx: int = 0


func _initialize() -> void:
	SquadAIConfigScript.force_offline()
	create_timer(120.0, true, false, true).timeout.connect(func() -> void:
		print("[enm_reg] WATCHDOG TIMEOUT")
		quit(2))
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	_run()


func _check(id_name: String, ok: bool, detail: String = "") -> void:
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", id_name, detail]
	_results.append(line)
	print("[enm_reg] ", line)


func _disable_non_test_enemies() -> void:
	for n in get_nodes_in_group("enemy"):
		if n is EnemyBaseScript and not String(n.name).begins_with("Test_") and not (n is WardenBossScript):
			(n as EnemyBase).set_section_enabled(false)


func _spawn(kind: String, pos: Vector3, face_toward: Vector3 = Vector3(0, 0, -140)) -> EnemyBase:
	_idx += 1
	var e: EnemyBase = _level.call("_add_roamer", _level, kind, "Test_%s_%d" % [kind, _idx], pos, EncounterDirectorScript.Section.ENTRY, face_toward) as EnemyBase
	_disable_non_test_enemies()
	if e != null:
		_spawned.append(e)
	return e


func _cleanup_test_enemies() -> void:
	var fd: Node = root.get_node_or_null("FaunaDirector")
	var fd_list: Array = fd.call("get_enemies") as Array if (fd != null and fd.has_method("get_enemies")) else []
	for e in _spawned:
		if is_instance_valid(e):
			e.is_dead = true
			e.set_section_enabled(false)
			e.remove_from_group("enemy")
			fd_list.erase(e)
			e.queue_free()
	_spawned.clear()
	_disable_non_test_enemies()
	if _coord != null and is_instance_valid(_coord):
		_coord.reset()
		_coord.max_attackers = 2
	await process_frame


func _step_physics(obj: EnemyBase, frames: int, dt: float = 0.05) -> void:
	for _i in range(frames):
		if is_instance_valid(obj) and obj.is_active and not obj.is_dead:
			obj._physics_process(dt)
		await physics_frame


func _run() -> void:
	for _i in range(5):
		await process_frame
	_main.call("start_run_now")
	var t0: int = Time.get_ticks_msec()
	while not bool(_main.get("level_ready")) and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	await physics_frame

	_level = _main.get_node("LevelRoot")
	_player = get_first_node_in_group("player") as Node3D
	_mgr = AllySquadManagerScript.instance
	_coord = SquadCoordinatorScript.get_for(_level)
	if _player != null:
		_player.set("max_health", 100000)
		_player.set("health", 100000)
		_player.global_position = Vector3(0.0, 0.0, -136.0)
	if _mgr != null:
		_mgr.set("rally_enabled", false)
		for a in _mgr.get("allies"):
			if is_instance_valid(a):
				a.set("auto_engage", false)
				a.call("clear_queue")
				a.call("_abort_current_effects")
				a.call("finish_current", "test")
				(a as Node3D).global_position = Vector3(-4.0, 0.0, -139.0)
				(a as Node).process_mode = Node.PROCESS_MODE_DISABLED

	# Disable pre-placed ENTRY roamers so tests remain isolated.
	_disable_non_test_enemies()

	var rm: RealmManager = RealmManagerScript.instance as RealmManager
	var brannoc: SquadAlly = _mgr.call("find_ally", "Brannoc") as SquadAlly if _mgr != null else null
	var sera: SquadAlly = _mgr.call("find_ally", "Sera") as SquadAlly if _mgr != null else null

	# --- ENM-01: Gravity across states + chase edge probe ---
	rm.force_realm(RealmManagerScript.Realm.REALITY, false)
	var e1: EnemyAI = _spawn("skeleton", Vector3(0.0, 3.0, -136.0)) as EnemyAI
	await process_frame
	var states_to_check: Array[int] = [
		EnemyAIScript.State.CHASE,
		EnemyAIScript.State.WINDUP,
		EnemyAIScript.State.ATTACK,
		EnemyAIScript.State.RECOVER,
		EnemyAIScript.State.STAGGER,
		EnemyAIScript.State.STUNNED,
	]
	var gravity_ok: bool = true
	for st in states_to_check:
		e1.global_position = Vector3(0.0, 3.0, -136.0)
		e1.velocity = Vector3.ZERO
		e1._set_target(_player)
		e1._transition_to(st, 2.0)
		await _step_physics(e1, 3, 0.05)
		if e1.velocity.y >= -0.2 or e1.global_position.y >= 3.0:
			gravity_ok = false
			break
	# Chase edge probe at Stage 01 stepping-stone chasm (floor ends at z = -0.5 in Reality).
	var edge_sk: EnemyAI = _spawn("skeleton", Vector3(0.0, 0.0, -1.0), Vector3(0, 0, 4)) as EnemyAI
	await process_frame
	_player.global_position = Vector3(0.0, 0.0, 3.6)
	edge_sk._set_target(_player)
	edge_sk._transition_to(EnemyAIScript.State.CHASE, 0.0)
	await _step_physics(edge_sk, 25, 0.03)
	_check("enm_01_gravity_and_edge_probe", gravity_ok and edge_sk.global_position.z < -0.2, "grav=%s z=%.2f" % [str(gravity_ok), edge_sk.global_position.z])
	_player.global_position = Vector3(0.0, 0.0, -136.0)
	await _cleanup_test_enemies()

	# --- ENM-02: PhantomTwin in Reality never holds/starves tokens or freezes ---
	rm.force_realm(RealmManagerScript.Realm.REALITY, false)
	var ph2: PhantomTwin = _spawn("phantom", Vector3(0.0, 0.0, -133.5)) as PhantomTwin
	var sk2: SkeletonGuard = _spawn("skeleton", Vector3(2.0, 0.0, -133.5)) as SkeletonGuard
	await process_frame
	ph2._taunt_timer = 0.0
	sk2._taunt_timer = 0.0
	ph2._set_target(_player)
	sk2._set_target(_player)
	ph2._transition_to(EnemyAIScript.State.CHASE, 0.0)
	sk2._transition_to(EnemyAIScript.State.CHASE, 0.0)
	await _step_physics(ph2, 10, 0.03)
	var ph_moved: bool = ph2.velocity.length_squared() > 0.01 and not _coord.has_token(ph2)
	var sk_got: bool = _coord.request_attack_token(sk2, _player)
	# Also verify shifting to Reality cancels active Mirror windup.
	rm.force_realm(RealmManagerScript.Realm.MIRROR, false)
	await process_frame
	ph2.start_windup(0.65)
	var was_windup: bool = ph2.current_state == EnemyAIScript.State.WINDUP
	rm.force_realm(RealmManagerScript.Realm.REALITY, false)
	await process_frame
	_check("enm_02_phantom_reality_no_token_or_freeze", ph_moved and sk_got and was_windup and ph2.current_state == EnemyAIScript.State.CHASE and not _coord.has_token(ph2), "moved=%s sk_got=%s state=%d" % [str(ph_moved), str(sk_got), ph2.current_state])
	await _cleanup_test_enemies()

	# --- ENM-03: SkeletonGuard self-revive exclusions, FloatingHPBar, and 3.0s stun retention ---
	var sk_env: SkeletonGuard = _spawn("skeleton", Vector3(-2.0, 0.0, -134.0)) as SkeletonGuard
	var sk_pit: SkeletonGuard = _spawn("skeleton", Vector3(2.0, 0.0, -134.0)) as SkeletonGuard
	var sk_rev: SkeletonGuard = _spawn("skeleton", Vector3(0.0, 0.0, -133.0), Vector3(0.0, 0.0, -125.0)) as SkeletonGuard
	await process_frame
	sk_env.apply_damage(9999, true, "environmental", _player)
	sk_pit.apply_damage(9999, true, "pit", _player)
	# Hit from behind (backstab) with a knockdown source ("player_landing") to verify 3.0s revive stun is preserved.
	_player.global_position = Vector3(0.0, 0.0, -136.0)
	sk_rev.set_facing_direction(Vector3(0.0, 0.0, 1.0))
	sk_rev.apply_damage(9999, true, "player_landing", _player)
	var hp_lbl: Label3D = sk_rev.get_node_or_null("FloatingHPBar") as Label3D
	var revive_ok: bool = (not sk_rev.is_dead) and sk_rev.current_state == EnemyAIScript.State.STUNNED \
		and absf(sk_rev.get_state_duration() - 3.0) < 0.05 \
		and sk_rev.health == maxi(1, int(sk_rev.max_health * 0.5)) \
		and hp_lbl != null and hp_lbl.visible and hp_lbl.text == "%d/%d" % [sk_rev.health, sk_rev.max_health]
	sk_rev.apply_damage(9999, true, "player_heavy", _player)
	_check("enm_03_skeleton_revive_rules", sk_env.is_dead and sk_pit.is_dead and revive_ok and sk_rev.is_dead, "env=%s pit=%s rev=%s second_kill=%s" % [str(sk_env.is_dead), str(sk_pit.is_dead), str(revive_ok), str(sk_rev.is_dead)])
	await _cleanup_test_enemies()

	# --- ENM-04: SquadCoordinator _peak_engaged resets across encounters and reset() ---
	var sq_a: EnemyAI = _spawn("skeleton", Vector3(-1.5, 0.0, -134.0)) as EnemyAI
	var sq_b: EnemyAI = _spawn("skeleton", Vector3(1.5, 0.0, -134.0)) as EnemyAI
	await process_frame
	sq_a._set_target(_player)
	sq_b._set_target(_player)
	sq_a._transition_to(EnemyAIScript.State.CHASE, 0.0)
	sq_b._transition_to(EnemyAIScript.State.CHASE, 0.0)
	var multi_not_enraged: bool = not _coord.is_last_standing(sq_a, _player)
	sq_a.apply_damage(9999, true, "environmental", _player)
	var last_enraged: bool = _coord.is_last_standing(sq_b, _player)
	sq_b.apply_damage(9999, true, "environmental", _player)
	var solo_sg: EnemyAI = _spawn("shield", Vector3(0.0, 0.0, -134.0)) as EnemyAI
	await process_frame
	solo_sg._set_target(_player)
	solo_sg._transition_to(EnemyAIScript.State.CHASE, 0.0)
	await _step_physics(solo_sg, 2, 0.02)
	var solo_calm: bool = not solo_sg.is_enraged()
	_coord._peak_engaged = 3
	_coord.reset()
	_check("enm_04_peak_engaged_resets", multi_not_enraged and last_enraged and solo_calm and _coord._peak_engaged == 0, "multi=%s last=%s solo_calm=%s" % [str(multi_not_enraged), str(last_enraged), str(solo_calm)])
	await _cleanup_test_enemies()

	# --- ENM-05, ENM-06, ENM-22, ENM-23: WardenBoss range sync, rune exposure clear, tracked lunge, Phase 2 cleanup ---
	var warden: WardenBoss = _level.get_node_or_null("Stage05_ExecutionArena/Enemies/TheWarden") as WardenBoss
	if warden != null:
		warden.auto_finalize_run_on_death = false
		warden.set_section_enabled(true)
		warden.reset_enemy()
		await process_frame
		var init_cleave: bool = warden.current_move == WardenBossScript.BossMove.CLEAVE and absf(warden.attack_range - warden.cleave_range) < 0.05
		warden._set_target(_player)
		warden.start_windup(0.05)
		warden._begin_attack_strike()
		warden._enter_recover()
		var next_lunge: bool = warden.current_move == WardenBossScript.BossMove.LUNGE and absf(warden.attack_range - warden.lunge_range) < 0.05 and warden.is_chest_rune_exposed
		# ENM-06: Heavy punish Phase 1 Mirror recovery must clear is_chest_rune_exposed on entering STAGGER.
		rm.force_realm(RealmManagerScript.Realm.MIRROR, false)
		await process_frame
		warden.apply_damage(60, true, "player_heavy", _player)
		var cleared_on_stagger: bool = warden.current_state == EnemyAIScript.State.STAGGER and not warden.is_chest_rune_exposed
		warden._transition_to(EnemyAIScript.State.CHASE, 0.0)
		var armored_in_chase: bool = not warden.is_vulnerable_to_full_damage()
		_check("enm_05_warden_move_range_sync", init_cleave and next_lunge, "init=%s next=%s" % [str(init_cleave), str(next_lunge)])
		_check("enm_06_warden_stagger_clears_rune", cleared_on_stagger and armored_in_chase, "stagger_clear=%s armored=%s" % [str(cleared_on_stagger), str(armored_in_chase)])

		# ENM-22: Warden lunge uses get_facing_direction() even with null target during start_windup.
		warden._set_target(null)
		warden.select_next_move(WardenBossScript.BossMove.LUNGE)
		warden.start_windup(0.2)
		warden.set_facing_direction(Vector3.LEFT)
		warden._begin_attack_strike()
		var w_dir: Vector2 = Vector2(warden.velocity.x, warden.velocity.z).normalized()
		_check("enm_22_warden_lunges_along_tracked_facing", w_dir.dot(Vector2(-1.0, 0.0)) > 0.98, "vel=%s" % str(warden.velocity))

		# ENM-23: Phase 2 transition clears telegraph, token, and windup state.
		warden.reset_enemy()
		warden._set_target(_player)
		_coord.request_attack_token(warden, _player)
		warden.start_windup(0.9)
		warden.apply_damage(600, true, "environmental", _player)
		var p2_clean: bool = warden.current_phase == WardenBossScript.Phase.PHASE_2_TRANSITION \
			and warden.current_state != EnemyAIScript.State.WINDUP \
			and not warden._telegraph_active and not _coord.has_token(warden)
		_check("enm_23_phase2_transition_clears_windup_telegraph_token", p2_clean, "phase=%d state=%d tel=%s" % [int(warden.current_phase), warden.current_state, str(warden._telegraph_active)])
		# Verify reset restores CLEAVE range.
		warden.reset_enemy()
		_check("enm_05_reset_restores_cleave", warden.current_move == WardenBossScript.BossMove.CLEAVE and absf(warden.attack_range - warden.cleave_range) < 0.05)
		warden.set_section_enabled(false)
		rm.force_realm(RealmManagerScript.Realm.REALITY, false)
	else:
		_check("enm_05_warden_move_range_sync", false, "TheWarden missing")
		_check("enm_06_warden_stagger_clears_rune", false, "TheWarden missing")
		_check("enm_22_warden_lunges_along_tracked_facing", false, "TheWarden missing")
		_check("enm_23_phase2_transition_clears_windup_telegraph_token", false, "TheWarden missing")
	_coord.reset()

	# --- ENM-07: Single DAMAGE_SCALE (1.4x) on archetypes ---
	var hx7: ArchetypeEnemy = _spawn("hexcaster", Vector3(-3.0, 0.0, -133.0)) as ArchetypeEnemy
	var br7: ArchetypeEnemy = _spawn("brute", Vector3(0.0, 0.0, -133.0)) as ArchetypeEnemy
	var st7: ArchetypeEnemy = _spawn("stalker", Vector3(3.0, 0.0, -133.0)) as ArchetypeEnemy
	await process_frame
	var exp_hx: int = int(float(hx7.archetype.attack_damage) * EnemyAIScript.DAMAGE_SCALE)
	var exp_br: int = int(float(br7.archetype.attack_damage) * EnemyAIScript.DAMAGE_SCALE)
	var exp_st: int = int(float(st7.archetype.attack_damage) * EnemyAIScript.DAMAGE_SCALE)
	_check("enm_07_single_damage_scale", hx7.attack_damage == exp_hx and br7.attack_damage == exp_br and st7.attack_damage == exp_st, "%d/%d/%d" % [hx7.attack_damage, br7.attack_damage, st7.attack_damage])

	# --- ENM-08 & ENM-09: Bolt evade decay and fire-band token gating ---
	hx7._set_target(_player)
	hx7._transition_to(EnemyAIScript.State.CHASE, 0.0)
	hx7.evade_skill = 1.0
	hx7.consider_evade(_player, true, 0.3)
	var ev_started: bool = hx7.is_evading()
	await _step_physics(hx7, 12, 0.04)
	var ev_ended: bool = not hx7.is_evading()
	_check("enm_08_bolt_evade_timer_decays", ev_started and ev_ended, "started=%s ended=%s" % [str(ev_started), str(ev_ended)])

	hx7._clear_telegraph_flash()
	_coord.release_token(hx7)
	hx7._transition_to(EnemyAIScript.State.CHASE, 0.0)
	hx7.global_position = Vector3(0.0, 0.0, -118.0) # 18 m > attack_range 10.0
	await _step_physics(hx7, 3, 0.03)
	var far_no_tok: bool = not _coord.has_token(hx7)
	hx7.global_position = Vector3(0.0, 0.0, -134.5) # 1.5 m < pref * 0.45 (3.15)
	await _step_physics(hx7, 3, 0.03)
	var close_no_tok: bool = not _coord.has_token(hx7)
	_check("enm_09_bolt_token_only_in_fire_band", far_no_tok and close_no_tok, "far=%s close=%s" % [str(far_no_tok), str(close_no_tok)])

	# --- ENM-10: Shade Stalker blink respects closed Gate01_EntryToHall ---
	_player.global_position = Vector3(0.0, 0.0, 5.8) # north of closed Gate01 (z=5.0)
	_player.call("set_facing_direction", Vector3(0.0, 0.0, -1.0))
	st7.global_position = Vector3(0.0, 0.0, 3.8) # south of closed Gate01
	st7._blink_cd = 0.0
	st7._try_blink_behind(_player)
	var blocked_across_gate: bool = st7.global_position.z < 4.9
	_player.global_position = Vector3(0.0, 0.0, 4.3)
	_player.call("set_facing_direction", Vector3(0.0, 0.0, -1.0)) # back toward Gate01
	st7.global_position = Vector3(0.0, 0.0, 3.2)
	st7._blink_cd = 0.0
	st7._try_blink_behind(_player)
	var blocked_into_gate: bool = st7.global_position.z < 4.9
	_check("enm_10_stalker_blink_respects_gates_and_walls", blocked_across_gate and blocked_into_gate, "across=%s into=%s" % [str(blocked_across_gate), str(blocked_into_gate)])
	_player.global_position = Vector3(0.0, 0.0, -136.0)

	# --- ENM-11: Grave Brute slam ring aligned in world space across rotation & tracking ---
	br7.global_position = Vector3(0.0, 0.0, -132.0)
	br7.rotation.y = PI
	br7.set_facing_direction(Vector3(0.0, 0.0, 1.0))
	br7._set_target(_player)
	br7.start_windup(0.6)
	var ring_m: MeshInstance3D = br7.get_node_or_null("SlamTelegraph") as MeshInstance3D
	var expected_pos: Vector3 = br7.global_position + br7.get_facing_direction() * 0.8 + Vector3.UP * 0.06
	var rot_ok: bool = ring_m != null and ring_m.global_position.distance_to(expected_pos) < 0.05
	br7.set_facing_direction(Vector3.RIGHT)
	br7._process_windup(0.02, _player)
	expected_pos = br7.global_position + br7.get_facing_direction() * 0.8 + Vector3.UP * 0.06
	var track_ok: bool = ring_m != null and ring_m.global_position.distance_to(expected_pos) < 0.05
	_check("enm_11_slam_ring_world_aligned", rot_ok and track_ok, "rot=%s track=%s" % [str(rot_ok), str(track_ok)])

	# --- ENM-24: Inactive/dead archetype skips windup FX ---
	br7.is_active = false
	br7._hide_slam_ring()
	br7.start_windup(0.6)
	var ring_hidden: bool = ring_m == null or not ring_m.visible
	st7.is_dead = true
	var pre_blink_pos: Vector3 = st7.global_position
	st7._blink_cd = 0.0
	st7._set_target(_player)
	st7.start_windup(0.4)
	_check("enm_24_inactive_archetype_skips_windup_fx", ring_hidden and st7.global_position.distance_to(pre_blink_pos) < 0.01)
	await _cleanup_test_enemies()

	# --- ENM-12, ENM-13, ENM-14, ENM-15, ENM-16, ENM-17, ENM-25, ENM-26 ---
	var sk12: EnemyAI = _spawn("skeleton", Vector3(0.0, 0.0, -133.0)) as EnemyAI
	var sk_buddy: EnemyAI = _spawn("skeleton", Vector3(5.0, 0.0, -133.0)) as EnemyAI
	await process_frame
	if brannoc != null and sera != null:
		brannoc.global_position = Vector3(-2.5, 0.0, -133.0)
		sera.global_position = Vector3(2.5, 0.0, -133.0)
		sk12.apply_taunt(brannoc, -1.0, 4.0)
		sk12.apply_taunt(brannoc, 30.0, 2.5)
		_check("enm_12_same_ally_nudge_keeps_fixation", sk12.is_fixated() and sk12._taunt_lock_timer >= 3.9, "fix=%s t=%.2f" % [str(sk12.is_fixated()), sk12._taunt_lock_timer])
	else:
		_check("enm_12_same_ally_nudge_keeps_fixation", false, "Allies missing")

	sk_buddy.target_player = null
	sk_buddy._transition_to(EnemyAIScript.State.IDLE, 0.0)
	sk_buddy.consider_evade(_player, true, 0.3)
	var idle_no_evade: bool = sk_buddy.current_state == EnemyAIScript.State.IDLE and not sk_buddy.is_evading()
	sk12.consider_evade(_player, true, 0.3)
	sk12.enter_stagger(0.4)
	_check("enm_13_evade_idle_and_timer_clear", idle_no_evade and not sk12.is_evading(), "idle_no=%s cleared=%s" % [str(idle_no_evade), str(not sk12.is_evading())])

	# ENM-14: Opening heavy on IDLE enemy sets target, clears reaggro block, and alerts squadmate.
	sk12.reset_enemy()
	sk_buddy.reset_enemy()
	sk12._reaggro_block = 1.5
	sk12.apply_damage(10, true, "player_heavy", _player)
	_check("enm_14_idle_opening_stagger_alerts_squad", sk12.get_current_target() == _player and sk12._reaggro_block == 0.0 and sk12.current_state == EnemyAIScript.State.STAGGER and sk_buddy.is_aggroed(), "tgt=%s buddy=%s" % [str(sk12.get_current_target() == _player), str(sk_buddy.is_aggroed())])

	# ENM-15: Backstab during ATTACK does not queue turn_around, and _finish_turn_around respects taunt fixation.
	sk12.reset_enemy()
	sk12._transition_to(EnemyAIScript.State.ATTACK, 0.3)
	sk12.set_facing_direction(Vector3(0.0, 0.0, -1.0))
	sk12.apply_damage(10, false, "player_light", _player)
	var atk_no_turn: bool = sk12._turn_to_id == 0
	var taunt_kept: bool = false
	if brannoc != null and sera != null:
		sk12.reset_enemy()
		sk12.apply_taunt(brannoc, -1.0, 4.0)
		sk12.set_facing_direction((brannoc.global_position - sk12.global_position))
		sera.global_position = sk12.global_position - sk12.get_facing_direction() * 1.5
		sk12.apply_damage(10, false, "player_light", sera)
		sk12._finish_turn_around()
		taunt_kept = sk12.get_current_target() == brannoc
	_check("enm_15_backstab_respects_boss_attack_and_taunt", atk_no_turn and taunt_kept, "atk=%s taunt=%s" % [str(atk_no_turn), str(taunt_kept)])

	# ENM-16: Taunted enemy cannot flee even below flee_health_ratio.
	sk12.health = 10
	sk12._has_fled = false
	sk12.apply_damage(1, false, "player_light", _player)
	_check("enm_16_taunted_enemy_cannot_flee", sk12.current_state != EnemyAIScript.State.FLEEING, "state=%d" % sk12.current_state)

	# ENM-17: Heavy hit does not cancel STUNNED into STAGGER, and heavy knockdown emits staggered once.
	sk12.reset_enemy()
	sk12.enter_stunned(1.6)
	sk12.apply_damage(10, true, "player_heavy", _player)
	var stayed_stunned: bool = sk12.current_state == EnemyAIScript.State.STUNNED
	sk12.reset_enemy()
	var stag_count: Array[int] = [0]
	var conn_cb: Callable = func(_d: float) -> void: stag_count[0] += 1
	sk12.staggered.connect(conn_cb)
	sk12.apply_damage(10, true, "player_landing", _player)
	sk12.staggered.disconnect(conn_cb)
	_check("enm_17_stunned_not_cancelled_and_no_double_emit", stayed_stunned and stag_count[0] == 1, "stayed=%s emits=%d" % [str(stayed_stunned), stag_count[0]])

	# ENM-18: Realm collision mask sync + ENM-20 ShieldedGuard STUNNED shield drop.
	var sg20: ShieldedGuard = _spawn("shield", Vector3(2.0, 0.0, -133.0)) as ShieldedGuard
	await process_frame
	sg20.evaluate_for_realm(0, false)
	var mask_reality: bool = (sg20.collision_mask & RealmManagerScript.LAYER_WORLD_MIRROR) == 0 and (sg20.collision_mask & RealmManagerScript.LAYER_WORLD_REALITY) != 0
	sg20.evaluate_for_realm(1, false)
	var mask_mirror: bool = (sg20.collision_mask & RealmManagerScript.LAYER_WORLD_REALITY) == 0 and (sg20.collision_mask & RealmManagerScript.LAYER_WORLD_MIRROR) != 0
	_check("enm_18_enemy_collision_mask_syncs_realm", mask_reality and mask_mirror, "real=%s mir=%s" % [str(mask_reality), str(mask_mirror)])

	sg20.evaluate_for_realm(0, false)
	sg20.set_facing_direction(Vector3(0.0, 0.0, -1.0))
	_player.global_position = sg20.global_position + Vector3(0.0, 0.0, -1.5)
	sg20.enter_stunned(1.6)
	var hp_pre: int = sg20.health
	var accepted_stun: bool = sg20.apply_damage(20, false, "player_light", _player)
	_check("enm_20_stunned_shield_guard_drops_shield", not sg20.is_shield_raised() and accepted_stun and (hp_pre - sg20.health) >= 20, "dmg=%d" % (hp_pre - sg20.health))

	# ENM-19: PhantomTwin lunge uses tracked get_facing_direction().
	var ph19: PhantomTwin = _spawn("phantom", Vector3(-3.0, 0.0, -133.0)) as PhantomTwin
	await process_frame
	rm.force_realm(RealmManagerScript.Realm.MIRROR, false)
	await process_frame
	ph19.set_facing_direction(Vector3.BACK)
	ph19.start_windup(0.5)
	ph19.set_facing_direction(Vector3.RIGHT)
	ph19._begin_attack_strike()
	var ph_dir: Vector2 = Vector2(ph19.velocity.x, ph19.velocity.z).normalized()
	_check("enm_19_phantom_lunges_along_tracked_facing", ph_dir.dot(Vector2(1.0, 0.0)) > 0.98, "vel=%s" % str(ph19.velocity))
	rm.force_realm(RealmManagerScript.Realm.REALITY, false)

	# ENM-25: Poise counter in WINDUP retains existing token even under cap pressure.
	_coord.reset()
	_coord.max_attackers = 1
	sk12.reset_enemy()
	sk12._set_target(_player)
	sk12._transition_to(EnemyAIScript.State.CHASE, 0.0)
	_coord.request_attack_token(sk12, _player)
	sk12.start_windup(0.6)
	sk12.counter_attack_chance = 1.0
	sk12._flinch_chain = sk12.max_flinch_chain
	sk12.global_position = _player.global_position + Vector3(0.0, 0.0, 1.0)
	sk12.apply_damage(10, false, "player_light", _player)
	_check("enm_25_poise_counter_preserves_windup_token", _coord.has_token(sk12) and sk12.current_state == EnemyAIScript.State.WINDUP, "has=%s state=%d" % [str(_coord.has_token(sk12)), sk12.current_state])

	# ENM-26: _hit_flash during windup never restores cleared _telegraph_mat.
	sk12.reset_enemy()
	sk12._set_target(_player)
	sk12.start_windup(0.9)
	sk12._hit_flash(Color.WHITE, 0.08)
	sk12._clear_telegraph_flash()
	await create_timer(0.14).timeout
	var vis_root: Node3D = sk12.get_node_or_null("VisualRoot") as Node3D
	var stale_found: bool = false
	if vis_root != null:
		for m in vis_root.find_children("*", "MeshInstance3D", true, false):
			if (m as MeshInstance3D).material_overlay != null:
				stale_found = true
	_check("enm_26_hit_flash_never_restores_cleared_telegraph", not stale_found, "stale=%s" % str(stale_found))

	await _cleanup_test_enemies()

	# ENM-21: Active waiter is not evicted at >2.5s while still requesting tokens.
	_player.global_position = Vector3(0.0, 0.0, -136.0)
	var blocker: EnemyAI = _spawn("skeleton", Vector3(-4.0, 0.0, -133.0)) as EnemyAI
	var waiter_a: EnemyAI = _spawn("skeleton", Vector3(4.0, 0.0, -133.0)) as EnemyAI
	var waiter_b: EnemyAI = _spawn("skeleton", Vector3(4.5, 0.0, -133.0)) as EnemyAI
	await process_frame
	_coord.reset()
	_coord.max_attackers = 1
	for w_e in [blocker, waiter_a, waiter_b]:
		w_e.reset_enemy()
		w_e._set_target(_player)
		w_e._transition_to(EnemyAIScript.State.CHASE, 0.0)
	_coord.request_attack_token(blocker, _player)
	_coord.request_attack_token(waiter_a, _player)
	var aid: int = waiter_a.get_instance_id()
	var now_t: float = SquadCoordinatorScript._now()
	_coord._waiting_since[aid] = now_t - 2.8
	_coord._last_wait_touch[aid] = now_t
	_coord.release_token(blocker)
	var b_stole: bool = _coord.request_attack_token(waiter_b, _player)
	var a_kept: bool = _coord._waiting_since.has(aid)
	var a_won: bool = _coord.request_attack_token(waiter_a, _player)
	_check("enm_21_token_waiter_not_evicted_while_active", not b_stole and a_kept and a_won, "b_stole=%s a_kept=%s a_won=%s" % [str(b_stole), str(a_kept), str(a_won)])

	await _cleanup_test_enemies()
	var fails: int = _results.filter(func(r: String) -> bool: return r.begins_with("FAIL")).size()
	print("[enm_reg] SUMMARY %d checks, %d failed" % [_results.size(), fails])
	quit(1 if fails > 0 else 0)
