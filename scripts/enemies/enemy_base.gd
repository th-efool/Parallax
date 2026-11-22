class_name EnemyBase
extends CharacterBody3D
## Shared base class for all PARALLAX enemies (Skeleton Guard, Phantom Twin, Shielded Guard, The Warden).
## Enforces the Golden Collision Rule: when realm-inactive or section-disabled, disables colliders, hurtbox, hitbox, and AI processing.

signal health_changed(current_hp: int, max_hp: int)
signal damaged(amount: int, is_heavy: bool, source_type: String)
signal staggered(duration: float)
signal died(enemy: Node, kill_context: Dictionary)
signal realm_activity_changed(active: bool)

const GoreFXScript := preload("res://scripts/core/gore_fx.gd")
const GameFeelScript := preload("res://scripts/core/game_feel.gd")

@export_group("Identity & Realm")
@export var enemy_id: String = ""
@export var section_id: int = 1
@export var encounter_id: String = "hall_of_echoes"
@export var realm_affinity: RealmReactive.Affinity = RealmReactive.Affinity.REALITY_ONLY
@export var award_standard_kill_score: bool = true

@export_group("Stats")
@export var max_health: int = 100
@export var heavy_attack_staggers: bool = true
## Bosses: the Execution finisher (instant kill at low HP) does not apply.
@export var execute_immune: bool = false

## Global enemy durability multiplier (+30% over 2.5x = 3.25x). Applied once to the
## authored max_health in _ready(), so scripted enemies and data-driven archetypes are all covered.
const HEALTH_SCALE: float = 3.74   # 3.25 x 1.15 (2026-11-21 playtest)
var _health_scaled: bool = false

@export_group("Node Paths")
@export var hurtbox_path: NodePath = NodePath("Hurtbox3D")
@export var attack_hitbox_path: NodePath = NodePath("AttackHitbox")
@export var visual_root_path: NodePath = NodePath("VisualRoot")

@export_group("Hit Feel & Gore")
## Alpha 0 = automatic (red blood; cyan ichor for Mirror-only spectral enemies).
@export var blood_color: Color = Color(0.0, 0.0, 0.0, 0.0)
@export var gib_on_death: bool = true
@export var flinch_on_light_hits: bool = true
@export var knockback_scale: float = 1.0

var health: int = 100
var last_hit_direction: Vector3 = Vector3.FORWARD
var last_hit_source: String = ""
var last_hit_heavy: bool = false
var _flash_mat: StandardMaterial3D = null
var _flash_serial: int = 0
var _flash_previous: Dictionary = {}
var _wound_fx: CPUParticles3D = null
var is_active: bool = true
var is_section_enabled: bool = true
var is_realm_enabled: bool = true
var is_dead: bool = false
## Held back by a WaveDirector until its wave starts: hidden, inert, untargetable.
var is_wave_held: bool = false
var facing_direction: Vector3 = Vector3.FORWARD
var _last_attacker: Node = null
var _spawn_transform: Transform3D = Transform3D.IDENTITY


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("realm_reactive")
	_spawn_transform = global_transform
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 0.001:
		facing_direction = fwd.normalized()
	if not _health_scaled:
		_health_scaled = true
		max_health = maxi(1, int(round(float(max_health) * HEALTH_SCALE)))
	health = max_health
	health_changed.emit(health, max_health)

	if EncounterDirector.instance != null:
		EncounterDirector.instance.register_section_enemy(section_id as EncounterDirector.Section, self)
		if not EncounterDirector.instance.section_reset_requested.is_connected(_on_section_reset_requested):
			EncounterDirector.instance.section_reset_requested.connect(_on_section_reset_requested)

	if has_signal("shield_deflected"):
		connect("shield_deflected", _on_shield_deflected_fx)

	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm != null:
		if not rm.realm_changed.is_connected(_on_manager_realm_changed):
			rm.realm_changed.connect(_on_manager_realm_changed)
		if not rm.realms_merged.is_connected(_on_manager_realms_merged):
			rm.realms_merged.connect(_on_manager_realms_merged)
		evaluate_for_realm(int(rm.current_realm), rm.is_merged)
	else:
		evaluate_for_realm(0, false)


func get_enemy_unique_id() -> String:
	if not enemy_id.is_empty():
		return enemy_id
	return "%s_%d" % [name, get_instance_id()]


func set_section_enabled(enabled: bool) -> void:
	is_section_enabled = enabled
	_refresh_active_state()


func evaluate_for_realm(active_realm: int, realms_merged: bool = false) -> void:
	if realms_merged or realm_affinity == RealmReactive.Affinity.BOTH_STATEFUL:
		is_realm_enabled = true
	elif realm_affinity == RealmReactive.Affinity.REALITY_ONLY:
		is_realm_enabled = (active_realm == 0)
	elif realm_affinity == RealmReactive.Affinity.MIRROR_ONLY:
		is_realm_enabled = (active_realm == 1)

	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm != null and (not realms_merged or rm.is_merged):
		rm.update_actor_collision_mask(self, active_realm as RealmManager.Realm)
	else:
		var cleared_mask: int = collision_mask & ~(RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_REALITY | RealmManager.LAYER_WORLD_MIRROR)
		var world_mask: int = RealmManager.LAYER_WORLD_SHARED | RealmManager.LAYER_WORLD_REALITY | RealmManager.LAYER_WORLD_MIRROR
		if not realms_merged:
			world_mask = RealmManager.LAYER_WORLD_SHARED | (RealmManager.LAYER_WORLD_MIRROR if active_realm == 1 else RealmManager.LAYER_WORLD_REALITY)
		collision_mask = cleared_mask | world_mask

	_refresh_active_state()
	on_realm_changed(active_realm)
	# Mirror = insight: in the (unmerged) Mirror every enemy shows its weak point.
	_on_mirror_insight(active_realm == 1 and not realms_merged)


## Virtual: the Mirror "insight" view turned on/off for this enemy (weak-point glow, damage bonus).
func _on_mirror_insight(_on: bool) -> void:
	pass


func set_realm_active(active: bool) -> void:
	is_realm_enabled = active
	_refresh_active_state()


func on_realm_changed(_active_realm: int) -> void:
	pass


func get_facing_direction() -> Vector3:
	if facing_direction.length_squared() > 0.001:
		return facing_direction.normalized()
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	return fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD


func set_facing_direction(dir: Vector3) -> void:
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() <= 0.0001:
		return
	facing_direction = flat.normalized()
	var vis_root: Node3D = get_node_or_null(visual_root_path) as Node3D
	var target_world_yaw: float = atan2(-facing_direction.x, -facing_direction.z)
	var parent_yaw: float = global_rotation.y if is_inside_tree() else rotation.y
	var target_yaw: float = wrapf(target_world_yaw - parent_yaw, -PI, PI)
	if vis_root != null:
		vis_root.rotation.y = target_yaw
	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null and hb.get_parent() == self:
		hb.rotation.y = target_yaw


func apply_damage(amount: int, is_heavy: bool = false, source_type: String = "", attacker: Node = null) -> bool:
	if is_dead or not is_active or amount <= 0:
		return false

	_last_attacker = attacker
	_record_hit(attacker, is_heavy, source_type)
	var final_damage: int = _modify_incoming_damage(amount, is_heavy, source_type)
	if final_damage <= 0:
		return false

	health = maxi(0, health - final_damage)
	damaged.emit(final_damage, is_heavy, source_type)
	health_changed.emit(health, max_health)

	_on_damage_taken(final_damage, is_heavy, source_type)
	if is_dead:
		return true  # a subclass hook (e.g. phase change) already resolved the death

	var lethal: bool = health <= 0
	_play_hit_feedback(final_damage, is_heavy, source_type, lethal)

	if lethal:
		_die(source_type)
	elif is_heavy and _should_stagger_on_hit(is_heavy, source_type):
		_on_stagger_triggered()
		_on_hit_reaction(final_damage, is_heavy, source_type, true)
	else:
		_on_hit_reaction(final_damage, is_heavy, source_type, false)

	return true


func reset_enemy() -> void:
	is_dead = false
	health = max_health
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	_last_attacker = null
	_flash_serial += 1
	_flash_previous.clear()
	var fwd: Vector3 = -_spawn_transform.basis.z
	fwd.y = 0.0
	facing_direction = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	_clear_wound_fx()
	_on_enemy_reset()
	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm != null:
		evaluate_for_realm(int(rm.current_realm), rm.is_merged)
	else:
		evaluate_for_realm(0, false)
	health_changed.emit(health, max_health)


func get_hurtbox() -> Hurtbox3D:
	return get_node_or_null(hurtbox_path) as Hurtbox3D


func get_attack_hitbox() -> Hitbox3D:
	return get_node_or_null(attack_hitbox_path) as Hitbox3D


func _modify_incoming_damage(amount: int, _is_heavy: bool, _source_type: String) -> int:
	return amount


## Virtual: false while this enemy can't be hurt in the current realm (Mirror-only phantoms in Reality).
## Allies skip such targets.
func is_hittable_now() -> bool:
	return true


func _should_stagger_on_hit(is_heavy: bool, _source_type: String) -> bool:
	return heavy_attack_staggers and is_heavy


func _on_damage_taken(_final_damage: int, _is_heavy: bool, _source_type: String) -> void:
	pass


func _on_stagger_triggered() -> void:
	pass


func _on_enemy_reset() -> void:
	pass


## Virtual: per-hit reaction (flinch / knockback). `staggered` = heavy stagger already triggered.
func _on_hit_reaction(_final_damage: int, _is_heavy: bool, _source_type: String, _staggered: bool) -> void:
	pass


# ------------------------------------------------------------------ hit feel & gore

func _record_hit(attacker: Node, is_heavy: bool, source_type: String) -> void:
	last_hit_heavy = is_heavy
	last_hit_source = source_type
	var dir: Vector3 = Vector3.ZERO
	if attacker is Node3D and (attacker as Node3D).is_inside_tree() and is_inside_tree():
		dir = global_position - (attacker as Node3D).global_position
		dir.y = 0.0
		if attacker.has_method("get_facing_direction") and dir.length_squared() < 0.04:
			dir = attacker.call("get_facing_direction")
	if dir.length_squared() < 0.0001:
		dir = -get_facing_direction()
	last_hit_direction = dir.normalized()


func get_blood_color() -> Color:
	if blood_color.a > 0.0:
		return blood_color
	return GoreFXScript.blood_color_for(is_spectral())


func is_spectral() -> bool:
	return realm_affinity == RealmReactive.Affinity.MIRROR_ONLY


func get_chest_position() -> Vector3:
	var vis: Node3D = get_node_or_null(visual_root_path) as Node3D
	var h: float = 1.15
	var model: Node3D = get_node_or_null(NodePath(String(visual_root_path) + "/ModelRoot")) as Node3D
	if model != null:
		h *= model.scale.y
	return (vis.global_position if vis != null else global_position) + Vector3.UP * h


func _play_hit_feedback(final_damage: int, is_heavy: bool, source_type: String, lethal: bool) -> void:
	if not is_inside_tree() or source_type == "environmental":
		return
	var col: Color = get_blood_color()
	var spectral: bool = is_spectral()
	var chest: Vector3 = get_chest_position()
	var contact: Vector3 = chest - last_hit_direction * 0.3
	if not lethal:
		var intensity: float = clampf(float(final_damage) / 28.0, 0.45, 1.5) + (0.5 if is_heavy else 0.0)
		# Spray exits away from the blade, fanned sideways like a cut.
		var side: Vector3 = Vector3(last_hit_direction.z, 0.0, -last_hit_direction.x) * randf_range(-0.6, 0.6)
		GoreFXScript.blood_burst(self, contact, last_hit_direction + side, intensity, col, spectral)
		GameFeelScript.play_sound(self, "splat", contact, -9.0 if not is_heavy else -4.0, 1.1)
		if is_heavy:
			GameFeelScript.play_sound(self, "bone_crunch", contact, -6.0, 1.0)
	_hit_flash(Color(1.0, 0.95, 0.9, 0.85) if not spectral else Color(0.7, 1.0, 1.0, 0.9), 0.07 if not is_heavy else 0.11)
	_update_wound_fx()


## Virtual: subclasses (e.g. EnemyAI telegraph overlay) reject stale overlays whose effect already ended.
func _is_overlay_still_valid(mat: Material) -> bool:
	return mat != null


## Additive white overlay for a few frames (restores whatever overlay was there if still valid).
func _hit_flash(color: Color, duration: float) -> void:
	var vis: Node3D = get_node_or_null(visual_root_path) as Node3D
	if vis == null:
		return
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.albedo_color = color
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(vis, meshes)
	for mi in meshes:
		if mi.material_overlay != _flash_mat:
			_flash_previous[mi] = mi.material_overlay
		mi.material_overlay = _flash_mat
	_flash_serial += 1
	var serial: int = _flash_serial
	get_tree().create_timer(duration, true, false, true).timeout.connect(func() -> void:
		if not is_instance_valid(self) or serial != _flash_serial:
			return
		for mi2 in meshes:
			if is_instance_valid(mi2) and mi2.material_overlay == _flash_mat:
				var restore: Material = _flash_previous.get(mi2, null) as Material
				if restore != null and not _is_overlay_still_valid(restore):
					restore = null
				mi2.material_overlay = restore
		_flash_previous.clear()
	)


func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		if c is CPUParticles3D:
			continue
		_collect_mesh_instances(c, out)


## Badly wounded enemies drip continuously.
func _update_wound_fx() -> void:
	var hurt_ratio: float = 1.0 - float(health) / maxf(1.0, float(max_health))
	if hurt_ratio < 0.45 or is_dead:
		return
	var vis: Node3D = get_node_or_null(visual_root_path) as Node3D
	if vis == null:
		return
	if _wound_fx == null or not is_instance_valid(_wound_fx):
		_wound_fx = CPUParticles3D.new()
		_wound_fx.name = "WoundDrip"
		_wound_fx.amount = 6
		_wound_fx.lifetime = 0.7
		_wound_fx.local_coords = false
		var m := SphereMesh.new()
		m.radius = 0.025
		m.height = 0.05
		m.radial_segments = 6
		m.rings = 3
		var mat := StandardMaterial3D.new()
		mat.albedo_color = get_blood_color()
		mat.roughness = 0.2
		if is_spectral():
			mat.emission_enabled = true
			mat.emission = get_blood_color()
			mat.emission_energy_multiplier = 2.0
		m.material = mat
		_wound_fx.mesh = m
		_wound_fx.direction = Vector3.DOWN
		_wound_fx.spread = 25.0
		_wound_fx.initial_velocity_min = 0.1
		_wound_fx.initial_velocity_max = 0.6
		_wound_fx.gravity = Vector3(0.0, -12.0, 0.0)
		_wound_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_wound_fx.emission_sphere_radius = 0.18
		vis.add_child(_wound_fx)
		_wound_fx.position = Vector3(0.0, 1.0, 0.0)
	_wound_fx.amount = clampi(int(4.0 + hurt_ratio * 14.0), 4, 18)
	_wound_fx.emitting = true


func _clear_wound_fx() -> void:
	if _wound_fx != null and is_instance_valid(_wound_fx):
		_wound_fx.queue_free()
	_wound_fx = null


func _on_shield_deflected_fx(is_heavy: bool) -> void:
	if not is_inside_tree():
		return
	var contact: Vector3 = get_chest_position() - last_hit_direction * 0.55
	GoreFXScript.sparks(self, contact, -last_hit_direction, Color(1.0, 0.82, 0.4), 40 if is_heavy else 26)
	GameFeelScript.play_sound(self, "clang", contact, 0.0 if is_heavy else -3.0, 0.85 if is_heavy else 1.05)
	if _last_attacker != null and is_instance_valid(_last_attacker) and _last_attacker.has_method("on_attack_deflected"):
		_last_attacker.call("on_attack_deflected", is_heavy, contact)


## Explodes the rig into posed physics gibs with a blood fountain and a floor pool.
func _spawn_death_gore(source_type: String) -> void:
	if not is_inside_tree():
		return
	var col: Color = get_blood_color()
	var spectral: bool = is_spectral()
	var chest: Vector3 = get_chest_position()
	var force: float = 3.2
	match source_type:
		"player_heavy":
			force = 7.5
		"player_landing":
			force = 8.5
		"environmental":
			force = 1.5
		_:
			force = 4.2 if not last_hit_heavy else 7.0
	var model: Node3D = get_node_or_null(NodePath(String(visual_root_path) + "/ModelRoot")) as Node3D
	var gibs: int = 0
	if gib_on_death and model != null:
		gibs = GoreFXScript.dismember(self, model, last_hit_direction, force, col, spectral)
	GoreFXScript.blood_burst(self, chest, last_hit_direction, 2.4, col, spectral)
	GoreFXScript.blood_burst(self, chest + Vector3.UP * 0.35, Vector3.UP + last_hit_direction * 0.4, 1.4, col, spectral)
	GoreFXScript.blood_decal(self, global_position, randf_range(1.3, 1.9), col, 0.25)
	if spectral:
		GoreFXScript.flash_light(self, chest, col, 5.0, 0.35, 5.0)
	GameFeelScript.play_sound(self, "gib_burst", chest, 0.0, 1.0 if gibs > 0 else 1.2)
	GameFeelScript.play_sound(self, "bone_crunch", chest, -2.0, 0.8)
	GameFeelScript.add_trauma(self, 0.18, chest)


func _die(source_type: String) -> void:
	if is_dead:
		return
	is_dead = true

	var hb: Hitbox3D = get_attack_hitbox()
	if hb != null:
		hb.end_swing()

	_clear_wound_fx()
	_spawn_death_gore(source_type)

	var in_mirror: bool = false
	if RealmManager.instance != null and not RealmManager.instance.is_merged:
		in_mirror = (RealmManager.instance.current_realm == RealmManager.Realm.MIRROR)
	var is_env: bool = (source_type == "environmental")

	if award_standard_kill_score:
		var run_state: Node = _get_run_state()
		if run_state != null and run_state.has_method("record_enemy_kill"):
			run_state.call("record_enemy_kill", get_enemy_unique_id(), in_mirror, is_env)

	if RealmManager.instance != null and RealmManager.instance.has_method("add_mirror_charge"):
		RealmManager.instance.call("add_mirror_charge", get_mirror_kill_refill())

	if not encounter_id.is_empty() and EncounterDirector.instance != null:
		EncounterDirector.instance.register_enemy_kill(encounter_id)

	_refresh_active_state()
	var context: Dictionary = {
		"enemy_id": get_enemy_unique_id(),
		"in_mirror": in_mirror,
		"is_environmental": is_env,
		"source_type": source_type,
	}
	died.emit(self, context)


func get_mirror_kill_refill() -> float:
	var min_hp: float = 70.0 * HEALTH_SCALE
	var max_hp: float = 260.0 * HEALTH_SCALE
	var t: float = clampf((float(max_health) - min_hp) / maxf(1.0, max_hp - min_hp), 0.0, 1.0)
	var min_refill: float = 5.0
	var max_refill: float = 30.0
	if RealmManager.instance != null:
		var rmin: Variant = RealmManager.instance.get("mirror_kill_refill_min")
		var rmax: Variant = RealmManager.instance.get("mirror_kill_refill_max")
		if rmin != null:
			min_refill = float(rmin)
		if rmax != null:
			max_refill = float(rmax)
	return lerpf(min_refill, max_refill, t)


func _refresh_active_state() -> void:
	var should_be_active: bool = is_section_enabled and is_realm_enabled and not is_dead and not is_wave_held
	is_active = should_be_active

	visible = should_be_active
	var vis_root: Node3D = get_node_or_null(visual_root_path) as Node3D
	if vis_root != null:
		vis_root.visible = should_be_active

	set_physics_process(should_be_active)
	set_process(should_be_active)

	for child in get_children():
		if child is CollisionShape3D:
			var cs: CollisionShape3D = child as CollisionShape3D
			cs.set_deferred("disabled", not should_be_active)

	var hurtbox: Hurtbox3D = get_hurtbox()
	if hurtbox != null:
		hurtbox.is_invulnerable = not should_be_active
		# Deferred only: this runs inside physics signal flushes (death mid-swing); is_invulnerable above
		# already blocks hits immediately.
		hurtbox.set_deferred("monitorable", should_be_active)

	if not should_be_active:
		var hitbox: Hitbox3D = get_attack_hitbox()
		if hitbox != null:
			hitbox.end_swing()

	realm_activity_changed.emit(should_be_active)


func _on_manager_realm_changed(new_realm: int) -> void:
	var merged: bool = bool(RealmManager.instance.is_merged) if RealmManager.instance != null else false
	evaluate_for_realm(new_realm, merged)


func _on_manager_realms_merged() -> void:
	evaluate_for_realm(0, true)


func set_wave_held(held: bool) -> void:
	is_wave_held = held
	_refresh_active_state()


func _on_section_reset_requested(reset_sec_id: int) -> void:
	if reset_sec_id == section_id:
		reset_enemy()


func _get_run_state() -> Node:
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		return get_tree().root.get_node_or_null("RunState")
	return null
