class_name PhantomTwin
extends EnemyAI
## Stage 02 Hall of Echoes Mirror-only spectral combatant (80 HP, 20 dmg lunge, 1.0s recovery).
## Slaying in Mirror awards base +100 Enemy Kill and +200 Mirror Kill (multiplied by active combo).

@export var lunge_speed: float = 9.5
@export var lunge_trigger_range: float = 4.2

var _lunge_direction: Vector3 = Vector3.FORWARD


func _init() -> void:
	realm_affinity = RealmReactive.Affinity.MIRROR_ONLY
	max_health = 80
	health = 80
	detection_range = 9.0
	attack_range = 4.2
	move_speed = 3.8
	windup_duration = 0.65
	attack_active_duration = 0.32
	recover_duration = 1.00
	attack_damage = 20
	attack_name = "phantom_lunge"
	section_id = EncounterDirector.Section.HALL_COMBAT
	encounter_id = "hall_of_echoes"
	# Spectral duelist: light on its feet, slips out of telegraphed swings.
	evade_skill = 0.7
	knockback_scale = 1.3
	ring_margin = 1.2


func start_windup(custom_windup: float = -1.0) -> void:
	var p: Node3D = _resolve_target_player()
	if p != null:
		var dir: Vector3 = p.global_position - global_position
		dir.y = 0.0
		if dir.length_squared() > 0.001:
			_lunge_direction = dir.normalized()
	else:
		_lunge_direction = -global_transform.basis.z.normalized()
	super.start_windup(custom_windup)


func _begin_attack_strike() -> void:
	super._begin_attack_strike()
	velocity = _lunge_direction * lunge_speed
