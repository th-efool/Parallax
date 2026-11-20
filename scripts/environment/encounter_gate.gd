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
## Cosmetic: the portcullis rises when opening and slams down when sealing. Colliders still switch
## instantly, so gameplay timing is identical to the instant greybox gate.
@export var animate_gate: bool = true
@export var lift_height: float = 3.4
@export var open_duration: float = 0.7
@export var close_duration: float = 0.28

var is_open: bool = false
var is_permanently_unlocked: bool = false
var _mesh_rest_y: float = 0.0
var _ready_msec: int = 0
var _gate_tween: Tween = null


func _ready() -> void:
	add_to_group("encounter_gate")
	var mesh_node: Node3D = get_node_or_null(gate_mesh_path) as Node3D
	if mesh_node != null:
		_mesh_rest_y = mesh_node.position.y
	is_open = starts_open
	_apply_gate_state()
	_ready_msec = Time.get_ticks_msec()

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
	if reset_sec_id == section_id:
		is_permanently_unlocked = false
		is_open = starts_open
		_apply_gate_state()


func _apply_gate_state() -> void:
	var mesh_node: Node3D = get_node_or_null(gate_mesh_path) as Node3D
	if mesh_node != null:
		_animate_mesh(mesh_node)
	else:
		visible = not is_open

	_set_colliders_disabled_recursive(self, is_open)


func _animate_mesh(mesh_node: Node3D) -> void:
	if _gate_tween != null and _gate_tween.is_valid():
		_gate_tween.kill()
	# Snap (no animation) during scene setup / save restore, or when disabled.
	var can_animate: bool = animate_gate and is_inside_tree() and _ready_msec > 0 and Time.get_ticks_msec() - _ready_msec > 250
	if not can_animate:
		mesh_node.visible = not is_open
		mesh_node.position.y = _mesh_rest_y
		return
	mesh_node.visible = true
	_gate_tween = create_tween()
	if is_open:
		_gate_tween.tween_property(mesh_node, "position:y", _mesh_rest_y + lift_height, open_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_gate_tween.tween_callback(func() -> void:
			if is_instance_valid(mesh_node) and is_open:
				mesh_node.visible = false
				mesh_node.position.y = _mesh_rest_y)
	else:
		mesh_node.position.y = _mesh_rest_y + lift_height
		_gate_tween.tween_property(mesh_node, "position:y", _mesh_rest_y, close_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


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
