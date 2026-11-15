class_name RealmPlatform
extends Node3D
## Swaps or toggles Reality vs Mirror visual meshes and StaticBody3D colliders for stepping stones and the Collapsed Gallery bridge.
## Supports `repair_for_reality()` so activating the Stage 03 Bridge Anchor permanently enables the bridge in both realms.

signal platform_repaired()

@export var reality_node_path: NodePath = NodePath("RealityGeometry")
@export var mirror_node_path: NodePath = NodePath("MirrorGeometry")
@export var is_permanently_repaired: bool = false

var reality_node: Node = null
var mirror_node: Node = null


func _ready() -> void:
	add_to_group("realm_reactive")
	reality_node = get_node_or_null(reality_node_path)
	mirror_node = get_node_or_null(mirror_node_path)

	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm != null:
		if not rm.realm_changed.is_connected(on_realm_changed):
			rm.realm_changed.connect(on_realm_changed)
		if not rm.realms_merged.is_connected(_on_realms_merged):
			rm.realms_merged.connect(_on_realms_merged)
		evaluate_for_realm(int(rm.current_realm), rm.is_merged)
	else:
		evaluate_for_realm(0, false)


func evaluate_for_realm(active_realm: int, realms_merged: bool = false) -> void:
	reality_node = get_node_or_null(reality_node_path) if reality_node == null else reality_node
	mirror_node = get_node_or_null(mirror_node_path) if mirror_node == null else mirror_node

	var reality_active: bool = is_permanently_repaired or realms_merged or (active_realm == 0)
	var mirror_active: bool = is_permanently_repaired or realms_merged or (active_realm == 1)

	if reality_node != null:
		_set_subtree_active(reality_node, reality_active)
	if mirror_node != null:
		_set_subtree_active(mirror_node, mirror_active)


func on_realm_changed(active_realm: int) -> void:
	var merged: bool = bool(RealmManager.instance.is_merged) if RealmManager.instance != null else false
	evaluate_for_realm(active_realm, merged)


func repair_for_reality() -> void:
	if is_permanently_repaired:
		return
	is_permanently_repaired = true
	var cur_realm: int = int(RealmManager.instance.current_realm) if RealmManager.instance != null else 0
	var merged: bool = bool(RealmManager.instance.is_merged) if RealmManager.instance != null else false
	evaluate_for_realm(cur_realm, merged)
	platform_repaired.emit()


func _on_realms_merged() -> void:
	evaluate_for_realm(0, true)


func _set_subtree_active(node: Node, active: bool) -> void:
	if node is Node3D:
		(node as Node3D).visible = active
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
	for child in node.get_children():
		_set_subtree_active(child, active)
