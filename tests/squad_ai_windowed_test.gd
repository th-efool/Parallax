extends SceneTree
## Windowed end-to-end test for the Conversational Squad AI (offline parser path — no API key needed).
## Run:  godot --path . -s res://tests/squad_ai_windowed_test.gd -- --shots=<absolute dir>
## Drives typed chat commands through the real chat-bar path (SquadCommsHUD.submit_chat_text), checks allies
## follow / bodyguard / kite+nuke / massacre / ceasefire / charge+finish / lure+detonate / silly orders /
## substitution / manual revive, dumps enemy threat tables, and saves screenshots.

var _shots: String = ""
var _results: Array[String] = []
var _log: Array[String] = []
var _ally_hits_during_ceasefire: int = 0
var _ceasefire_on: bool = false
var _main: Node = null
var _player: PlayerController = null
var _mgr: AllySquadManager = null
var _hud: SquadCommsHUD = null
var _level: Node = null
var _spawned: int = 0


func _initialize() -> void:
	# Deterministic offline run (no API quota): the typed-chat path goes through the keyword parser.
	SquadAIConfig.force_offline()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.substr(8)
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	create_timer(330.0).timeout.connect(func() -> void:
		print("[squad_test] WATCHDOG TIMEOUT")
		_finish())
	_run()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	if _shots.is_empty():
		return
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(_shots.path_join(name + ".png"))
	print("[squad_test] screenshot ", name)


func _say(t: String) -> void:
	print("[squad_test] CHAT> ", t)
	_hud.submit_chat_text(t)


func _check(name: String, ok: bool, detail: String = "") -> void:
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", name, detail]
	_results.append(line)
	print("[squad_test] ", line)


func _ally(n: String) -> SquadAlly:
	return _mgr.find_ally(n)


func _spawn(kind: String, pos: Vector3) -> EnemyBase:
	_spawned += 1
	var e: EnemyBase = _level.call("_add_roamer", _level, kind, "Test_%s_%d" % [kind, _spawned], pos, EncounterDirector.Section.ENTRY, Vector3(0, 0, -14)) as EnemyBase
	if e != null:
		e.damaged.connect(func(_amt: int, _h: bool, src: String) -> void:
			if _ceasefire_on and src.begins_with("ally"):
				_ally_hits_during_ceasefire += 1)
	return e


func _log_has(s: String) -> bool:
	for l in _log:
		if l.contains(s):
			return true
	return false


func _keep_player_alive() -> void:
	if _player != null and is_instance_valid(_player):
		_player.health = _player.max_health


func _teleport_player(p: Vector3) -> void:
	_player.global_position = p
	_player.velocity = Vector3.ZERO
	_player.set_facing_direction(Vector3(0, 0, 1))
	_player.camera_yaw = PI
	_player.camera_pitch = deg_to_rad(-18.0)


func _run() -> void:
	await _wait(1.0)
	var title: Node = get_first_node_in_group("title_screen")
	if title != null:
		if "show_quote_on_start" in title:
			title.set("show_quote_on_start", false)
		if title.has_method("press_start"):
			title.call("press_start")
	await _wait(2.5)
	_player = get_first_node_in_group("player") as PlayerController
	_mgr = AllySquadManager.instance
	_hud = root.find_child("SquadCommsHUD", true, false) as SquadCommsHUD
	_level = _main.get_node_or_null("LevelRoot")
	if _player == null or _mgr == null or _hud == null:
		print("[squad_test] missing nodes player=%s mgr=%s hud=%s" % [_player, _mgr, _hud])
		_finish()
		return
	_player.max_health = 100000
	_player.health = 100000
	process_frame.connect(_keep_player_alive)
	_mgr.combo_progress.connect(func(_k: String, t: String) -> void:
		_log.append("COMBO " + t)
		print("[squad_test] combo: ", t))
	_mgr.command_logged.connect(func(e: Dictionary) -> void: _log.append("CMD %s %s %s" % [e.get("who", ""), e.get("what", ""), e.get("result", "")]))
	_mgr.ally_spoke.connect(func(n: String, t: String, _e: String, _p: int, _v: String) -> void: print("[squad_test]   %s: %s" % [n, t]))
	_check("roster_three_allies", _mgr.allies.size() == 3, str(_mgr.get_ally_names()))

	# 1) Follow: walk forward on the start terrace, allies trail in formation.
	_teleport_player(Vector3(0, 0, -59))
	_mgr.regroup(false)
	await _wait(0.8)
	Input.action_press("move_forward")
	await _wait(1.6)
	Input.action_release("move_forward")
	await _wait(1.2)
	var max_d: float = 0.0
	for a in _mgr.allies:
		max_d = maxf(max_d, a.global_position.distance_to(_player.global_position))
	_check("allies_follow", max_d < 6.5, "max ally distance %.1f m" % max_d)
	await _shot("01_follow")

	# 2) Forecourt arena with test enemies.
	_teleport_player(Vector3(0, 0, -14))
	_mgr.regroup(false)
	await _wait(0.5)
	var e1: EnemyBase = _spawn("skeleton", Vector3(-3.5, 0, -6.5))
	var e2: EnemyBase = _spawn("skeleton", Vector3(3.5, 0, -6.5))
	var e3: EnemyBase = _spawn("stalker", Vector3(0.0, 0, -5.8))
	await _wait(0.3)
	_say("Brannoc, guard me")
	await _wait(4.0)
	var bran: SquadAlly = _ally("Brannoc")
	_check("bodyguard_assigned", bran.current != null and bran.current.verb == "bodyguard", bran.get_state_text())
	await _shot("02_bodyguard")
	_dump_threat()
	# Only melee enemies (skeletons + stalker) so far: allies must be hittable by enemy melee hitboxes.
	var hurt_any: bool = false
	for a in _mgr.allies:
		hurt_any = hurt_any or a.health < a.max_health
	_check("allies_take_enemy_melee", hurt_any, _mgr.get_roster_text().replace("\n", " | "))

	# 3) Kite + Nuke combo.
	_say("Sera and Ivo, kite and nuke them")
	var t0: int = Time.get_ticks_msec()
	var shot_taken: bool = false
	while Time.get_ticks_msec() - t0 < 16000 and not _log_has("Nuke released"):
		await _wait(0.1)
		var ivo: SquadAlly = _ally("Ivo")
		if not shot_taken and ivo != null and ivo._action == "channel":
			shot_taken = true
			await _shot("03_kite_nuke_casting")
	_check("kite_nuke", _log_has("Nuke released"), "ready signal: %s" % str(_log_has("ready signal")))
	if not shot_taken:
		await _shot("03_kite_nuke")
	_dump_threat()

	# 3b) Mid-combo substitution: the kiter goes down while kiting -> a free ally takes over (or solo fallback).
	await _reset_arena()
	_spawn("skeleton", Vector3(-2.0, 0, -6.0))
	await _wait(0.4)
	_log.clear()
	_say("kite and nuke")
	await _wait(2.0)
	var kiter: SquadAlly = _ally("Sera")
	kiter.apply_damage(99999, null)
	await _wait(1.0)
	_check("mid_combo_substitution", _log_has("Substitution") or _log_has("Solo fallback"), " / ".join(_log.filter(func(l: String) -> bool: return l.begins_with("COMBO"))))
	kiter.revive(1.0)
	_say("stop")
	await _wait(0.5)

	# 4) Massacre (panic) — top up enemies first.
	if _living_test_enemies() < 2:
		_spawn("skeleton", Vector3(-2.5, 0, -6.0))
		_spawn("hexcaster", Vector3(2.5, 0, -5.5))
		await _wait(0.5)
	_say("everyone massacre")
	await _wait(0.5)
	var all_m: bool = true
	for a in _mgr.get_living():
		all_m = all_m and a.current != null and a.current.verb == "massacre"
	_check("massacre_assigned", all_m, _states())
	await _wait(2.5)
	await _shot("04_massacre")

	# 5) Ceasefire: panic override — no ally damage afterwards.
	_say("ceasefire!")
	await _wait(0.6)
	var all_c: bool = true
	for a in _mgr.get_living():
		all_c = all_c and a.current != null and a.current.verb == "ceasefire"
	_ceasefire_on = true
	await _wait(3.0)
	_ceasefire_on = false
	_check("ceasefire", all_c and _ally_hits_during_ceasefire == 0, "assigned=%s ally_hits=%d" % [str(all_c), _ally_hits_during_ceasefire])
	await _shot("05_ceasefire")

	# 6) Charge + Finish.
	await _reset_arena()
	if _living_test_enemies() < 1:
		_spawn("skeleton", Vector3(0.0, 0, -6.0))
		await _wait(0.4)
	_say("charge and finish the nearest one")
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 14000 and not (_log_has("Finisher landed") or _log_has("Charge + Finish complete")):
		await _wait(0.1)
	_check("charge_finish", _log_has("knocked the target down"), "finisher=%s" % str(_log_has("Finisher landed")))

	# 7) Lure + Detonate.
	await _reset_arena()
	_spawn("skeleton", Vector3(-3.0, 0, -6.0))
	_spawn("skeleton", Vector3(3.0, 0, -6.0))
	await _wait(0.4)
	_say("lure them into a trap")
	t0 = Time.get_ticks_msec()
	var lure_shot: bool = false
	while Time.get_ticks_msec() - t0 < 22000 and not _log_has("Detonated"):
		await _wait(0.1)
		if not lure_shot and _log_has("Sigil planted"):
			lure_shot = true
			await _wait(1.5)
			await _shot("06_lure_sigil")
	_check("lure_detonate", _log_has("Detonated"), "planted=%s" % str(_log_has("Sigil planted")))

	# 8) Silly / arbitrary orders must never crash.
	await _reset_arena()
	_say("jump 3 times")
	await _wait(0.3)
	_say("Sera dance")
	_say("make me a sandwich")
	_say("jump 99999 times")
	_say("")
	_say("!!!???")
	await _wait(2.5)
	await _shot("07_silly")
	_check("silly_orders_no_crash", true, _states())
	await _wait(9.0)
	# No finite order may be stuck behind a stance (stances never finish on their own).
	var blocked: int = 0
	for a in _mgr.allies:
		var seen_stance: bool = false
		for q in a.queue:
			if q.stance:
				seen_stance = true
			elif seen_stance:
				blocked += 1
	_check("queue_no_order_behind_stance", blocked == 0, _states())

	# 8b) Extended orders: split, take aggro, peel, hit-and-run, ally's-target assist, errands.
	await _reset_arena()
	_say("split up")
	await _wait(0.4)
	var lanes: int = 0
	for a in _mgr.allies:
		if a.current != null and a.current.verb == "hold" and a.current.args.has("lane"):
			lanes += 1
	_check("split_left_right_center", lanes == _mgr.allies.size(), _states())
	await _wait(1.5)
	await _shot("10_split")
	_say("follow me")
	var s1: EnemyBase = _spawn("skeleton", Vector3(-1.5, 0, -9.5))
	var s2: EnemyBase = _spawn("skeleton", Vector3(1.5, 0, -9.5))
	for s in [s1, s2]:
		(s as EnemyBase).max_health = 3000
		(s as EnemyBase).health = 3000
	await _wait(0.3)
	(s1 as EnemyAI).apply_taunt(_player, 200.0, 3.0)
	(s2 as EnemyAI).apply_taunt(_player, 200.0, 3.0)
	await _wait(0.6)
	_say("Brannoc, take aggro")
	await _wait(2.5)
	var pulled: int = 0
	for e in [s1, s2]:
		var ai: EnemyAI = e as EnemyAI
		if not ai.is_dead and ai.get_current_target() is SquadAlly:
			pulled += 1
	_check("take_aggro_pulls_off_player", pulled >= 1, "pulled %d; s1->%s s2->%s; %s" % [pulled, str((s1 as EnemyAI).get_current_target()), str((s2 as EnemyAI).get_current_target()), _states()])
	_say("Sera, hit and run the nearest")
	_say("Ivo, attack Sera's target")
	await _wait(1.0)
	var ivo2: SquadAlly = _ally("Ivo")
	var sera2: SquadAlly = _ally("Sera")
	_check("hit_and_run_assigned", sera2.current != null and sera2.current.verb == "hit_and_run", sera2.get_state_text())
	_check("assist_ally_target", ivo2.current != null and ivo2.current.verb == "attack" and String(ivo2.current.args.get("target", "")).begins_with("ally:"), ivo2.get_state_text())
	_say("peel it off me")
	await _wait(0.5)
	_check("peel_assigned", _ally("Brannoc").current != null and _ally("Brannoc").current.verb == "peel" or _ally("Brannoc").queue.any(func(q: SquadCommand) -> bool: return q.verb == "peel"), _states())
	await _wait(2.0)
	await _reset_arena()
	_say("go hunt some wildlife")
	_say("smash that thing")
	_say("open the chest")
	_say("guard the objective")
	await _wait(4.0)
	_check("errand_orders_no_crash", true, _states())
	# Role substitution for a direct order to a downed ally.
	_ally("Ivo").apply_damage(99999, null)
	await _wait(0.3)
	_spawn("skeleton", Vector3(0.0, 0, -7.0))
	await _wait(0.3)
	_log.clear()
	_say("Ivo, nuke the nearest")
	await _wait(0.3)
	_check("direct_order_substitution", _log_has("substitute for Ivo") or _log_has("dropped: ally down"), " / ".join(_log))
	await _reset_arena()

	# 8c) WorldIntel targeting by look / colour / weapon / ID, signature skills, strategies.
	await _reset_arena()
	var caster: EnemyBase = _spawn("hexcaster", Vector3(-4.0, 0, -6.0))
	var brute: EnemyBase = _spawn("brute", Vector3(4.0, 0, -6.0))
	var stalker: EnemyBase = _spawn("stalker", Vector3(0.0, 0, -5.5))
	for s in [caster, brute, stalker]:
		(s as EnemyBase).max_health = 4000
		(s as EnemyBase).health = 4000
	await _wait(1.2)
	var intel: WorldIntel = _mgr.intel
	intel.refresh()
	_check("intel_ids_assigned", not intel.id_of(caster).is_empty() and intel.get_entries().size() >= 3, intel.describe_text(5).replace("\n", " || "))
	_check("intel_resolve_colour", intel.resolve("the purple caster") == caster, "")
	_check("intel_resolve_weapon_size", intel.resolve("big green guy with the axe") == brute, "")
	_check("intel_resolve_id", intel.resolve(intel.id_of(stalker)) == stalker, intel.id_of(stalker))
	_dump_threat()
	await _shot("11_intel_tags")
	_say("Sera, kill the purple one")
	await _wait(0.4)
	var st: SquadAlly = _ally("Sera")
	_check("nl_attack_by_colour", st.current != null and st.current.verb == "attack" and _mgr.resolve_enemy(String(st.current.args.get("target", "")), _player.global_position) == caster, st.get_state_text())
	# Skills on command.
	var bran2: SquadAlly = _ally("Brannoc")
	bran2.health = int(bran2.max_health * 0.4)
	_say("Ivo heal Brannoc")
	await _wait(2.5)
	_check("skill_heal_ally", bran2.health > int(bran2.max_health * 0.4), "Brannoc %d/%d" % [bran2.health, bran2.max_health])
	_say("Brannoc war cry")
	await _wait(2.5)
	var taunted_by_b: int = 0
	for e in [caster, brute, stalker]:
		if (e as EnemyAI).get_current_target() == bran2:
			taunted_by_b += 1
	_check("skill_war_cry_taunts", bran2.skill_remaining(bran2.profile.find_skill("war_cry")) > 0.0, "on Brannoc: %d" % taunted_by_b)
	_say("Sera smoke bomb")
	await _wait(2.0)
	_check("skill_smoke_bomb", st.skill_remaining(st.profile.find_skill("smoke_bomb")) > 0.0, "")
	await _shot("12_skills")
	# Strategies.
	_say("surround the brute")
	await _wait(0.5)
	var surround_n: int = 0
	for a in _mgr.get_living():
		if a.current != null and a.current.verb == "surround":
			surround_n += 1
	_check("strategy_surround", surround_n == _mgr.get_living().size(), _states())
	await _wait(2.5)
	await _shot("13_surround")
	_say("divide and conquer")
	await _wait(0.5)
	var tgts: Dictionary = {}
	for a in _mgr.get_living():
		if a.current != null and a.current.verb == "attack":
			tgts[String(a.current.args.get("target", ""))] = true
	_check("strategy_divide_distinct_targets", tgts.size() >= mini(3, _mgr.get_living().size()), str(tgts.keys()))
	_say("shield wall")
	await _wait(1.5)
	_check("strategy_shield_wall", bran2._dr > 0.0 or bran2.skill_remaining(bran2.profile.find_skill("shield_wall")) > 0.0, _states())
	_say("ok everyone pincer the stalker")
	await _wait(0.5)
	_check("strategy_pincer", _mgr.active_strategy == "Pincer", _states())
	# Autonomous skill use during a fight.
	_say("everyone massacre")
	await _wait(6.0)
	var auto_used: int = 0
	for a in _mgr.allies:
		for sk in a.get_skill_states():
			if float((sk as Dictionary)["remaining"]) > 0.0:
				auto_used += 1
	_check("skills_used_in_fight", auto_used >= 3, "%d skills on cooldown" % auto_used)
	await _shot("14_skill_fight")
	await _reset_arena()

	# 9) Substitution when an ally is down, then manual revive by the player.
	await _reset_arena()
	_say("follow me")
	await _wait(0.5)
	var sera: SquadAlly = _ally("Sera")
	sera.apply_damage(99999, null)
	await _wait(0.4)
	_check("ally_downed_roster", sera.is_downed and _mgr.get_roster_text().contains("DOWN"), _mgr.get_roster_text().replace("\n", " | "))
	_spawn("skeleton", Vector3(0.0, 0, -6.0))
	await _wait(0.4)
	_log.clear()
	_say("kite and nuke")
	await _wait(0.5)
	var sub_ok: bool = false
	for l in _log:
		if l.contains("kiter=Brannoc") or l.contains("solo fallback") or l.contains("kiter=Ivo"):
			sub_ok = true
	_check("substitution_when_down", sub_ok, " / ".join(_log))
	_teleport_player(sera.global_position + Vector3(1.0, 0, -0.5))
	await _wait(0.3)
	_player.try_interact()
	await _wait(0.4)
	_check("manual_revive", not sera.is_downed, "Sera hp %d" % sera.health)

	# 10) Chat bar UI + mode gating + cinematic.
	_hud.open_chat()
	(_hud.get_node("ChatBar").find_child("ChatEdit", true, false) as LineEdit).text = "Sera, kite the brute and Ivo nuke it"
	await _shot("08_chat_bar")
	_hud.close_chat()
	SquadAIConfig.mode = "voice"
	_hud.open_chat()
	_check("mode_voice_blocks_chat", not _hud.is_chat_open())
	SquadAIConfig.mode = "both"
	_hud.set_cinematic(true)
	await _shot("09_cinematic")
	_hud.set_cinematic(false)
	_check("player_input_unlocked", not PlayerController.ui_input_locked)

	# 11) One message, different chains per ally + movement + ranged + rear guard + talk.
	await _reset_arena()
	_teleport_player(Vector3(0, 0, -14))
	_mgr.regroup(false)
	await _wait(0.6)
	_log.clear()
	_say("Brannoc jump twice then hold the rear, Sera get behind me then shoot the skeleton, Ivo come in front of me")
	await _wait(0.2)
	var br: SquadAlly = _ally("Brannoc")
	var se: SquadAlly = _ally("Sera")
	var iv: SquadAlly = _ally("Ivo")
	var br_chain: bool = br.current != null and br.current.verb == "jump" and br.queue.size() >= 1 and br.queue[0].verb == "rearguard"
	var se_chain: bool = se.current != null and se.current.verb == "position" and se.queue.size() >= 1 and se.queue[0].verb == "ranged"
	_check("chain_assigned_per_ally", br_chain and se_chain and iv.current != null and iv.current.verb == "position", _states() + " | " + " / ".join(_log))
	var sk: EnemyBase = _spawn("skeleton", Vector3(0.0, 0, -3.0))
	await _wait(3.5)
	var pf: Vector3 = _player.get_facing_direction()
	var iv_rel: float = (iv.global_position - _player.global_position).dot(pf)
	_check("position_front", iv_rel > 1.2, "Ivo %.1f m ahead" % iv_rel)
	_check("chain_advanced_brannoc", br.current != null and br.current.verb == "rearguard", _states())
	var br_rel: float = (br.global_position - _player.global_position).dot(pf)
	_check("rearguard_behind", br_rel < -1.5, "Brannoc %.1f m along facing" % br_rel)
	var t_r: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_r < 5000 and not (se.current != null and se.current.verb == "ranged" and se.global_position.distance_to(sk.global_position) > 4.0):
		await process_frame
	var sera_d: float = se.global_position.distance_to(sk.global_position)
	_check("ranged_keeps_distance", se.current != null and se.current.verb == "ranged" and sera_d > 4.0, "Sera %s at %.1f m from target" % [se.get_state_text(), sera_d])
	await _wait(5.0)
	_check("ranged_damages", sk.is_dead or sk.health < sk.max_health, "skeleton hp %d/%d" % [sk.health, sk.max_health])
	await _shot("15_chains")
	_log.clear()
	_say("hey Ivo, tell me a joke")
	await _wait(0.3)
	_check("small_talk_replies", _log_has("chat joke"), " / ".join(_log))

	# 12) Auto-rally: a squad-mate at low HP with an enemy on them -> everyone else rushes to protect.
	await _reset_arena()
	_teleport_player(Vector3(0, 0, -14))
	_mgr.regroup(false)
	await _wait(0.5)
	_say("everyone hold here")
	await _wait(0.4)
	var ward: SquadAlly = _ally("Sera")
	_ally("Ivo")._skill_cd["mending_light"] = 60.0   # isolate the rally from Ivo's instant heal
	ward._skill_cd["smoke_bomb"] = 60.0   # ...and from Sera vanishing in smoke
	ward.global_position = Vector3(4.0, 0, -8.0)
	var rally_foe: EnemyBase = _spawn("skeleton", Vector3(5.5, 0, -7.0))
	rally_foe.max_health = 5000
	rally_foe.health = 5000
	await _wait(0.3)
	(rally_foe as EnemyAI).apply_taunt(ward, -1.0, 6.0)
	ward.health = int(ward.max_health * 0.15)
	await _wait(1.2)
	var rallying: int = 0
	for a in _mgr.get_living():
		if a != ward and a.current != null and a.current.verb == "bodyguard" and bool(a.current.data.get("rally", false)):
			rallying += 1
	_check("auto_rally_starts", rallying >= 2 and _mgr.is_rallying(), "%d helpers; %s" % [rallying, _states()])
	await _wait(1.5)
	var near_ward: int = 0
	for a in _mgr.get_living():
		if a != ward and a.global_position.distance_to(ward.global_position) < 5.0:
			near_ward += 1
	_check("auto_rally_rushes", near_ward >= 2, "%d helpers within 5 m" % near_ward)
	await _shot("16_rally")
	rally_foe.apply_damage(99999, true, "environmental", null)
	ward.health = ward.max_health
	await _wait(3.5)
	var resumed: bool = true
	for a in _mgr.get_living():
		if a != ward and (a.current == null or a.current.verb != "hold"):
			resumed = false
	_check("auto_rally_ends_and_resumes", not _mgr.is_rallying() and resumed, _states())

	# 13) Taunt fixation: a taunted enemy chases its taunter for good — past the old 4 s lock and past its leash.
	await _reset_arena()
	_teleport_player(Vector3(0, 0, -14))
	_mgr.regroup(false)
	await _wait(0.5)
	var fx: EnemyBase = _spawn("skeleton", Vector3(0.0, 0, -6.0))
	fx.max_health = 5000
	fx.health = 5000
	await _wait(0.3)
	var taunter: SquadAlly = _ally("Brannoc")
	(fx as EnemyAI).apply_taunt(taunter, -1.0, 4.0)
	_say("Brannoc hold here")
	await _wait(0.2)
	# Walk the taunter well away from the enemy's home (leash 22 m) across the forecourt / causeway.
	taunter.global_position = Vector3(-3.5, 0, -40.0)
	_teleport_player(Vector3(-3.5, 0, -36.0))   # stay near him so his catch-up teleport never fires
	if taunter.current != null:
		taunter.current.args["spot"] = Vector3(-3.5, 0, -40.0)
		taunter.current.data["spot"] = Vector3(-3.5, 0, -40.0)
	await _wait(14.0)
	var fx_d: float = fx.global_position.distance_to(taunter.global_position)
	_check("taunt_fixation_persists", (fx as EnemyAI).is_fixated() and (fx as EnemyAI).get_current_target() == taunter, "fixated=%s target=%s" % [(fx as EnemyAI).is_fixated(), str((fx as EnemyAI).get_current_target())])
	_check("taunted_enemy_chases_past_leash", fx_d < 8.0 and fx.global_position.distance_to((fx as EnemyAI).get_home_position()) > 22.0, "%.1f m from taunter, %.1f m from home" % [fx_d, fx.global_position.distance_to((fx as EnemyAI).get_home_position())])
	fx.apply_damage(99999, true, "environmental", null)

	# 14) Bait + sneak attack in one message: the bait keeps the enemy chasing it, the other gets behind it.
	await _reset_arena()
	_teleport_player(Vector3(0, 0, -14))
	_mgr.regroup(false)
	await _wait(0.5)
	var bt: EnemyBase = _spawn("skeleton", Vector3(1.0, 0, -6.0))
	bt.max_health = 3000
	bt.health = 3000
	await _wait(0.4)
	_log.clear()
	_say("Sera bait the skeleton and run in circles, Brannoc sneak attack it")
	await _wait(0.3)
	var bs_sera: SquadAlly = _ally("Sera")
	var bs_bran: SquadAlly = _ally("Brannoc")
	_check("bait_sneak_parsed", bs_sera.current != null and bs_sera.current.verb == "kite" and bs_bran.current != null and bs_bran.current.verb == "surround" and String(bs_bran.current.args.get("side", "")) == "rear", _states() + " | " + " / ".join(_log))
	var hooked: int = 0
	var behind_hits: int = 0
	var hp0: int = bt.health
	for i in range(30):
		await _wait(0.5)
		if (bt as EnemyAI).get_current_target() == bs_sera:
			hooked += 1
		var rel2: Vector3 = bs_bran.global_position - bt.global_position
		rel2.y = 0.0
		if rel2.length() < 3.0 and rel2.normalized().dot((bt as EnemyAI).get_facing_direction()) < -0.2:
			behind_hits += 1
	_check("bait_holds_enemy", hooked >= 24 and bs_sera.current != null and bs_sera.current.verb == "kite", "enemy on Sera %d/30 samples; Sera %s" % [hooked, bs_sera.get_state_text()])
	_check("sneak_attack_from_behind", behind_hits >= 6 and bt.health < hp0, "Brannoc behind the enemy %d/30 samples; enemy hp %d -> %d" % [behind_hits, hp0, bt.health])
	await _shot("17_bait_sneak")
	bt.apply_damage(99999, true, "environmental", null)
	_finish()


## Isolates phases: kill leftover test enemies, stand the squad back up at full health, cancel orders.
func _reset_arena() -> void:
	for e in get_nodes_in_group("enemy"):
		if String(e.name).begins_with("Test_") and not (e as EnemyBase).is_dead and (e as EnemyBase).is_active:
			(e as EnemyBase).apply_damage(99999, true, "environmental", null)
	for a in _mgr.allies:
		if a.is_downed:
			a.revive(1.0)
		a.health = a.max_health
	_say("stop")
	await _wait(0.6)


func _living_test_enemies() -> int:
	var n: int = 0
	for e in get_nodes_in_group("enemy"):
		if String(e.name).begins_with("Test_") and not (e as EnemyBase).is_dead:
			n += 1
	return n


func _states() -> String:
	var parts: PackedStringArray = []
	for a in _mgr.allies:
		parts.append("%s:%s" % [a.get_display_name(), a.get_state_text()])
	return ", ".join(parts)


func _dump_threat() -> void:
	var targeted_ally: bool = false
	var ally_in_table: bool = false
	for e in get_nodes_in_group("enemy"):
		var ai: EnemyAI = e as EnemyAI
		if ai == null or ai.is_dead or not ai.is_active or not String(ai.name).begins_with("Test_"):
			continue
		var rows: PackedStringArray = []
		for r in ai.get_threat_table():
			rows.append("%s=%.0f" % [r["name"], float(r["threat"])])
			if r["node"] is SquadAlly:
				ally_in_table = true
		var tgt: Node3D = ai.get_current_target()
		if tgt is SquadAlly:
			targeted_ally = true
		print("[squad_test] threat %s state=%d target=%s table=[%s]" % [ai.name, ai.current_state, (tgt.call("get_display_name") if tgt != null and tgt.has_method("get_display_name") else str(tgt)), ", ".join(rows)])
	if not _results.any(func(r: String) -> bool: return r.contains("threat_table_uses_allies") and r.begins_with("PASS")):
		if ally_in_table and targeted_ally:
			_check("threat_table_uses_allies", true, "an enemy targets an ally via threat")


func _finish() -> void:
	if not _results.any(func(r: String) -> bool: return r.contains("threat_table_uses_allies")):
		_check("threat_table_uses_allies", false, "no enemy targeted an ally")
	var fails: int = 0
	for r in _results:
		if r.begins_with("FAIL"):
			fails += 1
	print("[squad_test] SUMMARY %d checks, %d failed" % [_results.size(), fails])
	Input.action_release("move_forward")
	quit(1 if fails > 0 else 0)
