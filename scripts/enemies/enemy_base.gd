class_name EnemyBase
extends CharacterBody3D
## Shared base class for all PARALLAX enemies (Skeleton Guard, Phantom Twin, Shielded Guard, The Warden).
## Enforces the Golden Collision Rule: when realm-inactive or section-disabled, disables colliders, hurtbox, hitbox, and AI processing.

signal health_changed(current_hp: int, max_hp: int)
signal damaged(amount: int, is_heavy: bool, source_type: String)
signal staggered(duration: float)
signal died(enemy: EnemyBase, kill_context: Dictionary)
signal realm_activity_changed(active: bool)

@export_group("Identity & Realm")
@export var enemy_id: String = ""
@export var section_id: int = 1
@export var encounter_id: String = "hall_of_echoes"
@export var realm_affinity: RealmReactive.Affinity = RealmReactive.Affinity.REALITY_ONLY
@export var award_standard_kill_score: bool = true

@export_group("Stats")
@export var max_health: int = 100
@export var heavy_attack_staggers: bool = true

@export_group("Node Paths")
@export var hurtbox_path: NodePath = NodePath("Hurtbox3D")
@export var attack_hitbox_path: NodePath = NodePath("AttackHitbox")
@export var visual_root_path: NodePath = NodePath("VisualRoot")

var health: int = 100
var is_active: bool = true
var is_section_enabled: bool = true
var is_realm_enabled: bool = true
var is_dead: bool = false
var facing_direction: Vector3 = Vector3.FORWARD
var _last_attacker: Node = null
var _spawn_transform: Transform3D = Transform3D.IDENTITY


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("realm_reactive")
	_spawn_transform = global_transform
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 0.001:
		facing_direction = fwd.normalized()
	health = max_health

	if EncounterDirector.instance != null:
		EncounterDirector.instance.register_section_enemy(section_id as EncounterDirector.Section, self)
		if not EncounterDirector.instance.section_reset_requested.is_connected(_on_section_reset_requested):
			EncounterDirector.instance.section_reset_requested.connect(_on_section_reset_requested)

	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm != null:
		if not rm.realm_changed.is_connected(_on_manager_realm_changed):
			rm.realm_changed.connect(_on_manager_realm_changed)
		if not rm.realms_merged.is_connected(_on_manager_realms_merged):
			rm.realms_merged.connect(_on_manager_realms_merged)
		evaluate_for_realm(int(rm.current_realm), rm.is_merged)
	else:
		evaluate_for_realm(0, false)


func get_enemy_unique_id() -> String:
	if not enemy_id.is_empty():
		return enemy_id
	return "%s_%d" % [name, get_instance_id()]


func set_section_enabled(enabled: bool) -> void:
	is_section_enabled = enabled
	_refresh_active_state()


func evaluate_for_realm(active_realm: int, realms_merged: bool = false) -> void:
	if realms_merged or realm_affinity == RealmReactive.Affinity.BOTH_STATEFUL:
		is_realm_enabled = true
	elif realm_affinity == RealmReactive.Affinity.REALITY_ONLY:
		is_realm_enabled = (active_realm == 0)
	elif realm_affinity == RealmReactive.Affinity.MIRROR_ONLY:
		is_realm_enabled = (active_realm == 1)

	_refresh_active_state()
	on_realm_changed(active_realm)


func set_realm_active(active: bool) -> void:
	is_realm_enabled = active
	_refresh_active_state()


func on_realm_changed(_active_realm: int) -> void:
	pass


func get_facing_direction() -> Vector3:
	if facing_direction.length_squared() > 0.001:
		return facing_direction.normalized()
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	return fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD


func set_facing_direction(dir: Vector3) -> void:
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() <= 0.0001:
		return
	facing_direction = flat.normalized()
	var vis_root: Node3D = get_node_or_null(visual_root_path) as Node3D
	var target_yaw: float = atan2(-facing_direction.x, -facing_direction.z)
	if vis_root != null:
		vis_root.rotation.y = target_yaw
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null and hb.get_parent() == self:
		hb.rotation.y = target_yaw


func apply_damage(amount: int, is_heavy: bool = false, source_type: String = "", attacker: Node = null) -> bool:
	if is_dead or not is_active or amount <= 0:
		return false

	_last_attacker = attacker
	var final_damage: int = _modify_incoming_damage(amount, is_heavy, source_type)
	if final_damage <= 0:
		return false

	health = maxi(0, health - final_damage)
	damaged.emit(final_damage, is_heavy, source_type)
	health_changed.emit(health, max_health)

	_on_damage_taken(final_damage, is_heavy, source_type)

	if health <= 0:
		_die(source_type)
	elif is_heavy and _should_stagger_on_hit(is_heavy, source_type):
		_on_stagger_triggered()

	return true


func reset_enemy() -> void:
	is_dead = false
	health = max_health
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	_last_attacker = null
	var fwd: Vector3 = -_spawn_transform.basis.z
	fwd.y = 0.0
	facing_direction = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	_on_enemy_reset()
	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm != null:
		evaluate_for_realm(int(rm.current_realm), rm.is_merged)
	else:
		evaluate_for_realm(0, false)
	health_changed.emit(health, max_health)


func get_hurtbox() -> Hurtbox3D:
	return get_node_or_null(hurtbox_path) as Hurtbox3D


func get_attack_hitbox() -> Hitbox3D:
	return get_node_or_null(attack_hitbox_path) as Hitbox3D


func _modify_incoming_damage(amount: int, _is_heavy: bool, _source_type: String) -> int:
	return amount


func _should_stagger_on_hit(is_heavy: bool, _source_type: String) -> bool:
	return heavy_attack_staggers and is_heavy


func _on_damage_taken(_final_damage: int, _is_heavy: bool, _source_type: String) -> void:
	pass


func _on_stagger_triggered() -> void:
	pass


func _on_enemy_reset() -> void:
	pass


func _die(source_type: String) -> void:
	if is_dead:
		return
	is_dead = true

	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.end_swing()

	var in_mirror: bool = false
	if RealmManager.instance != null and not RealmManager.instance.is_merged:
		in_mirror = (RealmManager.instance.current_realm == RealmManager.Realm.MIRROR)
	var is_env: bool = (source_type == "environmental")

	if award_standard_kill_score:
		var run_state: Node = _get_run_state()
		if run_state != null and run_state.has_method("record_enemy_kill"):
			run_state.call("record_enemy_kill", get_enemy_unique_id(), in_mirror, is_env)

	if not encounter_id.is_empty() and EncounterDirector.instance != null:
		EncounterDirector.instance.register_enemy_kill(encounter_id)

	_refresh_active_state()
	var context: Dictionary = {
		"enemy_id": get_enemy_unique_id(),
		"in_mirror": in_mirror,
		"is_environmental": is_env,
		"source_type": source_type,
	}
	died.emit(self, context)


func _refresh_active_state() -> void:
	var should_be_active: bool = is_section_enabled and is_realm_enabled and not is_dead
	is_active = should_be_active

	visible = should_be_active
	var vis_root: Node3D = get_node_or_null(visual_root_path) as Node3D
	if vis_root != null:
		vis_root.visible = should_be_active

	set_physics_process(should_be_active)
	set_process(should_be_active)

	for child in get_children():
		if child is CollisionShape3D:
			var cs: CollisionShape3D = child as CollisionShape3D
			cs.disabled = not should_be_active
			cs.set_deferred("disabled", not should_be_active)

	var hurtbox: Hurtbox3D = get_hurtbox()
	if hurtbox != null:
		hurtbox.is_invulnerable = not should_be_active
		hurtbox.monitorable = should_be_active
		hurtbox.set_deferred("monitorable", should_be_active)

	if not should_be_active:
		var hitbox: Hitbox3D = get_attack_hitbox()
		if hitbox != null:
			hitbox.end_swing()

	realm_activity_changed.emit(should_be_active)


func _on_manager_realm_changed(new_realm: int) -> void:
	var merged: bool = bool(RealmManager.instance.is_merged) if RealmManager.instance != null else false
	evaluate_for_realm(new_realm, merged)


func _on_manager_realms_merged() -> void:
	evaluate_for_realm(0, true)


func _on_section_reset_requested(reset_sec_id: int) -> void:
	if reset_sec_id == section_id:
		reset_enemy()


func _get_run_state() -> Node:
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		return get_tree().root.get_node_or_null("RunState")
	return null
