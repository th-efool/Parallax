class_name TitleScreenController
extends Control
## Title screen controller (GDD Section 9.2):
## Displays PARALLAX branding, tagline "Same arena. Different rules.", handles Start / Leaderboard / Options / Quit,
## and plays the <= 5.0s dismissible opening quote card ("They built a mirror to preserve champions. It learned to preserve their deaths.").

signal start_run_requested()
signal opening_quote_started(quote_text: String)
signal opening_quote_finished()
signal leaderboard_requested()
signal options_requested()
signal quit_requested()

const TITLE_TEXT: String = "PARALLAX"
const TAGLINE_TEXT: String = "Same arena. Different rules."
const OPENING_QUOTE_TEXT: String = "They built a mirror to preserve champions. It learned to preserve their deaths."

@export var quote_duration: float = 4.5
@export var show_quote_on_start: bool = true

@export_group("Optional Scene Node Bindings")
@export var title_label_path: NodePath
@export var tagline_label_path: NodePath
@export var start_button_path: NodePath
@export var leaderboard_button_path: NodePath
@export var options_button_path: NodePath
@export var quit_button_path: NodePath
@export var quote_overlay_path: NodePath
@export var quote_label_path: NodePath

var quote_overlay_visible: bool = false
var quote_timer: float = 0.0


func _ready() -> void:
	add_to_group("title_screen")
	_bind_buttons()
	_sync_ui_nodes()


func _process(delta: float) -> void:
	if quote_overlay_visible and quote_timer > 0.0:
		quote_timer = maxf(0.0, quote_timer - delta)
		if quote_timer <= 0.0:
			dismiss_quote_card()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not quote_overlay_visible:
		return
	if (event is InputEventKey and event.is_pressed()) or (event is InputEventMouseButton and event.is_pressed()):
		dismiss_quote_card()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()


func press_start() -> void:
	if show_quote_on_start and quote_duration > 0.0:
		quote_overlay_visible = true
		quote_timer = minf(quote_duration, 5.0)
		_sync_ui_nodes()
		opening_quote_started.emit(OPENING_QUOTE_TEXT)
	else:
		_complete_start_sequence()


func dismiss_quote_card() -> void:
	if not quote_overlay_visible:
		return
	quote_overlay_visible = false
	quote_timer = 0.0
	_sync_ui_nodes()
	opening_quote_finished.emit()
	_complete_start_sequence()


func press_leaderboard() -> void:
	leaderboard_requested.emit()


func press_options() -> void:
	options_requested.emit()


func press_quit() -> void:
	quit_requested.emit()


func _complete_start_sequence() -> void:
	visible = false
	var run_state: Node = _get_run_state()
	if run_state != null and run_state.has_method("start_new_run"):
		run_state.call("start_new_run")
	start_run_requested.emit()


func _bind_buttons() -> void:
	_connect_button(start_button_path, press_start)
	_connect_button(leaderboard_button_path, press_leaderboard)
	_connect_button(options_button_path, press_options)
	_connect_button(quit_button_path, press_quit)


func _connect_button(path: NodePath, callable_fn: Callable) -> void:
	if path.is_empty():
		return
	var btn: BaseButton = get_node_or_null(path) as BaseButton
	if btn != null and not btn.pressed.is_connected(callable_fn):
		btn.pressed.connect(callable_fn)


func _sync_ui_nodes() -> void:
	_set_label_text(title_label_path, TITLE_TEXT)
	_set_label_text(tagline_label_path, TAGLINE_TEXT)
	_set_label_text(quote_label_path, OPENING_QUOTE_TEXT)
	if not quote_overlay_path.is_empty():
		var overlay: CanvasItem = get_node_or_null(quote_overlay_path) as CanvasItem
		if overlay != null:
			overlay.visible = quote_overlay_visible


func _set_label_text(path: NodePath, value: String) -> void:
	if path.is_empty():
		return
	var lbl: Label = get_node_or_null(path) as Label
	if lbl != null:
		lbl.text = value


func _get_run_state() -> Node:
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		return get_tree().root.get_node_or_null("RunState")
	return null
