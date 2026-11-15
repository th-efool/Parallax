class_name PauseMenuController
extends Control
## Pause menu controller (`Escape` toggle, `PROCESS_MODE_ALWAYS`):
## Freezes `SceneTree.paused` and `RunState` timer while open.
## Actions: Resume, Restart Section, Restart Run (confirm), Options, Main Menu (confirm).

signal pause_toggled(is_paused: bool)
signal section_restarted()
signal full_run_restarted()
signal options_requested()
signal main_menu_requested()
signal confirmation_prompt_changed(pending_action: String)

@export var pause_scene_tree: bool = true
@export var handle_escape_input: bool = true

@export_group("Optional Scene Node Bindings")
@export var resume_button_path: NodePath
@export var restart_section_button_path: NodePath
@export var restart_run_button_path: NodePath
@export var options_button_path: NodePath
@export var main_menu_button_path: NodePath
@export var confirm_dialog_path: NodePath
@export var confirm_yes_button_path: NodePath
@export var confirm_no_button_path: NodePath

var is_paused_state: bool = false
var pending_confirm_action: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pause_menu")
	visible = false
	_bind_buttons()
	_sync_ui_nodes()


func _unhandled_input(event: InputEvent) -> void:
	if not handle_escape_input:
		return
	if event.is_action_pressed("pause"):
		toggle_pause()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()


func toggle_pause() -> void:
	set_paused(not is_paused_state)


func set_paused(paused: bool) -> void:
	if is_paused_state == paused:
		return
	is_paused_state = paused
	pending_confirm_action = ""
	visible = is_paused_state

	if pause_scene_tree and is_inside_tree() and get_tree() != null:
		get_tree().paused = is_paused_state

	var run_state: Node = _get_run_state()
	if run_state != null:
		if is_paused_state and run_state.has_method("pause_timer"):
			run_state.call("pause_timer")
		elif not is_paused_state and run_state.has_method("resume_timer"):
			run_state.call("resume_timer")

	_sync_ui_nodes()
	pause_toggled.emit(is_paused_state)


func press_resume() -> void:
	set_paused(false)


func press_restart_section(player: Node = null) -> void:
	set_paused(false)
	var target_player: Node = player
	if target_player == null and is_inside_tree() and get_tree() != null:
		target_player = get_tree().get_first_node_in_group("player")
	if EncounterDirector.instance != null:
		EncounterDirector.instance.handle_player_death(target_player)
	section_restarted.emit()


func press_restart_run(confirmed: bool = false) -> void:
	if not confirmed and pending_confirm_action != "restart_run":
		pending_confirm_action = "restart_run"
		_sync_ui_nodes()
		confirmation_prompt_changed.emit(pending_confirm_action)
		return

	pending_confirm_action = ""
	set_paused(false)
	if EncounterDirector.instance != null:
		EncounterDirector.instance.restart_full_run()
	full_run_restarted.emit()


func press_options() -> void:
	options_requested.emit()


func press_main_menu(confirmed: bool = false) -> void:
	if not confirmed and pending_confirm_action != "main_menu":
		pending_confirm_action = "main_menu"
		_sync_ui_nodes()
		confirmation_prompt_changed.emit(pending_confirm_action)
		return

	pending_confirm_action = ""
	set_paused(false)
	var run_state: Node = _get_run_state()
	if run_state != null and run_state.has_method("pause_timer"):
		run_state.call("pause_timer")
	main_menu_requested.emit()


func confirm_pending_action() -> void:
	if pending_confirm_action == "restart_run":
		press_restart_run(true)
	elif pending_confirm_action == "main_menu":
		press_main_menu(true)


func cancel_pending_action() -> void:
	pending_confirm_action = ""
	_sync_ui_nodes()
	confirmation_prompt_changed.emit("")


func _bind_buttons() -> void:
	_connect_button(resume_button_path, press_resume)
	_connect_button(restart_section_button_path, func() -> void: press_restart_section())
	_connect_button(restart_run_button_path, func() -> void: press_restart_run(false))
	_connect_button(options_button_path, press_options)
	_connect_button(main_menu_button_path, func() -> void: press_main_menu(false))
	_connect_button(confirm_yes_button_path, confirm_pending_action)
	_connect_button(confirm_no_button_path, cancel_pending_action)


func _connect_button(path: NodePath, callable_fn: Callable) -> void:
	if path.is_empty():
		return
	var btn: BaseButton = get_node_or_null(path) as BaseButton
	if btn != null and not btn.pressed.is_connected(callable_fn):
		btn.pressed.connect(callable_fn)


func _sync_ui_nodes() -> void:
	if not confirm_dialog_path.is_empty():
		var dlg: CanvasItem = get_node_or_null(confirm_dialog_path) as CanvasItem
		if dlg != null:
			dlg.visible = not pending_confirm_action.is_empty()


func _get_run_state() -> Node:
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		return get_tree().root.get_node_or_null("RunState")
	return null
