class_name RealmReactive
extends Node
## Component or base node for any platform, prop, light, or actor that responds to Reality vs Mirror.
## Enforces the Golden Collision Rule: inactive realm objects disable CollisionShape3D, Area3D monitoring, and processing.

enum Affinity {
	REALITY_ONLY = 0,
	MIRROR_ONLY = 1,
	BOTH_STATEFUL = 2,
}

@export var realm_affinity: Affinity = Affinity.REALITY_ONLY
@export var target_node_path: NodePath = NodePath("..")
@export var manage_visibility: bool = true
@export var manage_collisions: bool = true
@export var manage_processing: bool = true

var is_active: bool = true
var is_permanently_repaired: bool = false


func _ready() -> void:
	add_to_group("realm_reactive")
	var rm: Node = _find_realm_manager()
	if rm != null:
		if not rm.is_connected("realm_changed", _on_manager_realm_changed):
			rm.connect("realm_changed", _on_manager_realm_changed)
		if not rm.is_connected("realms_merged", _on_manager_realms_merged):
			rm.connect("realms_merged", _on_manager_realms_merged)
		evaluate_for_realm(int(rm.get("current_realm")), bool(rm.get("is_merged")))
	else:
		evaluate_for_realm(0, false)


func get_target_node() -> Node:
	if not target_node_path.is_empty():
		var candidate: Node = get_node_or_null(target_node_path)
		if candidate != null and (get_tree() == null or candidate != get_tree().root):
			return candidate
	return self


func evaluate_for_realm(active_realm: int, realms_merged: bool = false) -> void:
	var should_be_active: bool = true
	if is_permanently_repaired or realms_merged or realm_affinity == Affinity.BOTH_STATEFUL:
		should_be_active = true
	elif realm_affinity == Affinity.REALITY_ONLY:
		should_be_active = (active_realm == 0)
	elif realm_affinity == Affinity.MIRROR_ONLY:
		should_be_active = (active_realm == 1)

	set_realm_active(should_be_active)
	on_realm_changed(active_realm)
	var target: Node = get_target_node()
	if target != self and target.has_method("on_realm_changed"):
		target.call("on_realm_changed", active_realm)


func set_realm_active(active: bool) -> void:
	is_active = active
	var target: Node = get_target_node()
	if target == null:
		return

	if manage_visibility and target is Node3D:
		(target as Node3D).visible = active

	if manage_collisions:
		_apply_collision_state_recursive(target, active)

	if manage_processing and target != self:
		target.set_physics_process(active)
		target.set_process(active)


func repair_for_reality() -> void:
	is_permanently_repaired = true
	set_realm_active(true)


func on_realm_changed(_active_realm: int) -> void:
	pass


func _on_manager_realm_changed(new_realm: int) -> void:
	var rm: Node = _find_realm_manager()
	var merged: bool = bool(rm.get("is_merged")) if rm != null else false
	evaluate_for_realm(new_realm, merged)


func _on_manager_realms_merged() -> void:
	evaluate_for_realm(0, true)


func _find_realm_manager() -> Node:
	if get_tree() != null:
		var rm: Node = get_tree().get_first_node_in_group("realm_manager")
		if rm != null:
			return rm
	return null


func _apply_collision_state_recursive(node: Node, active: bool) -> void:
	if node is CollisionShape3D:
		var shape: CollisionShape3D = node as CollisionShape3D
		shape.disabled = not active
		shape.set_deferred("disabled", not active)
	elif node is CSGShape3D:
		var csg: CSGShape3D = node as CSGShape3D
		if not csg.has_meta("_orig_use_collision"):
			csg.set_meta("_orig_use_collision", csg.use_collision)
		if bool(csg.get_meta("_orig_use_collision")):
			csg.use_collision = active
	elif node is Area3D:
		var area: Area3D = node as Area3D
		area.monitoring = active
		area.monitorable = active
		area.set_deferred("monitoring", active)
		area.set_deferred("monitorable", active)

	for child in node.get_children():
		if child != self and child is RealmReactive:
			continue
		_apply_collision_state_recursive(child, active)
