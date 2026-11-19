extends SceneTree
## Headless checks for guide 02: HP x2.5, Warden execution immunity / hit cap / fall safety / phase threshold,
## Phantom Mirror-only rules. Run: godot --headless --path . -s res://tests/combat_rules_test.gd
var _results: Array[String] = []
var _main: Node = null

func _initialize() -> void:
	SquadAIConfig.force_offline()
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	_run()

func _check(n: String, ok: bool, d: String = "") -> void:
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", n, d]
	_results.append(line)
	print("[combat] ", line)

func _run() -> void:
	for _i in range(5):
		await process_frame
	_main.call("start_run_now")
	var t0: int = Time.get_ticks_msec()
	while not bool(_main.get("level_ready")) and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	var level: Node = _main.get_node("LevelRoot")
	# HP x3.25: a fresh skeleton (authored 100) has 325.
	var sk: EnemyBase = level.call("_add_roamer", level, "skeleton", "Test_hp", Vector3(0, 0, -10), EncounterDirector.Section.ENTRY, Vector3(0, 0, -14)) as EnemyBase
	await process_frame
	_check("hp_scaled", sk != null and sk.max_health == 325 and sk.health == 325, "max=%d" % (sk.max_health if sk != null else -1))
	# Warden rules.
	var w: WardenBoss = level.get_node_or_null("Stage05_ExecutionArena/Enemies/TheWarden") as WardenBoss
	_check("warden_found", w != null)
	if w != null:
		_check("warden_hp_scaled", w.max_health == 1500, "max=%d" % w.max_health)
		_check("warden_execute_immune", w.execute_immune)
		_check("warden_phase_threshold", w._phase2_threshold() == 999 or w._phase2_threshold() == 1000, str(w._phase2_threshold()))
		w.set_section_enabled(true)
		w.current_phase = WardenBoss.Phase.PHASE_2_MERGED
		var hp0: int = w.health
		w.apply_damage(999, true, "player_heavy", null)
		_check("warden_phase2_hit_cap", hp0 - w.health == 120, "took %d" % (hp0 - w.health))
		w.global_position = w.get_home_position() + Vector3(0, -12, 0)
		w.step_ai(0.016)
		_check("warden_fall_snaps_home", w.global_position.distance_to(w.get_home_position()) < 0.5 and not w.is_dead)
	# Phantom: immune in Reality, hittable in Mirror.
	var ph: EnemyBase = level.call("_add_roamer", level, "phantom", "Test_ph", Vector3(2, 0, -10), EncounterDirector.Section.ENTRY, Vector3(0, 0, -14)) as EnemyBase
	await process_frame
	if ph != null:
		RealmManager.instance.force_realm(RealmManager.Realm.REALITY, false)
		await process_frame
		var h1: int = ph.health
		var acc_r: bool = ph.apply_damage(30, false, "player_light", null)
		_check("phantom_immune_in_reality", not acc_r and ph.health == h1 and not ph.is_hittable_now())
		_check("phantom_harmless_in_reality", not bool(ph.call("can_damage_target", get_first_node_in_group("player"))))
		RealmManager.instance.force_realm(RealmManager.Realm.MIRROR, false)
		await process_frame
		var acc_m: bool = ph.apply_damage(30, false, "player_light", null)
		_check("phantom_hurt_in_mirror", acc_m and ph.health < h1 and ph.is_hittable_now())
		RealmManager.instance.force_realm(RealmManager.Realm.REALITY, false)
	else:
		_check("phantom_spawned", false)
	var fails: int = _results.filter(func(r: String) -> bool: return r.begins_with("FAIL")).size()
	print("[combat] SUMMARY %d checks, %d failed" % [_results.size(), fails])
	quit(1 if fails > 0 else 0)
