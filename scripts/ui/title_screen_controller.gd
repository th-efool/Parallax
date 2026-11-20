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
var _crack_rect: ColorRect = null
var _menu_items: Array[Button] = []
var _mirror_side: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("title_screen")
	MenuStyle.enforce_full_rect(self)
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
	if visible and not quote_overlay_visible and event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_Q:
		_toggle_realm_glimpse()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
		return
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
	var bg := ColorRect.new()
	bg.name = "TitleBackground"
	bg.color = Color(MenuStyle.DIMMER_RGB.r, MenuStyle.DIMMER_RGB.g, MenuStyle.DIMMER_RGB.b, 0.93)
	MenuStyle.enforce_full_rect(bg)
	add_child(bg)
	_crack_rect = MenuStyle.add_mirror_crack(self, 0.62, 0.30)

	var margin := MarginContainer.new()
	margin.name = "TitleMargin"
	MenuStyle.enforce_full_rect(margin)
	margin.add_theme_constant_override("margin_left", 96)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 36)
	add_child(margin)

	var column := VBoxContainer.new()
	column.name = "TitleVBox"
	column.custom_minimum_size = Vector2(420, 0)
	column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var t_lbl := Label.new()
	t_lbl.name = "TitleLabel"
	t_lbl.text = TITLE_TEXT
	MenuStyle.style_title(t_lbl, 92, Color(1.0, 0.93, 0.74))
	t_lbl.add_theme_constant_override("shadow_outline_size", 22)
	t_lbl.add_theme_color_override("font_shadow_color", Color(0.95, 0.62, 0.22, 0.38))
	column.add_child(t_lbl)
	title_label_path = get_path_to(t_lbl)

	var sub_lbl := Label.new()
	sub_lbl.name = "SubtitleLabel"
	sub_lbl.text = "A  MIRROR-REALM  COMBAT  GAME"
	MenuStyle.style_label(sub_lbl, 16, UITheme.GOLD)
	sub_lbl.add_theme_constant_override("outline_size", 0)
	column.add_child(sub_lbl)

	var tag_lbl := Label.new()
	tag_lbl.name = "TaglineLabel"
	tag_lbl.text = TAGLINE_TEXT
	tag_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	MenuStyle.style_flavor(tag_lbl, 26, Color(0.80, 0.84, 0.94))
	column.add_child(tag_lbl)
	tagline_label_path = get_path_to(tag_lbl)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	column.add_child(spacer)
	MenuStyle.style_divider(column)

	var specs: Array = [
		["ContinueButton", "Continue Saved Run", "continue_button_path"],
		["StartButton", "Start New Run", "start_button_path"],
		["LeaderboardButton", "Hall of Champions", "leaderboard_button_path"],
		["OptionsButton", "Options & Controls", "options_button_path"],
		["QuitButton", "Quit", "quit_button_path"],
	]
	_menu_items.clear()
	for spec: Array in specs:
		var b := Button.new()
		b.name = spec[0]
		b.text = spec[1]
		MenuStyle.style_button(b, 22, 52.0)
		column.add_child(b)
		set(spec[2], get_path_to(b))
		_menu_items.append(b)
	(get_node(quit_button_path) as Button).add_theme_color_override("font_color", Color(0.70, 0.62, 0.62))

	var hint := Label.new()
	hint.name = "RealmHintLabel"
	hint.text = "Press  Q  to glimpse the Mirror"
	MenuStyle.style_flavor(hint, 18, Color(0.55, 0.60, 0.72))
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 40)
	add_child(hint)

	var ver := Label.new()
	ver.name = "VersionLabel"
	ver.text = "PARALLAX  ·  IGDC BUILD"
	MenuStyle.style_label(ver, 13, Color(0.45, 0.47, 0.55))
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 28)
	add_child(ver)

	MenuStyle.add_atmosphere(self, 0.8, 0.9)

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
	UIFx.stagger_in(items, 0.08, 0.45)
	if _crack_rect != null:
		_crack_rect.modulate.a = 0.0
		var tw: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_property(_crack_rect, "modulate:a", 1.0, 1.4)
	var title_node: Control = get_node_or_null(title_label_path) as Control
	if title_node != null:
		UIFx.fade_in(title_node, 0.9)


func _toggle_realm_glimpse() -> void:
	if _crack_rect == null or _crack_rect.material == null:
		return
	_mirror_side = not _mirror_side
	var mat: ShaderMaterial = _crack_rect.material as ShaderMaterial
	var tw: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("realm_mix", v), float(mat.get_shader_parameter("realm_mix")), 0.18 if _mirror_side else 0.82, 0.45).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
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
