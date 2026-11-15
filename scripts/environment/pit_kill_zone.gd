class_name PitKillZone
extends Area3D
## Kill-plane volume positioned below chasms (Stage 01 Entry Gap and Stage 03 Collapsed Gallery Chasm).
## Forces immediate lethal damage and checkpoint respawn when the player falls below `kill_y_threshold`,
## preventing infinite falling (`Y -> -infinity`).

signal pit_fall_triggered(actor: Node)

@export var kill_y_threshold: float = -3.5
@export var half_extents: Vector3 = Vector3(8.0, 2.5, 6.0)
@export var check_position_bounds_each_frame: bool = true


func _ready() -> void:
	add_to_group("pit_kill_zone")
	collision_layer = 0
	collision_mask = RealmManager.LAYER_PLAYER | RealmManager.LAYER_ENEMY
	monitoring = true
	monitorable = false
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _physics_process(_delta: float) -> void:
	if not check_position_bounds_each_frame or get_tree() == null:
		return
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and p is Node3D:
			var p3d: Node3D = p as Node3D
			if is_point_inside_zone(p3d.global_position):
				trigger_pit_death(p)


func is_point_inside_zone(world_pos: Vector3) -> bool:
	if world_pos.y > kill_y_threshold:
		return false
	var local_delta: Vector3 = world_pos - global_position
	return (
		absf(local_delta.x) <= half_extents.x
		and absf(local_delta.y) <= half_extents.y
		and absf(local_delta.z) <= half_extents.z
	)


func trigger_pit_death(actor: Node) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false

	if actor is PlayerController:
		var pc: PlayerController = actor as PlayerController
		if pc.current_state == PlayerController.State.DEAD:
			return false
		# Clear any dodge i-frames so falling into a bottomless chasm is always lethal
		var hb: Hurtbox3D = pc.get_hurtbox()
		if hb != null:
			hb.is_invulnerable = false
		if pc.current_state == PlayerController.State.DODGE:
			pc.current_state = PlayerController.State.LOCOMOTION
		pc.apply_damage(maxi(9999, pc.health), self)
		pit_fall_triggered.emit(pc)
		return true

	if actor is EnemyBase:
		var eb: EnemyBase = actor as EnemyBase
		if eb.is_dead:
			return false
		eb.apply_damage(maxi(9999, eb.health), true, "environmental", self)
		pit_fall_triggered.emit(eb)
		return true

	if actor.has_method("apply_damage"):
		actor.call("apply_damage", 9999, self)
		pit_fall_triggered.emit(actor)
		return true

	return false


func _on_body_entered(body: Node3D) -> void:
	trigger_pit_death(body)
