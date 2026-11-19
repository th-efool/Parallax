class_name SkeletonGuard
extends EnemyAI
## Stage 02 Hall of Echoes Reality-only melee combatant (100 HP, 15 dmg, 0.8s recovery).
## Emits `mirror_hint_requested` on first Hall of Echoes Skeleton kill to remind the player of Phantom Twins.

signal mirror_hint_requested()

var _first_hall_skeleton_hint_emitted: bool = false
var _has_revived: bool = false


func _init() -> void:
	# Realm redesign (2026-11-17): every enemy exists in BOTH realms; the Mirror reveals their weak points.
	realm_affinity = RealmReactive.Affinity.BOTH_STATEFUL
	max_health = 100
	health = 100
	detection_range = 22.0
	attack_range = 1.85
	move_speed = 3.4
	windup_duration = 0.55
	attack_active_duration = 0.22
	recover_duration = 0.80
	attack_damage = 15
	attack_name = "skeleton_slash"
	section_id = EncounterDirector.Section.HALL_COMBAT
	encounter_id = "hall_of_echoes"
	flee_health_ratio = 0.15


func reset_hall_hint_flag() -> void:
	_first_hall_skeleton_hint_emitted = false


func _on_enemy_reset() -> void:
	super._on_enemy_reset()
	_first_hall_skeleton_hint_emitted = false
	_has_revived = false


func _die(source_type: String) -> void:
	if not _has_revived and source_type != "player_execution" and source_type != "execution":
		_has_revived = true
		health = int(max_health * 0.5)
		enter_stunned(3.0)
		return
	super._die(source_type)
	if not _first_hall_skeleton_hint_emitted and encounter_id == "hall_of_echoes":
		_first_hall_skeleton_hint_emitted = true
		mirror_hint_requested.emit()
