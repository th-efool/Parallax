class_name SkeletonGuard
extends EnemyAI
## Stage 02 Hall of Echoes melee combatant.
## On first non-environmental/non-execution kill, collapses into scattered bones on the floor,
## then after a random 3-7 s delay magnetically rejoins its bones and stands back up at FULL health.
## Emits `mirror_hint_requested` on first Hall of Echoes permanent Skeleton kill.

signal mirror_hint_requested()

var _first_hall_skeleton_hint_emitted: bool = false
var _has_revived: bool = false
var _is_reassembling: bool = false
var _reassemble_timer: float = 0.0
var _reassemble_total: float = 0.0
var _bone_parts: Array[Dictionary] = [] # [{"node": MeshInstance3D, "rest": Vector3, "rot": Vector3}]
var _orig_collision_layer: int = -1


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


func _exit_tree() -> void:
	_clear_bone_parts()


func reset_hall_hint_flag() -> void:
	_first_hall_skeleton_hint_emitted = false


func is_hittable_now() -> bool:
	if _is_reassembling:
		return false
	return super.is_hittable_now()


func _on_enemy_reset() -> void:
	_clear_bone_parts()
	_restore_collapsed_state()
	super._on_enemy_reset()
	_first_hall_skeleton_hint_emitted = false
	_has_revived = false
	_is_reassembling = false
	_reassemble_timer = 0.0


func _physics_process(delta: float) -> void:
	if _is_reassembling:
		_tick_reassembly(delta)
		return
	super._physics_process(delta)


func _die(source_type: String) -> void:
	if not _has_revived and source_type not in ["environmental", "pit", "player_execution", "execution"]:
		_has_revived = true
		_revived_this_hit = true
		_begin_collapse_and_reassemble()
		return
	_clear_bone_parts()
	_restore_collapsed_state()
	super._die(source_type)
	if not _first_hall_skeleton_hint_emitted and encounter_id == "hall_of_echoes":
		_first_hall_skeleton_hint_emitted = true
		mirror_hint_requested.emit()


func _begin_collapse_and_reassemble() -> void:
	_is_reassembling = true
	_reassemble_total = randf_range(3.0, 7.0)
	_reassemble_timer = _reassemble_total
	health = 0
	health_changed.emit(0, max_health)
	velocity = Vector3.ZERO
	enter_stunned(_reassemble_total)

	# Hide body & disable hitboxes/colliders while collapsed into a pile of bones.
	if _orig_collision_layer < 0:
		_orig_collision_layer = collision_layer
	collision_layer = 0
	var vis: Node3D = get_node_or_null("VisualRoot") as Node3D
	if vis != null:
		vis.visible = false
	var hp_lbl: Node3D = get_node_or_null("FloatingHPBar") as Node3D
	if hp_lbl != null:
		hp_lbl.visible = false
	var hurt: Area3D = get_node_or_null("Hurtbox3D") as Area3D
	if hurt != null:
		hurt.set_deferred("monitorable", false)
		hurt.set_deferred("monitoring", false)

	_spawn_collapsed_bones()
	if is_inside_tree():
		GoreFXScript.dust_puff(self, global_position + Vector3(0.0, 0.25, 0.0), 0.7, 10, Color(0.75, 0.72, 0.65, 0.6), 1.4)
		GameFeelScript.play_sound(self, "bone_crunch", global_position + Vector3(0.0, 0.8, 0.0), -6.0, randf_range(0.9, 1.1))


func _spawn_collapsed_bones() -> void:
	_clear_bone_parts()
	if not is_inside_tree():
		return
	var host: Node = get_parent() if get_parent() != null else self
	var bone_mat := StandardMaterial3D.new()
	bone_mat.albedo_color = Color(0.86, 0.82, 0.72)
	bone_mat.roughness = 0.78

	var specs: Array = [
		["skull", Vector3(0.24, 0.24, 0.24)],
		["torso", Vector3(0.38, 0.42, 0.22)],
		["limb", Vector3(0.11, 0.52, 0.11)],
		["limb", Vector3(0.11, 0.52, 0.11)],
		["limb", Vector3(0.10, 0.44, 0.10)],
		["limb", Vector3(0.10, 0.44, 0.10)],
		["pelvis", Vector3(0.32, 0.16, 0.20)],
	]
	for i in range(specs.size()):
		var sp: Array = specs[i]
		var mi := MeshInstance3D.new()
		mi.name = "CollapsedBone_%d" % i
		if String(sp[0]) == "skull":
			var sm := SphereMesh.new()
			sm.radius = 0.15
			sm.height = 0.30
			mi.mesh = sm
		else:
			var bm := BoxMesh.new()
			bm.size = sp[1] as Vector3
			mi.mesh = bm
		mi.material_override = bone_mat
		var ang: float = TAU * float(i) / float(specs.size()) + randf_range(-0.35, 0.35)
		var rad: float = randf_range(0.35, 1.15)
		var rest_pos: Vector3 = global_position + Vector3(cos(ang) * rad, 0.12, sin(ang) * rad)
		var rest_rot := Vector3(randf_range(-1.3, 1.3), randf_range(0.0, TAU), randf_range(-1.3, 1.3))
		host.add_child(mi)
		mi.global_position = global_position + Vector3(0.0, 0.9 + randf_range(-0.2, 0.3), 0.0)
		mi.rotation = rest_rot * 0.4
		# Drop/scatter onto the floor over 0.35 s
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "global_position", rest_pos, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "rotation", rest_rot, 0.35)
		_bone_parts.append({"node": mi, "rest": rest_pos, "rot": rest_rot})


func _tick_reassembly(delta: float) -> void:
	_reassemble_timer -= delta
	var rejoin_window: float = 0.85
	if _reassemble_timer <= rejoin_window and _reassemble_timer > 0.0:
		# Magnetically pull all scattered bones back together into the standing silhouette!
		var t: float = clampf(1.0 - (_reassemble_timer / rejoin_window), 0.0, 1.0)
		var ease_t: float = t * t * (3.0 - 2.0 * t)
		var center: Vector3 = global_position + Vector3(0.0, 0.95, 0.0)
		for rec in _bone_parts:
			var mi: MeshInstance3D = rec.get("node") as MeshInstance3D
			if is_instance_valid(mi):
				var rest: Vector3 = rec.get("rest", center) as Vector3
				mi.global_position = rest.lerp(center, ease_t)
				mi.rotation = (rec.get("rot", Vector3.ZERO) as Vector3).lerp(Vector3.ZERO, ease_t)
	if _reassemble_timer <= 0.0:
		_finish_reassembly()


func _finish_reassembly() -> void:
	_is_reassembling = false
	_reassemble_timer = 0.0
	_clear_bone_parts()
	_restore_collapsed_state()
	health = max_health
	health_changed.emit(health, max_health)
	current_state = State.CHASE
	state_changed.emit(current_state)
	if is_inside_tree():
		GoreFXScript.flash_light(self, global_position + Vector3(0.0, 1.1, 0.0), Color(0.55, 0.92, 1.0), 3.5, 0.35, 4.5)
		GameFeelScript.play_sound(self, "bone_crunch", global_position + Vector3(0.0, 1.0, 0.0), -5.0, 1.25)


func _restore_collapsed_state() -> void:
	if _orig_collision_layer >= 0:
		collision_layer = _orig_collision_layer
	var vis: Node3D = get_node_or_null("VisualRoot") as Node3D
	if vis != null:
		vis.visible = true
	var hp_lbl: Node3D = get_node_or_null("FloatingHPBar") as Node3D
	if hp_lbl != null:
		hp_lbl.visible = true
	var hurt: Area3D = get_node_or_null("Hurtbox3D") as Area3D
	if hurt != null:
		hurt.set_deferred("monitorable", true)
		hurt.set_deferred("monitoring", true)


func _clear_bone_parts() -> void:
	for rec in _bone_parts:
		var mi: MeshInstance3D = rec.get("node") as MeshInstance3D
		if is_instance_valid(mi):
			mi.queue_free()
	_bone_parts.clear()
