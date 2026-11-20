extends SceneTree
## Headless regression suite for Enemy Marking, 18 m Region Detection & Free-Leash Ally Commands (MRK-01..MRK-12).
## Usage: godot --headless --path . -s res://tests/enemy_marking_free_leash_regression_test.gd

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
const SquadCommsScript := preload("res://addons/parallax_squad_ai/squad_comms.gd")
const SquadAIConfigScript := preload("res://addons/parallax_squad_ai/squad_ai_config.gd")
const EnemyAIScript := preload("res://scripts/enemies/enemy_ai.gd")
const ArchetypeEnemyScript := preload("res://scripts/enemies/archetype_enemy.gd")
const HexArchetype := preload("res://data/enemies/hollow_hexcaster.tres")
const PhantomScript := preload("res://scripts/enemies/phantom_twin.gd")
const PitKillZoneScript := preload("res://scripts/environment/pit_kill_zone.gd")
const EncounterGateScript := preload("res://scripts/environment/encounter_gate.gd")

var _fails: int = 0
var _checks: int = 0


func _check(test_name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[mark_leash] %s %s %s" % ["PASS" if ok else "FAIL", test_name, detail])


func _initialize() -> void:
	SquadAIConfigScript.force_offline()
	create_timer(120.0, true, false, true).timeout.connect(func() -> void:
		print("[mark_leash] WATCHDOG TIMEOUT")
		quit(2))
	_run()


func _make_enemy(script_res: GDScript, pos: Vector3, node_name: String) -> EnemyAI:
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


func _make_caster(pos: Vector3, node_name: String) -> ArchetypeEnemy:
	var e: ArchetypeEnemy = ArchetypeEnemyScript.new() as ArchetypeEnemy
	e.archetype = HexArchetype
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
	floor_box.size = Vector3(500.0, 1.0, 500.0)
	floor_cs.shape = floor_box
	floor_cs.position = Vector3(0.0, -0.5, -80.0)
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
	player._update_camera_pivot()

	var brannoc: SquadAlly = mgr.find_ally("Brannoc")
	var sera: SquadAlly = mgr.find_ally("Sera")
	var ivo: SquadAlly = mgr.find_ally("Ivo")
	var intel: WorldIntel = mgr.intel
	if brannoc == null or sera == null or ivo == null or intel == null:
		_check("harness_ready", false, "missing allies or intel")
		quit(1)
		return

	# ---- MRK-01: Aim-based marking, toggle unmark, MAX_MARKS FIFO eviction, clear_marks ----
	var m_e1: EnemyAI = _make_enemy(EnemyAIScript, Vector3(0.0, 0.0, -50.0), "Mark_E1")
	var m_e2: EnemyAI = _make_enemy(EnemyAIScript, Vector3(2.0, 0.0, -50.0), "Mark_E2")
	var m_e3: EnemyAI = _make_enemy(EnemyAIScript, Vector3(4.0, 0.0, -50.0), "Mark_E3")
	var m_e4: EnemyAI = _make_enemy(EnemyAIScript, Vector3(-2.0, 0.0, -50.0), "Mark_E4")
	var m_e5: EnemyAI = _make_enemy(EnemyAIScript, Vector3(-4.0, 0.0, -50.0), "Mark_E5")
	for me in [m_e1, m_e2, m_e3, m_e4, m_e5]:
		harness.add_child(me)
	await physics_frame
	var res_mark: Dictionary = intel.mark_enemy_at_aim()
	var res_unmark: Dictionary = intel.mark_enemy_at_aim()
	for me in [m_e1, m_e2, m_e3, m_e4, m_e5]:
		intel.mark_enemy(me)
	var mark_count_capped: int = intel.get_marked_enemies(false).size()
	var fifo_evicted_e1: bool = not intel.is_marked(m_e1) and intel.is_marked(m_e5)
	var nums_in_range: bool = true
	for sm in intel.get_marked_summaries():
		var mn: int = int(sm.get("num", 0))
		if mn < 1 or mn > 4:
			nums_in_range = false
	intel.clear_marks()
	var cleared_clean: bool = not intel.has_marks() and not intel.has_mark_zones()
	_check("mrk01_aim_mark_toggle_and_max_eviction",
		String(res_mark.get("action", "")) == "marked"
		and String(res_unmark.get("action", "")) == "unmarked"
		and mark_count_capped == 4
		and fifo_evicted_e1
		and nums_in_range
		and cleared_clean,
		"mark=%s unmark=%s cap=%d fifo=%s nums=%s" % [res_mark.get("action"), res_unmark.get("action"), mark_count_capped, fifo_evicted_e1, nums_in_range])
	for me in [m_e1, m_e2, m_e3, m_e4, m_e5]:
		me.queue_free()
	await process_frame

	# ---- MRK-02: Far-distance persistence (> 40 m, facing away) & 18 m region-radius detection ----
	player.camera_yaw = PI
	player._update_camera_pivot()
	var e_far_m: EnemyAI = _make_enemy(EnemyAIScript, Vector3(0.0, 0.0, -95.0), "Far_Marked")
	var e_reg_in: EnemyAI = _make_enemy(EnemyAIScript, Vector3(12.0, 0.0, -95.0), "Far_RegionIn")
	var e_reg_out: EnemyAI = _make_enemy(EnemyAIScript, Vector3(35.0, 0.0, -95.0), "Far_RegionOut")
	for fe in [e_far_m, e_reg_in, e_reg_out]:
		harness.add_child(fe)
	await physics_frame
	var m_num2: int = intel.mark_enemy(e_far_m)
	var has_far_m: bool = false
	var has_reg_in: bool = false
	var has_reg_out: bool = false
	for en in intel.get_entries():
		if en.get("node") == e_far_m and bool(en.get("marked", false)):
			has_far_m = true
		elif en.get("node") == e_reg_in and bool(en.get("in_mark_region", false)) and int(en.get("near_mark_num", 0)) == m_num2:
			has_reg_in = true
		elif en.get("node") == e_reg_out:
			has_reg_out = true
	_check("mrk02_far_mark_and_18m_region_detection",
		has_far_m and has_reg_in and not has_reg_out,
		"far=%s in18=%s out18=%s" % [has_far_m, has_reg_in, has_reg_out])

	# ---- MRK-03: Dead mark pruning, 10 s combat-death region linger, clear & regroup reset ----
	e_far_m.is_dead = true
	e_far_m._refresh_active_state()
	intel.refresh()
	var pruned_dead: bool = not intel.is_marked(e_far_m)
	var lingers_zone: bool = intel.has_mark_zones()
	var reg_still_detected: bool = false
	for en2 in intel.get_entries():
		if en2.get("node") == e_reg_in and bool(en2.get("in_mark_region", false)):
			reg_still_detected = true
	intel.clear_marks()
	var zone_cleared: bool = not intel.has_mark_zones()
	intel.mark_enemy(e_reg_in)
	mgr.regroup(true)
	var regroup_cleared: bool = not intel.has_marks() and not intel.has_mark_zones()
	_check("mrk03_dead_mark_prune_and_10s_region_linger",
		pruned_dead and lingers_zone and reg_still_detected and zone_cleared and regroup_cleared,
		"pruned=%s linger=%s reg=%s zclr=%s rclr=%s" % [pruned_dead, lingers_zone, reg_still_detected, zone_cleared, regroup_cleared])
	for fe in [e_far_m, e_reg_in, e_reg_out]:
		fe.queue_free()
	await process_frame

	# ---- MRK-04: Visual pins (MarkPin & MarkRegionPin), HUD input actions, no IntelTag, F10 hiding ----
	player.camera_yaw = 0.0
	player._update_camera_pivot()
	var v1: EnemyAI = _make_enemy(EnemyAIScript, Vector3(0.0, 0.0, -70.0), "Vis_Marked")
	var v2: EnemyAI = _make_enemy(EnemyAIScript, Vector3(8.0, 0.0, -70.0), "Vis_Neighbor")
	harness.add_child(v1)
	harness.add_child(v2)
	var hud_layer := CanvasLayer.new()
	harness.add_child(hud_layer)
	var comms_hud: SquadCommsHUD = CommsHudScript.new() as SquadCommsHUD
	hud_layer.add_child(comms_hud)
	await physics_frame
	var ev_m := InputEventAction.new()
	ev_m.action = "mark_enemy"
	ev_m.pressed = true
	comms_hud._input(ev_m)
	var m_pin: Label3D = v1.get_node_or_null("MarkPin") as Label3D
	var r_pin: Label3D = v2.get_node_or_null("MarkRegionPin") as Label3D
	var itag: Node3D = v1.get_node_or_null("IntelTag") as Node3D
	var pins_ok: bool = (
		not intel.show_tags
		and (itag == null or not itag.visible)
		and m_pin != null and m_pin.visible and String(m_pin.get_meta("wl_kind", "")) == "mark"
		and r_pin != null and r_pin.visible and String(r_pin.get_meta("wl_kind", "")) == "mark_nearby"
	)
	comms_hud.set_cinematic(true)
	var cine_hid: bool = (m_pin != null and not m_pin.visible) and (r_pin != null and not r_pin.visible)
	comms_hud.set_cinematic(false)
	var cine_restored: bool = (m_pin != null and m_pin.visible) and (r_pin != null and r_pin.visible)
	var ev_clr := InputEventAction.new()
	ev_clr.action = "clear_marks"
	ev_clr.pressed = true
	comms_hud._input(ev_clr)
	var x_cleared: bool = not intel.has_marks()
	_check("mrk04_visual_pins_and_hud_input_actions",
		pins_ok and cine_hid and cine_restored and x_cleared,
		"pins=%s cine_h=%s cine_r=%s x_clr=%s" % [pins_ok, cine_hid, cine_restored, x_cleared])
	hud_layer.queue_free()
	v1.queue_free()
	v2.queue_free()
	await process_frame

	# ---- MRK-05: WorldIntel.resolve default/explicit/region/nearest + Reality PhantomTwin mark ----
	var r_close: EnemyAI = _make_enemy(EnemyAIScript, Vector3(0.0, 0.0, -10.0), "Res_Close")
	var r_marked: EnemyAI = _make_enemy(EnemyAIScript, Vector3(0.0, 0.0, -90.0), "Res_Marked")
	var r_caster: ArchetypeEnemy = _make_caster(Vector3(10.0, 0.0, -90.0), "Res_Caster")
	var r_phant: PhantomTwin = _make_enemy(PhantomScript, Vector3(0.0, 0.0, -120.0), "Res_Phant") as PhantomTwin
	var r_phant_phys: EnemyAI = _make_enemy(EnemyAIScript, Vector3(10.0, 0.0, -120.0), "Res_PhantNeighbor")
	for re in [r_close, r_marked, r_caster, r_phant, r_phant_phys]:
		harness.add_child(re)
	await physics_frame
	rm.force_realm(RealmManagerScript.Realm.REALITY, false)
	await physics_frame
	var mn1: int = intel.mark_enemy(r_marked)
	var res_def: EnemyAI = intel.resolve("", player)
	var res_mrk: EnemyAI = intel.resolve("marked", player)
	var res_m1: EnemyAI = intel.resolve("M%d" % mn1, player)
	var res_caster: EnemyAI = intel.resolve("caster near M%d" % mn1, player)
	var res_near: EnemyAI = intel.resolve("nearest", player)
	intel.clear_marks()
	intel.mark_enemy(r_phant)
	var phant_pin: Label3D = r_phant.get_node_or_null("MarkPin") as Label3D
	var phant_null_in_real: bool = intel.get_primary_marked(true) == null
	var phant_radiates: bool = intel.is_in_mark_region(r_phant_phys) and phant_pin != null and phant_pin.visible
	intel.clear_marks()
	_check("mrk05_resolve_default_explicit_and_region_queries",
		res_def == r_marked and res_mrk == r_marked and res_m1 == r_marked
		and res_caster == r_caster and res_near == r_close
		and phant_null_in_real and phant_radiates,
		"def=%s mrk=%s m1=%s cast=%s near=%s ph_null=%s ph_rad=%s" % [res_def == r_marked, res_mrk == r_marked, res_m1 == r_marked, res_caster == r_caster, res_near == r_close, phant_null_in_real, phant_radiates])
	for re in [r_close, r_marked, r_caster, r_phant, r_phant_phys]:
		re.queue_free()
	await process_frame

	# ---- MRK-06: Offline parser mark phrases & verb-less M1 ----
	var ctx: Dictionary = mgr.get_parser_context()
	var names: Array = mgr.get_ally_names()
	var p_mrk: Array = ParserScript.parse("attack marked", names, ctx)
	var p_m1: Array = ParserScript.parse("M1!", names, ctx)
	var p_reg: Array = ParserScript.parse("Sera kite the caster near M1", names, ctx)
	var p_sk: Array = ParserScript.parse("Ivo mirror barrage M1", names, ctx)
	var p_that: Array = ParserScript.parse("attack that one", names, ctx)
	var p_grp: Array = ParserScript.parse("nuke the marked group", names, ctx)
	_check("mrk06_parser_mark_phrases_and_verbless",
		String(p_mrk[0].get("verb", "")) == "attack" and String(p_mrk[0].get("target", "")).contains("marked")
		and String(p_m1[0].get("verb", "")) == "attack" and String(p_m1[0].get("target", "")).contains("m1")
		and String(p_reg[0].get("verb", "")) == "kite" and String(p_reg[0].get("target", "")).contains("m1")
		and String(p_sk[0].get("verb", "")) == "skill" and String(p_sk[0].get("target", "")).contains("m1")
		and String(p_that[0].get("verb", "")) == "attack" and String(p_that[0].get("target", "")) == "marked_or_nearest"
		and String(p_grp[0].get("verb", "")) == "nuke" and String(p_grp[0].get("target", "")).contains("marked"),
		"mrk=%s m1=%s sk=%s that=%s" % [p_mrk[0], p_m1[0], p_sk[0], p_that[0]])

	# ---- MRK-07: Strategies ($distinct divide_and_conquer) & massacre target far marked pack ----
	var pk_m: EnemyAI = _make_enemy(EnemyAIScript, Vector3(0.0, 0.0, -85.0), "Pack_Mark")
	var pk_r1: EnemyAI = _make_enemy(EnemyAIScript, Vector3(8.0, 0.0, -85.0), "Pack_Reg1")
	var pk_r2: EnemyAI = _make_enemy(EnemyAIScript, Vector3(-8.0, 0.0, -85.0), "Pack_Reg2")
	var pk_close: EnemyAI = _make_enemy(EnemyAIScript, Vector3(0.0, 0.0, -12.0), "Pack_CloseUnmarked")
	for pe in [pk_m, pk_r1, pk_r2, pk_close]:
		harness.add_child(pe)
	await physics_frame
	intel.mark_enemy(pk_m)
	mgr.execute_strategy("divide_and_conquer", "", mgr.get_living(), "test")
	var div_all_in_pack: bool = true
	for a in mgr.get_living():
		var t_str: String = String(a.current.args.get("target", "")) if a.current != null else ""
		var t_node: EnemyAI = intel.resolve(t_str, a)
		if t_node == null or not intel.is_marked_or_in_region(t_node):
			div_all_in_pack = false
	mgr.issue({"verb": "massacre", "allies": ["all"]}, "test")
	var mass_pick: EnemyAI = mgr.pick_enemy_for(brannoc, player, 22.0, true)
	var mass_is_marked: bool = mass_pick != null and intel.is_marked_or_in_region(mass_pick)
	mgr.issue({"verb": "stop", "allies": ["all"]}, "test")
	intel.clear_marks()
	_check("mrk07_strategies_and_massacre_marked_pack",
		div_all_in_pack and mass_is_marked,
		"div=%s mass_pick=%s" % [div_all_in_pack, mass_pick.name if mass_pick != null else "null"])
	for pe in [pk_m, pk_r1, pk_r2, pk_close]:
		pe.queue_free()
	await process_frame

	# ---- MRK-08: describe_text() priority + SquadComms system prompt MARKED TARGETS ----
	var d_close: Array[EnemyAI] = []
	for di in range(4):
		var de: EnemyAI = _make_enemy(EnemyAIScript, Vector3(float(di) * 2.0, 0.0, -10.0), "Dist_%d" % di)
		harness.add_child(de)
		d_close.append(de)
	var d_far_m: EnemyAI = _make_enemy(EnemyAIScript, Vector3(0.0, 0.0, -120.0), "Prompt_Marked")
	var d_far_r: EnemyAI = _make_enemy(EnemyAIScript, Vector3(8.0, 0.0, -120.0), "Prompt_Reg")
	harness.add_child(d_far_m)
	harness.add_child(d_far_r)
	await physics_frame
	intel.mark_enemy(d_far_m)
	var field_txt: String = intel.describe_text(2)
	var comms: SquadComms = SquadCommsScript.new() as SquadComms
	harness.add_child(comms)
	await process_frame
	var sys_prompt: String = comms.build_system_prompt(brannoc)
	var combo_blank: Dictionary = SquadCommsScript.tool_to_command("start_combo", {"combo": "kite_nuke"})
	intel.clear_marks()
	_check("mrk08_describe_text_and_director_prompt",
		field_txt.contains("[MARKED M1]") and field_txt.contains("[NEAR M1]")
		and sys_prompt.contains("MARKED TARGETS:") and String(combo_blank.get("target", "x")) == "",
		"field=%s combo=%s" % [field_txt, combo_blank])
	comms.queue_free()
	d_far_m.queue_free()
	d_far_r.queue_free()
	for de in d_close:
		de.queue_free()
	await process_frame

	# ---- MRK-09: Free leash — no distance, >150 m, or lower-Y teleport under any active command ----
	var far_cmd_enemy: EnemyAI = _make_enemy(EnemyAIScript, Vector3(0.0, 0.0, -190.0), "Leash_FarEnemy")
	harness.add_child(far_cmd_enemy)
	await physics_frame
	intel.mark_enemy(far_cmd_enemy)
	brannoc.assign(CommandScript.make("attack", {"target": "M1"}, "test"))
	sera.assign(CommandScript.make("ranged", {"target": "M1"}, "test"))
	ivo.assign(CommandScript.make("hold", {"spot": Vector3(-3.0, 0.0, -190.0)}, "test"))
	brannoc.global_position = Vector3(0.0, -10.0, -190.0)
	sera.global_position = Vector3(3.0, -10.0, -190.0)
	ivo.global_position = Vector3(-3.0, -10.0, -190.0)
	for a in [brannoc, sera, ivo]:
		a._catch_up(player)
		a._last_pos = a.global_position
		a._stuck_timer = 2.5
		a._update_stuck(0.05)
	var stayed_190m: bool = (
		brannoc.has_free_leash() and sera.has_free_leash() and ivo.has_free_leash()
		and brannoc.global_position.z < -180.0
		and sera.global_position.z < -180.0
		and ivo.global_position.z < -180.0
	)
	_check("mrk09_free_leash_no_distance_or_elevation_teleport", stayed_190m,
		"z=[%.1f, %.1f, %.1f]" % [brannoc.global_position.z, sera.global_position.z, ivo.global_position.z])

	# ---- MRK-10: Free leash pit rescue returns to _last_safe_pos (distant battlefield), not player ----
	var pit := PitKillZoneScript.new() as PitKillZone
	pit.position = Vector3(0.0, -10.0, -95.0)
	pit.kill_y_threshold = -2.0
	pit.half_extents = Vector3(10.0, 10.0, 10.0)
	var pit_cs := CollisionShape3D.new()
	var pit_box := BoxShape3D.new()
	pit_box.size = Vector3(20.0, 20.0, 20.0)
	pit_cs.shape = pit_box
	pit.add_child(pit_cs)
	harness.add_child(pit)
	await physics_frame
	brannoc.assign(CommandScript.make("attack", {"target": "M1"}, "test"))
	brannoc._last_safe_pos = Vector3(0.0, 0.0, -90.0)
	brannoc._has_safe_pos = true
	brannoc.global_position = Vector3(0.0, -5.0, -95.0)
	brannoc._catch_up(player)
	var rescued_to_safe: bool = brannoc.global_position.distance_to(Vector3(0.0, 0.0, -90.0)) < 1.0 and brannoc.global_position.distance_to(player.global_position) > 80.0
	_check("mrk10_free_leash_pit_rescue_stays_at_last_safe_pos", rescued_to_safe, str(brannoc.global_position))
	pit.queue_free()
	far_cmd_enemy.queue_free()
	await process_frame

	# ---- MRK-11: Passive follow and ceasefire still catch up normally ----
	brannoc.clear_queue()
	ivo.clear_queue()
	brannoc.assign(CommandScript.make("follow", {}, "test"))
	ivo.assign(CommandScript.make("ceasefire", {}, "test"))
	brannoc.global_position = Vector3(0.0, 0.0, -35.0)
	ivo.global_position = Vector3(2.0, 0.0, -35.0)
	player.camera_yaw = 0.0
	player._update_camera_pivot()
	player.camera_yaw = PI
	player._update_camera_pivot()
	brannoc._catch_up(player)
	ivo._catch_up(player)
	var passive_caught_up: bool = (
		not brannoc.has_free_leash() and not ivo.has_free_leash()
		and brannoc.global_position.distance_to(player.global_position) < 8.0
		and ivo.global_position.distance_to(player.global_position) < 8.0
	)
	_check("mrk11_follow_and_ceasefire_still_catch_up", passive_caught_up,
		"b=%.1f i=%.1f" % [brannoc.global_position.distance_to(player.global_position), ivo.global_position.distance_to(player.global_position)])

	# ---- MRK-12: Distant ranged order (> 28 m) & scaled _approach_timeout ----
	var e_rng_far: EnemyAI = _make_enemy(EnemyAIScript, Vector3(0.0, 0.0, -80.0), "Ranged_FarMark")
	harness.add_child(e_rng_far)
	await physics_frame
	intel.mark_enemy(e_rng_far)
	brannoc.global_position = Vector3.ZERO
	var scaled_lim: float = brannoc._approach_timeout(10.0, Vector3(0.0, 0.0, -90.0))
	ivo.global_position = Vector3.ZERO
	var r_cmd := CommandScript.make("ranged", {}, "test")
	ivo.assign(r_cmd)
	ivo._run_ranged(0.05, player, r_cmd)
	_check("mrk12_ranged_and_approach_timeout_scale_for_distant_mark",
		scaled_lim > 20.0 and scaled_lim <= 45.0
		and not r_cmd.done and r_cmd.step == "closing to range",
		"lim=%.1f done=%s step=%s" % [scaled_lim, r_cmd.done, r_cmd.step])

	# ---- MRK-13: Safe blink never lands on parapets, blockers, or inside walls ----
	e_rng_far.queue_free()
	await process_frame
	for a_rst in [brannoc, sera, ivo]:
		a_rst.reset_full(Vector3.ZERO)
		a_rst.assign(CommandScript.make("follow", {}, "test"))
	var make_box := func(parent: Node, nm: String, pos: Vector3, sz: Vector3, layer: int) -> StaticBody3D:
		var sb := StaticBody3D.new()
		sb.name = nm
		sb.collision_layer = layer
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = sz
		cs.shape = bx
		sb.add_child(cs)
		sb.position = pos
		parent.add_child(sb)
		return sb

	var iso13 := Node3D.new()
	harness.add_child(iso13)
	make_box.call(iso13, "BridgeDeck13", Vector3(400.0, -0.5, 0.0), Vector3(2.6, 1.0, 14.0), RealmManagerScript.LAYER_WORLD_SHARED)
	make_box.call(iso13, "ParapetRailW13", Vector3(398.5, 0.56, 0.0), Vector3(0.61, 1.12, 14.0), RealmManagerScript.LAYER_WORLD_SHARED)
	make_box.call(iso13, "ParapetRailE13", Vector3(401.5, 0.56, 0.0), Vector3(0.61, 1.12, 14.0), RealmManagerScript.LAYER_WORLD_SHARED)
	make_box.call(iso13, "ParapetBlkW13", Vector3(398.5, 1.35, 0.0), Vector3(0.45, 2.7, 14.0), RealmManagerScript.LAYER_PLAYER_BLOCKER)
	make_box.call(iso13, "ParapetBlkE13", Vector3(401.5, 1.35, 0.0), Vector3(0.45, 2.7, 14.0), RealmManagerScript.LAYER_PLAYER_BLOCKER)
	make_box.call(iso13, "RearWall13", Vector3(400.0, 2.5, 1.5), Vector3(6.0, 5.0, 1.0), RealmManagerScript.LAYER_WORLD_SHARED)
	await physics_frame
	player.global_position = Vector3(400.0, 0.0, -2.0)
	player.set_facing_direction(Vector3.FORWARD)
	await physics_frame
	for a13 in [brannoc, sera, ivo]:
		a13.global_position = Vector3(400.0, 0.0, -40.0)
		a13._blink_to(player)
	var all_on_deck13: bool = true
	for a13 in [brannoc, sera, ivo]:
		if a13.global_position.y < -0.2 or a13.global_position.y > 0.3 or absf(a13.global_position.x - 400.0) > 1.1 or a13._is_embedded_in_world():
			all_on_deck13 = false
	_check("mrk13_blink_never_lands_on_parapet_or_inside_wall", all_on_deck13,
		"b=%s s=%s i=%s" % [brannoc.global_position, sera.global_position, ivo.global_position])
	iso13.queue_free()
	await process_frame

	# ---- MRK-14: Mirror stone & invalid _last_safe_pos / repeat falls never loop into valley ----
	var iso14 := Node3D.new()
	harness.add_child(iso14)
	make_box.call(iso14, "SafeDeck14", Vector3(450.0, -0.5, 0.0), Vector3(12.0, 1.0, 12.0), RealmManagerScript.LAYER_WORLD_SHARED)
	make_box.call(iso14, "MirrorStone14", Vector3(450.0, -0.5, -10.0), Vector3(3.0, 1.0, 3.0), RealmManagerScript.LAYER_WORLD_MIRROR)
	await physics_frame
	player.global_position = Vector3(450.0, 0.0, 0.0)
	brannoc.reset_full(Vector3(450.0, 0.0, 0.0))
	rm.force_realm(RealmManagerScript.Realm.MIRROR, false)
	await physics_frame
	brannoc.global_position = Vector3(450.0, 0.0, -10.0)
	brannoc._safe_pos_scan_t = 0.0
	for _m14 in range(3):
		brannoc._physics_process(0.05)
	var stone_ignored: bool = brannoc._last_safe_pos.z > -6.0
	rm.force_realm(RealmManagerScript.Realm.REALITY, false)
	await physics_frame
	brannoc.assign(CommandScript.make("attack", {"target": "M1"}, "test"))
	brannoc._last_safe_pos = Vector3(450.0, 0.0, -20.0)
	brannoc._has_safe_pos = true
	brannoc._pit_rescue_count = 0
	brannoc.global_position = Vector3(450.0, -25.0, -20.0)
	brannoc._catch_up(player)
	var invalid_safe_rescued_to_player: bool = brannoc.global_position.distance_to(player.global_position) < 5.0 and brannoc.global_position.y >= -0.2
	brannoc._last_safe_pos = Vector3(450.0, 0.0, -3.5)
	brannoc._has_safe_pos = true
	brannoc._pit_rescue_count = 0
	brannoc._pit_rescue_window_ms = Time.get_ticks_msec()
	brannoc.global_position = Vector3(450.0, -25.0, -10.0)
	brannoc._rescue_from_pit(player)
	var first_safe_z: float = brannoc.global_position.z
	brannoc.global_position = Vector3(450.0, -25.0, -10.0)
	brannoc._rescue_from_pit(player)
	var repeat_broke_loop: bool = absf(first_safe_z + 3.5) < 0.8 and brannoc.global_position.distance_to(player.global_position) < 5.0
	_check("mrk14_mirror_stone_safe_pos_never_causes_infinite_valley_fall",
		stone_ignored and invalid_safe_rescued_to_player and repeat_broke_loop,
		"stone=%s inv=%s rep=%s z1=%.1f" % [stone_ignored, invalid_safe_rescued_to_player, repeat_broke_loop, first_safe_z])
	iso14.queue_free()
	await process_frame

	# ---- MRK-15: Close follow stuck (< 6 m across chasm in camera view) still recovers ----
	var iso15 := Node3D.new()
	harness.add_child(iso15)
	make_box.call(iso15, "DeckNorth15", Vector3(500.0, -0.5, 0.0), Vector3(4.0, 1.0, 6.0), RealmManagerScript.LAYER_WORLD_SHARED)
	make_box.call(iso15, "DeckSouth15", Vector3(500.0, -0.5, -7.5), Vector3(4.0, 1.0, 6.0), RealmManagerScript.LAYER_WORLD_SHARED)
	await physics_frame
	player.global_position = Vector3(500.0, 0.0, 0.0)
	player.set_facing_direction(Vector3.BACK)
	player.camera_yaw = PI
	player._update_camera_pivot()
	await physics_frame
	brannoc.reset_full(Vector3(500.0, 0.0, -5.0))
	brannoc.assign(CommandScript.make("follow", {}, "test"))
	brannoc._stuck_anchor_pos = brannoc.global_position
	brannoc._last_pos = brannoc.global_position
	for _s15 in range(48):
		brannoc._physics_process(0.05)
	var recovered_close_chasm: bool = brannoc.global_position.z > -3.5 and brannoc.global_position.distance_to(player.global_position) < 4.5
	_check("mrk15_stuck_close_to_player_on_follow_or_across_chasm_recovers", recovered_close_chasm, str(brannoc.global_position))
	iso15.queue_free()
	await process_frame

	# ---- MRK-16: Ally embedded inside Blocker/wall pops out cleanly on scan ----
	var iso16 := Node3D.new()
	harness.add_child(iso16)
	make_box.call(iso16, "Floor16", Vector3(550.0, -0.5, 0.0), Vector3(10.0, 1.0, 10.0), RealmManagerScript.LAYER_WORLD_SHARED)
	make_box.call(iso16, "Blocker16", Vector3(550.0, 1.35, 0.0), Vector3(0.5, 2.7, 6.0), RealmManagerScript.LAYER_PLAYER_BLOCKER)
	brannoc.set_physics_process(false)
	await physics_frame
	player.global_position = Vector3(552.0, 0.0, 0.0)
	brannoc.reset_full(Vector3(550.0, 0.0, 0.0))
	await physics_frame
	var was_emb16: bool = brannoc._is_embedded_in_world()
	brannoc.set_physics_process(true)
	brannoc._embed_scan_t = 0.0
	brannoc._physics_process(0.05)
	var popped_out16: bool = was_emb16 and not brannoc._is_embedded_in_world() and brannoc.global_position.y >= -0.2
	_check("mrk16_embedded_in_wall_or_parapet_pops_out_automatically", popped_out16,
		"was=%s now_emb=%s pos=%s" % [was_emb16, brannoc._is_embedded_in_world(), brannoc.global_position])
	iso16.queue_free()
	await process_frame

	# ---- MRK-17: Free-leash staged unstick (bypass wall, block closed gate, Strike 2 rescue) ----
	var iso17 := Node3D.new()
	harness.add_child(iso17)
	make_box.call(iso17, "Floor17", Vector3(600.0, -0.5, -10.0), Vector3(14.0, 1.0, 36.0), RealmManagerScript.LAYER_WORLD_SHARED)
	make_box.call(iso17, "CornerWall17", Vector3(600.0, 1.5, -2.0), Vector3(4.0, 3.0, 0.8), RealmManagerScript.LAYER_WORLD_SHARED)
	var gate17: EncounterGate = EncounterGateScript.new() as EncounterGate
	gate17.starts_open = false
	gate17.animate_gate = false
	gate17.position = Vector3(600.0, 0.0, -18.0)
	make_box.call(gate17, "GateBody17", Vector3(0.0, 2.0, 0.0), Vector3(14.0, 4.0, 0.6), RealmManagerScript.LAYER_WORLD_SHARED)
	iso17.add_child(gate17)
	var e_bypass: EnemyAI = _make_enemy(EnemyAIScript, Vector3(600.0, 0.0, -15.0), "BypassTarget17")
	iso17.add_child(e_bypass)
	await physics_frame
	player.global_position = Vector3(600.0, 0.0, 5.0)
	intel.mark_enemy(e_bypass)
	brannoc.reset_full(Vector3(600.0, 0.0, -1.0))
	brannoc.assign(CommandScript.make("attack", {"target": "M1"}, "test"))
	brannoc._stuck_anchor_pos = brannoc.global_position
	brannoc._last_pos = brannoc.global_position
	brannoc._want_move_this_frame = true
	brannoc._want_move_goal = e_bypass.global_position
	brannoc._stuck_timer = 1.7
	brannoc._update_stuck(0.05)
	var strike0_stayed: bool = brannoc._stuck_strikes == 1 and brannoc.global_position.z > -1.8
	brannoc._stuck_anchor_pos = brannoc.global_position
	brannoc._last_pos = brannoc.global_position
	brannoc._want_move_this_frame = true
	brannoc._want_move_goal = e_bypass.global_position
	brannoc._stuck_timer = 1.7
	brannoc._update_stuck(0.05)
	var strike1_bypassed: bool = brannoc.global_position.z < -2.3 and brannoc.global_position.distance_to(e_bypass.global_position) < 13.5
	brannoc.global_position = Vector3(600.0, 0.0, -16.8)
	brannoc._last_pos = brannoc.global_position
	brannoc._stuck_anchor_pos = brannoc.global_position
	var crossed_gate: bool = brannoc._unstick_bypass(Vector3(600.0, 0.0, -24.0))
	brannoc._stuck_strikes = 2
	brannoc._want_move_this_frame = true
	brannoc._want_move_goal = Vector3(600.0, 0.0, -24.0)
	brannoc._stuck_timer = 1.7
	brannoc._update_stuck(0.05)
	var strike2_rescued: bool = brannoc.global_position.distance_to(player.global_position) < 5.0
	intel.clear_marks()
	_check("mrk17_free_leash_staged_unstick_and_closed_gate_respect",
		strike0_stayed and strike1_bypassed and not crossed_gate and strike2_rescued,
		"s0=%s s1=%s gate=%s s2=%s" % [strike0_stayed, strike1_bypassed, crossed_gate, strike2_rescued])
	iso17.queue_free()
	await process_frame

	# ---- MRK-18: Personal space push never shoves ally off unrailed ledge ----
	var iso18 := Node3D.new()
	harness.add_child(iso18)
	make_box.call(iso18, "Ledge18", Vector3(660.0, -0.5, 0.0), Vector3(2.0, 1.0, 10.0), RealmManagerScript.LAYER_WORLD_SHARED)
	await physics_frame
	player.global_position = Vector3(659.5, 0.0, 0.0)
	brannoc.reset_full(Vector3(660.6, 0.0, 0.0))
	brannoc.assign(CommandScript.make("follow", {}, "test"))
	await physics_frame
	for _h18 in range(15):
		brannoc._halt(0.05)
		brannoc._steer_toward_dir(Vector3.FORWARD, 3.0, 0.05, true, 5.0)
	var stayed_on_ledge: bool = brannoc.global_position.x <= 660.95 and brannoc.global_position.y >= -0.2
	_check("mrk18_personal_space_push_never_shoves_ally_off_ledge", stayed_on_ledge, str(brannoc.global_position))
	iso18.queue_free()
	await process_frame

	harness.queue_free()
	await process_frame
	print("[mark_leash] SUMMARY %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
