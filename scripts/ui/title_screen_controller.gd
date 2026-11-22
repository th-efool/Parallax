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
const SEAM_REALITY: float = 0.68
const SEAM_MIRROR: float = 0.06

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
var _crack_rect: ColorRect = null
var _menu_items: Array[Button] = []
var _mirror_side: bool = false
var _selected_idx: int = 0
var _current_seam: float = SEAM_REALITY
var _seam_tween: Tween = null
var _prev_keys: Dictionary = {}
var _last_nav_frame: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("title_screen")
	MenuStyle.enforce_full_rect(self)
	if build_default_ui_if_empty and get_child_count() == 0:
		_build_default_ui()
	_bind_buttons()
	_sync_ui_nodes()
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)
	_focus_first_item.call_deferred()


func _process(delta: float) -> void:
	if quote_overlay_visible and quote_timer > 0.0:
		quote_timer = maxf(0.0, quote_timer - delta)
		if quote_timer <= 0.0:
			dismiss_quote_card()
	if not visible or not is_visible_in_tree():
		_prev_keys.clear()
		return
	var q_down: bool = Input.is_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_Q)
	var up_down: bool = Input.is_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_W)
	var down_down: bool = Input.is_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_S)
	var enter_down: bool = Input.is_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER) or Input.is_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_SPACE)
	var q_edge: bool = q_down and not bool(_prev_keys.get("q", false))
	var up_edge: bool = up_down and not bool(_prev_keys.get("up", false))
	var down_edge: bool = down_down and not bool(_prev_keys.get("down", false))
	var enter_edge: bool = enter_down and not bool(_prev_keys.get("enter", false))
	_prev_keys["q"] = q_down
	_prev_keys["up"] = up_down
	_prev_keys["down"] = down_down
	_prev_keys["enter"] = enter_down
	var cur_frame: int = Engine.get_process_frames()
	if cur_frame == _last_nav_frame:
		return
	if quote_overlay_visible:
		if q_edge or up_edge or down_edge or enter_edge:
			_last_nav_frame = cur_frame
			dismiss_quote_card()
		return
	if q_edge:
		_last_nav_frame = cur_frame
		_toggle_realm_glimpse()
	elif up_edge:
		_last_nav_frame = cur_frame
		_select_menu_index(_selected_idx - 1)
	elif down_edge:
		_last_nav_frame = cur_frame
		_select_menu_index(_selected_idx + 1)
	elif enter_edge:
		_last_nav_frame = cur_frame
		_activate_selected_button()


func _visible_menu_buttons() -> Array[Button]:
	var out: Array[Button] = []
	var src: Array = _menu_items
	if src.is_empty():
		for p: NodePath in [continue_button_path, start_button_path, leaderboard_button_path, options_button_path, quit_button_path]:
			if not p.is_empty():
				var n: Node = get_node_or_null(p)
				if n is Button:
					src.append(n)
	for b in src:
		if b is Button and is_instance_valid(b) and (b as Button).visible and not (b as Button).disabled:
			out.append(b as Button)
	return out


func _select_menu_index(idx: int) -> void:
	var vis_btns: Array[Button] = _visible_menu_buttons()
	if vis_btns.is_empty():
		return
	_selected_idx = (idx % vis_btns.size() + vis_btns.size()) % vis_btns.size()
	for i in range(vis_btns.size()):
		var b: Button = vis_btns[i]
		var is_sel: bool = (i == _selected_idx)
		MenuStyle._tween_highlight(b, 1.0 if is_sel else 0.0)
		b.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT if is_sel else Color(0.86, 0.82, 0.74, 0.66))
		if is_sel and b.is_inside_tree() and not b.has_focus():
			b.grab_focus()


func _activate_selected_button() -> void:
	var vis_btns: Array[Button] = _visible_menu_buttons()
	if vis_btns.is_empty():
		return
	var idx: int = clampi(_selected_idx, 0, vis_btns.size() - 1)
	var target_btn: Button = vis_btns[idx]
	_select_menu_index(idx)
	target_btn.pressed.emit()


func _input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree():
		return
	var cur_frame: int = Engine.get_process_frames()
	if quote_overlay_visible:
		if (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo) or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
			_last_nav_frame = cur_frame
			dismiss_quote_card()
			if get_viewport() != null:
				get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey):
		return
	var kev: InputEventKey = event as InputEventKey
	if not kev.pressed or kev.echo:
		return
	var code: Key = kev.keycode if kev.keycode != KEY_NONE else kev.physical_keycode
	var phys: Key = kev.physical_keycode
	if code == KEY_Q or phys == KEY_Q:
		if cur_frame != _last_nav_frame:
			_last_nav_frame = cur_frame
			_prev_keys["q"] = true
			_toggle_realm_glimpse()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
		return
	var vis_btns: Array[Button] = _visible_menu_buttons()
	if vis_btns.is_empty():
		return
	if code == KEY_UP or phys == KEY_UP or code == KEY_W or phys == KEY_W:
		if cur_frame != _last_nav_frame:
			_last_nav_frame = cur_frame
			_prev_keys["up"] = true
			_select_menu_index(_selected_idx - 1)
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
	elif code == KEY_DOWN or phys == KEY_DOWN or code == KEY_S or phys == KEY_S:
		if cur_frame != _last_nav_frame:
			_last_nav_frame = cur_frame
			_prev_keys["down"] = true
			_select_menu_index(_selected_idx + 1)
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
	elif code == KEY_ENTER or phys == KEY_ENTER or code == KEY_KP_ENTER or phys == KEY_KP_ENTER or code == KEY_SPACE or phys == KEY_SPACE:
		if cur_frame != _last_nav_frame:
			_last_nav_frame = cur_frame
			_prev_keys["enter"] = true
			_activate_selected_button()
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
	# The saved world is applied by MainController once the level has been built behind the loading screen.
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
		var qo: CanvasItem = get_node_or_null(quote_overlay_path) as CanvasItem
		if qo != null:
			UIFx.fade_in(qo, 0.8)
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
	if leaderboard_requested.get_connections().is_empty() and is_inside_tree() and get_tree() != null:
		var lb: Node = get_tree().get_first_node_in_group("leaderboard_screen")
		if lb is CanvasItem:
			visible = false
			if lb.has_method("refresh_entries"):
				lb.call("refresh_entries")
			(lb as CanvasItem).visible = true


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
	UITheme.apply(self)
	# Procedural backdrop: ruined colosseum at dusk, split by the mirror seam, reflected in still water.
	var bg := ColorRect.new()
	bg.name = "TitleBackground"
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStyle.enforce_full_rect(bg)
	var bg_mat := ShaderMaterial.new()
	bg_mat.shader = load("res://assets/shaders/ui/ui_title_backdrop.gdshader") as Shader
	bg_mat.set_shader_parameter("seam", SEAM_REALITY)
	bg.material = bg_mat
	add_child(bg)
	_crack_rect = bg

	var margin := MarginContainer.new()
	margin.name = "TitleMargin"
	MenuStyle.enforce_full_rect(margin)
	margin.add_theme_constant_override("margin_left", 112)
	margin.add_theme_constant_override("margin_right", 64)
	margin.add_theme_constant_override("margin_top", 64)
	margin.add_theme_constant_override("margin_bottom", 96)
	add_child(margin)

	var column := VBoxContainer.new()
	column.name = "TitleVBox"
	column.custom_minimum_size = Vector2(560, 0)
	column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 0)
	margin.add_child(column)

	var sub_lbl := Label.new()
	sub_lbl.name = "SubtitleLabel"
	sub_lbl.text = "A MIRROR-REALM COMBAT GAME"
	sub_lbl.add_theme_font_override("font", UITheme.spaced(UITheme.body_font(), 6))
	sub_lbl.add_theme_font_size_override("font_size", 17)
	sub_lbl.add_theme_color_override("font_color", Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.95))
	sub_lbl.add_theme_constant_override("outline_size", 0)
	column.add_child(sub_lbl)

	var t_lbl := Label.new()
	t_lbl.name = "TitleLabel"
	t_lbl.text = TITLE_TEXT
	t_lbl.add_theme_font_override("font", UITheme.spaced(UITheme.display_font(), 14, 0.35))
	t_lbl.add_theme_font_size_override("font_size", 124)
	t_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.74))
	t_lbl.add_theme_color_override("font_outline_color", Color(0.10, 0.05, 0.02, 0.9))
	t_lbl.add_theme_constant_override("outline_size", 3)
	t_lbl.add_theme_color_override("font_shadow_color", Color(1.0, 0.62, 0.25, 0.30))
	t_lbl.add_theme_constant_override("shadow_offset_x", 0)
	t_lbl.add_theme_constant_override("shadow_offset_y", 0)
	t_lbl.add_theme_constant_override("shadow_outline_size", 30)
	column.add_child(t_lbl)
	title_label_path = get_path_to(t_lbl)

	var tag_lbl := Label.new()
	tag_lbl.name = "TaglineLabel"
	tag_lbl.text = TAGLINE_TEXT
	MenuStyle.style_flavor(tag_lbl, 31, Color(0.92, 0.90, 0.94, 0.92))
	tag_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	tag_lbl.add_theme_constant_override("outline_size", 3)
	column.add_child(tag_lbl)
	tagline_label_path = get_path_to(tag_lbl)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 52)
	column.add_child(spacer)

	var list := VBoxContainer.new()
	list.name = "MenuList"
	list.add_theme_constant_override("separation", 2)
	list.custom_minimum_size = Vector2(420, 0)
	list.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(list)

	var specs: Array = [
		["ContinueButton", "Continue", "continue_button_path"],
		["StartButton", "New Run", "start_button_path"],
		["LeaderboardButton", "Hall of Champions", "leaderboard_button_path"],
		["OptionsButton", "Options", "options_button_path"],
		["QuitButton", "Quit", "quit_button_path"],
	]
	_menu_items.clear()
	for spec: Array in specs:
		var b := Button.new()
		b.name = spec[0]
		b.text = String(spec[1]).to_upper()
		b.size_flags_horizontal = Control.SIZE_FILL
		MenuStyle.style_menu_item(b, 27)
		b.mouse_entered.connect(func() -> void:
			var vb: Array[Button] = _visible_menu_buttons()
			var idx: int = vb.find(b)
			if idx >= 0:
				_select_menu_index(idx))
		list.add_child(b)
		set(spec[2], get_path_to(b))
		_menu_items.append(b)

	# Footer: key hints on the left, build tag on the right.
	var footer := HBoxContainer.new()
	footer.name = "FooterHints"
	footer.add_theme_constant_override("separation", 28)
	footer.anchor_left = 0.0
	footer.anchor_right = 1.0
	footer.anchor_top = 1.0
	footer.anchor_bottom = 1.0
	footer.offset_left = 112.0
	footer.offset_right = -48.0
	footer.offset_top = -64.0
	footer.offset_bottom = -36.0
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(footer)
	footer.add_child(MenuStyle.make_key_hint("↑ ↓", "Select"))
	footer.add_child(MenuStyle.make_key_hint("ENTER", "Confirm"))
	var realm_hint := MenuStyle.make_key_hint("Q", "Glimpse the Mirror")
	realm_hint.name = "RealmHintLabel"
	footer.add_child(realm_hint)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(fill)
	var ver := Label.new()
	ver.name = "VersionLabel"
	ver.text = "IGDC BUILD"
	ver.add_theme_font_override("font", UITheme.spaced(UITheme.body_font(), 4))
	ver.add_theme_font_size_override("font_size", 14)
	ver.add_theme_color_override("font_color", Color(0.62, 0.64, 0.72, 0.6))
	footer.add_child(ver)

	MenuStyle.add_atmosphere(self, 0.55, 0.7)

	var quote_card := PanelContainer.new()
	quote_card.name = "QuoteOverlay"
	quote_card.visible = false
	MenuStyle.enforce_full_rect(quote_card)
	quote_card.add_theme_stylebox_override("panel", MenuStyle.make_panel_box(Color(0.02, 0.022, 0.035, 1.0), MenuStyle.BORDER_GOLD, 0, 0, 0, 0))
	add_child(quote_card)
	quote_overlay_path = get_path_to(quote_card)

	var q_margin := MarginContainer.new()
	MenuStyle.enforce_full_rect(q_margin)
	q_margin.add_theme_constant_override("margin_left", 160)
	q_margin.add_theme_constant_override("margin_right", 160)
	q_margin.add_theme_constant_override("margin_top", 48)
	q_margin.add_theme_constant_override("margin_bottom", 48)
	quote_card.add_child(q_margin)

	var q_vbox := VBoxContainer.new()
	q_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	q_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	q_vbox.add_theme_constant_override("separation", 22)
	q_margin.add_child(q_vbox)

	q_vbox.add_child(UIDivider.new())
	var q_lbl := Label.new()
	q_lbl.name = "QuoteLabel"
	q_lbl.text = OPENING_QUOTE_TEXT
	q_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	q_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuStyle.style_flavor(q_lbl, 38, Color(0.96, 0.90, 0.74))
	q_vbox.add_child(q_lbl)
	quote_label_path = get_path_to(q_lbl)
	q_vbox.add_child(UIDivider.new())

	call_deferred("_play_intro")


func _play_intro() -> void:
	var items: Array = []
	for b: Button in _menu_items:
		if b.visible:
			items.append(b)
	UIFx.stagger_in(items, 0.07, 0.5)
	if _crack_rect != null and _crack_rect.material is ShaderMaterial:
		var mat: ShaderMaterial = _crack_rect.material as ShaderMaterial
		var tw: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("intro", v), 0.0, 1.0, 1.6).set_trans(Tween.TRANS_SINE)
	var title_node: Control = get_node_or_null(title_label_path) as Control
	if title_node != null:
		UIFx.fade_in(title_node, 1.2)
	_focus_first_item()


func _focus_first_item() -> void:
	if not visible or not is_inside_tree():
		return
	_select_menu_index(0)


func _on_visibility_changed() -> void:
	if visible:
		_sync_ui_nodes()
		_focus_first_item.call_deferred()


func _toggle_realm_glimpse() -> void:
	if _crack_rect == null or not (_crack_rect.material is ShaderMaterial):
		return
	_mirror_side = not _mirror_side
	var mat: ShaderMaterial = _crack_rect.material as ShaderMaterial
	var target_seam: float = SEAM_MIRROR if _mirror_side else SEAM_REALITY
	if _seam_tween != null and is_instance_valid(_seam_tween):
		_seam_tween.kill()
	var start_seam: float = _current_seam
	_seam_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_seam_tween.tween_method(func(v: float) -> void:
		_current_seam = v
		if is_instance_valid(mat):
			mat.set_shader_parameter("seam", v), start_seam, target_seam, 0.55).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	if AudioManager.instance != null:
		AudioManager.instance.play_sfx("shift_to_mirror" if _mirror_side else "shift_to_reality", -6.0)


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
