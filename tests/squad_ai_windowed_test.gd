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
	create_timer(240.0).timeout.connect(func() -> void:
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
	_check("take_aggro_pulls_off_player", pulled >= 1, "pulled %d" % pulled)
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
