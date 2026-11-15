class_name OptionsScreenController
extends Control
## Options screen controller (GDD Section 9.2):
## Binds Master / Music / SFX volume sliders, Mouse Sensitivity, Invert Y toggle,
## Display Mode (Fullscreen / Windowed) & Resolution, Restore Defaults, and Reset Local Leaderboard (with confirm).

signal settings_applied(settings: Dictionary)
signal defaults_restored(settings: Dictionary)
signal leaderboard_reset_confirm_requested()
signal leaderboard_reset_completed()
signal back_requested()

@export_group("Optional Scene Node Bindings")
@export var apply_button_path: NodePath
@export var restore_defaults_button_path: NodePath
@export var reset_leaderboard_button_path: NodePath
@export var back_button_path: NodePath

var working_settings: Dictionary = {}
var reset_confirm_pending: bool = false


func _ready() -> void:
	add_to_group("options_screen")
	reload_from_store()
	_bind_buttons()


func reload_from_store() -> void:
	reset_confirm_pending = false
	var store: Node = _get_leaderboard_store()
	if store != null and store.has_method("get_settings"):
		working_settings = (store.call("get_settings") as Dictionary).duplicate()
	else:
		working_settings = {
			"master_volume": 1.0,
			"music_volume": 0.85,
			"sfx_volume": 0.90,
			"mouse_sensitivity": 0.0025,
			"invert_y": false,
			"fullscreen": false,
			"resolution": Vector2i(1920, 1080),
		}


func set_volume(bus_key: String, linear_value: float) -> void:
	if bus_key in ["master_volume", "music_volume", "sfx_volume"]:
		working_settings[bus_key] = clampf(linear_value, 0.0, 1.0)


func set_mouse_sensitivity(sens: float) -> void:
	working_settings["mouse_sensitivity"] = clampf(sens, 0.0002, 0.02)


func set_invert_y(enabled: bool) -> void:
	working_settings["invert_y"] = enabled


func set_fullscreen(enabled: bool) -> void:
	working_settings["fullscreen"] = enabled


func set_resolution(res: Vector2i) -> void:
	if res.x >= 640 and res.y >= 360:
		working_settings["resolution"] = res


func press_apply() -> void:
	reset_confirm_pending = false
	var store: Node = _get_leaderboard_store()
	if store != null and store.has_method("save_settings"):
		store.call("save_settings", working_settings)
	settings_applied.emit(working_settings.duplicate())


func press_restore_defaults() -> void:
	reset_confirm_pending = false
	var store: Node = _get_leaderboard_store()
	if store != null and store.has_method("restore_default_settings"):
		working_settings = (store.call("restore_default_settings") as Dictionary).duplicate()
	defaults_restored.emit(working_settings.duplicate())


func press_reset_leaderboard(confirmed: bool = false) -> bool:
	if not confirmed and not reset_confirm_pending:
		reset_confirm_pending = true
		leaderboard_reset_confirm_requested.emit()
		return false

	reset_confirm_pending = false
	var store: Node = _get_leaderboard_store()
	if store != null and store.has_method("reset_leaderboard"):
		store.call("reset_leaderboard")
	leaderboard_reset_completed.emit()
	return true


func press_back() -> void:
	reset_confirm_pending = false
	back_requested.emit()


func _bind_buttons() -> void:
	_connect_button(apply_button_path, press_apply)
	_connect_button(restore_defaults_button_path, press_restore_defaults)
	_connect_button(reset_leaderboard_button_path, func() -> void: press_reset_leaderboard(false))
	_connect_button(back_button_path, press_back)


func _connect_button(path: NodePath, callable_fn: Callable) -> void:
	if path.is_empty():
		return
	var btn: BaseButton = get_node_or_null(path) as BaseButton
	if btn != null and not btn.pressed.is_connected(callable_fn):
		btn.pressed.connect(callable_fn)


func _get_leaderboard_store() -> Node:
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		return get_tree().root.get_node_or_null("LeaderboardStore")
	return null
