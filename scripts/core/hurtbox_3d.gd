class_name Hurtbox3D
extends Area3D
## Standardized damage receiver component attached to Player, Enemies, Breakables, or Mechanism targets.

signal hit_received(amount: int, is_heavy: bool, source_type: String, attacker: Node)
signal hit_blocked_invulnerable(attacker: Node)

@export var owner_actor_path: NodePath = NodePath("..")
@export var is_player_hurtbox: bool = false
@export var is_enemy_hurtbox: bool = true
@export var is_breakable_hurtbox: bool = false

var is_invulnerable: bool = false


func _ready() -> void:
	add_to_group("hurtbox")


func get_owner_actor() -> Node:
	if not owner_actor_path.is_empty():
		var node: Node = get_node_or_null(owner_actor_path)
		if node != null and (get_tree() == null or node != get_tree().root):
			return node
	return get_parent() if get_parent() != null else self


func receive_hit(amount: int, is_heavy: bool, source_type: String, attacker: Node = null) -> bool:
	if is_invulnerable or not monitorable:
		hit_blocked_invulnerable.emit(attacker)
		return false

	var actor: Node = get_owner_actor()
	if actor == null:
		return false

	var accepted: bool = false

	if source_type == "player_landing" and actor.has_method("on_landing_slam_impact"):
		accepted = bool(actor.call("on_landing_slam_impact", amount, source_type))
	elif is_breakable_hurtbox or actor.has_method("trigger_break"):
		accepted = bool(actor.call("trigger_break", is_heavy, attacker))
	elif is_player_hurtbox:
		if actor.has_method("apply_damage"):
			var res: Variant = actor.call("apply_damage", amount, attacker)
			accepted = bool(res) if typeof(res) == TYPE_BOOL else true
	elif is_enemy_hurtbox or actor.is_in_group("enemy"):
		if actor.has_method("apply_damage"):
			var res: Variant = actor.call("apply_damage", amount, is_heavy, source_type, attacker)
			accepted = bool(res) if typeof(res) == TYPE_BOOL else true
	elif actor.has_method("apply_damage"):
		var res: Variant = actor.call("apply_damage", amount, is_heavy, source_type)
		accepted = bool(res) if typeof(res) == TYPE_BOOL else true

	if accepted:
		hit_received.emit(amount, is_heavy, source_type, attacker)
	return accepted
