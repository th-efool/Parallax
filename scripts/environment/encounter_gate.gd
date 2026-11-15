class_name EncounterGate
extends Node3D
## Stage connector gate present in both Reality and Mirror.
## Can be opened by an InteractSwitch, MechanismPuzzle, or automatically when EncounterDirector clears a linked encounter.

signal gate_opened(gate: EncounterGate)
signal gate_closed(gate: EncounterGate)

@export var starts_open: bool = false
@export var linked_encounter_id: String = ""
@export var section_id: int = 0
@export var gate_mesh_path: NodePath = NodePath("GateMesh")

var is_open: bool = false
var is_permanently_unlocked: bool = false


func _ready() -> void:
	add_to_group("encounter_gate")
	is_open = starts_open
	_apply_gate_state()

	if EncounterDirector.instance != null:
		if not EncounterDirector.instance.encounter_cleared.is_connected(_on_encounter_cleared):
			EncounterDirector.instance.encounter_cleared.connect(_on_encounter_cleared)
		if not EncounterDirector.instance.section_reset_requested.is_connected(_on_section_reset_requested):
			EncounterDirector.instance.section_reset_requested.connect(_on_section_reset_requested)


func open_gate(permanent: bool = true) -> void:
	if permanent:
		is_permanently_unlocked = true
	if is_open:
		return
	is_open = true
	_apply_gate_state()
	gate_opened.emit(self)


func close_gate() -> void:
	if is_permanently_unlocked or not is_open:
		return
	is_open = false
	_apply_gate_state()
	gate_closed.emit(self)


func seal_gate_for_encounter() -> void:
	if not is_open:
		return
	is_open = false
	_apply_gate_state()
	gate_closed.emit(self)


func unlock_and_open() -> void:
	open_gate(true)


func _on_encounter_cleared(encounter_id: String, _sec_id: int) -> void:
	if not linked_encounter_id.is_empty() and encounter_id == linked_encounter_id:
		open_gate(true)


func _on_section_reset_requested(reset_sec_id: int) -> void:
	if reset_sec_id == section_id and not is_permanently_unlocked:
		is_open = starts_open
		_apply_gate_state()


func _apply_gate_state() -> void:
	var mesh_node: Node3D = get_node_or_null(gate_mesh_path) as Node3D
	if mesh_node != null:
		mesh_node.visible = not is_open
	else:
		visible = not is_open

	_set_colliders_disabled_recursive(self, is_open)


func _set_colliders_disabled_recursive(node: Node, disable_collision: bool) -> void:
	if node is CollisionShape3D:
		var cs: CollisionShape3D = node as CollisionShape3D
		cs.disabled = disable_collision
		cs.set_deferred("disabled", disable_collision)
	elif node is CSGShape3D:
		var csg: CSGShape3D = node as CSGShape3D
		if not csg.has_meta("_orig_use_collision"):
			csg.set_meta("_orig_use_collision", csg.use_collision)
		if bool(csg.get_meta("_orig_use_collision")):
			csg.use_collision = not disable_collision
	for child in node.get_children():
		_set_colliders_disabled_recursive(child, disable_collision)
