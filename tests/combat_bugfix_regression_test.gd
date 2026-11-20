extends SceneTree
## Dedicated headless regression suite for IdiotHandOffGuide 01 (CMB-01..CMB-19).
## Run: godot --headless --path . -s res://tests/combat_bugfix_regression_test.gd

const SquadAIConfigScript := preload("res://addons/parallax_squad_ai/squad_ai_config.gd")
const RealmManagerScript := preload("res://scripts/core/realm_manager.gd")
const EncounterDirectorScript := preload("res://scripts/core/encounter_director.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const SwordTrailScript := preload("res://scripts/player/sword_trail.gd")
const BreakablePropScript := preload("res://scripts/environment/breakable_prop.gd")
const Hitbox3DScript := preload("res://scripts/core/hitbox_3d.gd")
const GameFeelScript := preload("res://scripts/core/game_feel.gd")
const EnemyBaseScript := preload("res://scripts/enemies/enemy_base.gd")
const EnemyAIScript := preload("res://scripts/enemies/enemy_ai.gd")

var _results: Array[String] = []
var _main: Node = null


func _initialize() -> void:
	SquadAIConfigScript.force_offline()
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	create_timer(150.0, true, false, true).timeout.connect(func() -> void:
		print("[combat_bugfix] WATCHDOG TIMEOUT")
		quit(2))
	_run()


func _check(req_id: String, ok: bool, detail: String = "") -> void:
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", req_id, detail]
	_results.append(line)
	print("[combat_bugfix] ", line)


func _wait_physics(frames: int) -> void:
	for _i in range(frames):
		await physics_frame


func _settle_player(pc: Node) -> void:
	pc.call("_abort_attack")
	pc.call("_close_finisher_window", "")
	pc.call("_consume_buffer")
	pc.call("_set_state", PlayerControllerScript.State.LOCOMOTION, 0.0)
	pc.set("velocity", Vector3.ZERO)
	pc.set("_pending_ground_slam", false)
	pc.set("_landing_recover_timer", 0.0)
	pc.set("_dodge_charges", pc.get("max_dodge_charges"))
	pc.set("_dodge_cooldown_timer", 0.0)
	pc.set("_air_dash_used", false)
	pc.set("_coyote_timer", 0.0)
	pc.set("stamina", pc.get("max_stamina"))
	pc.call("set_simulated_airborne", false)
	pc.call("_update_hurtbox_invulnerability", false)
	PlayerControllerScript.ui_input_locked = false


func _set_allies_frozen(frozen: bool) -> void:
	var mgr: Node = get_first_node_in_group("squad_manager")
	if mgr != null:
		mgr.set_physics_process(not frozen)
		mgr.set_process(not frozen)
	for a in get_nodes_in_group("squad_ally"):
		if is_instance_valid(a):
			a.set_physics_process(not frozen)
			a.set_process(not frozen)
			if a is CharacterBody3D:
				(a as CharacterBody3D).velocity = Vector3.ZERO


func _retire_dummy(d: EnemyBaseScript) -> void:
	if d == null or not is_instance_valid(d):
		return
	d.is_dead = true
	d.set_section_enabled(false)
	d.visible = false
	d.remove_from_group("enemy")
	d.global_position = Vector3(0.0, -500.0, 0.0)
	var fd: Node = _main.find_child("FaunaDirector", true, false)
	if fd != null and fd.has_method("get_enemies"):
		var enemies_arr: Array = fd.call("get_enemies") as Array
		enemies_arr.erase(d)


func _run() -> void:
	for _i in range(5):
		await process_frame
	_main.call("start_run_now")
	var t0: int = Time.get_ticks_msec()
	while not bool(_main.get("level_ready")) and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	await _wait_physics(4)

	var level: Node = _main.get_node("LevelRoot")
	var pc: PlayerControllerScript = get_first_node_in_group("player") as PlayerControllerScript
	var rm: RealmManagerScript = RealmManagerScript.instance as RealmManagerScript
	var rig: Node = pc.get_node_or_null("PlayerFeelRig") if pc != null else null
	if pc == null or rm == null or rig == null:
		_check("bootstrap", false, "missing pc/rm/rig")
		quit(1)
		return

	# Ensure spawned test dummies do not kill the player during deterministic checks.
	pc.max_health = 100000
	pc.health = 100000
	_settle_player(pc)

	# --- CMB-01: Ground plunge requires >= 50 stamina and never freezes mid-air ---
	pc.global_position = Vector3(0.0, 0.0, -138.0)
	await _wait_physics(3)
	pc.stamina = 10.0
	pc.call("_buffer", "plunge")
	await _wait_physics(16)
	var no_low_leap: bool = (not bool(pc.get("_pending_ground_slam"))) and pc.current_state == PlayerControllerScript.State.LOCOMOTION and pc.velocity.y <= 0.1
	pc.call("set_simulated_airborne", true)
	pc.set("_pending_ground_slam", true)
	pc.set("_pending_ground_slam_timer", 0.005)
	pc.stamina = 0.0
	pc.velocity = Vector3(4.0, 0.0, 0.0)
	var x0: float = pc.global_position.x
	await _wait_physics(2)
	var no_midair_freeze: bool = (not bool(pc.get("_pending_ground_slam"))) and pc.global_position.x > x0 + 0.01
	_check("cmb01_ground_plunge_low_stamina_no_freeze", no_low_leap and no_midair_freeze, "no_low_leap=%s no_freeze=%s" % [str(no_low_leap), str(no_midair_freeze)])
	_settle_player(pc)

	# --- CMB-02: CentralMirrorPlane rejects trigger_break() and player F slam ---
	var plane: BreakablePropScript = level.get_node_or_null("Stage05_ExecutionArena/CentralMirrorPlane") as BreakablePropScript
	var tb_res: bool = plane.trigger_break(true) if plane != null else true
	if plane != null:
		pc.global_position = plane.global_position + Vector3(0.0, 1.5, -1.0)
		pc.call("set_simulated_airborne", true)
		pc.stamina = 200.0
		pc.start_landing_attack()
		pc.complete_landing_slam()
	_check("cmb02_central_mirror_plane_ignores_plunge_and_trigger_break", plane != null and (not tb_res) and plane.current_state == BreakablePropScript.PropState.INTACT and not rm.is_merged, "tb=%s state=%s merged=%s" % [str(tb_res), str(plane.current_state if plane != null else -1), str(rm.is_merged)])
	_settle_player(pc)

	# --- CMB-03: Heavy hold abort on ui_input_locked prevents _enter_strike in LOCOMOTION ---
	var fired_count: Array[int] = [0]
	var on_exec := func(_n: String, _s: int, _d: int, _h: bool) -> void:
		fired_count[0] += 1
	pc.attack_executed.connect(on_exec)
	pc.global_position = Vector3(0.0, 0.0, -138.0)
	pc.call("_begin_attack", "heavy", 60, true, PlayerControllerScript.State.HEAVY_ATTACK)
	var w_heavy: float = float(pc.current_attack.get("windup", 0.3))
	pc.set("_attack_elapsed", w_heavy * clampf(pc.heavy_hold_pose_u, 0.1, 0.95))
	PlayerControllerScript.ui_input_locked = true
	pc.call("_process_attack_state", 0.08)
	PlayerControllerScript.ui_input_locked = false
	pc.attack_executed.disconnect(on_exec)
	_check("cmb03_ui_lock_during_heavy_hold_no_strike", fired_count[0] == 0 and pc.current_state == PlayerControllerScript.State.LOCOMOTION and pc.attack_phase == PlayerControllerScript.AttackPhase.NONE and not pc.get_sword_hitbox().is_swing_active, "fired=%d state=%d phase=%d" % [fired_count[0], pc.current_state, pc.attack_phase])
	_settle_player(pc)

	# --- Spawn controlled test dummies on isolated terrace ---
	_set_allies_frozen(true)
	var sk_dummy: EnemyBaseScript = level.call("_add_roamer", level, "skeleton", "Test_cmb_sk", Vector3(0.0, 0.0, -135.0), EncounterDirectorScript.Section.ENTRY, Vector3(0.0, 0.0, -138.0)) as EnemyBaseScript
	await process_frame
	sk_dummy.set_section_enabled(true)
	sk_dummy.max_health = 5000
	sk_dummy.health = 5000
	if sk_dummy is EnemyAIScript:
		(sk_dummy as EnemyAIScript).move_speed = 0.0
		(sk_dummy as EnemyAIScript).attack_damage = 0

	# --- CMB-04: Zero-charge dodge cannot free-cancel attack or leak finisher invuln ---
	pc.global_position = Vector3(0.0, 0.0, -136.5)
	pc.set_facing_direction(Vector3(0.0, 0.0, 1.0))
	pc.set("_finisher_cooldown_end_ms", 0)
	pc.open_finisher_window(sk_dummy)
	pc.call("_close_finisher_window", "fin_rend")
	pc.start_finisher("fin_rend")
	pc.set("_dodge_charges", 0)
	pc.call("_buffer", "dodge")
	pc.call("_process_attack_state", 0.016)
	var stayed_attack: bool = pc.current_state == PlayerControllerScript.State.HEAVY_ATTACK
	pc.call("_abort_attack")
	var invuln_cleared: bool = (not pc.is_invulnerable()) and (not pc.get_hurtbox().is_invulnerable)
	_check("cmb04_zero_charge_dodge_cannot_cancel_attack_or_leak_invuln", stayed_attack and invuln_cleared, "stayed=%s cleared=%s" % [str(stayed_attack), str(invuln_cleared)])
	_settle_player(pc)

	# --- CMB-05: fin_sunder passes "fin_sunder" source_type and applies STUNNED knockdown ---
	pc.global_position = sk_dummy.global_position - Vector3(0.0, 0.0, 1.5)
	pc.set_facing_direction(Vector3(0.0, 0.0, 1.0))
	pc.set("_finisher_cooldown_end_ms", 0)
	pc.open_finisher_window(sk_dummy)
	pc.call("_close_finisher_window", "fin_sunder")
	pc.start_finisher("fin_sunder")
	await _wait_physics(40)
	var sunder_stunned: bool = (sk_dummy as EnemyAIScript).current_state == EnemyAIScript.State.STUNNED and sk_dummy.last_hit_source == "fin_sunder"
	_check("cmb05_fin_sunder_applies_stunned_knockdown", sunder_stunned, "state=%d src=%s" % [(sk_dummy as EnemyAIScript).current_state, sk_dummy.last_hit_source])
	_settle_player(pc)

	# --- CMB-06: _acquire_target ignores unhittable PhantomTwin in Reality ---
	rm.force_realm(RealmManagerScript.Realm.REALITY, false)
	var ph_dummy: EnemyBaseScript = level.call("_add_roamer", level, "phantom", "Test_cmb_ph", Vector3(0.0, 0.0, -136.2), EncounterDirectorScript.Section.ENTRY, Vector3(0.0, 0.0, -138.0)) as EnemyBaseScript
	await process_frame
	ph_dummy.set_section_enabled(true)
	ph_dummy.global_position = Vector3(0.0, 0.0, -136.2)
	sk_dummy.global_position = Vector3(0.0, 0.0, -134.8)
	pc.global_position = Vector3(0.0, 0.0, -138.0)
	var mag_target: Node3D = pc.call("_acquire_target", Vector3(0.0, 0.0, 1.0), 4.8) as Node3D
	_check("cmb06_acquire_target_skips_unhittable_phantom_in_reality", mag_target == sk_dummy, "got=%s" % (mag_target.name if mag_target != null else "null"))
	_retire_dummy(ph_dummy)

	# --- CMB-07: player_landing after fin_execution does not inherit stale execute ---
	pc.set("_finisher_cooldown_end_ms", 0)
	pc.open_finisher_window(sk_dummy)
	pc.call("_close_finisher_window", "fin_execution")
	pc.start_finisher("fin_execution")
	pc.call("_abort_attack")
	pc.call("_set_state", PlayerControllerScript.State.LOCOMOTION, 0.0)
	var dict_cleared: bool = pc.current_attack.is_empty()
	sk_dummy.is_dead = false
	sk_dummy.health = int(floor(float(sk_dummy.max_health) * 0.25))
	pc.global_position = sk_dummy.global_position + Vector3(0.0, 1.5, 0.0)
	pc.stamina = 200.0
	pc.call("set_simulated_airborne", true)
	pc.start_landing_attack()
	var slam_hits: int = pc.complete_landing_slam([sk_dummy])
	_check("cmb07_landing_slam_after_fin_execution_no_stale_execute", dict_cleared and slam_hits == 1 and not sk_dummy.is_dead and sk_dummy.health > 0, "cleared=%s hits=%d dead=%s hp=%d" % [str(dict_cleared), slam_hits, str(sk_dummy.is_dead), sk_dummy.health])
	_settle_player(pc)

	# --- CMB-08: Deflected heavy on Reality shield never opens finisher window ---
	rm.force_realm(RealmManagerScript.Realm.REALITY, false)
	var sg_dummy: EnemyBaseScript = level.call("_add_roamer", level, "shield", "Test_cmb_sg", Vector3(0.0, 0.0, -130.0), EncounterDirectorScript.Section.ENTRY, Vector3(0.0, 0.0, -132.0)) as EnemyBaseScript
	await process_frame
	sg_dummy.set_section_enabled(true)
	if sg_dummy is EnemyAIScript:
		(sg_dummy as EnemyAIScript).move_speed = 0.0
		(sg_dummy as EnemyAIScript).attack_damage = 0
	sg_dummy.set_facing_direction(Vector3(0.0, 0.0, -1.0))
	pc.global_position = sg_dummy.global_position + Vector3(0.0, 0.0, -1.6)
	pc.set_facing_direction(Vector3(0.0, 0.0, 1.0))
	pc.set("_finisher_cooldown_end_ms", 0)
	pc.call("_close_finisher_window", "")
	var sg_hp0: int = sg_dummy.health
	pc.call("_begin_attack", "heavy", 60, true, PlayerControllerScript.State.HEAVY_ATTACK)
	pc.call("_release_heavy_charge")
	pc.current_attack["finisher"] = true
	await _wait_physics(32)
	_check("cmb08_deflected_heavy_on_reality_shield_never_opens_finisher", sg_dummy.health < sg_hp0 and not pc.is_finisher_window_open(), "hp %d->%d win=%s" % [sg_hp0, sg_dummy.health, str(pc.is_finisher_window_open())])
	_retire_dummy(sg_dummy)
	_settle_player(pc)

	# --- CMB-09: open_finisher_window clears pre-buffered inputs ---
	pc.set("_finisher_cooldown_end_ms", 0)
	pc.call("_buffer", "light")
	pc.open_finisher_window(sk_dummy)
	pc.call("_update_finisher_window")
	pc.call("_update_finisher_window")
	_check("cmb09_open_finisher_window_clears_prebuffered_input", pc.is_finisher_window_open() and String(pc.get("_buffer_action")) == "" and pc.current_state == PlayerControllerScript.State.LOCOMOTION, "open=%s buf=%s state=%d" % [str(pc.is_finisher_window_open()), String(pc.get("_buffer_action")), pc.current_state])
	_settle_player(pc)

	# --- CMB-10: fin_phantom respects open pits and LAYER_PLAYER_BLOCKER ---
	var iso_arena := Node3D.new()
	iso_arena.name = "IsolatedPhantomCheck"
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = RealmManagerScript.LAYER_WORLD_SHARED
	var floor_cs := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(10.0, 1.0, 10.0)
	floor_cs.shape = floor_box
	floor_cs.position = Vector3(200.0, -0.5, 0.0)
	floor_body.add_child(floor_cs)
	iso_arena.add_child(floor_body)
	var blocker_body := StaticBody3D.new()
	blocker_body.collision_layer = RealmManagerScript.LAYER_PLAYER_BLOCKER
	var blocker_cs := CollisionShape3D.new()
	var blocker_box := BoxShape3D.new()
	blocker_box.size = Vector3(6.0, 4.0, 0.4)
	blocker_cs.shape = blocker_box
	blocker_cs.position = Vector3(200.0, 1.5, 0.6)
	blocker_body.add_child(blocker_cs)
	iso_arena.add_child(blocker_body)
	root.add_child(iso_arena)
	sk_dummy.set_physics_process(false)
	sk_dummy.global_position = Vector3(200.0, 0.0, 4.8)
	pc.global_position = Vector3(200.0, 0.0, 3.0)
	await _wait_physics(3)
	pc.set("_finisher_cooldown_end_ms", 0)
	pc.open_finisher_window(sk_dummy)
	pc.call("_close_finisher_window", "fin_phantom")
	pc.start_finisher("fin_phantom")
	var no_pit_tp: bool = pc.global_position.z <= 4.8
	_settle_player(pc)
	sk_dummy.global_position = Vector3(200.0, 0.0, 0.0)
	pc.global_position = Vector3(200.0, 0.0, -2.0)
	await _wait_physics(2)
	pc.set("_finisher_cooldown_end_ms", 0)
	pc.open_finisher_window(sk_dummy)
	pc.call("_close_finisher_window", "fin_phantom")
	pc.start_finisher("fin_phantom")
	var blocked_by_rail: bool = pc.global_position.z < 0.6
	_check("cmb10_fin_phantom_respects_pit_and_player_blocker", no_pit_tp and blocked_by_rail, "pit_z_ok=%s blocker_z_ok=%s" % [str(no_pit_tp), str(blocked_by_rail)])
	iso_arena.queue_free()
	sk_dummy.set_physics_process(true)
	sk_dummy.global_position = Vector3(0.0, 0.0, -135.0)
	pc.global_position = Vector3(0.0, 0.0, -138.0)
	_settle_player(pc)

	# --- CMB-11: Finisher i-frames pause cleanly and clear on _abort_attack() ---
	pc.set("_finisher_cooldown_end_ms", 0)
	pc.open_finisher_window(sk_dummy)
	pc.call("_close_finisher_window", "fin_rend")
	pc.start_finisher("fin_rend")
	var inv_start: bool = pc.is_invulnerable() and pc.get_hurtbox().is_invulnerable
	paused = true
	await create_timer(0.9, true, false, true).timeout
	var inv_paused: bool = pc.is_invulnerable() and pc.get_hurtbox().is_invulnerable
	paused = false
	pc.call("_abort_attack")
	pc.call("_set_state", PlayerControllerScript.State.LOCOMOTION, 0.0)
	var inv_aborted: bool = (not pc.is_invulnerable()) and (not pc.get_hurtbox().is_invulnerable)
	_check("cmb11_finisher_invuln_uses_scaled_time_and_clears_on_abort", inv_start and inv_paused and inv_aborted, "start=%s paused=%s abort=%s" % [str(inv_start), str(inv_paused), str(inv_aborted)])
	_settle_player(pc)

	# --- CMB-12: Rejected 2nd air-dash preserves dodge charges & active i-frames ---
	pc.call("set_simulated_airborne", true)
	pc.set("_coyote_timer", 0.0)
	pc.set("_air_dash_used", false)
	pc.set("_dodge_charges", 2)
	pc.set("_dodge_cooldown_timer", 0.0)
	var air1: bool = pc.start_dodge(Vector3.FORWARD)
	pc.set("_dodge_elapsed", pc.dodge_duration * 0.50)
	pc.call("_update_hurtbox_invulnerability", true)
	pc.call("_buffer", "dodge")
	pc.call("_process_dodge_state", 0.016)
	var kept_iframes: bool = pc.get_hurtbox().is_invulnerable
	var charges_chain: int = int(pc.get("_dodge_charges"))
	var air2: bool = pc.start_dodge(Vector3.FORWARD)
	var charges_direct: int = int(pc.get("_dodge_charges"))
	_check("cmb12_rejected_second_air_dash_preserves_charge_and_iframes", air1 and kept_iframes and charges_chain == 1 and (not air2) and charges_direct == 1, "air1=%s iframes=%s c1=%d air2=%s c2=%d" % [str(air1), str(kept_iframes), charges_chain, str(air2), charges_direct])
	_settle_player(pc)

	# --- CMB-13: Custom camera_fov persists across PlayerFeelRig updates ---
	var store: Node = root.get_node_or_null("LeaderboardStore")
	var orig_fov: float = 65.0
	var fov_ok: bool = false
	if store != null and store.has_method("get_settings") and store.has_method("save_settings"):
		orig_fov = float((store.call("get_settings") as Dictionary).get("camera_fov", 65.0))
		store.call("save_settings", {"camera_fov": 82.0})
		rig.set("_fov_kick", 0.0)
		rig.set("_fov_kick_vel", 0.0)
		var cam: Camera3D = pc.get_node("CameraPivot/SpringArm3D/Camera3D") as Camera3D
		for _f in range(5):
			rig.call("_update_camera", 0.016)
		fov_ok = absf(cam.fov - 82.0) < 0.05 and absf(float(rig.get("_base_fov")) - 82.0) < 0.05
		store.call("save_settings", {"camera_fov": orig_fov})
	_check("cmb13_custom_camera_fov_persists_across_feel_rig_updates", fov_ok, "base=%s" % str(rig.get("_base_fov")))

	# --- CMB-14: SquadAlly's 5 sound sites no longer call GameFeelScript with invalid keys ---
	var ally: Node = get_first_node_in_group("squad_ally")
	var am: Node = root.get_node_or_null("GameAudio")
	var cues_valid: bool = am != null \
		and am.call("_cue_stream", "hit_metal") != null \
		and am.call("_cue_stream", "glass_shatter") != null \
		and am.call("_cue_stream", "landing_slam") != null \
		and am.call("_cue_stream", "enemy_hit") != null
	if ally != null:
		ally.call("apply_damage", 5, null)
	var gf_probe := GameFeelScript.new()
	var fallback_valid: bool = gf_probe.get_stream("clang") != null and gf_probe.get_stream("land_heavy") != null and gf_probe.get_stream("slash_flesh") != null
	gf_probe.free()
	var ally_src: String = FileAccess.get_file_as_string("res://scripts/allies/squad_ally.gd")
	var legacy_fixed: bool = not ally_src.contains("GameFeelScript.play_sound(self, \"glass_shatter\"") and not ally_src.contains("GameFeelScript.play_sound(self, \"landing_slam\"")
	_check("cmb14_squad_ally_sound_keys_valid", cues_valid and fallback_valid and legacy_fixed, "cues=%s fb=%s src=%s" % [str(cues_valid), str(fallback_valid), str(legacy_fixed)])

	# --- CMB-15: GameFeel.add_trauma() distance falloff works for Node PlayerFeelRig ---
	pc.global_position = Vector3.ZERO
	pc.camera_shake_intensity = 1.0
	rig.set("trauma", 0.0)
	GameFeelScript.add_trauma(pc, 0.8, Vector3(0.0, 0.0, 50.0), 18.0)
	var far_trauma: float = float(rig.get("trauma"))
	GameFeelScript.add_trauma(pc, 0.8, Vector3(0.0, 0.0, 9.0), 18.0)
	var mid_trauma: float = float(rig.get("trauma"))
	_check("cmb15_gamefeel_add_trauma_distance_falloff", far_trauma == 0.0 and absf(mid_trauma - 0.4) < 0.02, "far=%.3f mid=%.3f" % [far_trauma, mid_trauma])

	# --- CMB-16: Hitbox3D registers RunState combo hits for fin_* and player_execution ---
	var rs: Node = root.get_node_or_null("RunState")
	var hb: Hitbox3DScript = pc.get_sword_hitbox() as Hitbox3DScript
	sk_dummy.health = sk_dummy.max_health
	var combo_ok: bool = false
	if rs != null and hb != null:
		rs.call("start_new_run")
		hb.begin_swing(20, true, "fin_sunder")
		var h1: bool = hb.try_hit_target(sk_dummy)
		hb.end_swing()
		hb.begin_swing(20, true, "player_execution")
		var h2: bool = hb.try_hit_target(sk_dummy)
		hb.end_swing()
		combo_ok = h1 and h2 and int(rs.get("combo_hits")) == 2
	_check("cmb16_hitbox_registers_combo_for_execution_and_finishers", combo_ok, "combo=%s" % str(rs.get("combo_hits") if rs != null else -1))

	# --- CMB-17: 0s-warning breakable defers CollisionShape3D.disabled cleanly ---
	var prop: BreakablePropScript = (load("res://scenes/props/breakable_prop.tscn") as PackedScene).instantiate() as BreakablePropScript
	prop.prop_kind = BreakablePropScript.PropKind.WEAK_STONE_SUPPORT
	prop.warning_duration = 0.0
	prop.require_heavy_attack = true
	prop.position = Vector3(0.0, 0.0, -135.0)
	root.add_child(prop)
	await _wait_physics(2)
	pc.global_position = prop.global_position - Vector3(0.0, 0.0, 2.5)
	pc.set_facing_direction(Vector3(0.0, 0.0, 1.0))
	hb.begin_swing(60, true, "player_heavy")
	await _wait_physics(1)
	pc.global_position = prop.global_position - Vector3(0.0, 0.0, 1.0)
	await _wait_physics(3)
	hb.end_swing()
	var prop_cs := prop.get_node("SolidBody/CollisionShape3D") as CollisionShape3D
	var prop_hb := prop.get_node("Hurtbox3D") as Area3D
	var prop_src: String = FileAccess.get_file_as_string("res://scripts/environment/breakable_prop.gd")
	var no_sync_disable: bool = not prop_src.contains("cs.disabled =") and not prop_src.contains("scs.disabled =")
	_check("cmb17_zero_warning_breakable_defers_colliders_cleanly", prop.current_state == BreakablePropScript.PropState.BROKEN and prop_cs.disabled and not prop_hb.monitorable and no_sync_disable, "state=%d cs=%s mon=%s sync=%s" % [prop.current_state, str(prop_cs.disabled), str(prop_hb.monitorable), str(no_sync_disable)])
	prop.queue_free()
	_retire_dummy(sk_dummy)
	_set_allies_frozen(false)

	# --- CMB-18: Heavy charge rumble respects camera_shake_intensity = 0.0 ---
	pc.camera_shake_intensity = 0.0
	rig.set("trauma", 0.0)
	pc.call("_begin_attack", "heavy", 60, true, PlayerControllerScript.State.HEAVY_ATTACK)
	pc.set("_heavy_charge_t", 2.5)
	rig.call("_update_camera", 0.016)
	var zero_rumble: bool = float(rig.get("trauma")) == 0.0
	_check("cmb18_heavy_charge_respects_zero_camera_shake_intensity", zero_rumble, "trauma=%.3f" % float(rig.get("trauma")))
	_settle_player(pc)
	pc.camera_shake_intensity = 1.0

	# --- CMB-19: SwordTrail does not bridge consecutive swings across emitting toggles ---
	var blade := MeshInstance3D.new()
	blade.mesh = BoxMesh.new()
	var trail := SwordTrailScript.new()
	root.add_child(blade)
	root.add_child(trail)
	trail.bind_blade(blade)
	trail.max_age = 0.25
	trail.emitting = true
	for i in range(4):
		blade.global_position = Vector3(float(i) * 0.2, 1.0, 0.0)
		trail._process(0.016)
	trail.emitting = false
	trail._process(0.016)
	blade.global_position = Vector3(25.0, 1.0, 0.0)
	trail.emitting = true
	for i in range(4):
		blade.global_position = Vector3(25.0 + float(i) * 0.2, 1.0, 0.0)
		trail._process(0.016)
	var surf_count: int = trail.mesh.get_surface_count()
	var bridged: bool = false
	for s in range(surf_count):
		var arrays: Array = trail.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var min_x: float = INF
		var max_x: float = -INF
		for v in verts:
			min_x = minf(min_x, v.x)
			max_x = maxf(max_x, v.x)
		if min_x < 5.0 and max_x > 20.0:
			bridged = true
	_check("cmb19_sword_trail_no_bridge_across_swings_or_blink", surf_count >= 2 and not bridged, "surfaces=%d bridged=%s" % [surf_count, str(bridged)])
	trail.queue_free()
	blade.queue_free()

	var fails: int = _results.filter(func(r: String) -> bool: return r.begins_with("FAIL")).size()
	print("[combat_bugfix] SUMMARY %d checks, %d failed" % [_results.size(), fails])
	quit(1 if fails > 0 else 0)
