class_name TitleScreenController
extends Control
## Title screen controller (GDD Section 9.2 + Pass 9 Save/Continue):
## Displays PARALLAX branding, tagline "Same arena. Different rules.", handles Continue / Start / Leaderboard / Options / Quit,
## and plays the <= 5.0s dismissible opening quote card ("They built a mirror to preserve champions. It learned to preserve their deaths.").

signal start_run_requested()
signal continue_run_requested()
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
@export var build_default_ui_if_empty: bool = true

@export_group("Optional Scene Node Bindings")
@export var title_label_path: NodePath
@export var tagline_label_path: NodePath
@export var continue_button_path: NodePath
@export var start_button_path: NodePath
@export var leaderboard_button_path: NodePath
@export var options_button_path: NodePath
@export var quit_button_path: NodePath
@export var quote_overlay_path: NodePath
@export var quote_label_path: NodePath

var quote_overlay_visible: bool = false
var quote_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("title_screen")
	if build_default_ui_if_empty and get_child_count() == 0:
		_build_default_ui()
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


func has_saved_run() -> bool:
	var store: Node = _get_leaderboard_store()
	if store != null and store.has_method("has_saved_run"):
		return bool(store.call("has_saved_run"))
	return false


func press_continue() -> bool:
	if not has_saved_run():
		return false
	visible = false
	var store: Node = _get_leaderboard_store()
	if store != null and store.has_method("apply_saved_world_state"):
		store.call("apply_saved_world_state")
	continue_run_requested.emit()
	return true


func press_start() -> void:
	var store: Node = _get_leaderboard_store()
	if store != null and store.has_method("clear_saved_run"):
		store.call("clear_saved_run", true)
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
	var ed: Node = get_tree().get_first_node_in_group("encounter_director") if (is_inside_tree() and get_tree() != null) else null
	if ed != null and ed.has_method("restart_full_run"):
		ed.call("restart_full_run")
	else:
		var run_state: Node = _get_run_state()
		if run_state != null and run_state.has_method("start_new_run"):
			run_state.call("start_new_run")
	start_run_requested.emit()


func _build_default_ui() -> void:
	var bg := ColorRect.new()
	bg.name = "TitleBackground"
	bg.color = Color(0.06, 0.07, 0.11, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.name = "TitleVBox"
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(460, 380)
	vbox.offset_left = -230.0
	vbox.offset_top = -190.0
	vbox.offset_right = 230.0
	vbox.offset_bottom = 190.0
	add_child(vbox)

	var t_lbl := Label.new()
	t_lbl.name = "TitleLabel"
	t_lbl.text = TITLE_TEXT
	t_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(t_lbl)
	title_label_path = get_path_to(t_lbl)

	var tag_lbl := Label.new()
	tag_lbl.name = "TaglineLabel"
	tag_lbl.text = TAGLINE_TEXT
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tag_lbl)
	tagline_label_path = get_path_to(tag_lbl)

	var cont_btn := Button.new()
	cont_btn.name = "ContinueButton"
	cont_btn.text = "Continue Saved Run"
	vbox.add_child(cont_btn)
	continue_button_path = get_path_to(cont_btn)

	var start_btn := Button.new()
	start_btn.name = "StartButton"
	start_btn.text = "Start New Run"
	vbox.add_child(start_btn)
	start_button_path = get_path_to(start_btn)

	var lb_btn := Button.new()
	lb_btn.name = "LeaderboardButton"
	lb_btn.text = "Leaderboard"
	vbox.add_child(lb_btn)
	leaderboard_button_path = get_path_to(lb_btn)

	var opts_btn := Button.new()
	opts_btn.name = "OptionsButton"
	opts_btn.text = "Options & Controls"
	vbox.add_child(opts_btn)
	options_button_path = get_path_to(opts_btn)

	var quit_btn := Button.new()
	quit_btn.name = "QuitButton"
	quit_btn.text = "Quit"
	vbox.add_child(quit_btn)
	quit_button_path = get_path_to(quit_btn)

	var quote_card := PanelContainer.new()
	quote_card.name = "QuoteOverlay"
	quote_card.visible = false
	quote_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(quote_card)
	quote_overlay_path = get_path_to(quote_card)

	var q_lbl := Label.new()
	q_lbl.name = "QuoteLabel"
	q_lbl.text = OPENING_QUOTE_TEXT
	q_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quote_card.add_child(q_lbl)
	quote_label_path = get_path_to(q_lbl)


func _bind_buttons() -> void:
	_connect_button(continue_button_path, _on_continue_btn)
	_connect_button(start_button_path, press_start)
	_connect_button(leaderboard_button_path, press_leaderboard)
	_connect_button(options_button_path, press_options)
	_connect_button(quit_button_path, press_quit)


func _on_continue_btn() -> void:
	press_continue()


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
	if not continue_button_path.is_empty():
		var cbtn: CanvasItem = get_node_or_null(continue_button_path) as CanvasItem
		if cbtn != null:
			cbtn.visible = has_saved_run()
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


func _get_leaderboard_store() -> Node:
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		return get_tree().root.get_node_or_null("LeaderboardStore")
	return null
