class_name OptionsScreenController
extends Control
## Comprehensive Options & Settings controller (GDD Section 9.2 + Pass 9):
## - Audio: Master / Music / SFX volume sliders, Mute When Unfocused
## - Display / Screen Type: Windowed / Borderless / Fullscreen, Resolution, VSync, Max FPS
## - Graphics: Quality Preset (Low/Medium/High/Ultra), MSAA 3D, Screen-Space AA (FXAA), Shadow Quality, Glow, Fog, Brightness
## - Gameplay & Camera: Mouse Sensitivity, Invert Y, Camera FOV, Camera Shake Intensity, Hit-Stop toggle
## - Controls: Live interactive key/mouse rebinding for all 11 actions with strict conflict validation & HUD prompt sync
## - Data / Save: Restore Defaults, Reset Controls, Reset Local Leaderboard (2-step confirm), Clear Saved Run (2-step confirm)

signal settings_applied(settings: Dictionary)
signal defaults_restored(settings: Dictionary)
signal rebind_listening_started(action_name: String)
signal rebind_listening_cancelled()
signal action_rebound(action_name: String, binding_code: String, display_label: String)
signal rebind_conflict_detected(action_name: String, attempted_code: String, conflict_action: String, reason: String)
signal controls_reset_to_default(labels: Dictionary)
signal leaderboard_reset_confirm_requested()
signal leaderboard_reset_completed()
signal save_clear_confirm_requested()
signal save_clear_completed()
signal back_requested()

@export var build_default_ui_if_empty: bool = true

@export_group("Optional Scene Node Bindings")
@export var apply_button_path: NodePath
@export var restore_defaults_button_path: NodePath
@export var reset_controls_button_path: NodePath
@export var reset_leaderboard_button_path: NodePath
@export var clear_save_button_path: NodePath
@export var back_button_path: NodePath
@export var conflict_warning_label_path: NodePath

var working_settings: Dictionary = {}
var listening_for_action: String = ""
var conflict_warning_text: String = ""
var reset_confirm_pending: bool = false
var clear_save_confirm_pending: bool = false
var keybind_buttons: Dictionary = {}

# Internal UI references when auto-built
var _screen_mode_option: OptionButton = null
var _resolution_option: OptionButton = null
var _vsync_option: OptionButton = null
var _preset_option: OptionButton = null
var _msaa_option: OptionButton = null
var _shadow_option: OptionButton = null
var _glow_toggle: CheckButton = null
var _fog_toggle: CheckButton = null
var _brightness_slider: HSlider = null
var _master_slider: HSlider = null
var _music_slider: HSlider = null
var _sfx_slider: HSlider = null
var _sens_slider: HSlider = null
var _invert_y_toggle: CheckButton = null
var _fov_slider: HSlider = null
var _shake_slider: HSlider = null
var _hitstop_toggle: CheckButton = null
var _conflict_label: Label = null


func _exit_tree() -> void:
	keybind_buttons.clear()
	_screen_mode_option = null
	_resolution_option = null
	_vsync_option = null
	_preset_option = null
	_msaa_option = null
	_shadow_option = null
	_glow_toggle = null
	_fog_toggle = null
	_brightness_slider = null
	_master_slider = null
	_music_slider = null
	_sfx_slider = null
	_sens_slider = null
	_invert_y_toggle = null
	_fov_slider = null
	_shake_slider = null
	_hitstop_toggle = null
	_conflict_label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("options_screen")
	if build_default_ui_if_empty and get_child_count() == 0:
		_build_default_ui()
	reload_from_store()
	_bind_buttons()
	_sync_ui_from_working_settings()


func _input(event: InputEvent) -> void:
	if not visible or listening_for_action.is_empty():
		return

	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var kev: InputEventKey = event as InputEventKey
		var kcode: int = int(kev.physical_keycode) if int(kev.physical_keycode) != 0 else int(kev.keycode)
		if kcode == KEY_ESCAPE:
			cancel_listening_for_rebind()
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
			return
		try_rebind_action_with_event(listening_for_action, event)
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.is_pressed():
		try_rebind_action_with_event(listening_for_action, event)
		if get_viewport() != null:
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not listening_for_action.is_empty():
		return
	if event.is_action_pressed("pause"):
		press_back()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()


func reload_from_store() -> void:
	reset_confirm_pending = false
	clear_save_confirm_pending = false
	listening_for_action = ""
	conflict_warning_text = ""
	var store: Node = _get_leaderboard_store()
	if store != null and store.has_method("get_settings"):
		working_settings = (store.call("get_settings") as Dictionary).duplicate(true)
	else:
		working_settings = {
			"master_volume": 1.0,
			"music_volume": 0.85,
			"sfx_volume": 0.90,
			"mute_when_unfocused": false,
			"screen_mode": "windowed",
			"fullscreen": false,
			"resolution": Vector2i(1920, 1080),
			"vsync_mode": DisplayServer.VSYNC_ENABLED,
			"max_fps": 0,
			"graphics_preset": "high",
			"msaa_3d": Viewport.MSAA_2X,
			"screen_space_aa": Viewport.SCREEN_SPACE_AA_FXAA,
			"shadow_quality": 2,
			"glow_enabled": true,
			"fog_enabled": true,
			"brightness": 1.0,
			"mouse_sensitivity": 0.0025,
			"invert_y": false,
			"camera_fov": 65.0,
			"camera_shake_intensity": 1.0,
			"hit_stop_enabled": true,
			"keybindings": {},
		}
	_sync_ui_from_working_settings()


# ============================================================================
# AUDIO, DISPLAY, GRAPHICS & GAMEPLAY SETTERS
# ============================================================================

func set_volume(bus_key: String, linear_value: float) -> void:
	if bus_key in ["master_volume", "music_volume", "sfx_volume"]:
		working_settings[bus_key] = clampf(linear_value, 0.0, 1.0)


func set_mute_when_unfocused(enabled: bool) -> void:
	working_settings["mute_when_unfocused"] = enabled


func set_screen_mode(mode_str: String) -> void:
	var m: String = mode_str.to_lower()
	if m in ["windowed", "borderless", "fullscreen"]:
		working_settings["screen_mode"] = m
		working_settings["fullscreen"] = (m != "windowed")


func set_fullscreen(enabled: bool) -> void:
	working_settings["fullscreen"] = enabled
	working_settings["screen_mode"] = "fullscreen" if enabled else "windowed"


func set_resolution(res: Vector2i) -> void:
	if res.x >= 640 and res.y >= 360:
		working_settings["resolution"] = res


func set_vsync_mode(vsync_int: int) -> void:
	working_settings["vsync_mode"] = clampi(vsync_int, 0, 3)


func set_max_fps(fps_int: int) -> void:
	working_settings["max_fps"] = maxi(0, fps_int)


func set_graphics_preset(preset_name: String) -> void:
	var p: String = preset_name.to_lower()
	if p in ["low", "medium", "high", "ultra"]:
		working_settings["graphics_preset"] = p
		match p:
			"low":
				working_settings["msaa_3d"] = Viewport.MSAA_DISABLED
				working_settings["screen_space_aa"] = Viewport.SCREEN_SPACE_AA_DISABLED
				working_settings["shadow_quality"] = 0
				working_settings["glow_enabled"] = false
				working_settings["fog_enabled"] = false
			"medium":
				working_settings["msaa_3d"] = Viewport.MSAA_2X
				working_settings["screen_space_aa"] = Viewport.SCREEN_SPACE_AA_DISABLED
				working_settings["shadow_quality"] = 1
				working_settings["glow_enabled"] = true
				working_settings["fog_enabled"] = true
			"high":
				working_settings["msaa_3d"] = Viewport.MSAA_2X
				working_settings["screen_space_aa"] = Viewport.SCREEN_SPACE_AA_FXAA
				working_settings["shadow_quality"] = 2
				working_settings["glow_enabled"] = true
				working_settings["fog_enabled"] = true
			"ultra":
				working_settings["msaa_3d"] = Viewport.MSAA_4X
				working_settings["screen_space_aa"] = Viewport.SCREEN_SPACE_AA_FXAA
				working_settings["shadow_quality"] = 3
				working_settings["glow_enabled"] = true
				working_settings["fog_enabled"] = true
		_sync_ui_from_working_settings()


func set_msaa_3d(msaa_int: int) -> void:
	working_settings["msaa_3d"] = clampi(msaa_int, 0, 3)
	working_settings["graphics_preset"] = "custom"


func set_screen_space_aa(ssaa_int: int) -> void:
	working_settings["screen_space_aa"] = clampi(ssaa_int, 0, 1)
	working_settings["graphics_preset"] = "custom"


func set_shadow_quality(quality_int: int) -> void:
	working_settings["shadow_quality"] = clampi(quality_int, 0, 3)
	working_settings["graphics_preset"] = "custom"


func set_glow_enabled(enabled: bool) -> void:
	working_settings["glow_enabled"] = enabled
	working_settings["graphics_preset"] = "custom"


func set_fog_enabled(enabled: bool) -> void:
	working_settings["fog_enabled"] = enabled
	working_settings["graphics_preset"] = "custom"


func set_brightness(exposure_val: float) -> void:
	working_settings["brightness"] = clampf(exposure_val, 0.5, 1.5)


func set_mouse_sensitivity(sens: float) -> void:
	working_settings["mouse_sensitivity"] = clampf(sens, 0.0002, 0.02)


func set_invert_y(enabled: bool) -> void:
	working_settings["invert_y"] = enabled


func set_camera_fov(fov_deg: float) -> void:
	working_settings["camera_fov"] = clampf(fov_deg, 55.0, 95.0)


func set_camera_shake_intensity(intensity: float) -> void:
	working_settings["camera_shake_intensity"] = clampf(intensity, 0.0, 1.0)


func set_hit_stop_enabled(enabled: bool) -> void:
	working_settings["hit_stop_enabled"] = enabled


# ============================================================================
# INTERACTIVE CONTROL REBINDING & CONFLICT VALIDATION
# ============================================================================

func begin_listening_for_rebind(action_name: String) -> bool:
	if not LeaderboardManager.REBINDABLE_ACTIONS.has(action_name):
		return false
	listening_for_action = action_name
	conflict_warning_text = ""
	_sync_keybind_buttons()
	rebind_listening_started.emit(action_name)
	return true


func cancel_listening_for_rebind() -> void:
	if listening_for_action.is_empty():
		return
	listening_for_action = ""
	_sync_keybind_buttons()
	rebind_listening_cancelled.emit()


func try_rebind_action(action_name: String, binding_code: String, swap_on_conflict: bool = false) -> Dictionary:
	listening_for_action = ""
	var store: Node = _get_leaderboard_store()
	if store == null or not store.has_method("rebind_action"):
		return {"valid": false, "conflict_action": "", "reason": "STORE UNAVAILABLE"}

	var res: Dictionary = store.call("rebind_action", action_name, binding_code, swap_on_conflict) as Dictionary
	if bool(res.get("valid", false)):
		conflict_warning_text = ""
		if store.has_method("get_settings"):
			working_settings = (store.call("get_settings") as Dictionary).duplicate(true)
		var new_lbl: String = String(store.call("get_action_display_label", action_name))
		_sync_keybind_buttons()
		action_rebound.emit(action_name, binding_code, new_lbl)
	else:
		conflict_warning_text = String(res.get("reason", "CONFLICT DETECTED"))
		var conflict_act: String = String(res.get("conflict_action", ""))
		_sync_keybind_buttons()
		rebind_conflict_detected.emit(action_name, binding_code, conflict_act, conflict_warning_text)
	return res


func try_rebind_action_with_event(action_name: String, event: InputEvent, swap_on_conflict: bool = false) -> Dictionary:
	var code: String = LeaderboardManager.event_to_binding_code(event)
	return try_rebind_action(action_name, code, swap_on_conflict)


func press_reset_controls() -> void:
	listening_for_action = ""
	conflict_warning_text = ""
	var store: Node = _get_leaderboard_store()
	var labels: Dictionary = {}
	if store != null and store.has_method("reset_keybindings_to_default"):
		labels = store.call("reset_keybindings_to_default") as Dictionary
		working_settings = (store.call("get_settings") as Dictionary).duplicate(true)
	_sync_keybind_buttons()
	controls_reset_to_default.emit(labels)


# ============================================================================
# APPLY, RESTORE DEFAULTS, RESET LEADERBOARD & CLEAR SAVE
# ============================================================================

func press_apply() -> void:
	reset_confirm_pending = false
	clear_save_confirm_pending = false
	listening_for_action = ""
	var store: Node = _get_leaderboard_store()
	if store != null and store.has_method("save_settings"):
		store.call("save_settings", working_settings)
		working_settings = (store.call("get_settings") as Dictionary).duplicate(true)
	_sync_ui_from_working_settings()
	settings_applied.emit(working_settings.duplicate(true))


func press_restore_defaults() -> void:
	reset_confirm_pending = false
	clear_save_confirm_pending = false
	listening_for_action = ""
	conflict_warning_text = ""
	var store: Node = _get_leaderboard_store()
	if store != null and store.has_method("restore_default_settings"):
		working_settings = (store.call("restore_default_settings") as Dictionary).duplicate(true)
	_sync_ui_from_working_settings()
	defaults_restored.emit(working_settings.duplicate(true))


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


func press_clear_saved_run(confirmed: bool = false) -> bool:
	if not confirmed and not clear_save_confirm_pending:
		clear_save_confirm_pending = true
		save_clear_confirm_requested.emit()
		return false

	clear_save_confirm_pending = false
	var store: Node = _get_leaderboard_store()
	if store != null and store.has_method("clear_saved_run"):
		store.call("clear_saved_run", true)
	save_clear_completed.emit()
	return true


func press_back() -> void:
	reset_confirm_pending = false
	clear_save_confirm_pending = false
	listening_for_action = ""
	conflict_warning_text = ""
	back_requested.emit()


# ============================================================================
# DEFAULT INTERACTIVE UI BUILDER & SYNC
# ============================================================================

func _build_default_ui() -> void:
	var bg := ColorRect.new()
	bg.name = "DimmerBackground"
	bg.color = Color(0.05, 0.06, 0.09, 0.88)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel := PanelContainer.new()
	panel.name = "OptionsPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(860, 620)
	panel.offset_left = -430.0
	panel.offset_top = -310.0
	panel.offset_right = 430.0
	panel.offset_bottom = 310.0
	add_child(panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.name = "RootVBox"
	panel.add_child(root_vbox)

	var header := Label.new()
	header.name = "HeaderLabel"
	header.text = "OPTIONS & SETTINGS"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(header)

	var tabs := TabContainer.new()
	tabs.name = "SettingsTabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(tabs)

	# TAB 1: DISPLAY & GRAPHICS
	var gfx_tab := VBoxContainer.new()
	gfx_tab.name = "Display_Graphics"
	tabs.add_child(gfx_tab)

	_screen_mode_option = _make_option_row(gfx_tab, "Screen Type", ["Windowed", "Borderless", "Fullscreen"], _on_screen_mode_selected)
	_resolution_option = _make_option_row(gfx_tab, "Resolution", ["1280x720", "1600x900", "1920x1080", "2560x1440", "3840x2160"], _on_resolution_selected)
	_vsync_option = _make_option_row(gfx_tab, "VSync", ["Disabled", "Enabled", "Adaptive"], set_vsync_mode)
	_preset_option = _make_option_row(gfx_tab, "Graphics Preset", ["Low", "Medium", "High", "Ultra", "Custom"], _on_preset_selected)
	_msaa_option = _make_option_row(gfx_tab, "3D Anti-Aliasing (MSAA)", ["Off", "2x MSAA", "4x MSAA", "8x MSAA"], set_msaa_3d)
	_shadow_option = _make_option_row(gfx_tab, "Shadow Quality", ["Off", "Low", "Medium", "High"], set_shadow_quality)
	_glow_toggle = _make_toggle_row(gfx_tab, "Bloom / Glow", true, set_glow_enabled)
	_fog_toggle = _make_toggle_row(gfx_tab, "Atmospheric Fog", true, set_fog_enabled)
	_brightness_slider = _make_slider_row(gfx_tab, "Brightness / Exposure", 0.5, 1.5, 0.05, 1.0, set_brightness)

	# TAB 2: SOUND / AUDIO
	var audio_tab := VBoxContainer.new()
	audio_tab.name = "Sound"
	tabs.add_child(audio_tab)

	_master_slider = _make_slider_row(audio_tab, "Master Volume", 0.0, 1.0, 0.05, 1.0, _on_master_volume_changed)
	_music_slider = _make_slider_row(audio_tab, "Music Volume", 0.0, 1.0, 0.05, 0.85, _on_music_volume_changed)
	_sfx_slider = _make_slider_row(audio_tab, "SFX Volume", 0.0, 1.0, 0.05, 0.90, _on_sfx_volume_changed)

	# TAB 3: CONTROLS (INTERACTIVE REBINDING)
	var controls_tab := VBoxContainer.new()
	controls_tab.name = "Controls"
	tabs.add_child(controls_tab)

	_conflict_label = Label.new()
	_conflict_label.name = "ConflictWarningLabel"
	_conflict_label.text = ""
	_conflict_label.modulate = Color(1.0, 0.35, 0.30, 1.0)
	controls_tab.add_child(_conflict_label)
	conflict_warning_label_path = get_path_to(_conflict_label)

	var scroll := ScrollContainer.new()
	scroll.name = "ControlsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls_tab.add_child(scroll)

	var binds_vbox := VBoxContainer.new()
	binds_vbox.name = "KeybindsVBox"
	binds_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(binds_vbox)

	keybind_buttons.clear()
	for act in LeaderboardManager.REBINDABLE_ACTIONS:
		var row := HBoxContainer.new()
		row.name = "Row_" + act
		var lbl := Label.new()
		lbl.text = String(LeaderboardManager.ACTION_DISPLAY_NAMES.get(act, act))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var btn := Button.new()
		btn.name = "BindBtn_" + act
		btn.custom_minimum_size = Vector2(180, 32)
		btn.pressed.connect(_on_keybind_button_pressed.bind(act))
		row.add_child(btn)
		binds_vbox.add_child(row)
		keybind_buttons[act] = btn

	var reset_ctrl_btn := Button.new()
	reset_ctrl_btn.name = "ResetControlsButton"
	reset_ctrl_btn.text = "Reset Controls to Default"
	controls_tab.add_child(reset_ctrl_btn)
	reset_controls_button_path = get_path_to(reset_ctrl_btn)

	# TAB 4: GAMEPLAY & SAVE DATA
	var gp_tab := VBoxContainer.new()
	gp_tab.name = "Gameplay_Save"
	tabs.add_child(gp_tab)

	_sens_slider = _make_slider_row(gp_tab, "Mouse Sensitivity", 0.0005, 0.01, 0.00025, 0.0025, set_mouse_sensitivity)
	_invert_y_toggle = _make_toggle_row(gp_tab, "Invert Look Y-Axis", false, set_invert_y)
	_fov_slider = _make_slider_row(gp_tab, "Camera FOV", 55.0, 95.0, 1.0, 65.0, set_camera_fov)
	_shake_slider = _make_slider_row(gp_tab, "Camera Shake Intensity", 0.0, 1.0, 0.05, 1.0, set_camera_shake_intensity)
	_hitstop_toggle = _make_toggle_row(gp_tab, "Combat Hit-Stop", true, set_hit_stop_enabled)

	var clear_save_btn := Button.new()
	clear_save_btn.name = "ClearSaveButton"
	clear_save_btn.text = "Clear Active Checkpoint Save (Confirm)"
	gp_tab.add_child(clear_save_btn)
	clear_save_button_path = get_path_to(clear_save_btn)

	var reset_lb_btn := Button.new()
	reset_lb_btn.name = "ResetLeaderboardButton"
	reset_lb_btn.text = "Reset Local Top-5 Leaderboard (Confirm)"
	gp_tab.add_child(reset_lb_btn)
	reset_leaderboard_button_path = get_path_to(reset_lb_btn)

	# BOTTOM ACTION BAR
	var bottom_bar := HBoxContainer.new()
	bottom_bar.name = "BottomActionBar"
	bottom_bar.alignment = BoxContainer.ALIGNMENT_END
	root_vbox.add_child(bottom_bar)

	var apply_btn := Button.new()
	apply_btn.name = "ApplyButton"
	apply_btn.text = "Apply & Save"
	bottom_bar.add_child(apply_btn)
	apply_button_path = get_path_to(apply_btn)

	var defaults_btn := Button.new()
	defaults_btn.name = "RestoreDefaultsButton"
	defaults_btn.text = "Restore All Defaults"
	bottom_bar.add_child(defaults_btn)
	restore_defaults_button_path = get_path_to(defaults_btn)

	var back_btn := Button.new()
	back_btn.name = "BackButton"
	back_btn.text = "Back"
	bottom_bar.add_child(back_btn)
	back_button_path = get_path_to(back_btn)


func _make_option_row(parent: Node, title: String, items: Array[String], on_selected: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = title
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var opt := OptionButton.new()
	for it in items:
		opt.add_item(it)
	opt.item_selected.connect(on_selected)
	row.add_child(opt)
	parent.add_child(row)
	return opt


func _make_toggle_row(parent: Node, title: String, initial: bool, on_toggled: Callable) -> CheckButton:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = title
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var chk := CheckButton.new()
	chk.button_pressed = initial
	chk.toggled.connect(on_toggled)
	row.add_child(chk)
	parent.add_child(row)
	return chk


func _make_slider_row(parent: Node, title: String, min_v: float, max_v: float, step_v: float, initial: float, on_changed: Callable) -> HSlider:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = title
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var sld := HSlider.new()
	sld.custom_minimum_size = Vector2(220, 24)
	sld.min_value = min_v
	sld.max_value = max_v
	sld.step = step_v
	sld.value = initial
	sld.value_changed.connect(on_changed)
	row.add_child(sld)
	parent.add_child(row)
	return sld


func _sync_ui_from_working_settings() -> void:
	if _master_slider != null:
		_master_slider.set_value_no_signal(float(working_settings.get("master_volume", 1.0)))
	if _music_slider != null:
		_music_slider.set_value_no_signal(float(working_settings.get("music_volume", 0.85)))
	if _sfx_slider != null:
		_sfx_slider.set_value_no_signal(float(working_settings.get("sfx_volume", 0.90)))
	if _brightness_slider != null:
		_brightness_slider.set_value_no_signal(float(working_settings.get("brightness", 1.0)))
	if _sens_slider != null:
		_sens_slider.set_value_no_signal(float(working_settings.get("mouse_sensitivity", 0.0025)))
	if _invert_y_toggle != null:
		_invert_y_toggle.set_pressed_no_signal(bool(working_settings.get("invert_y", false)))
	if _fov_slider != null:
		_fov_slider.set_value_no_signal(float(working_settings.get("camera_fov", 65.0)))
	if _shake_slider != null:
		_shake_slider.set_value_no_signal(float(working_settings.get("camera_shake_intensity", 1.0)))
	if _hitstop_toggle != null:
		_hitstop_toggle.set_pressed_no_signal(bool(working_settings.get("hit_stop_enabled", true)))
	if _glow_toggle != null:
		_glow_toggle.set_pressed_no_signal(bool(working_settings.get("glow_enabled", true)))
	if _fog_toggle != null:
		_fog_toggle.set_pressed_no_signal(bool(working_settings.get("fog_enabled", true)))
	if _screen_mode_option != null:
		var m: String = String(working_settings.get("screen_mode", "windowed")).to_lower()
		var idx: int = ["windowed", "borderless", "fullscreen"].find(m)
		_screen_mode_option.select(maxi(0, idx))
	if _msaa_option != null:
		_msaa_option.select(clampi(int(working_settings.get("msaa_3d", 1)), 0, 3))
	if _shadow_option != null:
		_shadow_option.select(clampi(int(working_settings.get("shadow_quality", 2)), 0, 3))
	_sync_keybind_buttons()


func _sync_keybind_buttons() -> void:
	var store: Node = _get_leaderboard_store()
	for act in keybind_buttons.keys():
		var btn: Button = keybind_buttons[act] as Button
		if btn == null:
			continue
		if listening_for_action == act:
			btn.text = "PRESS KEY / MOUSE..."
		elif store != null and store.has_method("get_action_display_label"):
			btn.text = "[%s]" % String(store.call("get_action_display_label", act))
		else:
			var binds: Dictionary = working_settings.get("keybindings", {}) as Dictionary
			btn.text = "[%s]" % LeaderboardManager.format_binding_code(String(binds.get(act, "")))

	if not conflict_warning_label_path.is_empty():
		var clbl: Label = get_node_or_null(conflict_warning_label_path) as Label
		if clbl != null:
			clbl.text = conflict_warning_text
			clbl.visible = not conflict_warning_text.is_empty()


func _bind_buttons() -> void:
	_connect_button(apply_button_path, press_apply)
	_connect_button(restore_defaults_button_path, press_restore_defaults)
	_connect_button(reset_controls_button_path, press_reset_controls)
	_connect_button(reset_leaderboard_button_path, _on_reset_leaderboard_btn)
	_connect_button(clear_save_button_path, _on_clear_save_btn)
	_connect_button(back_button_path, press_back)


func _on_screen_mode_selected(idx: int) -> void:
	var modes: Array[String] = ["windowed", "borderless", "fullscreen"]
	set_screen_mode(modes[clampi(idx, 0, 2)])


func _on_resolution_selected(idx: int) -> void:
	var res_list: Array[Vector2i] = LeaderboardManager.SUPPORTED_RESOLUTIONS
	set_resolution(res_list[clampi(idx, 0, res_list.size() - 1)])


func _on_preset_selected(idx: int) -> void:
	var presets: Array[String] = ["low", "medium", "high", "ultra", "custom"]
	var chosen: String = presets[clampi(idx, 0, 4)]
	if chosen != "custom":
		set_graphics_preset(chosen)


func _on_master_volume_changed(v: float) -> void:
	set_volume("master_volume", v)


func _on_music_volume_changed(v: float) -> void:
	set_volume("music_volume", v)


func _on_sfx_volume_changed(v: float) -> void:
	set_volume("sfx_volume", v)


func _on_keybind_button_pressed(act: String) -> void:
	begin_listening_for_rebind(act)


func _on_reset_leaderboard_btn() -> void:
	press_reset_leaderboard(false)


func _on_clear_save_btn() -> void:
	press_clear_saved_run(false)


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
