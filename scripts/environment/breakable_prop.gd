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
@export var fall_zone_offset: Vector3 = Vector3(0.0, 0.0, 2.5)
@export var intact_visual_path: NodePath = NodePath("IntactVisual")
@export var broken_visual_path: NodePath = NodePath("BrokenVisual")

var current_state: PropState = PropState.INTACT
var _warning_timer: float = 0.0


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


func trigger_break(by_heavy_attack: bool = true) -> bool:
	if current_state != PropState.INTACT:
		return false
	if require_heavy_attack and not by_heavy_attack:
		return false

	current_state = PropState.BREAKING
	_warning_timer = warning_duration
	break_warning_started.emit(warning_duration)

	if warning_duration <= 0.0:
		complete_break_now()
	return true


func complete_break_now(explicit_candidates: Array[Node] = []) -> void:
	if current_state == PropState.BROKEN:
		return
	current_state = PropState.BROKEN
	_warning_timer = 0.0
	_sync_visuals_and_colliders()

	if prop_kind == PropKind.CRACKED_PILLAR:
		_apply_pillar_fall_hazard(explicit_candidates)
	elif prop_kind == PropKind.CENTRAL_MIRROR_PLANE:
		if RealmManager.instance != null and not RealmManager.instance.is_merged:
			RealmManager.instance.force_merge_realms()

	prop_broken.emit(self)


func reset_prop() -> void:
	current_state = PropState.INTACT
	_warning_timer = 0.0
	_sync_visuals_and_colliders()


func get_fall_zone_center() -> Vector3:
	return global_position + fall_zone_offset


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
	for node in targets:
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		var n3d: Node3D = node as Node3D
		if n3d.global_position.distance_to(impact_center) > damage_radius:
			continue

		if node.is_in_group("player"):
			if node.has_method("apply_damage"):
				if bool(node.call("apply_damage", player_hazard_damage, self)):
					player_hit = true
		elif node.has_method("apply_damage"):
			var res: Variant = node.call("apply_damage", enemy_hazard_damage, true, "environmental")
			if typeof(res) != TYPE_BOOL or bool(res):
				enemies_hit += 1

	hazard_damage_applied.emit(enemies_hit, player_hit)


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
			cs.disabled = not is_intact
			cs.set_deferred("disabled", not is_intact)
		elif child is StaticBody3D:
			for sub in child.get_children():
				if sub is CollisionShape3D:
					var scs: CollisionShape3D = sub as CollisionShape3D
					scs.disabled = not is_intact
					scs.set_deferred("disabled", not is_intact)
		elif child is Hurtbox3D:
			var hb: Hurtbox3D = child as Hurtbox3D
			hb.monitorable = is_intact
			hb.set_deferred("monitorable", is_intact)
