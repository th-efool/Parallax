class_name SectionTriggerVolume
extends Area3D
## Stage entry trigger volume that advances `EncounterDirector` to `target_section`,
## updates the player's respawn checkpoint, optionally seals the rear entry gate, and starts the room's combat encounter.

signal section_triggered(section_id: int, encounter_id: String)

@export var target_section: int = 0
@export var checkpoint_spawn_position: Vector3 = Vector3.ZERO
@export var save_checkpoint_on_enter: bool = true
@export var encounter_id: String = ""
@export var encounter_enemy_count: int = 0
@export var entry_gate_to_seal_path: NodePath
@export var reopen_entry_gate_on_clear: bool = true
@export var complete_run_on_enter: bool = false
@export var half_extents: Vector3 = Vector3(4.0, 2.5, 1.5)
@export var check_position_bounds_each_frame: bool = true

var has_triggered: bool = false


func _ready() -> void:
	add_to_group("section_trigger")
	collision_layer = 0
	collision_mask = RealmManager.LAYER_PLAYER
	monitoring = true
	monitorable = false
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	if EncounterDirector.instance != null:
		if not EncounterDirector.instance.encounter_cleared.is_connected(_on_encounter_cleared):
			EncounterDirector.instance.encounter_cleared.connect(_on_encounter_cleared)
		if not EncounterDirector.instance.section_reset_requested.is_connected(_on_section_reset_requested):
			EncounterDirector.instance.section_reset_requested.connect(_on_section_reset_requested)


func _physics_process(_delta: float) -> void:
	if has_triggered or not check_position_bounds_each_frame or get_tree() == null:
		return
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and p is Node3D:
			if is_point_inside_trigger((p as Node3D).global_position):
				trigger_for_player(p)
				return


func is_point_inside_trigger(world_pos: Vector3) -> bool:
	var local_delta: Vector3 = world_pos - global_position
	return (
		absf(local_delta.x) <= half_extents.x
		and absf(local_delta.y) <= half_extents.y
		and absf(local_delta.z) <= half_extents.z
	)


func trigger_for_player(player: Node = null) -> bool:
	if has_triggered:
		return false
	if player != null and not player.is_in_group("player") and not (player is PlayerController):
		return false

	has_triggered = true
	var ed: EncounterDirector = EncounterDirector.instance as EncounterDirector

	if complete_run_on_enter:
		if ed != null:
			ed.advance_to_section(EncounterDirector.Section.COMPLETE, Transform3D.IDENTITY, false)
		var run_state: Node = _get_run_state()
		if run_state != null and run_state.has_method("finalize_run"):
			run_state.call("finalize_run", true)
		section_triggered.emit(target_section, encounter_id)
		return true

	# Construct North-facing (+Z) checkpoint transform
	var spawn_pos: Vector3 = checkpoint_spawn_position if checkpoint_spawn_position != Vector3.ZERO else Vector3(global_position.x, 0.0, global_position.z)
	var xform := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), spawn_pos)

	if ed != null:
		ed.advance_to_section(target_section as EncounterDirector.Section, xform, save_checkpoint_on_enter)

	if not entry_gate_to_seal_path.is_empty():
		var gate: EncounterGate = get_node_or_null(entry_gate_to_seal_path) as EncounterGate
		if gate != null and (encounter_id.is_empty() or ed == null or not bool(ed.completed_encounters.get(encounter_id, false))):
			gate.seal_gate_for_encounter()

	if ed != null and not encounter_id.is_empty() and encounter_enemy_count > 0:
		if not bool(ed.completed_encounters.get(encounter_id, false)):
			ed.begin_combat_encounter(encounter_id, encounter_enemy_count)

	section_triggered.emit(target_section, encounter_id)
	return true


func _on_body_entered(body: Node3D) -> void:
	if body != null and (body.is_in_group("player") or body is PlayerController):
		trigger_for_player(body)


func _on_encounter_cleared(cleared_id: String, _sec_id: int) -> void:
	if not reopen_entry_gate_on_clear or encounter_id.is_empty() or cleared_id != encounter_id:
		return
	if not entry_gate_to_seal_path.is_empty():
		var gate: EncounterGate = get_node_or_null(entry_gate_to_seal_path) as EncounterGate
		if gate != null:
			gate.open_gate(true)


func _on_section_reset_requested(reset_sec_id: int) -> void:
	if reset_sec_id != target_section:
		return
	var ed: EncounterDirector = EncounterDirector.instance as EncounterDirector
	if ed != null and not encounter_id.is_empty() and encounter_enemy_count > 0:
		if not bool(ed.completed_encounters.get(encounter_id, false)):
			ed.begin_combat_encounter(encounter_id, encounter_enemy_count)


func _get_run_state() -> Node:
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		return get_tree().root.get_node_or_null("RunState")
	return null
