class_name PhantomTwin
extends EnemyAI
## Hall of Echoes spectral combatant ("dark enemy"). It exists in both realms but only FIGHTS in the Mirror:
##  - Reality: translucent ghost that stalks you; it can't be hurt (hits pass through with a cyan shimmer),
##    never starts an attack, and its hitbox can't damage anyone.
##  - Mirror (or realms merged): solid, hurtable and dangerous (lunge).
## Killing it in the Mirror still earns the Mirror Kill bonus.

@export var lunge_speed: float = 9.5
@export var lunge_trigger_range: float = 4.2
## Opacity loss in Reality (GeometryInstance3D.transparency on every mesh).
@export var reality_ghost_transparency: float = 0.6

var _shimmer_cd: int = 0


func _init() -> void:
	realm_affinity = RealmReactive.Affinity.BOTH_STATEFUL
	max_health = 80
	health = 80
	detection_range = 24.0
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
	flee_health_ratio = 0.25
	flee_duration = 2.2


func _ready() -> void:
	super._ready()
	call_deferred("_apply_ghost_look")


## Still a ghost: cyan ichor and spectral gibs.
func is_spectral() -> bool:
	return true


func _mirror_now() -> bool:
	var rm: RealmManager = RealmManager.instance as RealmManager
	return rm == null or rm.is_merged or rm.current_realm == RealmManager.Realm.MIRROR


func is_hittable_now() -> bool:
	return _mirror_now()


func can_attack_now() -> bool:
	return _mirror_now()


## Hitbox3D veto: in Reality the phantom's strikes pass through everyone.
func can_damage_target(_target: Node) -> bool:
	return _mirror_now()


func _modify_incoming_damage(amount: int, _is_heavy: bool, source_type: String) -> int:
	if source_type == "environmental" or _mirror_now():
		return amount
	_phase_shimmer()
	return 0


func _phase_shimmer() -> void:
	var now: int = Time.get_ticks_msec()
	if now < _shimmer_cd or not is_inside_tree():
		return
	_shimmer_cd = now + 250
	GoreFXScript.sparks(self, global_position + Vector3.UP * 1.2, Vector3.UP, Color(0.55, 0.9, 1.0), 10)


func on_realm_changed(_active_realm: int) -> void:
	_apply_ghost_look()
	if not _mirror_now():
		_release_token()
		if current_state == State.WINDUP or current_state == State.ATTACK:
			_clear_telegraph_flash()
			var hb: Hitbox3D = get_attack_hitbox()
			if hb != null:
				hb.end_swing()
			velocity.x = 0.0
			velocity.z = 0.0
			_transition_to(State.CHASE, 0.0)


func _apply_ghost_look() -> void:
	if not is_inside_tree():
		return
	var vis: Node = get_node_or_null(visual_root_path)
	if vis == null:
		return
	var t: float = 0.0 if _mirror_now() else clampf(reality_ghost_transparency, 0.0, 0.95)
	for mi in vis.find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).transparency = t


func start_windup(custom_windup: float = -1.0) -> void:
	if not _mirror_now():
		# A Mirror creature can't touch anyone in Reality: give the attack token back and keep stalking.
		_release_token()
		return
	super.start_windup(custom_windup)


func _begin_attack_strike() -> void:
	super._begin_attack_strike()
	var lunge_vel: Vector3 = get_facing_direction() * lunge_speed
	velocity.x = lunge_vel.x
	velocity.z = lunge_vel.z
