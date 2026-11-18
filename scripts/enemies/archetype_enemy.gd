class_name ArchetypeEnemy
extends EnemyAI
## Data-driven enemy: every stat, the rig, tint, loadout and attack behaviour come from an `EnemyArchetype`
## resource (`res://data/enemies/*.tres`). Reuses the KayKit rigs + `CharacterAnimationBridge` timeline.
## Kinds: melee (token swing, optional blink-behind + backstab bonus), bolt (ranged caster holding a
## preferred range), slam (ground AoE with floor ring telegraph that also hits squad allies).

const ArchetypeScript := preload("res://scripts/enemies/enemy_archetype.gd")
const LoadoutScript := preload("res://scripts/core/character_loadout.gd")

@export var archetype: EnemyArchetype = null

var _blink_cd: float = 0.0
var _ring_mesh: MeshInstance3D = null
var _ring_mat: StandardMaterial3D = null
var _ring_tween: Tween = null
var _strafe_sign: float = 1.0


func _ready() -> void:
	apply_archetype()
	super._ready()
	_strafe_sign = 1.0 if _rng.randf() < 0.5 else -1.0
	call_deferred("_dress_model")


## Copies archetype values onto the EnemyAI/EnemyBase exports (call before _ready or on reset).
func apply_archetype() -> void:
	if archetype == null:
		return
	var a: EnemyArchetype = archetype
	match a.realm:
		"mirror":
			realm_affinity = RealmReactive.Affinity.MIRROR_ONLY
		"both":
			realm_affinity = RealmReactive.Affinity.BOTH_STATEFUL
		_:
			realm_affinity = RealmReactive.Affinity.REALITY_ONLY
	max_health = a.max_health
	health = a.max_health
	move_speed = a.move_speed
	detection_range = a.detection_range
	attack_range = a.attack_range
	windup_duration = a.windup_duration
	attack_active_duration = a.attack_active_duration
	recover_duration = a.recover_duration
	stagger_duration = a.stagger_duration
	attack_damage = int(float(a.attack_damage) * DAMAGE_SCALE)
	attack_name = a.attack_name
	attack_lunge_speed = a.attack_lunge_speed
	evade_skill = a.evade_skill
	knockback_scale = a.knockback_scale
	max_flinch_chain = a.max_flinch_chain
	flinch_on_light_hits = a.flinch_on_light_hits
	heavy_attack_staggers = a.heavy_attack_staggers
	knockdown_immune = a.knockdown_immune
	flee_health_ratio = a.flee_health_ratio
	flee_duration = a.flee_duration
	threat_decay_per_sec = a.threat_decay_per_sec
	max_chase_distance = a.max_chase_distance
	if get_kind() == "bolt":
		max_chase_distance *= 1.5
	patrol_radius = a.patrol_radius
	ring_margin = a.ring_margin


func get_display_name() -> String:
	return archetype.display_name if archetype != null else String(name)


func get_kind() -> String:
	return archetype.attack_kind if archetype != null else "melee"


# ------------------------------------------------------------------ visuals

func _dress_model() -> void:
	if archetype == null or not is_inside_tree():
		return
	var model: Node3D = get_node_or_null(NodePath(String(visual_root_path) + "/ModelRoot")) as Node3D
	if model == null:
		return
	LoadoutScript.apply(model, archetype.keep_props)
	var bp: Array[String] = archetype.borrow_props
	var i: int = 0
	while i + 2 < bp.size():
		LoadoutScript.arm_with_borrowed(model, bp[i], bp[i + 1], bp[i + 2])
		i += 3
	if archetype.tint != Color(1, 1, 1, 1) or archetype.emission_tint.get_luminance() > 0.01:
		_tint_meshes(model)
	if archetype.attack_kind == "bolt":
		_attach_hand_orb(model)


func _tint_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh != null:
			for s in range(mi.mesh.get_surface_count()):
				var src: Material = mi.get_surface_override_material(s)
				if src == null:
					src = mi.mesh.surface_get_material(s)
				if src is StandardMaterial3D:
					var m: StandardMaterial3D = (src as StandardMaterial3D).duplicate() as StandardMaterial3D
					m.albedo_color = m.albedo_color * archetype.tint
					if archetype.emission_tint.get_luminance() > 0.01:
						m.emission_enabled = true
						m.emission = archetype.emission_tint
						m.emission_energy_multiplier = 0.6
					mi.set_surface_override_material(s, m)
	for c in node.get_children():
		_tint_meshes(c)


func _attach_hand_orb(model: Node3D) -> void:
	var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D if not model.find_children("*", "Skeleton3D", true, false).is_empty() else null
	if skel == null or skel.find_bone("handslot.r") < 0:
		return
	var att := BoneAttachment3D.new()
	att.name = "HexOrb"
	att.bone_name = "handslot.r"
	skel.add_child(att)
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.11
	sm.height = 0.22
	orb.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = archetype.bolt_color
	mat.emission_enabled = true
	mat.emission = archetype.bolt_color
	orb.material_override = mat
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	att.add_child(orb)
	var l := OmniLight3D.new()
	l.light_color = archetype.bolt_color
	l.light_energy = 0.9
	l.omni_range = 2.2
	att.add_child(l)


# ------------------------------------------------------------------ behaviour

func _tick_timers(delta: float) -> void:
	super._tick_timers(delta)
	_blink_cd = maxf(0.0, _blink_cd - delta)


func _process_chase(delta: float, target: Node3D) -> void:
	if get_kind() != "bolt":
		super._process_chase(delta, target)
		return
	# --- Caster: hold the preferred range, strafe, and fire when holding a token. ---
	if target == null:
		_lose_target()
		return
	var to_p: Vector3 = target.global_position - global_position
	to_p.y = 0.0
	var dist: float = to_p.length()
	if global_position.distance_to(_home) > max_chase_distance and not is_taunted():
		_begin_return()
		return
	if dist > detection_range * 2.2 and not is_taunted():
		_threat.erase(target.get_instance_id())
		_lose_target()
		return
	var dir: Vector3 = to_p / dist if dist > 0.001 else get_facing_direction()
	set_facing_direction(dir)
	if _taunt_timer > 0.0:
		velocity = Vector3.ZERO
		return
	var pref: float = archetype.preferred_range
	var has_token: bool = _squad == null or _squad.request_attack_token(self, target)
	if has_token and dist <= attack_range and dist >= pref * 0.45:
		start_windup()
		return
	var desired := Vector3.ZERO
	if dist < pref * 0.7:
		desired = -dir * move_speed
	elif dist > pref * 1.1:
		desired = dir * move_speed
	else:
		desired = Vector3(-dir.z, 0.0, dir.x) * _strafe_sign * move_speed * 0.55
	if not _has_floor_ahead(desired.normalized() if desired.length_squared() > 0.01 else dir):
		_strafe_sign = -_strafe_sign
	_steer_toward(desired, delta, true)


func start_windup(custom_windup: float = -1.0) -> void:
	var t: Node3D = _resolve_target_player()
	if get_kind() == "melee" and archetype != null and archetype.blink_cooldown > 0.0 and _blink_cd <= 0.0 and t != null:
		_try_blink_behind(t)
	super.start_windup(custom_windup)
	if get_kind() == "slam":
		_show_slam_ring(windup_duration if custom_windup < 0.0 else custom_windup)


## Shade step: reappear behind the target (floor-checked), so the stab lands as a backstab.
func _try_blink_behind(t: Node3D) -> void:
	var f: Vector3 = Vector3.FORWARD
	if t.has_method("get_facing_direction"):
		f = t.call("get_facing_direction")
	var spot: Vector3 = t.global_position - f.normalized() * 1.3
	if not is_inside_tree():
		return
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 1.0, spot + Vector3.DOWN * 1.6, collision_mask & (RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_REALITY | RealmManager.LAYER_WORLD_MIRROR), [get_rid()])
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return
	var col: Color = archetype.bolt_color
	GoreFXScript.flash_light(self, global_position + Vector3.UP, col, 3.0, 0.25, 4.0)
	GoreFXScript.dust_puff(self, global_position, 0.5, 12, Color(col.r, col.g, col.b, 0.5), 1.5)
	global_position = (hit["position"] as Vector3)
	GoreFXScript.dust_puff(self, global_position, 0.5, 12, Color(col.r, col.g, col.b, 0.5), 1.5)
	GameFeelScript.play_sound(self, "mirror_whisper", global_position, -4.0, 1.4)
	_blink_cd = archetype.blink_cooldown
	set_facing_direction(t.global_position - global_position)


func _begin_attack_strike() -> void:
	match get_kind():
		"bolt":
			_release_telegraph_flash()
			_transition_to(State.ATTACK, attack_active_duration)
			velocity = Vector3.ZERO
			_fire_bolt()
			attack_started.emit(attack_name, attack_damage)
		"slam":
			_release_telegraph_flash()
			_transition_to(State.ATTACK, attack_active_duration)
			velocity = Vector3.ZERO
			_do_slam()
			attack_started.emit(attack_name, attack_damage)
		_:
			var base: int = attack_damage
			var t: Node3D = _resolve_target_player()
			if t != null and archetype != null and archetype.backstab_bonus_mult > 1.0 and t.has_method("get_facing_direction"):
				var tf: Vector3 = t.call("get_facing_direction")
				var to_me: Vector3 = global_position - t.global_position
				to_me.y = 0.0
				if to_me.length_squared() > 0.01 and tf.dot(to_me.normalized()) < -0.3:
					attack_damage = int(round(float(base) * archetype.backstab_bonus_mult))
			super._begin_attack_strike()
			attack_damage = base


func _fire_bolt() -> void:
	var t: Node3D = _resolve_target_player()
	if t == null or not is_inside_tree():
		return
	var from: Vector3 = get_chest_position() + get_facing_direction() * 0.5 + Vector3.UP * 0.2
	var aim: Vector3 = t.global_position + Vector3.UP * 1.0
	# Lead the target a little; dodging sideways still beats it.
	if t is CharacterBody3D:
		aim += (t as CharacterBody3D).velocity * 0.18
	var bolt := HexBolt.new()
	bolt.setup(self, from, (aim - from).normalized(), archetype.bolt_speed, attack_damage, archetype.bolt_color)
	GoreFXScript.host_for(self).add_child(bolt)
	GameFeelScript.play_sound(self, "mirror_whisper", from, -2.0, 1.8)


func _do_slam() -> void:
	var c: Vector3 = global_position + get_facing_direction() * 0.8
	var r: float = archetype.aoe_radius
	GoreFXScript.shockwave_ring(self, c + Vector3.UP * 0.05, r, Color(1.0, 0.55, 0.25, 0.9), 0.4, 0.35)
	GoreFXScript.dust_puff(self, c, r * 0.6, 34, Color(0.6, 0.52, 0.42, 0.6), 2.4)
	GoreFXScript.ground_crack(self, c, get_facing_direction(), r * 1.2, Color(1.0, 0.45, 0.15))
	GameFeelScript.play_sound(self, "landing_slam", c, 0.0, 0.75)
	GameFeelScript.add_trauma(self, 0.35, c)
	if _squad != null:
		_squad.broadcast_noise(c, 14.0)
	for n in _gather_candidates():
		var d: Vector3 = n.global_position - c
		if Vector2(d.x, d.z).length() <= r and absf(d.y) < 2.0:
			_damage_entity(n, attack_damage)
	_hide_slam_ring()


func _damage_entity(n: Node, amount: int) -> void:
	if n == null or not is_instance_valid(n) or not n.has_method("apply_damage"):
		return
	n.call("apply_damage", amount, self)


func _show_slam_ring(dur: float) -> void:
	if not is_inside_tree():
		return
	if _ring_mesh == null or not is_instance_valid(_ring_mesh):
		_ring_mesh = MeshInstance3D.new()
		_ring_mesh.name = "SlamTelegraph"
		var tm := TorusMesh.new()
		tm.inner_radius = 0.92
		tm.outer_radius = 1.0
		tm.rings = 48
		tm.ring_segments = 6
		_ring_mesh.mesh = tm
		_ring_mat = StandardMaterial3D.new()
		_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_ring_mat.no_depth_test = false
		_ring_mesh.material_override = _ring_mat
		_ring_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ring_mesh)
	_ring_mesh.position = get_facing_direction() * 0.8 + Vector3.UP * 0.06
	_ring_mesh.scale = Vector3(archetype.aoe_radius * 0.3, 0.25, archetype.aoe_radius * 0.3)
	_ring_mesh.visible = true
	_ring_mat.albedo_color = Color(1.0, 0.25, 0.1, 0.25)
	if _ring_tween != null and _ring_tween.is_valid():
		_ring_tween.kill()
	_ring_tween = create_tween().set_parallel(true)
	_ring_tween.tween_property(_ring_mesh, "scale", Vector3(archetype.aoe_radius, 0.25, archetype.aoe_radius), maxf(0.05, dur * 0.8))
	_ring_tween.tween_property(_ring_mat, "albedo_color:a", 0.95, maxf(0.05, dur))


func _hide_slam_ring() -> void:
	if _ring_tween != null and _ring_tween.is_valid():
		_ring_tween.kill()
	if _ring_mesh != null and is_instance_valid(_ring_mesh):
		_ring_mesh.visible = false


func enter_stagger(custom_duration: float = -1.0) -> void:
	_hide_slam_ring()
	super.enter_stagger(custom_duration)


func enter_stunned(custom_duration: float = -1.0) -> void:
	_hide_slam_ring()
	super.enter_stunned(custom_duration)


func _on_enemy_reset() -> void:
	_hide_slam_ring()
	_blink_cd = 0.0
	super._on_enemy_reset()


func _die(source_type: String) -> void:
	_hide_slam_ring()
	super._die(source_type)


## Slow, dodgeable caster projectile. Hits the first player/ally it passes within 0.7 m of; fizzles on walls.
class HexBolt:
	extends Node3D

	var _owner_enemy: WeakRef = null
	var _dir: Vector3 = Vector3.FORWARD
	var _speed: float = 10.0
	var _damage: int = 10
	var _life: float = 2.6
	var _color: Color = Color(0.75, 0.35, 1.0)
	var _mask: int = RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_REALITY | RealmManager.LAYER_WORLD_MIRROR

	func setup(owner_enemy: Node, from: Vector3, dir: Vector3, speed: float, damage: int, color: Color) -> void:
		_owner_enemy = weakref(owner_enemy)
		position = from
		_dir = dir
		_speed = speed
		_damage = damage
		_color = color
		if owner_enemy is CollisionObject3D:
			_mask = (owner_enemy as CollisionObject3D).collision_mask & _mask

	func _ready() -> void:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.32
		mi.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = _color
		mat.emission_enabled = true
		mat.emission = _color
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var l := OmniLight3D.new()
		l.light_color = _color
		l.light_energy = 1.6
		l.omni_range = 3.0
		add_child(l)

	func _physics_process(delta: float) -> void:
		_life -= delta
		if _life <= 0.0:
			queue_free()
			return
		var step: Vector3 = _dir * _speed * delta
		var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(global_position, global_position + step, _mask)
		if not space.intersect_ray(q).is_empty():
			GoreFX.sparks(self, global_position, -_dir, _color, 14)
			queue_free()
			return
		global_position += step
		var targets: Array[Node] = []
		var p: Node = get_tree().get_first_node_in_group("player")
		if p != null:
			targets.append(p)
		targets.append_array(get_tree().get_nodes_in_group("squad_ally"))
		for t in targets:
			if not (t is Node3D) or not is_instance_valid(t):
				continue
			if t.has_method("is_targetable") and not bool(t.call("is_targetable")):
				continue
			var c: Vector3 = (t as Node3D).global_position + Vector3.UP * 1.0
			if c.distance_to(global_position) < 0.75:
				var src: Node = _owner_enemy.get_ref() as Node if _owner_enemy != null else null
				if t.has_method("apply_damage") and bool(t.call("apply_damage", _damage, src)):
					GoreFX.flash_light(self, global_position, _color, 3.0, 0.2, 3.0)
				queue_free()
				return
