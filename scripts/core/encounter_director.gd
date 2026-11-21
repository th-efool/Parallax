class_name EncounterDirector
extends Node
## Owns the linear 5-stage FSM, encounter gates, section enemy activation, and checkpoint respawn flow.

enum Section {
	ENTRY = 0,
	HALL_COMBAT = 1,
	COLLAPSED_GALLERY = 2,
	MECHANISM_CHAMBER = 3,
	EXECUTION_ARENA = 4,
	COMPLETE = 5,
}

signal section_changed(section_id: int, section_name: String)
signal encounter_started(encounter_id: String, section_id: int)
signal encounter_cleared(encounter_id: String, section_id: int)
signal checkpoint_updated(section_id: int, spawn_transform: Transform3D)
signal player_respawned(section_id: int, spawn_transform: Transform3D)
signal section_reset_requested(section_id: int)

static var instance = null

@export var auto_save_on_checkpoint: bool = true

var current_section: Section = Section.ENTRY
var active_enemy_count: int = 0
var current_encounter_id: String = ""
var _is_processing_death: bool = false

var completed_sections: Dictionary = {}
var completed_encounters: Dictionary = {}

var checkpoint_section: Section = Section.ENTRY
var checkpoint_transform: Transform3D = Transform3D.IDENTITY
var checkpoint_realm: int = 0

var _section_enemies: Dictionary = {}


var _checkpoint_history: Array[Dictionary] = []
const MAX_HISTORY: int = 5

func _enter_tree() -> void:
	instance = self
	add_to_group("encounter_director")
	# Initialize history with Entry Vestibule at start terrace
	var default_spawn := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 0.0, -136.0))
	checkpoint_section = Section.ENTRY
	checkpoint_transform = default_spawn
	checkpoint_realm = 0
	_checkpoint_history.clear()
	_checkpoint_history.append({"section": Section.ENTRY, "transform": default_spawn, "realm": 0})


func _exit_tree() -> void:
	_section_enemies.clear()
	if instance == self:
		instance = null


func get_section_name(section_id: Section) -> String:
	match section_id:
		Section.ENTRY:
			return "Entry Vestibule"
		Section.HALL_COMBAT:
			return "Hall of Echoes"
		Section.COLLAPSED_GALLERY:
			return "Collapsed Gallery"
		Section.MECHANISM_CHAMBER:
			return "Mechanism Chamber"
		Section.EXECUTION_ARENA:
			return "Execution Arena"
		Section.COMPLETE:
			return "Run Complete"
	return "Unknown"


func register_section_enemy(section_id: Section, enemy: Node) -> void:
	if enemy == null:
		return
	if not _section_enemies.has(section_id):
		_section_enemies[section_id] = []
	var list: Array = _section_enemies[section_id]
	if not list.has(enemy):
		list.append(enemy)
	_update_section_enemy_activation()


## Runtime-spawned enemies (Warden thralls) drop out of the activation list when they are freed.
func unregister_section_enemy(section_id: Section, enemy: Node) -> void:
	if _section_enemies.has(section_id):
		(_section_enemies[section_id] as Array).erase(enemy)


func advance_to_section(next_section: Section, new_checkpoint_xform: Transform3D = Transform3D.IDENTITY, save_checkpoint: bool = true) -> void:
	if current_section != next_section:
		completed_sections[current_section] = true
		current_section = next_section

	if save_checkpoint:
		var rm: RealmManager = RealmManager.instance as RealmManager
		var realm_val: int = int(rm.current_realm) if rm != null else 0
		set_checkpoint(next_section, new_checkpoint_xform, realm_val)

	_update_section_enemy_activation()
	alert_section_enemies(current_section)
	section_changed.emit(current_section, get_section_name(current_section))


func set_checkpoint(section_id: Section, spawn_transform: Transform3D, realm: int = 0) -> void:
	checkpoint_section = section_id
	if spawn_transform != Transform3D.IDENTITY:
		checkpoint_transform = spawn_transform
	checkpoint_realm = realm
	
	# Maintain checkpoint history
	var new_cp = {"section": section_id, "transform": checkpoint_transform, "realm": realm}
	if _checkpoint_history.is_empty() or _checkpoint_history.back().section != section_id:
		_checkpoint_history.append(new_cp)
		if _checkpoint_history.size() > MAX_HISTORY:
			_checkpoint_history.remove_at(0)
	else:
		_checkpoint_history[_checkpoint_history.size() - 1] = new_cp
			
	var run_state: Node = _get_run_state()
	if run_state != null and run_state.has_method("bank_section_score"):
		run_state.call("bank_section_score")
	checkpoint_updated.emit(checkpoint_section, checkpoint_transform)
	_trigger_auto_save()


func alert_section_enemies(section_id: Section) -> void:
	if not _section_enemies.has(section_id):
		return
	var list: Array = _section_enemies[section_id]
	for enemy in list:
		if is_instance_valid(enemy) and enemy.has_method("receive_alert"):
			# Alerting the enemy to player entry
			enemy.call("receive_alert", null, null, false)


func begin_combat_encounter(encounter_id: String, enemy_count: int = 0) -> bool:
	if encounter_id.is_empty() or bool(completed_encounters.get(encounter_id, false)):
		return false

	current_encounter_id = encounter_id
	active_enemy_count = maxi(0, enemy_count)
	var run_state: Node = _get_run_state()
	if run_state != null and run_state.has_method("begin_encounter"):
		run_state.call("begin_encounter", encounter_id)
	encounter_started.emit(encounter_id, current_section)
	return true


func register_enemy_kill(encounter_id: String = "") -> void:
	var target_id: String = encounter_id if not encounter_id.is_empty() else current_encounter_id
	if target_id.is_empty() or current_encounter_id.is_empty() or target_id != current_encounter_id or bool(completed_encounters.get(target_id, false)):
		return

	active_enemy_count = maxi(0, active_enemy_count - 1)
	if active_enemy_count == 0:
		complete_combat_encounter(target_id)


func complete_combat_encounter(encounter_id: String) -> bool:
	if encounter_id.is_empty() or bool(completed_encounters.get(encounter_id, false)):
		return false

	completed_encounters[encounter_id] = true
	active_enemy_count = 0
	if current_encounter_id == encounter_id:
		current_encounter_id = ""

	var run_state: Node = _get_run_state()
	if run_state != null:
		if run_state.has_method("end_encounter"):
			run_state.call("end_encounter", encounter_id)
		if run_state.has_method("bank_section_score"):
			run_state.call("bank_section_score")

	encounter_cleared.emit(encounter_id, current_section)
	_trigger_auto_save()
	return true


func handle_player_death(player: Node = null) -> void:
	if _is_processing_death:
		return
	_is_processing_death = true
	# 1. Revert unbanked section score and reset combo to x1; elapsed run timer continues uninterrupted
	var run_state: Node = _get_run_state()
	if run_state != null and run_state.has_method("revert_to_banked_score"):
		run_state.call("revert_to_banked_score")

	var failed_section: int = int(current_section)

	# 2. Reset active encounter state
	current_encounter_id = ""
	active_enemy_count = 0

	# 3. Death Rewind: Respawn 2 checkpoints behind
	var default_spawn := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 0.0, -136.0))
	if _checkpoint_history.is_empty():
		_checkpoint_history.append({"section": Section.ENTRY, "transform": default_spawn, "realm": 0})

	var target_idx: int = _checkpoint_history.size() - 3
	if target_idx < 0:
		target_idx = 0

	var target_cp: Dictionary = _checkpoint_history[target_idx]
	current_section = int(target_cp.get("section", Section.ENTRY)) as Section
	checkpoint_section = int(target_cp.get("section", Section.ENTRY)) as Section
	checkpoint_transform = target_cp.get("transform", default_spawn) as Transform3D
	checkpoint_realm = int(target_cp.get("realm", 0))
	_checkpoint_history.resize(target_idx + 1)

	# Collect deduplicated ascending sections from checkpoint_section through failed_section and any cleared ahead sections.
	var reset_set: Dictionary = {}
	for sec_i in range(int(checkpoint_section), maxi(int(checkpoint_section), failed_section) + 1):
		reset_set[sec_i] = true
	for sec_key in completed_sections.keys():
		var sec_val: int = int(sec_key)
		if sec_val >= int(checkpoint_section):
			reset_set[sec_val] = true
	var sections_to_reset: Array[int] = []
	for sec_key in reset_set.keys():
		sections_to_reset.append(int(sec_key))
	sections_to_reset.sort()

	for sec_val in sections_to_reset:
		completed_sections.erase(sec_val)
	_clear_completed_encounters_for_sections(sections_to_reset)

	# Clean up lingering physics bodies / blood / attack tokens / time scale
	var gore_script = load("res://scripts/core/gore_fx.gd")
	if gore_script != null and gore_script.has_method("cleanup_all_fx"):
		gore_script.call("cleanup_all_fx")

	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		var squad_coord = get_tree().root.get_node_or_null("SquadCoordinator")
		if squad_coord != null and squad_coord.has_method("reset"):
			squad_coord.call("reset")

	var game_feel = load("res://scripts/core/game_feel.gd")
	if game_feel != null and game_feel.has_method("reset_time_scale"):
		game_feel.call("reset_time_scale")

	# 4. Reset rewound sections (gates, switches, triggers, breakables, enemies, puzzles, platforms) once per section
	for sec_val in sections_to_reset:
		section_reset_requested.emit(sec_val)

	# 5. Restore realm to checkpoint realm AFTER Warden/puzzle resets so checkpoint_realm is authoritative
	if RealmManager.instance != null:
		RealmManager.instance.force_realm(checkpoint_realm as RealmManager.Realm, false)

	# 6. Respawn player at checkpoint transform with full health
	if player != null and player.has_method("respawn_at"):
		player.call("respawn_at", checkpoint_transform)

	_update_section_enemy_activation()
	alert_section_enemies(current_section)
	section_changed.emit(current_section, get_section_name(current_section))
	player_respawned.emit(checkpoint_section, checkpoint_transform)
	_is_processing_death = false


func _clear_completed_encounters_for_sections(sections_to_reset: Array[int]) -> void:
	const SECTION_ENCOUNTER_MAP: Dictionary = {
		1: ["hall_of_echoes"],
		2: ["shielded_guard"],
		4: ["the_warden"],
	}
	for sec_val in sections_to_reset:
		for enc_name in SECTION_ENCOUNTER_MAP.get(sec_val, []):
			completed_encounters.erase(enc_name)
	if not is_inside_tree() or get_tree() == null:
		return
	for trig in get_tree().get_nodes_in_group("section_trigger"):
		if trig != null and int(trig.get("target_section")) in sections_to_reset:
			var eid: String = String(trig.get("encounter_id"))
			if not eid.is_empty():
				completed_encounters.erase(eid)
	for gate in get_tree().get_nodes_in_group("encounter_gate"):
		if gate != null and int(gate.get("section_id")) in sections_to_reset:
			var gid: String = String(gate.get("linked_encounter_id"))
			if not gid.is_empty():
				completed_encounters.erase(gid)


func restore_checkpoint_history(entries: Array, fallback_section: int, fallback_xform: Transform3D, fallback_realm: int) -> void:
	var default_spawn := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 0.0, -136.0))
	_checkpoint_history.clear()
	for item in entries:
		if item is Dictionary:
			var d: Dictionary = item as Dictionary
			var sec_i: int = int(d.get("section", Section.ENTRY))
			var xform: Transform3D = d.get("transform", default_spawn) as Transform3D
			var r_i: int = int(d.get("realm", 0))
			_checkpoint_history.append({"section": sec_i, "transform": xform, "realm": r_i})
	if _checkpoint_history.is_empty():
		var section_xforms: Dictionary = {int(Section.ENTRY): default_spawn}
		if is_inside_tree() and get_tree() != null:
			for trig in get_tree().get_nodes_in_group("section_trigger"):
				if trig is Node3D and not bool(trig.get("complete_run_on_enter")):
					var t_sec: int = int(trig.get("target_section"))
					if not section_xforms.has(t_sec):
						var spos: Variant = trig.get("checkpoint_spawn_position")
						var cp_pos: Vector3 = spos if (spos is Vector3 and (spos as Vector3) != Vector3.ZERO) else (trig as Node3D).global_position
						cp_pos.y = (trig as Node3D).global_position.y - 1.25 if spos == Vector3.ZERO else cp_pos.y
						section_xforms[t_sec] = Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), cp_pos)
		for sec_i in range(0, maxi(0, fallback_section)):
			if section_xforms.has(sec_i):
				_checkpoint_history.append({"section": sec_i, "transform": section_xforms[sec_i], "realm": 0})
		_checkpoint_history.append({"section": fallback_section, "transform": fallback_xform, "realm": fallback_realm})
	else:
		if int(_checkpoint_history.back().get("section", -1)) != fallback_section:
			_checkpoint_history.append({"section": fallback_section, "transform": fallback_xform, "realm": fallback_realm})
		else:
			_checkpoint_history[_checkpoint_history.size() - 1] = {"section": fallback_section, "transform": fallback_xform, "realm": fallback_realm}
	while _checkpoint_history.size() > MAX_HISTORY:
		_checkpoint_history.remove_at(0)


func restart_full_run() -> void:
	completed_sections.clear()
	completed_encounters.clear()
	current_section = Section.ENTRY
	checkpoint_section = Section.ENTRY
	checkpoint_realm = 0
	active_enemy_count = 0
	current_encounter_id = ""

	var default_spawn := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI), Vector3(0.0, 0.0, -136.0))
	checkpoint_transform = default_spawn
	_checkpoint_history.clear()
	_checkpoint_history.append({"section": Section.ENTRY, "transform": default_spawn, "realm": 0})

	var gore_script = load("res://scripts/core/gore_fx.gd")
	if gore_script != null and gore_script.has_method("cleanup_all_fx"):
		gore_script.call("cleanup_all_fx")

	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		var squad_coord = get_tree().root.get_node_or_null("SquadCoordinator")
		if squad_coord != null and squad_coord.has_method("reset"):
			squad_coord.call("reset")

	var game_feel = load("res://scripts/core/game_feel.gd")
	if game_feel != null and game_feel.has_method("reset_time_scale"):
		game_feel.call("reset_time_scale")

	var run_state: Node = _get_run_state()
	if run_state != null and run_state.has_method("start_new_run"):
		run_state.call("start_new_run")

	if RealmManager.instance != null:
		RealmManager.instance.force_realm(RealmManager.Realm.REALITY, false)

	_update_section_enemy_activation()
	if is_inside_tree() and get_tree() != null:
		var squad: Node = get_tree().get_first_node_in_group("squad_manager")
		if squad != null and squad.has_method("regroup"):
			var ally_list: Variant = squad.get("allies")
			if ally_list is Array and not (ally_list as Array).is_empty():
				squad.call("regroup", true)
	section_changed.emit(current_section, get_section_name(current_section))


func _update_section_enemy_activation() -> void:
	for sec_key in _section_enemies.keys():
		var is_current: bool = (int(sec_key) == int(current_section))
		var list: Array = _section_enemies[sec_key]
		for enemy in list:
			if is_instance_valid(enemy):
				if enemy.has_method("set_section_enabled"):
					enemy.call("set_section_enabled", is_current)
				else:
					enemy.set_physics_process(is_current)
					enemy.set_process(is_current)


func _trigger_auto_save() -> void:
	if not auto_save_on_checkpoint or not is_inside_tree() or get_tree() == null or get_tree().root == null:
		return
	if current_section == Section.COMPLETE:
		return
	var store: Node = get_tree().root.get_node_or_null("LeaderboardStore")
	if store != null and store.has_method("capture_and_save_world_state"):
		store.call("capture_and_save_world_state")


func reset_triggers() -> void:
	completed_sections.clear()
	completed_encounters.clear()
	# Reset active encounter state
	active_enemy_count = 0
	current_encounter_id = ""
	# Notify observers
	section_reset_requested.emit(current_section)

func _get_run_state() -> Node:
	if get_tree() != null and get_tree().root != null:
		var node: Node = get_tree().root.get_node_or_null("RunState")
		if node != null:
			return node
	return null

