class_name BreakableProp
extends Node3D
## Deterministic authored breakable prop:
## - Cracked Central Pillar (Stage 02): requires Heavy Attack (`RMB`), 0.6s warning telegraph, northward 2.5m fall zone (150 enemy dmg / 40 player dmg).
## - Weak Stone Support (Stage 03): requires Heavy Attack (`RMB`), collapses to reveal Bridge Anchor Switch.
## - Central Mirror Plane (Stage 05): shatters at Warden <= 500 HP, merges realms.

enum PropState {
	INTACT = 0,
	BREAKING = 1,
	BROKEN = 2,
}

enum PropKind {
	CRACKED_PILLAR = 0,
	WEAK_STONE_SUPPORT = 1,
	CENTRAL_MIRROR_PLANE = 2,
	GENERIC_CRATE = 3,
}

signal break_warning_started(warning_sec: float)
signal prop_broken(prop: BreakableProp)
signal hazard_damage_applied(enemies_hit: int, player_hit: bool)

@export var prop_kind: PropKind = PropKind.CRACKED_PILLAR
@export var section_id: int = 1
@export var require_heavy_attack: bool = true
@export var warning_duration: float = 0.60
@export var enemy_hazard_damage: int = 150
@export var player_hazard_damage: int = 40
@export var damage_radius: float = 2.5
@export var splash_radius: float = 6.0
@export var fall_zone_offset: Vector3 = Vector3(0.0, 0.0, 2.5)
## Directional knock: the prop falls AWAY from whoever struck it and the hazard covers the whole fall line
## (segment of `knock_fall_length`, half-width `damage_radius`) instead of a fixed circle.
@export var knock_directional: bool = false
@export var knock_fall_length: float = 9.0
@export var intact_visual_path: NodePath = NodePath("IntactVisual")
@export var broken_visual_path: NodePath = NodePath("BrokenVisual")

@export_group("Shatter Fragments (Central Mirror Plane)")
@export var spawn_shatter_fragments: bool = true
@export var shatter_extent: Vector3 = Vector3(0.12, 5.5, 22.0)
@export var shatter_center_offset: Vector3 = Vector3(0.0, 2.75, 0.0)
@export var shatter_fragment_count: int = 28
@export var shatter_fragment_lifetime: float = 4.0

const CombatVFXScript := preload("res://scripts/core/combat_vfx.gd")
const PILLAR_COLLAPSE_TRAUMA: float = 0.75

var current_state: PropState = PropState.INTACT
var _warning_timer: float = 0.0
var _fragments: Array[Node] = []
var _topple: Node3D = null
var _fragment_mat: StandardMaterial3D = null


func _ready() -> void:
	add_to_group("breakable")
	if EncounterDirector.instance != null:
		if not EncounterDirector.instance.section_reset_requested.is_connected(_on_section_reset_requested):
			EncounterDirector.instance.section_reset_requested.connect(_on_section_reset_requested)
	_sync_visuals_and_colliders()


func _process(delta: float) -> void:
	if current_state == PropState.BREAKING and _warning_timer > 0.0:
		_warning_timer = maxf(0.0, _warning_timer - delta)
		if _warning_timer <= 0.0:
			complete_break_now()


func trigger_break(by_heavy_attack: bool = true, knocker: Node = null) -> bool:
	if prop_kind == PropKind.CENTRAL_MIRROR_PLANE:
		return false
	if current_state != PropState.INTACT:
		return false
	if require_heavy_attack and not by_heavy_attack:
		return false
	if knock_directional:
		_aim_knock(knocker)

	current_state = PropState.BREAKING
	_warning_timer = warning_duration
	if prop_kind == PropKind.CRACKED_PILLAR and warning_duration > 0.0:
		_start_topple(warning_duration)
	break_warning_started.emit(warning_duration)

	if warning_duration <= 0.0:
		complete_break_now()
	return true


func complete_break_now(explicit_candidates: Array[Node] = [], apply_hazard: bool = true) -> void:
	if current_state == PropState.BROKEN:
		return
	current_state = PropState.BROKEN
	_warning_timer = 0.0
	_clear_topple()
	_sync_visuals_and_colliders()

	if prop_kind == PropKind.CRACKED_PILLAR:
		if apply_hazard:
			_apply_pillar_fall_hazard(explicit_candidates)
			_emit_collapse_feedback()
	elif prop_kind == PropKind.CENTRAL_MIRROR_PLANE:
		_spawn_shatter_fragments()
		if RealmManager.instance != null and not RealmManager.instance.is_merged:
			RealmManager.instance.force_merge_realms()

	prop_broken.emit(self)


func reset_prop() -> void:
	current_state = PropState.INTACT
	_warning_timer = 0.0
	_clear_fragments()
	_clear_topple()
	_sync_visuals_and_colliders()


func _start_topple(duration: float) -> void:
	## Cosmetic only: a copy of the intact column tips over along `fall_zone_offset` during the warning
	## window, landing exactly when the hazard damage resolves. Gameplay timing is unchanged.
	var intact: Node3D = get_node_or_null(intact_visual_path) as Node3D
	if intact == null or not is_inside_tree():
		return
	_clear_topple()
	var pivot := Node3D.new()
	pivot.name = "ToppleCosmetic"
	add_child(pivot)
	var copy: Node3D = intact.duplicate() as Node3D
	copy.visible = true
	pivot.add_child(copy)
	intact.visible = false
	var fall_dir: Vector3 = Vector3(fall_zone_offset.x, 0.0, fall_zone_offset.z)
	if fall_dir.length_squared() < 0.0001:
		fall_dir = Vector3(0, 0, 1)
	fall_dir = fall_dir.normalized()
	var axis: Vector3 = Vector3.UP.cross(fall_dir).normalized()
	_topple = pivot
	var tw := pivot.create_tween()
	tw.tween_method(func(t: float) -> void:
		if is_instance_valid(pivot):
			pivot.basis = Basis(axis, t * PI * 0.5)
	, 0.0, 1.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _clear_topple() -> void:
	if _topple != null and is_instance_valid(_topple):
		_topple.queue_free()
	_topple = null


func _spawn_shatter_fragments() -> void:
	## Claude Pass B: purely cosmetic glass shards. Layer 0 (collide with nothing, nothing collides with them),
	## mask = World_Shared only so they land on the arena floor, then shrink away and free themselves.
	if not spawn_shatter_fragments or not is_inside_tree() or get_tree() == null:
		return
	_clear_fragments()
	var host: Node = get_parent() if get_parent() != null else self
	if _fragment_mat == null:
		_fragment_mat = StandardMaterial3D.new()
		_fragment_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_fragment_mat.albedo_color = Color(0.04, 0.06, 0.11, 0.85)
		_fragment_mat.metallic = 0.9
		_fragment_mat.roughness = 0.05
		_fragment_mat.emission_enabled = true
		_fragment_mat.emission = Color(0.18, 0.48, 1.0)
		_fragment_mat.emission_energy_multiplier = 0.8
		_fragment_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var count: int = maxi(1, shatter_fragment_count)
	var rows: int = 4
	var cols: int = int(ceil(float(count) / float(rows)))
	for i in range(count):
		var col: int = i % cols
		var row: int = i / cols
		var local := shatter_center_offset + Vector3(
			0.0,
			lerpf(-shatter_extent.y * 0.42, shatter_extent.y * 0.42, (float(row) + 0.5) / float(rows)),
			lerpf(-shatter_extent.z * 0.45, shatter_extent.z * 0.45, (float(col) + 0.5) / float(cols))
		)
		var s: float = rng.randf_range(0.45, 1.05)
		var frag_size := Vector3(0.06, s, s * rng.randf_range(0.5, 0.9))

		var rb := RigidBody3D.new()
		rb.name = "MirrorShard_%d" % i
		rb.collision_layer = 0
		rb.collision_mask = RealmManager.LAYER_WORLD_SHARED
		rb.mass = 1.5
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = frag_size
		cs.shape = box
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.name = "ShardMesh"
		var bm := BoxMesh.new()
		bm.size = frag_size
		mi.mesh = bm
		mi.material_override = _fragment_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rb.add_child(mi)
		host.add_child(rb)
		rb.global_position = to_global(local + Vector3(rng.randf_range(-0.05, 0.05), rng.randf_range(-0.2, 0.2), rng.randf_range(-0.3, 0.3)))
		rb.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-PI, PI), rng.randf_range(-0.6, 0.6))
		var side: float = 1.0 if (i % 2 == 0) else -1.0
		rb.linear_velocity = global_transform.basis * Vector3(side * rng.randf_range(2.0, 5.5), rng.randf_range(0.5, 3.5), rng.randf_range(-1.5, 1.5))
		rb.angular_velocity = Vector3(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
		_fragments.append(rb)

		var tw := rb.create_tween()
		tw.tween_interval(shatter_fragment_lifetime)
		tw.tween_property(mi, "scale", Vector3.ZERO, 0.6)
		tw.tween_callback(rb.queue_free)

	CombatVFXScript.spawn_impact_burst(host, to_global(shatter_center_offset), true, true, 2.5)


func _clear_fragments() -> void:
	for f in _fragments:
		if is_instance_valid(f):
			f.queue_free()
	_fragments.clear()


func get_fall_zone_center() -> Vector3:
	return global_position + fall_zone_offset


## Points the fall away from the striker; the rubble (BrokenVisual, authored falling toward +Z) turns with it.
func _aim_knock(knocker: Node) -> void:
	var dir := Vector3(0.0, 0.0, 1.0)
	if knocker is Node3D and is_inside_tree():
		var d: Vector3 = global_position - (knocker as Node3D).global_position
		d.y = 0.0
		if d.length() > 0.05:
			dir = d.normalized()
	fall_zone_offset = dir * knock_fall_length * 0.5
	var broken_vis: Node3D = get_node_or_null(broken_visual_path) as Node3D
	if broken_vis != null:
		broken_vis.rotation.y = atan2(dir.x, dir.z)


func _distance_to_fall_line(p: Vector3) -> float:
	if absf(p.y - global_position.y) >= 4.0:
		return INF
	var a := Vector2(global_position.x, global_position.z)
	var off := Vector2(fall_zone_offset.x, fall_zone_offset.z) * 2.0
	var q := Vector2(p.x, p.z)
	var t: float = clampf((q - a).dot(off) / maxf(off.length_squared(), 0.0001), 0.0, 1.0)
	return q.distance_to(a + off * t)


func _in_fall_line(p: Vector3) -> bool:
	return _distance_to_fall_line(p) <= damage_radius


func _apply_pillar_fall_hazard(explicit_candidates: Array[Node] = []) -> void:
	var impact_center: Vector3 = get_fall_zone_center()
	var targets: Array[Node] = []
	if not explicit_candidates.is_empty():
		targets = explicit_candidates
	elif get_tree() != null:
		for e in get_tree().get_nodes_in_group("enemy"):
			targets.append(e)
		for p in get_tree().get_nodes_in_group("player"):
			targets.append(p)

	var enemies_hit: int = 0
	var player_hit: bool = false
	var outer_r: float = damage_radius + maxf(0.0, splash_radius)
	for node in targets:
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		var n3d: Node3D = node as Node3D
		var dist: float = _distance_to_fall_line(n3d.global_position) if knock_directional else n3d.global_position.distance_to(impact_center)
		if dist > outer_r:
			continue

		if node.is_in_group("player"):
			# Only direct crush under the pillar hurts the player, not the outer shockwave.
			if dist <= damage_radius and node.has_method("apply_damage"):
				if bool(node.call("apply_damage", player_hazard_damage, self)):
					player_hit = true
		elif node.has_method("apply_damage"):
			var dmg: int = enemy_hazard_damage
			var is_splash: bool = dist > damage_radius
			if is_splash:
				var falloff: float = clampf((dist - damage_radius) / maxf(0.01, splash_radius), 0.0, 1.0)
				dmg = maxi(1, int(round(lerpf(float(enemy_hazard_damage) * 0.55, float(enemy_hazard_damage) * 0.25, falloff))))
			var res: Variant = node.call("apply_damage", dmg, true, "environmental")
			if typeof(res) != TYPE_BOOL or bool(res):
				enemies_hit += 1
				if is_splash and node.has_method("enter_stunned") and not bool(node.get("is_dead")):
					node.call("enter_stunned", 1.2)

	hazard_damage_applied.emit(enemies_hit, player_hit)


func _emit_collapse_feedback() -> void:
	## Claude Pass A: pillar collapse camera trauma (+0.75 at the impact, attenuated with distance) and debris burst.
	if not is_inside_tree() or get_tree() == null:
		return
	var impact: Vector3 = get_fall_zone_center()
	for p in get_tree().get_nodes_in_group("player"):
		if p is Node3D and p.has_method("add_camera_trauma"):
			var dist: float = (p as Node3D).global_position.distance_to(impact)
			var falloff: float = clampf(1.0 - maxf(0.0, dist - 4.0) / 18.0, 0.25, 1.0)
			p.call("add_camera_trauma", PILLAR_COLLAPSE_TRAUMA * falloff)
	var host: Node = get_parent() if get_parent() != null else self
	CombatVFXScript.spawn_impact_burst(host, impact + Vector3(0.0, 0.4, 0.0), false, true, 1.8)


func _on_section_reset_requested(reset_section_id: int) -> void:
	if reset_section_id == section_id:
		reset_prop()


func _sync_visuals_and_colliders() -> void:
	var is_intact: bool = (current_state != PropState.BROKEN)
	var intact_vis: Node3D = get_node_or_null(intact_visual_path) as Node3D
	var broken_vis: Node3D = get_node_or_null(broken_visual_path) as Node3D
	if intact_vis != null:
		intact_vis.visible = is_intact
	if broken_vis != null:
		broken_vis.visible = not is_intact

	for child in get_children():
		if child is CollisionShape3D:
			var cs: CollisionShape3D = child as CollisionShape3D
			cs.set_deferred("disabled", not is_intact)
		elif child is StaticBody3D:
			for sub in child.get_children():
				if sub is CollisionShape3D:
					var scs: CollisionShape3D = sub as CollisionShape3D
					scs.set_deferred("disabled", not is_intact)
		elif child is Hurtbox3D:
			var hb: Hurtbox3D = child as Hurtbox3D
			hb.set_deferred("monitorable", is_intact)  # may run inside a physics signal flush

	# Debris colliders living under the broken visual are solid only once the prop is broken.
	if broken_vis != null:
		_set_debris_colliders(broken_vis, not is_intact)


func _set_debris_colliders(node: Node, enabled: bool) -> void:
	for sub in node.get_children():
		if sub is CollisionShape3D:
			var cs: CollisionShape3D = sub as CollisionShape3D
			cs.set_deferred("disabled", not enabled)
		_set_debris_colliders(sub, enabled)
