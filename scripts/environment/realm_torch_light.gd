class_name RealmTorchLight
extends OmniLight3D
## Cosmetic wall-sconce light (Claude Pass B). Reality: warm ember torch with lively flicker.
## Mirror: cold cobalt crystal sconce with a slow, steady shimmer. Merged: violet blend.
## Optionally tints a flame/crystal `flame_mesh_path` emissive material to match.

@export var reality_color: Color = Color(1.0, 0.58, 0.22, 1.0)
@export var mirror_color: Color = Color(0.32, 0.62, 1.0, 1.0)
@export var merged_color: Color = Color(0.78, 0.52, 0.95, 1.0)
@export var base_energy: float = 1.6
@export var reality_flicker: float = 0.28
@export var mirror_flicker: float = 0.08
@export var flame_mesh_path: NodePath

var _t: float = 0.0
var _seed: float = 0.0
var _flicker_amount: float = 0.28
var _flame_mat: StandardMaterial3D = null


func _ready() -> void:
	add_to_group("realm_torch_light")
	_seed = float(get_instance_id() % 997) * 0.37
	shadow_enabled = false
	var flame: MeshInstance3D = get_node_or_null(flame_mesh_path) as MeshInstance3D
	if flame != null and flame.material_override is StandardMaterial3D:
		_flame_mat = flame.material_override as StandardMaterial3D
	var rm: Node = get_tree().get_first_node_in_group("realm_manager") if get_tree() != null else null
	if rm != null:
		if not rm.is_connected("realm_changed", _on_realm_changed):
			rm.connect("realm_changed", _on_realm_changed)
		if not rm.is_connected("realms_merged", _on_realms_merged):
			rm.connect("realms_merged", _on_realms_merged)
		_apply_realm(int(rm.get("current_realm")), bool(rm.get("is_merged")))
	else:
		_apply_realm(0, false)


func _process(delta: float) -> void:
	_t += delta
	var n: float = sin(_t * 11.0 + _seed) * 0.5 + sin(_t * 17.3 + _seed * 2.1) * 0.3 + sin(_t * 5.1 + _seed * 0.7) * 0.2
	light_energy = base_energy * (1.0 + n * _flicker_amount)


func _on_realm_changed(new_realm: int) -> void:
	var rm: Node = get_tree().get_first_node_in_group("realm_manager") if get_tree() != null else null
	var merged: bool = bool(rm.get("is_merged")) if rm != null else false
	_apply_realm(new_realm, merged)


func _on_realms_merged() -> void:
	_apply_realm(0, true)


func _apply_realm(active_realm: int, merged: bool) -> void:
	var col: Color = reality_color
	_flicker_amount = reality_flicker
	if merged:
		col = merged_color
		_flicker_amount = (reality_flicker + mirror_flicker) * 0.5
	elif active_realm == 1:
		col = mirror_color
		_flicker_amount = mirror_flicker
	light_color = col
	if _flame_mat != null:
		_flame_mat.albedo_color = col
		_flame_mat.emission = col
