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
@export var linked_gate_path: NodePath
@export var weight_node_path: NodePath = NodePath("SuspendedWeight")
@export var plate_node_path: NodePath = NodePath("PressurePlate")
@export var dropped_local_position: Vector3 = Vector3(0.0, 0.2, 0.0)

var is_solved: bool = false
var is_plate_pressed: bool = false


func _ready() -> void:
	add_to_group("mechanism_target")


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
		weight_node.position = dropped_local_position
		for child in weight_node.get_children():
			if child is RealmReactive:
				(child as RealmReactive).repair_for_reality()

	weight_slammed.emit()
	pressure_plate_depressed.emit()

	var gate: Node = get_node_or_null(linked_gate_path)
	if gate != null and gate.has_method("unlock_and_open"):
		gate.call("unlock_and_open")

	mechanism_solved.emit()
	return true
