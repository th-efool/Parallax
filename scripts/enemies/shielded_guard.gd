class_name ShieldedGuard
extends EnemyAI
## Stage 03 Collapsed Gallery dual-realm elite enemy (250 HP, 20 dmg shield bash).
## In Reality: raised shield blocks Light attacks (0 dmg) and mitigates Heavy attacks (10 chip dmg, no stagger).
## In Mirror: reflection loses its shield and takes full damage + staggers on Heavy attacks.

const CombatVFXScript := preload("res://scripts/core/combat_vfx.gd")

signal shield_deflected(is_heavy: bool)
signal shield_state_changed(shield_raised: bool)

@export var reality_heavy_chip_damage: int = 10
@export var block_light_in_reality: bool = true
@export var shield_block_half_angle_deg: float = 80.0


func _init() -> void:
	realm_affinity = RealmReactive.Affinity.BOTH_STATEFUL
	max_health = 250
	health = 250
	detection_range = 10.0
	attack_range = 2.0
	move_speed = 2.8
	windup_duration = 0.65
	attack_active_duration = 0.25
	recover_duration = 0.90
	attack_damage = 20
	attack_name = "shield_bash"
	section_id = EncounterDirector.Section.COLLAPSED_GALLERY
	encounter_id = "shielded_guard"
	# Heavy armour: shoves less, rarely dodges (it has a shield), slower to flinch.
	knockback_scale = 0.55
	evade_skill = 0.15
	max_flinch_chain = 1
	attack_lunge_speed = 4.0


func is_shield_raised() -> bool:
	if is_dead or current_state == State.STAGGER:
		return false
	if RealmManager.instance != null:
		if RealmManager.instance.is_merged or RealmManager.instance.current_realm == RealmManager.Realm.MIRROR:
			return false
	return true


func is_attacker_in_front(attacker: Node = null) -> bool:
	if attacker == null or not (attacker is Node3D):
		return true
	var attacker_3d: Node3D = attacker as Node3D
	var to_attacker: Vector3 = attacker_3d.global_position - global_position
	to_attacker.y = 0.0
	if to_attacker.length_squared() <= 0.0001:
		return true
	var fwd: Vector3 = get_facing_direction()
	var threshold: float = cos(deg_to_rad(shield_block_half_angle_deg))
	return fwd.dot(to_attacker.normalized()) >= threshold


func on_realm_changed(_active_realm: int) -> void:
	shield_state_changed.emit(is_shield_raised())


func _modify_incoming_damage(amount: int, is_heavy: bool, source_type: String) -> int:
	if source_type == "environmental":
		return amount

	if is_shield_raised() and is_attacker_in_front(_last_attacker):
		if not is_heavy and block_light_in_reality:
			shield_deflected.emit(false)
			return 0
		if is_heavy:
			shield_deflected.emit(true)
			return mini(amount, reality_heavy_chip_damage)

	return amount


func _spawn_deflect_sparks(is_heavy: bool) -> void:
	## Claude Pass A: amber parry sparks off the raised shield face.
	if not is_inside_tree():
		return
	var host: Node = get_parent() if get_parent() != null else self
	var pos: Vector3 = global_position + get_facing_direction() * 0.6 + Vector3(0.0, 1.1, 0.0)
	CombatVFXScript.spawn_impact_burst(host, pos, false, is_heavy, 1.2)


func _should_stagger_on_hit(is_heavy: bool, source_type: String) -> bool:
	if source_type == "environmental":
		return true
	if is_shield_raised() and is_attacker_in_front(_last_attacker):
		return false
	return is_heavy
