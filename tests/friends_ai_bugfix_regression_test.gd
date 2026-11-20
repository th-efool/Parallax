extends SceneTree
## Headless bugfix regression suite for Friends & Squad AI (ALY-01 .. ALY-24).
## Uses explicit preload constants (AGENTS.md §3) so --check-only and headless runs work
## independently of editor class-cache state.
## Usage: godot --headless --path . -s res://tests/friends_ai_bugfix_regression_test.gd

const RealmManagerScript := preload("res://scripts/core/realm_manager.gd")
const EncounterDirectorScript := preload("res://scripts/core/encounter_director.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const PlayerScript := preload("res://scripts/player/player_controller.gd")
const ManagerScript := preload("res://scripts/allies/ally_squad_manager.gd")
const AllyScript := preload("res://scripts/allies/squad_ally.gd")
const WorldIntelScript := preload("res://scripts/allies/world_intel.gd")
const CommandScript := preload("res://scripts/allies/squad_command.gd")
const ParserScript := preload("res://scripts/allies/squad_command_parser.gd")
const CommsHudScript := preload("res://scripts/ui/squad_comms_hud.gd")
const SquadAIConfigScript := preload("res://addons/parallax_squad_ai/squad_ai_config.gd")
const AllyProfileScript := preload("res://scripts/allies/ally_profile.gd")
const EnemyAIScript := preload("res://scripts/enemies/enemy_ai.gd")
const PhantomScript := preload("res://scripts/enemies/phantom_twin.gd")
const ShieldedScript := preload("res://scripts/enemies/shielded_guard.gd")
const PitKillZoneScript := preload("res://scripts/environment/pit_kill_zone.gd")
const BreakableScript := preload("res://scripts/environment/breakable_prop.gd")
const LoadingScreenScript := preload("res://scripts/ui/loading_screen.gd")

var _fails: int = 0
var _checks: int = 0


func _check(test_name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[friends_ai] %s %s %s" % ["PASS" if ok else "FAIL", test_name, detail])


func _initialize() -> void:
	SquadAIConfigScript.force_offline()
	create_timer(120.0, true, false, true).timeout.connect(func() -> void:
		print("[friends_ai] WATCHDOG TIMEOUT")
		quit(2))
	_run()


func _make_test_enemy(script_res: GDScript, pos: Vector3, node_name: String) -> EnemyAI:
	var e: EnemyAI = script_res.new() as EnemyAI
	e.name = node_name
	e.section_id = EncounterDirectorScript.Section.ENTRY
	e.encounter_id = ""
	e.use_squad_tactics = false
	e.patrol_radius = 0.0
	var col := CollisionShape3D.new()
	col.name = "BodyCollider"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position = Vector3(0.0, 0.9, 0.0)
	e.add_child(col)
	var vis := Node3D.new()
	vis.name = "VisualRoot"
	e.add_child(vis)
	var mr := Node3D.new()
	mr.name = "ModelRoot"
	vis.add_child(mr)
	e.position = pos
	return e


func _run() -> void:
	var harness := Node3D.new()
	harness.name = "Harness"
	root.add_child(harness)

	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = RealmManagerScript.LAYER_WORLD_SHARED
	var floor_cs := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(400.0, 1.0, 400.0)
	floor_cs.shape = floor_box
	floor_cs.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(floor_cs)
	harness.add_child(floor_body)

	var rm: RealmManager = RealmManagerScript.new() as RealmManager
	rm.handle_input_directly = false
	harness.add_child(rm)

	var ed: EncounterDirector = EncounterDirectorScript.new() as EncounterDirector
	ed.auto_save_on_checkpoint = false
	harness.add_child(ed)

	var player: PlayerController = (PlayerScene as PackedScene).instantiate() as PlayerController
	player.position = Vector3.ZERO
	harness.add_child(player)
	var cam: Camera3D = player.find_child("Camera3D", true, false) as Camera3D
	if cam != null:
		cam.current = true
	player.set_facing_direction(Vector3.FORWARD)
	player.camera_yaw = 0.0
	player.camera_pitch = 0.0

	var mgr: AllySquadManager = ManagerScript.new() as AllySquadManager
	mgr.spawn_allies = true
	harness.add_child(mgr)

	for _f in range(5):
		await physics_frame

	var brannoc: SquadAlly = mgr.find_ally("Brannoc")
	var sera: SquadAlly = mgr.find_ally("Sera")
	var ivo: SquadAlly = mgr.find_ally("Ivo")
	if brannoc == null or sera == null or ivo == null:
		_check("harness_spawned_allies", false, "missing allies")
		quit(1)
		return

	# ---- ALY-01 & ALY-19 & ALY-20: WorldIntel camera visibility, node_for_id, resolve guards ----
	var intel: WorldIntel = mgr.intel
	var e_vis: EnemyAI = _make_test_enemy(EnemyAIScript, Vector3(0.0, 0.0, -50.0), "Test_Vis50")
	var e_far: EnemyAI = _make_test_enemy(EnemyAIScript, Vector3(0.0, 0.0, -160.0), "Test_Far160")
	var e_back: EnemyAI = _make_test_enemy(EnemyAIScript, Vector3(0.0, 0.0, 20.0), "Test_Back20")
	var e_phant: PhantomTwin = _make_test_enemy(PhantomScript, Vector3(2.0, 0.0, -15.0), "Test_Phant") as PhantomTwin
	harness.add_child(e_vis)
	harness.add_child(e_far)
	harness.add_child(e_back)
	harness.add_child(e_phant)
	await physics_frame
	intel.refresh()
	var near30: Array[EnemyAI] = mgr._active_enemies_near(Vector3.ZERO, 30.0)
	_check("aly01_camera_visible_targeting",
		intel.is_camera_visible(e_vis)
		and not intel.is_camera_visible(e_far)
		and not intel.is_camera_visible(e_back)
		and not intel.is_camera_visible(e_phant)
		and near30.has(e_vis)
		and not near30.has(e_phant),
		"vis=%s far=%s back=%s phant=%s" % [intel.is_camera_visible(e_vis), intel.is_camera_visible(e_far), intel.is_camera_visible(e_back), intel.is_camera_visible(e_phant)])

	var vis_id: String = intel.id_of(e_vis)
	e_vis.set_section_enabled(false)
	_check("aly19_node_for_id_active_in_tree", intel.node_for_id(vis_id) == null, "inactive enemy should return null")
	e_vis.set_section_enabled(true)
	await physics_frame
	intel.refresh()
	var e_temp: EnemyAI = _make_test_enemy(EnemyAIScript, Vector3(1.0, 0.0, -8.0), "Test_Temp")
	harness.add_child(e_temp)
	await physics_frame
	intel.refresh()
	e_temp.queue_free()
	await process_frame
	harness.remove_child(player)
	var resolved_no_player: EnemyAI = intel.resolve("nearest", null)
	_check("aly20_world_intel_resolve_null_and_valid_guards", resolved_no_player == e_vis or resolved_no_player == e_back, str(resolved_no_player))
	harness.add_child(player)
	e_far.queue_free()
	e_back.queue_free()
	e_phant.queue_free()
	await process_frame

	# ---- ALY-02: Combo substitute freed/downed guards + mine cleanup & planted_t reset ----
	var lure_res: String = mgr.issue({"verb": "combo_lure_detonate", "target": "nearest"}, "test")
	var cid: int = mgr._combo_seq
	var rec: Dictionary = mgr._combos.get(cid, {}) as Dictionary
	var mine_cleared: bool = false
	var planted_reset: bool = false
	if rec.has("parts"):
		var trapper_ally: SquadAlly = rec["parts"].get("trapper", null) as SquadAlly
		if trapper_ally != null:
			trapper_ally.plant_mine(Vector3(3.0, 0.0, -3.0))
			rec["planted_t"] = 2.5
			mgr._substitute(cid, "trapper")
			mine_cleared = trapper_ally.get_mine_position() == Vector3.INF
			planted_reset = float(mgr._combos.get(cid, {}).get("planted_t", -1.0)) < 0.0
			trapper_ally.plant_mine(Vector3(3.0, 0.0, -3.0))
			trapper_ally._go_down()
			mine_cleared = mine_cleared and trapper_ally.get_mine_position() == Vector3.INF
			trapper_ally.revive(1.0)
		var k_dummy := AllyScript.new() as SquadAlly
		var dum_prof := AllyProfileScript.new() as AllyProfile
		dum_prof.ally_name = "Dummy"
		k_dummy.setup(dum_prof, mgr, 9)
		if mgr._combos.has(cid):
			mgr._combos[cid]["parts"]["trapper"] = k_dummy
			mgr._combos[cid]["planted_t"] = 2.5
			k_dummy.free()
			mgr._substitute(cid, "trapper")
			planted_reset = planted_reset and float(mgr._combos.get(cid, {}).get("planted_t", -1.0)) < 0.0
		else:
			k_dummy.free()
		mgr._abort_combo(cid, "cleanup")
	_check("aly02_substitute_and_mine_cleanup", not lure_res.is_empty() and mine_cleared and planted_reset, "res=%s mine=%s planted_reset=%s" % [lure_res, mine_cleared, planted_reset])
	mgr.issue({"verb": "stop", "allies": ["all"]}, "test")
	e_vis.queue_free()
	await process_frame

	# ---- ALY-03: _run_lurer fallback & done outside luring ----
	var e_lure: EnemyAI = _make_test_enemy(EnemyAIScript, Vector3(0.0, 0.0, -6.0), "Test_LurerTarget")
	harness.add_child(e_lure)
	await physics_frame
	sera.global_position = Vector3(0.0, 3.0, -3.0)
	var lcmd := CommandScript.make("combo_lure_detonate", {}, "test")
	lcmd.combo_id = 99
	lcmd.combo_part = "lurer"
	sera.assign(lcmd)
	lcmd.data["point"] = Vector3(0.0, 0.0, -2.0)
	lcmd.data["enemy"] = e_lure
	lcmd.step = "fallback"
	sera._run_lurer(0.1, player, lcmd)
	sera._run_lurer(0.1, player, lcmd)
	var moved_in_fallback: bool = sera.global_position.y < 3.0 or sera.velocity.length() > 0.01
	lcmd.data["done"] = true
	sera._run_lurer(0.05, player, lcmd)
	_check("aly03_lurer_fallback_and_done", moved_in_fallback and lcmd.done, "moved=%s done=%s" % [moved_in_fallback, lcmd.done])
	e_lure.queue_free()
	await process_frame

	# ---- ALY-04 & ALY-05: Downed realm layer + pit rescue + revive timeout + wall-occluded catchup + REQ-16 ----
	rm.force_realm(RealmManagerScript.Realm.MIRROR, false)
	brannoc.global_position = Vector3(0.0, 0.0, -2.0)
	brannoc._go_down()
	rm.force_realm(RealmManagerScript.Realm.REALITY, false)
	var keeps_mirror_mask: bool = (brannoc.collision_mask & RealmManagerScript.LAYER_WORLD_MIRROR) != 0
	brannoc.global_position = Vector3(0.0, -25.0, -2.0)
	brannoc._process_downed(0.05)
	var rescued_from_void: bool = brannoc.global_position.y > -2.0
	var rev_cmd := CommandScript.make("revive", {"target": "Brannoc"}, "test")
	sera.assign(rev_cmd)
	brannoc.global_position = Vector3(40.0, 0.0, 0.0)
	rev_cmd.timer = 10.5
	sera._revive_target(brannoc, 0.05, rev_cmd)
	_check("aly04_downed_safety_and_revive_timeout", keeps_mirror_mask and rescued_from_void and rev_cmd.done,
		"mask=%s rescued=%s rev_done=%s" % [keeps_mirror_mask, rescued_from_void, rev_cmd.done])
	brannoc.revive(1.0)
	mgr.regroup(true)

	# ALY-05 + REQ-16: wall occlusion blocks LOS ray so blink fires; distant attack order (60m) exempts from blink
	var wall := StaticBody3D.new()
	wall.name = "CatchupWall"
	wall.collision_layer = RealmManagerScript.LAYER_WORLD_SHARED
	var wall_cs := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(12.0, 6.0, 1.0)
	wall_cs.shape = wall_box
	wall.add_child(wall_cs)
	wall.position = Vector3(0.0, 2.0, -12.0)
	harness.add_child(wall)
	await physics_frame
	player.global_position = Vector3.ZERO
	player.set_facing_direction(Vector3.FORWARD)
	player.camera_yaw = 0.0
	player.camera_pitch = 0.0
	await physics_frame
	brannoc.assign(CommandScript.make("follow", {}, "test"))
	brannoc.global_position = Vector3(0.0, 0.0, -25.0)
	brannoc._catch_up(player)
	var blinked_past_wall: bool = brannoc.global_position.distance_to(player.global_position) < 8.0
	var distant_cmd := CommandScript.make("attack", {"target": "nearest"}, "test")
	sera.assign(distant_cmd)
	sera.global_position = Vector3(0.0, 0.0, -60.0)
	sera._catch_up(player)
	var req16_exempt: bool = sera.global_position.z < -55.0
	_check("aly05_catchup_wall_los_and_req16_exemption", blinked_past_wall and req16_exempt,
		"blinked=%s req16=%s" % [blinked_past_wall, req16_exempt])
	wall.queue_free()
	mgr.regroup(true)
	await process_frame

	# ---- ALY-06: Rally flag survives assign(), queue rally cleared, regroup(true) resets ----
	player.health = int(player.max_health * 0.2)
	var e_threat: EnemyAI = _make_test_enemy(EnemyAIScript, Vector3(0.0, 0.0, -4.0), "Test_RallyFoe")
	harness.add_child(e_threat)
	await physics_frame
	e_threat.apply_taunt(player, -1.0, 4.0)
	mgr._start_rally(player)
	var cut_skill := CommandScript.make("skill", {"skill": "war_cry"}, "test")
	if brannoc.current != null:
		brannoc.enqueue(brannoc.current, true)
	brannoc.assign(cut_skill)
	player.health = player.max_health
	e_threat.queue_free()
	await physics_frame
	mgr._update_rally(player, 3.0)
	var rally_queued_cleared: bool = brannoc.queue.is_empty()
	mgr._start_rally(player)
	mgr.regroup(true)
	_check("aly06_rally_queue_and_regroup_cleanup", rally_queued_cleared and mgr._rally.is_empty() and mgr._rally_cooldown.is_empty(),
		"q_empty=%s rally_empty=%s" % [rally_queued_cleared, mgr._rally.is_empty()])

	# ---- ALY-07, ALY-08, ALY-10: Stop/Strategy abort effects & PANIC protection ----
	ivo.begin_nuke(Vector3(0.0, 0.0, -4.0))
	var flip_cmd := CommandScript.make("emote", {"text": "backflip"}, "test")
	sera.assign(flip_cmd)
	sera._process_action(0.3)
	mgr.issue({"verb": "stop", "allies": ["all"]}, "test")
	var vis_sera: Node3D = sera.get_node_or_null("VisualRoot") as Node3D
	var effects_aborted: bool = ivo._action.is_empty() and (ivo._cast_ring == null or not ivo._cast_ring.visible) and sera._action.is_empty() and (vis_sera == null or is_zero_approx(vis_sera.rotation.x))
	_check("aly07_stop_and_strategy_abort_effects", effects_aborted, "ivo_act=%s sera_act=%s" % [ivo._action, sera._action])

	var e_strat: EnemyAI = _make_test_enemy(EnemyAIScript, Vector3(0.0, 0.0, -5.0), "Test_StratFoe")
	harness.add_child(e_strat)
	await physics_frame
	brannoc.start_charge(e_strat, Callable())
	mgr.issue({"verb": "ceasefire", "allies": ["Brannoc"]}, "test")
	var charge_cleared: bool = brannoc._dash_timer == 0.0 and not brannoc._dash_hit_cb.is_valid()
	_check("aly10_abort_all_actions_spins_flips_charges", charge_cleared, "dash_t=%s" % brannoc._dash_timer)
	var c_res: String = mgr.issue({"verb": "combo_kite_nuke", "target": "nearest"}, "test")
	var strat_res: String = mgr.execute_strategy("focus_fire", "nearest", mgr.get_living(), "test")
	var panic_kept: bool = brannoc.current != null and brannoc.current.verb == "ceasefire"
	var combos_cleared: bool = mgr.get_active_combos().is_empty()
	_check("aly08_strategy_respects_panic_and_cancels_combos", panic_kept and combos_cleared, "c=%s s=%s panic=%s" % [c_res, strat_res, panic_kept])
	mgr.issue({"verb": "stop", "allies": ["all"]}, "test")

	# ---- ALY-09: Downed ally cannot take or keep revive order ----
	sera._go_down()
	brannoc._go_down()
	var rev_route: String = mgr._route(brannoc, CommandScript.make("revive", {"target": "Sera"}, "test"))
	var rev_sub_res: String = mgr.issue({"verb": "revive", "allies": ["Brannoc"], "target": "Sera"}, "test")
	_check("aly09_downed_ally_revive_substitution", rev_route == "is down" and rev_sub_res.begins_with("Ivo"), "route=%s res=%s" % [rev_route, rev_sub_res])
	mgr.regroup(true)

	# ---- ALY-11: Area taunt collects idle enemies & single-target timeout ----
	e_strat.global_position = Vector3(0.0, 0.0, -5.0)
	brannoc.global_position = Vector3(0.0, 0.0, -1.0)
	var t_area := CommandScript.make("taunt", {"area": true}, "test")
	brannoc.assign(t_area)
	brannoc._run_taunt_cmd(0.05, player, t_area)
	var area_pulled: bool = t_area.done and e_strat.get_current_target() == brannoc
	var t_miss := CommandScript.make("taunt", {"target": "nearest"}, "test")
	brannoc.assign(t_miss)
	e_strat.global_position = Vector3(0.0, 0.0, -25.0)
	t_miss.data["enemy"] = e_strat
	t_miss.timer = 12.5
	brannoc._run_taunt_cmd(0.05, player, t_miss)
	_check("aly11_taunt_area_fallback_and_timeout", area_pulled and t_miss.done, "area=%s timeout=%s" % [area_pulled, t_miss.done])

	# ---- ALY-12: Dead player ignored by heals, wards, _friends(), _weakest_friend_name() ----
	player.current_state = PlayerScript.State.DEAD
	player.health = 0
	var mend_skill: AllySkill = ivo.profile.find_skill("mending_light")
	var ward_skill: AllySkill = ivo.profile.find_skill("mirror_ward")
	var dead_friends_ok: bool = not ivo._friends().has(player)
	var dead_mend_blocked: bool = not ivo._skill_mend(mend_skill, player)
	var dead_ward_blocked: bool = not ivo._skill_ward(ward_skill, player)
	var weakest_not_dead_player: bool = mgr._weakest_friend_name() != "player"
	_check("aly12_ignore_dead_player_in_heals_wards", dead_friends_ok and dead_mend_blocked and dead_ward_blocked and weakest_not_dead_player,
		"friends=%s mend=%s ward=%s weakest=%s" % [dead_friends_ok, dead_mend_blocked, dead_ward_blocked, mgr._weakest_friend_name()])
	player.current_state = PlayerScript.State.LOCOMOTION
	player.health = player.max_health

	# ---- ALY-13: Ranged wall-backed fires & hold spot no oscillation ----
	var back_wall := StaticBody3D.new()
	back_wall.collision_layer = RealmManagerScript.LAYER_WORLD_SHARED
	var bw_cs := CollisionShape3D.new()
	var bw_box := BoxShape3D.new()
	bw_box.size = Vector3(10.0, 4.0, 1.0)
	bw_cs.shape = bw_box
	back_wall.add_child(bw_cs)
	back_wall.position = Vector3(0.0, 1.0, 1.0)
	harness.add_child(back_wall)
	await physics_frame
	player.global_position = Vector3(12.0, 0.0, 0.0)
	brannoc.global_position = Vector3(10.0, 0.0, 0.0)
	sera.global_position = Vector3(14.0, 0.0, 0.0)
	ivo.global_position = Vector3(0.0, 0.0, 0.1)
	ivo.velocity = Vector3.ZERO
	ivo._attack_cd = 0.0
	e_strat.global_position = Vector3(0.0, 0.0, -3.5)
	ivo._ranged_engage(e_strat, 0.05)
	var fired_when_backed: bool = ivo._attack_cd > 0.0
	var hold_cmd := CommandScript.make("hold", {"spot": Vector3(0.0, 0.0, 0.1), "engage_r": 4.0}, "test")
	ivo.assign(hold_cmd)
	ivo.global_position = Vector3(0.0, 0.0, 0.1)
	ivo.velocity = Vector3.ZERO
	ivo._run_hold(0.05, hold_cmd)
	var held_spot: bool = ivo.global_position.distance_to(Vector3(0.0, 0.0, 0.1)) < 0.2 and ivo.velocity.length() < 0.2
	_check("aly13_ranged_wall_and_hold_no_oscillation", fired_when_backed and held_spot, "fired=%s held=%s" % [fired_when_backed, held_spot])
	player.global_position = Vector3.ZERO
	back_wall.queue_free()

	# ---- ALY-14: _run_skill() aborts mid-approach if enemy dies/unhittable or ally downed ----
	var sk_cmd := CommandScript.make("skill", {"skill": "chain_arc"}, "test")
	ivo.assign(sk_cmd)
	sk_cmd.data["target_node"] = e_strat
	e_strat.is_dead = true
	ivo._run_skill(0.05, player, sk_cmd)
	var skill_enemy_aborted: bool = sk_cmd.done
	e_strat.is_dead = false
	var sk_ally_cmd := CommandScript.make("skill", {"skill": "mirror_ward", "target": "Brannoc"}, "test")
	ivo.assign(sk_ally_cmd)
	sk_ally_cmd.data["target_node"] = brannoc
	brannoc.is_downed = true
	ivo._run_skill(0.05, player, sk_ally_cmd)
	brannoc.is_downed = false
	_check("aly14_run_skill_target_validity", skill_enemy_aborted and sk_ally_cmd.done, "en=%s ally=%s" % [skill_enemy_aborted, sk_ally_cmd.done])

	# ---- ALY-15: _run_position() left vs right uninverted ----
	player.global_position = Vector3.ZERO
	player.set_facing_direction(Vector3.FORWARD)
	var left_cmd := CommandScript.make("position", {"spot": "left"}, "test")
	var right_cmd := CommandScript.make("position", {"spot": "right"}, "test")
	brannoc.global_position = Vector3.ZERO
	brannoc.assign(left_cmd)
	brannoc._run_position(0.05, player, left_cmd)
	var left_spot: Vector3 = left_cmd.data.get("spot_cache", Vector3.ZERO) as Vector3
	brannoc.assign(right_cmd)
	brannoc._run_position(0.05, player, right_cmd)
	var right_spot: Vector3 = right_cmd.data.get("spot_cache", Vector3.ZERO) as Vector3
	_check("aly15_position_left_right_uninverted", left_spot.x < -0.5 and right_spot.x > 0.5, "left=%s right=%s" % [left_spot, right_spot])

	# ---- ALY-16, ALY-17, ALY-18: Command parser fixes ----
	var ctx: Dictionary = mgr.get_parser_context()
	var names: Array = mgr.get_ally_names()
	var p_hex: Array = ParserScript.parse("kill the hexcaster", names, ctx)
	var p_sg: Array = ParserScript.parse("kill the shielded guard", names, ctx)
	var p_bg: Array = ParserScript.parse("Brannoc guard Ivo", names, ctx)
	_check("aly16_parser_word_boundaries",
		String(p_hex[0].get("verb", "")) == "attack"
		and String(p_sg[0].get("verb", "")) == "attack"
		and String(p_bg[0].get("verb", "")) == "bodyguard",
		"hex=%s sg=%s bg=%s" % [p_hex, p_sg, p_bg])

	var p_warden: Array = ParserScript.parse("attack the warden", names, ctx)
	var p_health: Array = ParserScript.parse("what is your health", names, ctx)
	var p_archer: Array = ParserScript.parse("shoot the archer", names, ctx)
	_check("aly17_match_skill_trailing_boundary",
		String(p_warden[0].get("verb", "")) == "attack"
		and String(p_health[0].get("verb", "")) == "status"
		and String(p_archer[0].get("verb", "")) == "ranged",
		"w=%s h=%s a=%s" % [p_warden, p_health, p_archer])

	var p_ward_b: Array = ParserScript.parse("Ivo, ward Brannoc", names, ctx)
	_check("aly18_addressed_skill_first_verb_pos",
		p_ward_b.size() == 1
		and String(p_ward_b[0].get("verb", "")) == "skill"
		and (p_ward_b[0].get("allies", []) as Array) == ["Ivo"]
		and String(p_ward_b[0].get("target", "")) == "Brannoc",
		str(p_ward_b))

	# ---- ALY-21: SquadCommsHUD menu/loading/visibility gating & PTT release ----
	var hud_layer := CanvasLayer.new()
	harness.add_child(hud_layer)
	var comms_hud: SquadCommsHUD = CommsHudScript.new() as SquadCommsHUD
	hud_layer.add_child(comms_hud)
	await physics_frame
	hud_layer.visible = false
	var ev_f10 := InputEventAction.new()
	ev_f10.action = "cinematic_mode"
	ev_f10.pressed = true
	comms_hud._input(ev_f10)
	var f10_blocked_hidden: bool = not comms_hud._cinematic
	hud_layer.visible = true
	var loader := LoadingScreenScript.new()
	root.add_child(loader)
	comms_hud._input(ev_f10)
	var f10_blocked_loading: bool = not comms_hud._cinematic
	loader.free()
	comms_hud._ptt_held_key = true
	comms_hud._chat_open = true
	var ev_ptt_up := InputEventAction.new()
	ev_ptt_up.action = "push_to_talk"
	ev_ptt_up.pressed = false
	comms_hud._input(ev_ptt_up)
	comms_hud._chat_open = false
	PlayerScript.ui_input_locked = false
	_check("aly21_comms_hud_input_gating_and_ptt_release",
		f10_blocked_hidden and f10_blocked_loading and not comms_hud._ptt_held_key,
		"hidden=%s loading=%s ptt=%s" % [f10_blocked_hidden, f10_blocked_loading, comms_hud._ptt_held_key])

	# ---- ALY-22: 03_ivo.tres description 18% & no autonomous mending ----
	var mend_prof: AllySkill = ivo.profile.find_skill("mending_light")
	_check("aly22_ivo_mending_description_and_no_auto",
		mend_prof != null
		and is_equal_approx(mend_prof.power, 0.18)
		and mend_prof.description.contains("18%")
		and (mend_prof.auto_use.is_empty() or mend_prof.auto_use == "never"),
		mend_prof.description if mend_prof != null else "missing")

	# ---- ALY-23: _chain_arc_hop() checks apply_damage bool & continues on mid-flight death ----
	var sg_enemy: ShieldedGuard = _make_test_enemy(ShieldedScript, Vector3(0.0, 0.0, -4.0), "Test_Shielded") as ShieldedGuard
	sg_enemy.set_facing_direction(Vector3(0.0, 0.0, 1.0))
	var e_dead_mid: EnemyAI = _make_test_enemy(EnemyAIScript, Vector3(2.0, 0.0, -4.0), "Test_DeadMid")
	var e_hop3: EnemyAI = _make_test_enemy(EnemyAIScript, Vector3(4.0, 0.0, -4.0), "Test_Hop3")
	harness.add_child(sg_enemy)
	harness.add_child(e_dead_mid)
	harness.add_child(e_hop3)
	await physics_frame
	rm.force_realm(RealmManagerScript.Realm.REALITY, false)
	ivo.global_position = Vector3(0.0, 0.0, -1.0)
	var arc_skill: AllySkill = ivo.profile.find_skill("chain_arc")
	var hops: Array[EnemyAI] = [sg_enemy, e_dead_mid, e_hop3]
	var mults: Array[float] = [1.0, 0.72, 0.5]
	e_dead_mid.is_dead = true
	ivo._chain_arc_hop(arc_skill, hops, mults, 0, ivo.global_position + Vector3.UP)
	await create_timer(0.8).timeout
	_check("aly23_chain_arc_landed_guard_and_midflight_hops",
		not sg_enemy.is_stunned() and e_hop3.health < e_hop3.max_health,
		"sg_stun=%s hop3_hp=%d/%d" % [sg_enemy.is_stunned(), e_hop3.health, e_hop3.max_health])

	# ---- ALY-24: _run_destroy() checks vertical Y reach (3.6 m ledge unreachable from ground) ----
	var prop := BreakableScript.new() as BreakableProp
	prop.prop_kind = BreakableScript.PropKind.WEAK_STONE_SUPPORT
	prop.position = Vector3(0.0, 3.6, -2.0)
	harness.add_child(prop)
	await physics_frame
	brannoc.global_position = Vector3(0.0, 0.0, -2.0)
	var dst_cmd := CommandScript.make("destroy", {}, "test")
	brannoc.assign(dst_cmd)
	dst_cmd.data["prop"] = prop
	brannoc._run_destroy(0.05, player, dst_cmd)
	var stayed_intact_below: bool = prop.current_state == BreakableScript.PropState.INTACT
	brannoc.global_position = Vector3(0.0, 3.6, -1.5)
	brannoc._run_destroy(0.05, player, dst_cmd)
	var smashed_on_ledge: bool = dst_cmd.done and brannoc._action == "attack"
	_check("aly24_destroy_vertical_reach_check", stayed_intact_below and smashed_on_ledge,
		"below_intact=%s ledge_smashed=%s" % [stayed_intact_below, smashed_on_ledge])

	harness.queue_free()
	await process_frame
	print("[friends_ai] SUMMARY %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
