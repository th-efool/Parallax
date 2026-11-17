class_name RealmManager
extends Node
## Authoritative owner of active realm (Reality vs Mirror).
## Performs floor-support and overlap physics checks before shifting, swaps collision masks, and coordinates Boss Phase 2 realm merge.

enum Realm {
	REALITY = 0,
	MIRROR = 1,
}

signal realm_changed(new_realm: int)
signal shift_rejected(reason: String)
signal realms_merged()
signal shift_cooldown_updated(remaining: float, duration: float)

const LAYER_PLAYER: int = 1 << 0
const LAYER_ENEMY: int = 1 << 1
const LAYER_WORLD_SHARED: int = 1 << 2
const LAYER_WORLD_REALITY: int = 1 << 3
const LAYER_WORLD_MIRROR: int = 1 << 4
const LAYER_INTERACTABLE: int = 1 << 5
const LAYER_HITBOX: int = 1 << 6
## Layer 8: invisible movement blockers above low parapets/balustrades. Player + enemies collide with it;
## the camera SpringArm (mask = layers 3/4/5) deliberately ignores it so it never snaps in at railings.
const LAYER_PLAYER_BLOCKER: int = 1 << 7

@export var shift_cooldown_duration: float = 0.60
@export var floor_check_distance: float = 1.60
@export var require_floor_support: bool = true
@export var handle_input_directly: bool = true
@export var player_capsule_radius: float = 0.38
@export var player_capsule_height: float = 1.75

static var instance = null

var current_realm: Realm = Realm.REALITY
var shift_locked: bool = false
var is_merged: bool = false
var cooldown_timer: float = 0.0
var player_ref: CharacterBody3D = null


func _enter_tree() -> void:
	instance = self
	add_to_group("realm_manager")


func _exit_tree() -> void:
	player_ref = null
	if instance == self:
		instance = null


func _ready() -> void:
	call_deferred("_sync_all_realm_nodes")


func _process(delta: float) -> void:
	if cooldown_timer > 0.0:
		cooldown_timer = maxf(0.0, cooldown_timer - delta)
		shift_cooldown_updated.emit(cooldown_timer, shift_cooldown_duration)


func _unhandled_input(event: InputEvent) -> void:
	if not handle_input_directly:
		return
	if event.is_action_pressed("dimension_shift"):
		# Inside the critical-hit window Q is the Mirror Break finisher, not a realm shift.
		if player_ref != null and player_ref.has_method("is_finisher_window_open") and bool(player_ref.call("is_finisher_window_open")):
			return
		if request_shift():
			get_viewport().set_input_as_handled()


func register_player(player: CharacterBody3D) -> void:
	player_ref = player
	if player_ref != null:
		update_actor_collision_mask(player_ref, current_realm)


func get_realm_world_mask(target: Realm) -> int:
	if is_merged:
		return LAYER_WORLD_SHARED | LAYER_WORLD_REALITY | LAYER_WORLD_MIRROR
	if target == Realm.REALITY:
		return LAYER_WORLD_SHARED | LAYER_WORLD_REALITY
	return LAYER_WORLD_SHARED | LAYER_WORLD_MIRROR


func update_actor_collision_mask(body: CollisionObject3D, target: Realm) -> void:
	if body == null:
		return
	var cleared_mask: int = body.collision_mask & ~(LAYER_WORLD_SHARED | LAYER_WORLD_REALITY | LAYER_WORLD_MIRROR)
	body.collision_mask = cleared_mask | get_realm_world_mask(target)


func can_shift_to_realm(target: Realm) -> bool:
	var check: Dictionary = _check_shift_safety(target)
	return bool(check.get("safe", false))


func request_shift() -> bool:
	var target: Realm = Realm.MIRROR if current_realm == Realm.REALITY else Realm.REALITY
	var safety: Dictionary = _check_shift_safety(target)
	if not bool(safety.get("safe", false)):
		shift_rejected.emit(String(safety.get("reason", "unsafe")))
		return false

	current_realm = target
	cooldown_timer = shift_cooldown_duration
	shift_cooldown_updated.emit(cooldown_timer, shift_cooldown_duration)

	var p: CharacterBody3D = _resolve_player()
	if p != null:
		update_actor_collision_mask(p, current_realm)

	_sync_all_realm_nodes()
	realm_changed.emit(current_realm)
	return true


func force_realm(target: Realm, lock_shift: bool = false) -> void:
	is_merged = false
	shift_locked = lock_shift
	current_realm = target
	cooldown_timer = 0.0
	var p: CharacterBody3D = _resolve_player()
	if p != null:
		update_actor_collision_mask(p, current_realm)
	_sync_all_realm_nodes()
	realm_changed.emit(current_realm)


func force_merge_realms() -> void:
	is_merged = true
	shift_locked = true
	current_realm = Realm.REALITY
	cooldown_timer = 0.0
	var p: CharacterBody3D = _resolve_player()
	if p != null:
		update_actor_collision_mask(p, current_realm)
	_sync_all_realm_nodes()
	realms_merged.emit()


func _check_shift_safety(target: Realm) -> Dictionary:
	if shift_locked or is_merged:
		return {"safe": false, "reason": "locked"}
	if get_tree() != null and get_tree().paused:
		return {"safe": false, "reason": "paused"}
	if cooldown_timer > 0.0:
		return {"safe": false, "reason": "cooldown"}

	var p: CharacterBody3D = _resolve_player()
	if p == null or not p.is_inside_tree() or p.get_world_3d() == null:
		return {"safe": true, "reason": "ok"}

	var space_state: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	if space_state == null:
		return {"safe": true, "reason": "ok"}

	var target_only_layer: int = LAYER_WORLD_REALITY if target == Realm.REALITY else LAYER_WORLD_MIRROR

	# 1. Penetration / Overlap Check against destination realm geometry
	var capsule := CapsuleShape3D.new()
	capsule.radius = player_capsule_radius
	capsule.height = player_capsule_height

	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = capsule
	shape_query.transform = Transform3D(Basis.IDENTITY, p.global_position + Vector3(0.0, player_capsule_height * 0.5 + 0.05, 0.0))
	shape_query.collision_mask = target_only_layer
	shape_query.exclude = [p.get_rid()]

	var overlaps: Array[Dictionary] = space_state.intersect_shape(shape_query, 1)
	if not overlaps.is_empty():
		return {"safe": false, "reason": "overlap"}

	# 2. Destination Floor-Support Check (never drop the floor out from beneath the player)
	if require_floor_support:
		var ray_origin: Vector3 = p.global_position + Vector3(0.0, 0.25, 0.0)
		var ray_end: Vector3 = ray_origin + Vector3.DOWN * floor_check_distance
		var ray_query := PhysicsRayQueryParameters3D.create(
			ray_origin,
			ray_end,
			get_realm_world_mask(target),
			[p.get_rid()]
		)
		var floor_hit: Dictionary = space_state.intersect_ray(ray_query)
		if floor_hit.is_empty():
			return {"safe": false, "reason": "no_floor"}

	return {"safe": true, "reason": "ok"}


func _resolve_player() -> CharacterBody3D:
	if is_instance_valid(player_ref):
		return player_ref
	if get_tree() != null:
		var found: Node = get_tree().get_first_node_in_group("player")
		if found is CharacterBody3D:
			player_ref = found as CharacterBody3D
			return player_ref
	return null


func _sync_all_realm_nodes() -> void:
	if get_tree() == null:
		return
	for node in get_tree().get_nodes_in_group("realm_reactive"):
		if node != null and node.has_method("evaluate_for_realm"):
			node.call("evaluate_for_realm", current_realm, is_merged)
