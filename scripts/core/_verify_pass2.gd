extends SceneTree

class MockEnemy:
	extends Node3D
	var hp: int = 100
	var last_damage: int = 0
	var last_is_heavy: bool = false
	var last_source: String = ""
	var hurtbox: Hurtbox3D

	func _init(start_hp: int = 100) -> void:
		hp = start_hp

	func _ready() -> void:
		add_to_group("enemy")

	func apply_damage(amount: int, is_heavy: bool = false, source_type: String = "") -> bool:
		hp -= amount
		last_damage = amount
		last_is_heavy = is_heavy
		last_source = source_type
		return true

var _step: int = 0
var _realm_mgr: RealmManager
var _director: EncounterDirector
var _player: PlayerController
var _sword_hitbox: Hitbox3D
var _player_hurtbox: Hurtbox3D
var _floor_body: StaticBody3D
var _died_signal_count: int = 0


func _fail(msg: String) -> void:
	printerr("PASS 2 VERIFY FAILED: ", msg)
	quit(1)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)


func _initialize() -> void:
	_realm_mgr = RealmManager.new()
	_realm_mgr.name = "RealmManager"
	_realm_mgr.handle_input_directly = false
	root.add_child(_realm_mgr)

	_director = EncounterDirector.new()
	_director.name = "EncounterDirector"
	root.add_child(_director)
	_director.set_checkpoint(EncounterDirector.Section.ENTRY, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 0.0)), 0)

	# Shared floor covering player test spot so is_on_floor() works naturally
	_floor_body = StaticBody3D.new()
	_floor_body.name = "TestFloor"
	_floor_body.collision_layer = RealmManager.LAYER_WORLD_SHARED
	_floor_body.position = Vector3(0.0, -0.5, 0.0)
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	floor_shape.shape = box
	_floor_body.add_child(floor_shape)
	root.add_child(_floor_body)

	# PlayerController with SwordHitbox & Hurtbox3D
	_player = PlayerController.new()
	_player.name = "Player"
	_player.position = Vector3(0.0, 0.05, 0.0)
	var p_col := CollisionShape3D.new()
	var p_cap := CapsuleShape3D.new()
	p_cap.radius = 0.38
	p_cap.height = 1.75
	p_col.shape = p_cap
	p_col.position = Vector3(0.0, 0.9, 0.0)
	_player.add_child(p_col)

	_sword_hitbox = Hitbox3D.new()
	_sword_hitbox.name = "SwordHitbox"
	_sword_hitbox.affects_enemies = true
	_sword_hitbox.affects_breakables = true
	_sword_hitbox.affects_player = false
	_player.add_child(_sword_hitbox)

	_player_hurtbox = Hurtbox3D.new()
	_player_hurtbox.name = "Hurtbox3D"
	_player_hurtbox.is_player_hurtbox = true
	_player_hurtbox.is_enemy_hurtbox = false
	_player.add_child(_player_hurtbox)

	_player.player_died.connect(func() -> void: _died_signal_count += 1)
	root.add_child(_player)
	_player.velocity.y = -5.0
	_player.move_and_slide()


func _physics_process(_delta: float) -> bool:
	_step += 1
	if _step < 3:
		if is_instance_valid(_player):
			_player.velocity.y = -5.0
			_player.move_and_slide()
		return false

	_run_tests()
	return true


func _run_tests() -> void:
	var run_state: ScoreManager = root.get_node_or_null("RunState") as ScoreManager
	_expect(run_state != null, "RunState missing")
	run_state.start_new_run()

	# --- Test 1: Hitbox3D & Hurtbox3D Deduplication & i-Frames ---
	var test_attacker := Node3D.new()
	root.add_child(test_attacker)
	var test_hitbox := Hitbox3D.new()
	test_hitbox.register_combo_on_enemy_hit = false
	test_attacker.add_child(test_hitbox)

	var dummy_enemy := MockEnemy.new(100)
	dummy_enemy.position = Vector3(100.0, 0.0, 0.0)
	var enemy_hb := Hurtbox3D.new()
	enemy_hb.is_enemy_hurtbox = true
	dummy_enemy.add_child(enemy_hb)
	root.add_child(dummy_enemy)

	test_hitbox.begin_swing(25, false, "player_light")
	_expect(test_hitbox.try_hit_target(enemy_hb), "First hit in swing must succeed")
	_expect(dummy_enemy.hp == 75, "Dummy enemy HP expected 75 got %d" % dummy_enemy.hp)
	_expect(not test_hitbox.try_hit_target(enemy_hb), "Second hit same target in same swing must be deduplicated")
	_expect(dummy_enemy.hp == 75, "HP must stay 75 after deduplicated hit")
	test_hitbox.end_swing()

	enemy_hb.is_invulnerable = true
	test_hitbox.begin_swing(25, false, "player_light")
	_expect(not test_hitbox.try_hit_target(enemy_hb), "Invulnerable hurtbox must block hit")
	test_hitbox.end_swing()
	dummy_enemy.queue_free()
	test_attacker.queue_free()

	# --- Test 2: PlayerController Combat, Dodge i-Frames, Landing Attack & Respawn ---
	_expect(_player.is_on_floor(), "Player must start grounded on TestFloor")
	_expect(not _player.start_landing_attack(), "Landing attack must fail while grounded")

	var expected_light_dmg: Array[int] = [25, 25, 35]
	for i in range(3):
		_expect(_player.start_light_attack(), "Light attack %d should start" % (i + 1))
		_expect(_sword_hitbox.damage == expected_light_dmg[i], "Light step %d damage expected %d got %d" % [i + 1, expected_light_dmg[i], _sword_hitbox.damage])
		_player._physics_process(0.50)
		_expect(_player.current_state == PlayerController.State.LOCOMOTION, "Player should return to LOCOMOTION after attack %d" % (i + 1))

	_expect(_player.start_dodge(Vector3.FORWARD), "Dodge should start from ground LOCOMOTION")
	_expect(_player.current_state == PlayerController.State.DODGE, "State must be DODGE")
	_player._physics_process(0.15)
	_expect(_player.is_invulnerable(), "Player must be invulnerable during dodge i-frame window")
	_expect(not _player.apply_damage(20), "Damage during dodge i-frames must be rejected")
	_expect(_player.health == 100, "Health should remain 100 during i-frames")
	_player._physics_process(0.45)
	_expect(_player.current_state == PlayerController.State.LOCOMOTION, "Player should exit DODGE after 0.55s")
	_expect(not _player.is_invulnerable(), "Player must not stay invulnerable after dodge")

	_expect(_player.apply_damage(100), "Lethal damage when vulnerable must apply")
	_expect(_died_signal_count == 1, "player_died signal should emit once")
	_expect(_player.health == 100, "Respawn via EncounterDirector must restore health to 100")
	_expect(_player.current_state == PlayerController.State.LOCOMOTION, "Respawn must restore LOCOMOTION state")

	# --- Test 3: BreakableProp (Cracked Central Pillar) ---
	var pillar := BreakableProp.new()
	pillar.prop_kind = BreakableProp.PropKind.CRACKED_PILLAR
	pillar.require_heavy_attack = true
	pillar.warning_duration = 0.60
	pillar.position = Vector3(0.0, 0.0, 20.0)
	root.add_child(pillar)

	var victim_enemy := MockEnemy.new(100)
	victim_enemy.position = Vector3(0.0, 0.0, 22.5)
	root.add_child(victim_enemy)

	_expect(not pillar.trigger_break(false), "Light attack must NOT break Cracked Pillar")
	_expect(pillar.current_state == BreakableProp.PropState.INTACT, "Pillar state must remain INTACT")
	_expect(pillar.trigger_break(true), "Heavy attack MUST trigger Cracked Pillar break")
	_expect(pillar.current_state == BreakableProp.PropState.BREAKING, "Pillar state must enter BREAKING")
	pillar._process(0.65)
	_expect(pillar.current_state == BreakableProp.PropState.BROKEN, "Pillar state must enter BROKEN after 0.6s warning")
	_expect(victim_enemy.hp == -50, "Pillar fall zone must deal 150 dmg to enemy (100 - 150 = -50, got %d)" % victim_enemy.hp)
	_expect(victim_enemy.last_source == "environmental", "Source should be 'environmental'")
	pillar.reset_prop()
	_expect(pillar.current_state == BreakableProp.PropState.INTACT, "reset_prop must restore INTACT")
	victim_enemy.queue_free()

	# --- Test 4: RealmPlatform + Weak Stone Support + Bridge Anchor Switch ---
	_realm_mgr.require_floor_support = false
	var bridge := RealmPlatform.new()
	bridge.name = "GalleryBridge"
	var real_geo := StaticBody3D.new()
	real_geo.name = "RealityGeometry"
	var real_shape := CollisionShape3D.new()
	real_shape.shape = BoxShape3D.new()
	real_geo.add_child(real_shape)
	bridge.add_child(real_geo)

	var mir_geo := StaticBody3D.new()
	mir_geo.name = "MirrorGeometry"
	var mir_shape := CollisionShape3D.new()
	mir_shape.shape = BoxShape3D.new()
	mir_geo.add_child(mir_shape)
	bridge.add_child(mir_geo)
	root.add_child(bridge)

	var blocker := BreakableProp.new()
	blocker.name = "WeakStoneSupport"
	blocker.prop_kind = BreakableProp.PropKind.WEAK_STONE_SUPPORT
	blocker.warning_duration = 0.0
	root.add_child(blocker)

	var anchor := InteractSwitch.new()
	anchor.name = "BridgeAnchorSwitch"
	anchor.switch_role = InteractSwitch.SwitchRole.BRIDGE_ANCHOR
	anchor.required_realm = RealmManager.Realm.MIRROR
	anchor.linked_platform_path = anchor.get_path_to(bridge)
	anchor.blocking_prop_path = anchor.get_path_to(blocker)
	root.add_child(anchor)

	_expect(not real_shape.disabled and mir_shape.disabled, "Initial REALITY: real enabled, mirror disabled")
	_realm_mgr.cooldown_timer = 0.0
	_expect(_realm_mgr.request_shift(), "Shift to MIRROR should succeed")
	_expect(real_shape.disabled and not mir_shape.disabled, "In MIRROR: real disabled, mirror enabled")

	_expect(not anchor.interact(), "Anchor interact must fail while Weak Stone Support is intact")
	_expect(blocker.trigger_break(true) and blocker.current_state == BreakableProp.PropState.BROKEN, "Weak Stone Support should break immediately with 0.0s warning")
	_expect(anchor.interact(), "Anchor interact should succeed once blocker is broken in MIRROR")
	_expect(bridge.is_permanently_repaired, "Bridge must be marked permanently repaired")

	_realm_mgr.cooldown_timer = 0.0
	_expect(_realm_mgr.request_shift(), "Shift back to REALITY should succeed")
	_expect(not real_shape.disabled and not mir_shape.disabled, "Repaired bridge must keep geometry active in REALITY too")

	# --- Test 5: MechanismPuzzle & EncounterGate ---
	var gate := EncounterGate.new()
	gate.name = "MechanismNorthGate"
	gate.starts_open = false
	var gate_mesh := Node3D.new()
	gate_mesh.name = "GateMesh"
	gate.add_child(gate_mesh)
	var gate_body := StaticBody3D.new()
	var gate_shape := CollisionShape3D.new()
	gate_shape.shape = BoxShape3D.new()
	gate_body.add_child(gate_shape)
	gate.add_child(gate_body)
	root.add_child(gate)
	_expect(not gate.is_open and not gate_shape.disabled, "Gate must start closed and blocking")

	var mechanism := MechanismPuzzle.new()
	mechanism.name = "MechanismChamberPuzzle"
	mechanism.position = Vector3(0.0, 0.0, 68.0)
	mechanism.require_mirror_realm = true
	var weight_node := Node3D.new()
	weight_node.name = "SuspendedWeight"
	mechanism.add_child(weight_node)
	root.add_child(mechanism)
	mechanism.linked_gate_path = mechanism.get_path_to(gate)

	_realm_mgr.force_realm(RealmManager.Realm.MIRROR, false)
	_expect(not mechanism.on_landing_slam_impact(60, "player_heavy"), "Heavy attack must not trigger MechanismPuzzle")

	_player.global_position = Vector3(0.0, 0.0, 68.0)
	_player.set_simulated_airborne(true)
	_expect(_player.start_landing_attack(), "Airborne landing attack must start when simulated airborne")
	var slam_hits: int = _player.complete_landing_slam([mechanism])
	_expect(slam_hits == 1, "Landing slam should hit MechanismPuzzle once (got %d)" % slam_hits)
	_expect(mechanism.is_solved and mechanism.is_plate_pressed, "MechanismPuzzle should be solved and plate depressed")
	_expect(gate.is_open and gate_shape.disabled, "EncounterGate must unlock & disable collider when Mechanism solves")

	print("PASS 2 VERIFICATION SUCCEEDED")
	quit(0)
