class_name SkeletonGuard
extends EnemyAI
## Stage 02 Hall of Echoes Reality-only melee combatant (100 HP, 15 dmg, 0.8s recovery).
## Emits `mirror_hint_requested` on first Hall of Echoes Skeleton kill to remind the player of Phantom Twins.

signal mirror_hint_requested()

static var _first_hall_skeleton_hint_emitted: bool = false


func _init() -> void:
	realm_affinity = RealmReactive.Affinity.REALITY_ONLY
	max_health = 100
	health = 100
	detection_range = 9.0
	attack_range = 1.85
	move_speed = 3.4
	windup_duration = 0.55
	attack_active_duration = 0.22
	recover_duration = 0.80
	attack_damage = 15
	attack_name = "skeleton_slash"
	section_id = EncounterDirector.Section.HALL_COMBAT
	encounter_id = "hall_of_echoes"


static func reset_hall_hint_flag() -> void:
	_first_hall_skeleton_hint_emitted = false


func _on_enemy_reset() -> void:
	super._on_enemy_reset()
	_first_hall_skeleton_hint_emitted = false


func _die(source_type: String) -> void:
	super._die(source_type)
	if not _first_hall_skeleton_hint_emitted and encounter_id == "hall_of_echoes":
		_first_hall_skeleton_hint_emitted = true
		mirror_hint_requested.emit()
