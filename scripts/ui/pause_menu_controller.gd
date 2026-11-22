class_name PauseMenuController
extends Control
## Pause menu controller (`Escape` toggle, `PROCESS_MODE_ALWAYS`):
## Freezes `SceneTree.paused` and `RunState` timer while open.
## Actions: Resume, Save Checkpoint, Restart Section, Restart Run (confirm), Options, Main Menu (confirm & auto-save).

signal pause_toggled(is_paused: bool)
signal checkpoint_saved(save_data: Dictionary)
signal section_restarted()
signal full_run_restarted()
signal options_requested()
signal main_menu_requested()
signal confirmation_prompt_changed(pending_action: String)

@export var pause_scene_tree: bool = true
@export var handle_escape_input: bool = true
@export var build_default_ui_if_empty: bool = true

@export_group("Optional Scene Node Bindings")
@export var resume_button_path: NodePath
@export var save_checkpoint_button_path: NodePath
@export var restart_section_button_path: NodePath
@export var restart_run_button_path: NodePath
@export var options_button_path: NodePath
@export var main_menu_button_path: NodePath
@export var confirm_dialog_path: NodePath
@export var confirm_yes_button_path: NodePath
@export var confirm_no_button_path: NodePath
@export var save_status_label_path: NodePath

var is_paused_state: bool = false
var pending_confirm_action: String = ""
var last_save_status_text: String = ""

# Convenience properties for direct test/script inspection
var resume_button: BaseButton = null
var save_checkpoint_button: BaseButton = null
var restart_section_button: BaseButton = null
var restart_button: BaseButton = null
var options_button: BaseButton = null
var title_button: BaseButton = null


func _exit_tree() -> void:
	resume_button = null
	save_checkpoint_button = null
	restart_section_button = null
	restart_button = null
	options_button = null
	title_button = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pause_menu")
	MenuStyle.enforce_full_rect(self)
	visible = false
	if build_default_ui_if_empty and get_child_count() == 0:
		_build_default_ui()
	_bind_buttons()
	_sync_ui_nodes()


func _unhandled_input(event: InputEvent) -> void:
	if not handle_escape_input:
		return
	if event.is_action_pressed("pause"):
		# Do not toggle pause off while Options or Leaderboard subscreen is open on top
		# or when Title, Loading, Results, or Player death screen is active.
		if _is_subscreen_visible() or not _can_toggle_pause():
			return
		toggle_pause()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()


func toggle_pause() -> void:
	if not is_paused_state and not _can_toggle_pause():
		return
	set_paused(not is_paused_state)


func set_paused(paused: bool) -> void:
	if is_paused_state == paused:
		return
	is_paused_state = paused
	pending_confirm_action = ""
	last_save_status_text = ""
	visible = is_paused_state

	if pause_scene_tree and is_inside_tree() and get_tree() != null:
		get_tree().paused = is_paused_state

	if is_paused_state:
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			var vp: Viewport = get_viewport()
			if vp != null:
				var sz: Vector2 = vp.get_visible_rect().size
				if sz.x > 10.0 and sz.y > 10.0:
					# Move cursor off the dead-center "Restart Section" button where MOUSE_MODE_CAPTURED parks it.
					Input.warp_mouse(Vector2(sz.x * 0.5, maxf(40.0, sz.y * 0.5 - 210.0)))
				vp.gui_release_focus()
		call_deferred("_clear_stale_focus")

	var run_state: Node = _get_run_state()
	if run_state != null:
		if is_paused_state and run_state.has_method("pause_timer"):
			run_state.call("pause_timer")
		elif not is_paused_state and run_state.has_method("resume_timer"):
			run_state.call("resume_timer")

	_sync_ui_nodes()
	pause_toggled.emit(is_paused_state)


func _clear_stale_focus() -> void:
	if is_paused_state and is_inside_tree() and get_viewport() != null:
		get_viewport().gui_release_focus()


func press_resume() -> void:
	set_paused(false)


func press_save_checkpoint() -> Dictionary:
	# Update EncounterDirector's checkpoint to the player's exact current position, facing, and realm
	# so both Continue and death respawn return the player right where they saved.
	if is_inside_tree() and get_tree() != null and EncounterDirector.instance != null:
		var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
		if player != null and player.is_inside_tree() and int(player.get("current_state")) != PlayerController.State.DEAD:
			var yaw: float = float(player.get("camera_yaw")) if "camera_yaw" in player else player.global_rotation.y
			var live_xform := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, yaw), player.global_position)
			if EncounterDirector.instance.has_method("set_manual_save_checkpoint"):
				EncounterDirector.instance.set_manual_save_checkpoint(EncounterDirector.instance.current_section, live_xform)

	var store: Node = _get_leaderboard_store()
	var saved: Dictionary = {}
	if store != null and store.has_method("capture_and_save_world_state"):
		saved = store.call("capture_and_save_world_state") as Dictionary
	var save_ok: bool = false
	if store != null:
		if saved.has("_save_ok"):
			save_ok = bool(saved.get("_save_ok", false))
		elif "last_save_error" in store:
			save_ok = int(store.get("last_save_error")) == OK
		else:
			save_ok = not saved.is_empty()
	last_save_status_text = "CHECKPOINT SAVED" if save_ok else "SAVE FAILED"
	_sync_ui_nodes()
	checkpoint_saved.emit(saved)
	return saved


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
	if options_requested.get_connections().is_empty() and is_inside_tree() and get_tree() != null:
		var opts: Node = get_tree().get_first_node_in_group("options_screen")
		if opts is CanvasItem:
			visible = false
			if opts.has_method("open_options"):
				opts.call("open_options")
			else:
				if opts.has_method("reload_from_store"):
					opts.call("reload_from_store")
				(opts as CanvasItem).visible = true


func press_main_menu(confirmed: bool = false) -> void:
	if not confirmed and pending_confirm_action != "main_menu":
		pending_confirm_action = "main_menu"
		_sync_ui_nodes()
		confirmation_prompt_changed.emit(pending_confirm_action)
		return

	pending_confirm_action = ""
	# Auto-save active run checkpoint before exiting to Main Menu
	press_save_checkpoint()
	set_paused(false)
	var run_state: Node = _get_run_state()
	if run_state != null and run_state.has_method("pause_timer"):
		run_state.call("pause_timer")
	main_menu_requested.emit()
	if main_menu_requested.get_connections().is_empty() and is_inside_tree() and get_tree() != null:
		var title: Node = get_tree().get_first_node_in_group("title_screen")
		if title is CanvasItem:
			(title as CanvasItem).visible = true


func confirm_pending_action() -> void:
	if pending_confirm_action == "restart_run":
		press_restart_run(true)
	elif pending_confirm_action == "main_menu":
		press_main_menu(true)


func cancel_pending_action() -> void:
	pending_confirm_action = ""
	_sync_ui_nodes()
	confirmation_prompt_changed.emit("")


func _build_default_ui() -> void:
	var modal := MenuStyle.build_centered_modal(self, "PauseDimmer", "PausePanel", Vector2(460, 560), 0.78, 30, 26)
	var panel: PanelContainer = modal["panel"] as PanelContainer

	var scroll := ScrollContainer.new()
	scroll.name = "MenuScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.name = "MenuVBox"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.name = "PauseTitleLabel"
	title_lbl.text = "THE ARENA WAITS"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuStyle.style_title(title_lbl, 32)
	vbox.add_child(title_lbl)

	var flavor_lbl := Label.new()
	flavor_lbl.name = "PauseFlavorLabel"
	flavor_lbl.text = "Time holds its breath."
	flavor_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuStyle.style_flavor(flavor_lbl, 20, MenuStyle.MUTED_TEXT)
	vbox.add_child(flavor_lbl)

	MenuStyle.style_divider(vbox)

	var resume_btn := Button.new()
	resume_btn.name = "ResumeButton"
	resume_btn.text = "Resume"
	MenuStyle.style_button(resume_btn, 18, 42.0)
	vbox.add_child(resume_btn)
	resume_button_path = get_path_to(resume_btn)

	var save_btn := Button.new()
	save_btn.name = "SaveCheckpointButton"
	save_btn.text = "Save Checkpoint"
	MenuStyle.style_button(save_btn, 18, 42.0)
	vbox.add_child(save_btn)
	save_checkpoint_button_path = get_path_to(save_btn)

	var restart_sec_btn := Button.new()
	restart_sec_btn.name = "RestartSectionButton"
	restart_sec_btn.text = "Restart Section"
	MenuStyle.style_button(restart_sec_btn, 18, 42.0)
	vbox.add_child(restart_sec_btn)
	restart_section_button_path = get_path_to(restart_sec_btn)

	var restart_run_btn := Button.new()
	restart_run_btn.name = "RestartRunButton"
	restart_run_btn.text = "Restart Run"
	MenuStyle.style_button(restart_run_btn, 18, 42.0)
	vbox.add_child(restart_run_btn)
	restart_run_button_path = get_path_to(restart_run_btn)

	var opts_btn := Button.new()
	opts_btn.name = "OptionsButton"
	opts_btn.text = "Options & Controls"
	MenuStyle.style_button(opts_btn, 18, 42.0)
	vbox.add_child(opts_btn)
	options_button_path = get_path_to(opts_btn)

	var main_menu_btn := Button.new()
	main_menu_btn.name = "MainMenuButton"
	main_menu_btn.text = "Save & Main Menu"
	MenuStyle.style_button(main_menu_btn, 18, 42.0)
	vbox.add_child(main_menu_btn)
	main_menu_button_path = get_path_to(main_menu_btn)

	var status_lbl := Label.new()
	status_lbl.name = "SaveStatusLabel"
	status_lbl.text = ""
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuStyle.style_label(status_lbl, 16, MenuStyle.SUCCESS_TEXT)
	vbox.add_child(status_lbl)
	save_status_label_path = get_path_to(status_lbl)

	var confirm_box := VBoxContainer.new()
	confirm_box.name = "ConfirmDialog"
	confirm_box.visible = false
	confirm_box.add_theme_constant_override("separation", 8)
	vbox.add_child(confirm_box)
	confirm_dialog_path = get_path_to(confirm_box)

	var confirm_lbl := Label.new()
	confirm_lbl.name = "ConfirmLabel"
	confirm_lbl.text = "Confirm Action?"
	confirm_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	MenuStyle.style_label(confirm_lbl, 16, MenuStyle.GOLD_TEXT)
	confirm_box.add_child(confirm_lbl)

	var confirm_btns := HBoxContainer.new()
	confirm_btns.alignment = BoxContainer.ALIGNMENT_CENTER
	confirm_btns.add_theme_constant_override("separation", 12)
	confirm_box.add_child(confirm_btns)

	var yes_btn := Button.new()
	yes_btn.name = "ConfirmYesButton"
	yes_btn.text = "Confirm"
	yes_btn.custom_minimum_size = Vector2(120, 38)
	MenuStyle.style_button(yes_btn, 16, 38.0)
	confirm_btns.add_child(yes_btn)
	confirm_yes_button_path = get_path_to(yes_btn)

	var no_btn := Button.new()
	no_btn.name = "ConfirmNoButton"
	no_btn.text = "Cancel"
	no_btn.custom_minimum_size = Vector2(120, 38)
	MenuStyle.style_button(no_btn, 16, 38.0)
	confirm_btns.add_child(no_btn)
	confirm_no_button_path = get_path_to(no_btn)


func _bind_buttons() -> void:
	resume_button = get_node_or_null(resume_button_path) as BaseButton
	save_checkpoint_button = get_node_or_null(save_checkpoint_button_path) as BaseButton
	restart_section_button = get_node_or_null(restart_section_button_path) as BaseButton
	restart_button = get_node_or_null(restart_run_button_path) as BaseButton
	options_button = get_node_or_null(options_button_path) as BaseButton
	title_button = get_node_or_null(main_menu_button_path) as BaseButton

	_connect_button(resume_button_path, press_resume)
	_connect_button(save_checkpoint_button_path, _on_save_checkpoint_btn)
	_connect_button(restart_section_button_path, _on_restart_section_btn)
	_connect_button(restart_run_button_path, _on_restart_run_btn)
	_connect_button(options_button_path, press_options)
	_connect_button(main_menu_button_path, _on_main_menu_btn)
	_connect_button(confirm_yes_button_path, confirm_pending_action)
	_connect_button(confirm_no_button_path, cancel_pending_action)


func _on_save_checkpoint_btn() -> void:
	press_save_checkpoint()


func _on_restart_section_btn() -> void:
	press_restart_section()


func _on_restart_run_btn() -> void:
	press_restart_run(true)


func _on_main_menu_btn() -> void:
	press_main_menu(true)


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
	if not save_status_label_path.is_empty():
		var slbl: Label = get_node_or_null(save_status_label_path) as Label
		if slbl != null:
			slbl.text = last_save_status_text
			slbl.visible = not last_save_status_text.is_empty()
			var col: Color = Color(0.95, 0.35, 0.30) if last_save_status_text == "SAVE FAILED" else Color(0.48, 0.90, 0.55)
			slbl.add_theme_color_override("font_color", col)


func _can_toggle_pause() -> bool:
	if _is_subscreen_visible():
		return false
	if is_inside_tree() and get_tree() != null:
		for grp in ["title_screen", "results_screen", "victory_outro"]:
			for n in get_tree().get_nodes_in_group(grp):
				if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
					return false
		var mc: Node = get_tree().get_first_node_in_group("main_controller")
		if mc != null and (not bool(mc.get("level_ready")) or bool(mc.get("_building")) or mc.get("_loading") != null):
			return false
		var player: Node = get_tree().get_first_node_in_group("player")
		if not is_paused_state and player != null:
			if player.process_mode == Node.PROCESS_MODE_DISABLED or int(player.get("current_state")) == PlayerController.State.DEAD:
				return false
	return true


func _is_subscreen_visible() -> bool:
	if not is_inside_tree() or get_tree() == null:
		return false
	for grp in ["options_screen", "leaderboard_screen"]:
		for n in get_tree().get_nodes_in_group(grp):
			if n is CanvasItem and (n as CanvasItem).visible:
				return true
	return false


func _get_run_state() -> Node:
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		return get_tree().root.get_node_or_null("RunState")
	return null


func _get_leaderboard_store() -> Node:
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		return get_tree().root.get_node_or_null("LeaderboardStore")
	return null
