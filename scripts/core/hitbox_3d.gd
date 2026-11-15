class_name Hitbox3D
extends Area3D
## Standardized attack hitbox component (Layer 7: Hitbox).
## Enforces the GDD Hitbox Contract: tracks `hit_targets_this_swing` so each swing or shockwave damages a target at most once.

enum AttackType {
	LIGHT = 0,
	HEAVY = 1,
	LANDING = 2,
	HAZARD = 3,
	ENEMY_MELEE = 4,
	ENEMY_LUNGE = 5,
	ENEMY_BASH = 6,
	BOSS_CLEAVE = 7,
	BOSS_LUNGE = 8,
}

signal hit_landed(target: Node, damage_dealt: int, is_heavy_hit: bool, source_type: String)

@export var damage: int = 25
@export var attack_type: AttackType = AttackType.LIGHT
@export var is_heavy: bool = false
@export var source_type: String = "player_light"
@export var owner_actor_path: NodePath = NodePath("..")
@export var affects_player: bool = false
@export var affects_enemies: bool = true
@export var affects_breakables: bool = true
@export var register_combo_on_enemy_hit: bool = true

var hit_targets_this_swing: Array[Node] = []
var is_swing_active: bool = false


func _ready() -> void:
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	set_swing_shapes_enabled(is_swing_active)


func get_owner_actor() -> Node:
	if not owner_actor_path.is_empty():
		var node: Node = get_node_or_null(owner_actor_path)
		if node != null and (get_tree() == null or node != get_tree().root):
			return node
	return get_parent() if get_parent() != null else self


func begin_swing(custom_damage: int = -1, heavy: bool = false, custom_source_type: String = "") -> void:
	hit_targets_this_swing.clear()
	if custom_damage >= 0:
		damage = custom_damage
	is_heavy = heavy
	if not custom_source_type.is_empty():
		source_type = custom_source_type
	is_swing_active = true
	monitoring = true
	set_swing_shapes_enabled(true)


func end_swing() -> void:
	is_swing_active = false
	monitoring = false
	set_swing_shapes_enabled(false)
	hit_targets_this_swing.clear()


func try_hit_target(candidate: Node) -> bool:
	if not is_swing_active or candidate == null:
		return false

	var my_owner: Node = get_owner_actor()
	var logical_target: Node = candidate
	var hurtbox: Hurtbox3D = candidate as Hurtbox3D
	if hurtbox != null:
		logical_target = hurtbox.get_owner_actor()

	if logical_target == null or logical_target == my_owner or logical_target == self:
		return false
	if hit_targets_this_swing.has(logical_target):
		return false

	# Filter target category
	var is_target_player: bool = (hurtbox != null and hurtbox.is_player_hurtbox) or logical_target.is_in_group("player")
	var is_target_breakable: bool = (hurtbox != null and hurtbox.is_breakable_hurtbox) or logical_target.has_method("trigger_break") or logical_target.has_method("on_landing_slam_impact")
	var is_target_enemy: bool = (hurtbox != null and hurtbox.is_enemy_hurtbox) or logical_target.is_in_group("enemy")

	if is_target_player and not affects_player:
		return false
	if is_target_breakable and not affects_breakables:
		return false
	if is_target_enemy and not affects_enemies:
		return false

	var hit_accepted: bool = false
	if hurtbox != null:
		hit_accepted = hurtbox.receive_hit(damage, is_heavy, source_type, my_owner)
	elif source_type == "player_landing" and logical_target.has_method("on_landing_slam_impact"):
		hit_accepted = bool(logical_target.call("on_landing_slam_impact", damage, source_type))
	elif logical_target.has_method("trigger_break"):
		hit_accepted = bool(logical_target.call("trigger_break", is_heavy))
	elif is_target_player and logical_target.has_method("apply_damage"):
		var res_p: Variant = logical_target.call("apply_damage", damage, my_owner)
		hit_accepted = bool(res_p) if typeof(res_p) == TYPE_BOOL else true
	elif logical_target.has_method("apply_damage"):
		var res_e: Variant = logical_target.call("apply_damage", damage, is_heavy, source_type)
		hit_accepted = bool(res_e) if typeof(res_e) == TYPE_BOOL else true

	if not hit_accepted:
		return false

	hit_targets_this_swing.append(logical_target)

	if register_combo_on_enemy_hit and is_target_enemy and (source_type == "player_light" or source_type == "player_heavy"):
		var run_state: Node = _get_run_state()
		if run_state != null and run_state.has_method("register_hit"):
			run_state.call("register_hit")

	hit_landed.emit(logical_target, damage, is_heavy, source_type)
	return true


func pulse_radial_targets(center: Vector3, radius: float, candidates: Array[Node], pulse_damage: int = -1, heavy: bool = true, pulse_source: String = "player_landing") -> int:
	begin_swing(pulse_damage, heavy, pulse_source)
	var hits: int = 0
	for node in candidates:
		if not is_instance_valid(node):
			continue
		var node3d: Node3D = node as Node3D
		if node3d != null and node3d.global_position.distance_to(center) <= radius:
			if try_hit_target(node):
				hits += 1
	end_swing()
	return hits


func set_swing_shapes_enabled(enabled: bool) -> void:
	for child in get_children():
		if child is CollisionShape3D:
			var cs: CollisionShape3D = child as CollisionShape3D
			cs.disabled = not enabled
			cs.set_deferred("disabled", not enabled)


func _on_area_entered(area: Area3D) -> void:
	try_hit_target(area)


func _on_body_entered(body: Node3D) -> void:
	try_hit_target(body)


func _get_run_state() -> Node:
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		return get_tree().root.get_node_or_null("RunState")
	return null
