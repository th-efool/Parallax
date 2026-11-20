class_name MechanismPuzzle
extends Node3D
## Stage 04 Mechanism Chamber puzzle controller:
## A suspended Mirror Weight hovering above a Reality Pressure Plate.
## Striking the weight with an airborne Landing Attack (`F`, `source_type == "player_landing"`) while in Mirror
## slams the weight onto the pressure plate and opens the Stage 04 North Gate in both realms.

signal weight_slammed()
signal pressure_plate_depressed()
signal mechanism_solved()

@export var require_mirror_realm: bool = true
@export var section_id: int = 3
@export var linked_gate_path: NodePath
@export var weight_node_path: NodePath = NodePath("SuspendedWeight")
@export var plate_node_path: NodePath = NodePath("PressurePlate")
@export var dropped_local_position: Vector3 = Vector3(0.0, 0.2, 0.0)

var is_solved: bool = false
var is_plate_pressed: bool = false
var _initial_weight_position: Vector3 = Vector3(0.0, 2.5, 0.0)
var _drop_tween: Tween = null


func _exit_tree() -> void:
	if EncounterDirector.instance != null and EncounterDirector.instance.section_reset_requested.is_connected(_on_section_reset_requested):
		EncounterDirector.instance.section_reset_requested.disconnect(_on_section_reset_requested)


func _ready() -> void:
	add_to_group("mechanism_target")
	add_to_group("realm_reactive")
	var weight_node: Node3D = get_node_or_null(weight_node_path) as Node3D
	if weight_node != null:
		_initial_weight_position = weight_node.position

	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm != null:
		if not rm.realm_changed.is_connected(_on_realm_changed):
			rm.realm_changed.connect(_on_realm_changed)
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


func _on_section_reset_requested(reset_sec_id: int) -> void:
	if reset_sec_id == section_id:
		reset_puzzle()


func evaluate_for_realm(active_realm: int, realms_merged: bool = false) -> void:
	var weight_node: Node3D = get_node_or_null(weight_node_path) as Node3D
	if weight_node == null:
		return
	var should_show_weight: bool = is_solved or realms_merged or (active_realm == 1)
	weight_node.visible = should_show_weight
	for child in weight_node.get_children():
		if child is Hurtbox3D:
			var hb: Hurtbox3D = child as Hurtbox3D
			var can_hit: bool = (not is_solved) and should_show_weight
			hb.is_invulnerable = not can_hit
			hb.set_deferred("monitorable", can_hit)  # may run inside a physics signal flush
			hb.set_deferred("monitorable", can_hit)


func reset_puzzle() -> void:
	is_solved = false
	is_plate_pressed = false
	if _drop_tween != null and _drop_tween.is_valid():
		_drop_tween.kill()
	var weight_node: Node3D = get_node_or_null(weight_node_path) as Node3D
	if weight_node != null:
		weight_node.position = _initial_weight_position
	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm != null:
		evaluate_for_realm(int(rm.current_realm), rm.is_merged)
	else:
		evaluate_for_realm(0, false)


func on_landing_slam_impact(_damage: int = 60, source_type: String = "player_landing") -> bool:
	if is_solved:
		return false
	if source_type != "player_landing":
		return false

	if require_mirror_realm and RealmManager.instance != null and not RealmManager.instance.is_merged:
		if RealmManager.instance.current_realm != RealmManager.Realm.MIRROR:
			return false

	is_solved = true
	is_plate_pressed = true

	var weight_node: Node3D = get_node_or_null(weight_node_path) as Node3D
	if weight_node != null:
		if is_inside_tree():
			# Cosmetic gravity drop onto the plate (logic already resolved above / below).
			_drop_tween = create_tween()
			_drop_tween.tween_property(weight_node, "position", dropped_local_position, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		else:
			weight_node.position = dropped_local_position
		for child in weight_node.get_children():
			if child is RealmReactive:
				(child as RealmReactive).repair_for_reality()

	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm != null:
		evaluate_for_realm(int(rm.current_realm), rm.is_merged)
	else:
		evaluate_for_realm(0, false)

	weight_slammed.emit()
	pressure_plate_depressed.emit()

	var gate: Node = get_node_or_null(linked_gate_path)
	if gate != null and gate.has_method("unlock_and_open"):
		gate.call("unlock_and_open")

	mechanism_solved.emit()
	return true


## Resolves the puzzle and opens its gate if the player snuck past Gate04 without solving it.
func force_solve_bypass() -> void:
	if is_solved:
		return
	is_solved = true
	is_plate_pressed = true
	var weight_node: Node3D = get_node_or_null(weight_node_path) as Node3D
	if weight_node != null:
		weight_node.position = dropped_local_position
		for child in weight_node.get_children():
			if child is RealmReactive:
				(child as RealmReactive).repair_for_reality()
	var rm: RealmManager = RealmManager.instance as RealmManager
	evaluate_for_realm(int(rm.current_realm) if rm != null else 0, rm.is_merged if rm != null else false)
	var gate: Node = get_node_or_null(linked_gate_path)
	if gate != null and gate.has_method("unlock_and_open"):
		gate.call("unlock_and_open")
	mechanism_solved.emit()


func _on_realm_changed(new_realm: int) -> void:
	var merged: bool = bool(RealmManager.instance.is_merged) if RealmManager.instance != null else false
	evaluate_for_realm(new_realm, merged)


func _on_realms_merged() -> void:
	evaluate_for_realm(0, true)
