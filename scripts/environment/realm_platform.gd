class_name RealmPlatform
extends Node3D
## Swaps or toggles Reality vs Mirror visual meshes and StaticBody3D colliders for stepping stones and the Collapsed Gallery bridge.
## Supports `repair_for_reality()` so activating the Stage 03 Bridge Anchor permanently enables the bridge in both realms.

signal platform_repaired()

@export var reality_node_path: NodePath = NodePath("RealityGeometry")
@export var mirror_node_path: NodePath = NodePath("MirrorGeometry")
@export var repaired_node_path: NodePath = NodePath("RepairedGeometry")
@export var is_permanently_repaired: bool = false
@export var section_id: int = -1

var reality_node: Node = null
var mirror_node: Node = null
var repaired_node: Node = null


func _exit_tree() -> void:
	if EncounterDirector.instance != null and EncounterDirector.instance.section_reset_requested.is_connected(_on_section_reset_requested):
		EncounterDirector.instance.section_reset_requested.disconnect(_on_section_reset_requested)


func _ready() -> void:
	add_to_group("realm_reactive")
	reality_node = get_node_or_null(reality_node_path)
	mirror_node = get_node_or_null(mirror_node_path)
	repaired_node = get_node_or_null(repaired_node_path)

	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm != null:
		if not rm.realm_changed.is_connected(on_realm_changed):
			rm.realm_changed.connect(on_realm_changed)
		if not rm.realms_merged.is_connected(_on_realms_merged):
			rm.realms_merged.connect(_on_realms_merged)
		evaluate_for_realm(int(rm.current_realm), rm.is_merged)
	else:
		evaluate_for_realm(0, false)
	_connect_director()
	call_deferred("_connect_director")


func _connect_director() -> void:
	if EncounterDirector.instance != null and not EncounterDirector.instance.section_reset_requested.is_connected(_on_section_reset_requested):
		EncounterDirector.instance.section_reset_requested.connect(_on_section_reset_requested)


func _resolved_section_id() -> int:
	if section_id >= 0:
		return section_id
	var cur: Node = get_parent()
	while cur != null:
		var n: String = String(cur.name)
		if n.begins_with("Stage01"):
			return 0
		if n.begins_with("Stage02"):
			return 1
		if n.begins_with("Stage03"):
			return 2
		if n.begins_with("Stage04"):
			return 3
		if n.begins_with("Stage05"):
			return 4
		cur = cur.get_parent()
	return 2 if String(name).contains("Bridge") else -1


func reset_platform() -> void:
	is_permanently_repaired = false
	var cur_realm: int = int(RealmManager.instance.current_realm) if RealmManager.instance != null else 0
	var merged: bool = bool(RealmManager.instance.is_merged) if RealmManager.instance != null else false
	evaluate_for_realm(cur_realm, merged)


func _on_section_reset_requested(reset_sec_id: int) -> void:
	var resolved_id: int = _resolved_section_id()
	if resolved_id >= 0 and reset_sec_id == resolved_id:
		reset_platform()


func evaluate_for_realm(active_realm: int, realms_merged: bool = false) -> void:
	reality_node = get_node_or_null(reality_node_path) if reality_node == null else reality_node
	mirror_node = get_node_or_null(mirror_node_path) if mirror_node == null else mirror_node
	repaired_node = get_node_or_null(repaired_node_path) if repaired_node == null else repaired_node

	var reality_active: bool = is_permanently_repaired or realms_merged or (active_realm == 0)
	var mirror_active: bool = is_permanently_repaired or realms_merged or (active_realm == 1)

	if reality_node != null:
		_set_subtree_active(reality_node, reality_active)
	if mirror_node != null:
		# Once a RepairedGeometry span exists and is active it fully replaces the spectral one (it collides in
		# both realms), so the spectral copy is retired instead of overlapping it (coplanar z-fighting).
		var superseded: bool = is_permanently_repaired and repaired_node != null
		_set_subtree_active(mirror_node, mirror_active and not superseded)
	if repaired_node != null:
		_set_subtree_active(repaired_node, is_permanently_repaired)


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
