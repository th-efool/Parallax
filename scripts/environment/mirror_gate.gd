class_name MirrorGate
extends Area3D
## Thin trigger volume on the Warden arena's Central Mirror Plane (Phase 1 only).
## Walking or dodging *through* the glass swaps the player's realm instantly and without the Q cooldown
## (RealmManager.pass_through_mirror). The Warden's thralls also step out of this plane (WardenBoss summons),
## so the divider is both an escape hatch and the spawn wall. Disabled once the plane shatters (Phase 2).

## The BreakableProp this gate belongs to (its parent by default).
@export var plane_path: NodePath = NodePath("..")

var _entry_side: Dictionary = {}   # body instance id -> -1 / +1 (local X side it entered from)

signal player_passed_through(new_realm: int)


func _ready() -> void:
	collision_layer = 0
	collision_mask = RealmManager.LAYER_PLAYER
	monitoring = true
	monitorable = false
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func is_plane_intact() -> bool:
	var plane: BreakableProp = get_node_or_null(plane_path) as BreakableProp
	return plane == null or plane.current_state == BreakableProp.PropState.INTACT


func _side_of(body: Node3D) -> float:
	return signf(to_local(body.global_position).x)


func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		_entry_side[body.get_instance_id()] = _side_of(body)


func _on_body_exited(body: Node3D) -> void:
	if not (body is PlayerController):
		return
	var id: int = body.get_instance_id()
	if not _entry_side.has(id):
		return
	var from_side: float = float(_entry_side[id])
	_entry_side.erase(id)
	var to_side: float = _side_of(body)
	# Far from the glass = a teleport (death respawn, rewind), not a walk-through.
	if absf(to_local(body.global_position).x) > 1.0:
		return
	if from_side == 0.0 or to_side == 0.0 or from_side == to_side:
		return   # stepped in and back out on the same side
	# Deferred: body_exited fires inside the physics flush, and a realm swap toggles collision shapes.
	_cross.call_deferred()


func _cross() -> void:
	if not is_inside_tree() or not is_plane_intact():
		return
	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm == null or not rm.pass_through_mirror():
		return
	if AudioManager.instance != null:
		AudioManager.instance.play_sfx("mirror_whisper", -2.0)
	_ripple_plane()
	player_passed_through.emit(int(rm.current_realm))


## Brief brightening of the obsidian glass so the crossing reads as "you went through the mirror".
func _ripple_plane() -> void:
	var plane: Node = get_node_or_null(plane_path)
	if plane == null:
		return
	var mesh: MeshInstance3D = plane.find_child("MirrorPlaneMesh", true, false) as MeshInstance3D
	if mesh == null or not (mesh.material_override is ShaderMaterial):
		return
	var mat: ShaderMaterial = mesh.material_override as ShaderMaterial
	var base: Variant = mat.get_shader_parameter("surface_alpha")
	if base == null:
		return
	var start: float = float(base)
	var tw: Tween = create_tween()
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("surface_alpha", v), minf(1.0, start + 0.35), start, 0.5).set_trans(Tween.TRANS_SINE)
