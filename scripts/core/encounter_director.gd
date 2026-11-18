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
	# Initialize history with Entry Vestibule
	_checkpoint_history.append({"section": Section.ENTRY, "transform": Transform3D.IDENTITY, "realm": 0})


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
	# 1. Revert unbanked section score and reset combo to x1; elapsed run timer continues uninterrupted
	var run_state: Node = _get_run_state()
	if run_state != null and run_state.has_method("revert_to_banked_score"):
		run_state.call("revert_to_banked_score")

	# 2. Reset active incomplete encounter state
	if not current_encounter_id.is_empty() and not bool(completed_encounters.get(current_encounter_id, false)):
		current_encounter_id = ""
		active_enemy_count = 0

	# 3. Death Rewind: Respawn 2 checkpoints behind
	var target_idx = _checkpoint_history.size() - 3
	if target_idx < 0:
		target_idx = 0
	
	var target_cp = _checkpoint_history[target_idx]
	current_section = target_cp.section
	checkpoint_transform = target_cp.transform
	checkpoint_realm = target_cp.realm

	# 4. Restore checkpoint realm state (unlocks shift if died during Warden Phase 2)
	if RealmManager.instance != null:
		RealmManager.instance.force_realm(checkpoint_realm as RealmManager.Realm, false)

	# 5. Respawn player at checkpoint transform with full health
	if player != null and player.has_method("respawn_at"):
		player.call("respawn_at", checkpoint_transform)

	_update_section_enemy_activation()
	alert_section_enemies(current_section)
	section_reset_requested.emit(checkpoint_section)
	player_respawned.emit(checkpoint_section, checkpoint_transform)


func restart_full_run() -> void:
	completed_sections.clear()
	completed_encounters.clear()
	current_section = Section.ENTRY
	checkpoint_section = Section.ENTRY
	checkpoint_realm = 0
	active_enemy_count = 0
	current_encounter_id = ""

	var run_state: Node = _get_run_state()
	if run_state != null and run_state.has_method("start_new_run"):
		run_state.call("start_new_run")

	if RealmManager.instance != null:
		RealmManager.instance.force_realm(RealmManager.Realm.REALITY, false)

	_update_section_enemy_activation()
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


func _get_run_state() -> Node:
	if get_tree() != null and get_tree().root != null:
		var node: Node = get_tree().root.get_node_or_null("RunState")
		if node != null:
			return node
	return null
