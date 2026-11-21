extends RefCounted
class_name MenuStyle

## Shared obsidian-and-gold visual theme and responsive layout helpers for all game menus.

const DIMMER_RGB := Color(0.035, 0.042, 0.068)
const PANEL_BG := Color(0.065, 0.075, 0.115, 0.94)
const PANEL_INNER_BG := Color(0.095, 0.110, 0.165, 0.85)
const BORDER_GOLD := Color(0.76, 0.60, 0.34, 0.90)
const BORDER_SUBTLE := Color(0.42, 0.36, 0.26, 0.65)
const GOLD_TEXT := Color(0.96, 0.90, 0.72, 1.0)
const MUTED_TEXT := Color(0.76, 0.80, 0.88, 1.0)
const DANGER_TEXT := Color(1.0, 0.42, 0.36, 1.0)
const SUCCESS_TEXT := Color(0.45, 0.92, 0.65, 1.0)

const BTN_BG_NORMAL := Color(0.11, 0.13, 0.19, 0.95)
const BTN_BG_HOVER := Color(0.18, 0.16, 0.13, 0.98)
const BTN_BG_PRESSED := Color(0.25, 0.21, 0.14, 1.0)
const BTN_BG_DISABLED := Color(0.08, 0.09, 0.12, 0.55)


static func enforce_full_rect(ctrl: Control) -> void:
	ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ctrl.offset_left = 0.0
	ctrl.offset_top = 0.0
	ctrl.offset_right = 0.0
	ctrl.offset_bottom = 0.0
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl.size_flags_vertical = Control.SIZE_EXPAND_FILL


static func make_panel_box(
	bg: Color = PANEL_BG,
	border: Color = BORDER_GOLD,
	radius: int = 10,
	border_w: int = 2,
	pad_h: int = 28,
	pad_v: int = 24
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_w)
	box.set_corner_radius_all(radius)
	box.content_margin_left = pad_h
	box.content_margin_right = pad_h
	box.content_margin_top = pad_v
	box.content_margin_bottom = pad_v
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	box.shadow_size = 14
	return box


static func make_flat_box(bg: Color, border: Color, border_w: int = 1, radius: int = 6, pad_h: int = 14, pad_v: int = 8) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_w)
	box.set_corner_radius_all(radius)
	box.content_margin_left = pad_h
	box.content_margin_right = pad_h
	box.content_margin_top = pad_v
	box.content_margin_bottom = pad_v
	return box


static func style_panel(panel: PanelContainer, pad_h: int = 28, pad_v: int = 24, radius: int = 10) -> void:
	if panel is UIFrame:
		(panel as UIFrame).pad_h = pad_h
		(panel as UIFrame).pad_v = pad_v
		return
	panel.add_theme_stylebox_override("panel", make_panel_box(PANEL_BG, BORDER_GOLD, 0, 2, pad_h, pad_v))


## Angular button: dark plate, gold left bar that thickens on hover/focus, brighter fill, hover sound + nudge.
static func _btn_box(bg: Color, border: Color, bar_w: int, border_w: int = 1) -> StyleBoxFlat:
	var b := make_flat_box(bg, border, border_w, 0, 18, 8)
	b.border_width_left = bar_w
	b.corner_detail = 1
	return b


static func style_button(btn: BaseButton, font_size: int = 18, min_height: float = 42.0) -> void:
	btn.custom_minimum_size.y = maxf(btn.custom_minimum_size.y, min_height)
	btn.add_theme_stylebox_override("normal", _btn_box(BTN_BG_NORMAL, BORDER_SUBTLE, 3))
	btn.add_theme_stylebox_override("hover", _btn_box(BTN_BG_HOVER, UITheme.GOLD_BRIGHT, 8, 1))
	btn.add_theme_stylebox_override("pressed", _btn_box(BTN_BG_PRESSED, UITheme.GOLD_BRIGHT, 10, 1))
	btn.add_theme_stylebox_override("focus", _btn_box(BTN_BG_HOVER, UITheme.GOLD_BRIGHT, 8, 1))
	btn.add_theme_stylebox_override("disabled", _btn_box(BTN_BG_DISABLED, Color(0.25, 0.25, 0.30, 0.4), 2))
	btn.add_theme_font_override("font", UITheme.display_font())
	btn.add_theme_font_size_override("font_size", font_size)
	if btn is Button:
		(btn as Button).alignment = HORIZONTAL_ALIGNMENT_LEFT
	UIFx.wire_button(btn)
	btn.add_theme_color_override("font_color", GOLD_TEXT)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.82, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.98, 0.90, 1.0))
	btn.add_theme_color_override("font_focus_color", Color(1.0, 0.96, 0.82, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.50, 0.52, 0.58, 0.7))


## Borderless, letter-spaced main-menu entry: text only, with a gold diamond + underline that grow in
## on hover/focus. Hovering focuses the item, so mouse and keyboard share one highlight.
static func style_menu_item(btn: Button, font_size: int = 26) -> void:
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 40
	empty.content_margin_right = 16
	empty.content_margin_top = 7
	empty.content_margin_bottom = 7
	for state: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		btn.add_theme_stylebox_override(state, empty)
	btn.add_theme_font_override("font", UITheme.spaced(UITheme.display_font(), 3, 0.25))
	btn.add_theme_font_size_override("font_size", font_size)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.focus_mode = Control.FOCUS_ALL
	btn.add_theme_color_override("font_color", Color(0.86, 0.82, 0.74, 0.66))
	btn.add_theme_color_override("font_hover_color", UITheme.GOLD_BRIGHT)
	btn.add_theme_color_override("font_focus_color", UITheme.GOLD_BRIGHT)
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 0.94))
	btn.add_theme_color_override("font_hover_pressed_color", Color(1.0, 1.0, 0.94))
	btn.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.55, 0.4))
	btn.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.55))
	btn.add_theme_constant_override("outline_size", 4)
	btn.set_meta("hl", 0.0)
	btn.mouse_entered.connect(func() -> void:
		if not btn.disabled and not btn.has_focus():
			btn.grab_focus())
	btn.focus_entered.connect(func() -> void:
		_tween_highlight(btn, 1.0)
		if AudioManager.instance != null:
			AudioManager.instance.play_sfx("ui_click", -8.0))
	btn.focus_exited.connect(func() -> void: _tween_highlight(btn, 0.0))
	btn.pressed.connect(func() -> void:
		if AudioManager.instance != null:
			AudioManager.instance.play_sfx("ui_confirm", -4.0))
	btn.draw.connect(func() -> void: _draw_menu_item(btn))


static func _tween_highlight(btn: Button, target: float) -> void:
	if not is_instance_valid(btn) or not btn.is_inside_tree():
		btn.set_meta("hl", target)
		return
	var tw: Tween = btn.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_method(func(v: float) -> void:
		btn.set_meta("hl", v)
		btn.queue_redraw(), float(btn.get_meta("hl", 0.0)), target, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func _draw_menu_item(btn: Button) -> void:
	var hl: float = float(btn.get_meta("hl", 0.0))
	if hl <= 0.01:
		return
	var font: Font = btn.get_theme_font("font")
	var fs: int = btn.get_theme_font_size("font_size")
	var text_w: float = font.get_string_size(btn.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var cy: float = btn.size.y * 0.5
	var gold := UITheme.GOLD_BRIGHT
	# Soft glow band behind the text.
	btn.draw_rect(Rect2(Vector2(0, 2), Vector2((40.0 + text_w + 28.0) * hl, btn.size.y - 4)), Color(0.95, 0.70, 0.35, 0.07 * hl))
	# Diamond marker sliding in from the left.
	var x: float = 18.0 - (1.0 - hl) * 10.0
	var r: float = 6.0
	btn.draw_colored_polygon(PackedVector2Array([Vector2(x, cy - r), Vector2(x + r, cy), Vector2(x, cy + r), Vector2(x - r, cy)]), Color(gold.r, gold.g, gold.b, hl))
	# Underline growing from the text start.
	var y: float = btn.size.y - 5.0
	btn.draw_line(Vector2(40, y), Vector2(40.0 + text_w * hl, y), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.75 * hl), 1.5)


## Small framed key glyph + caption, for footer key hints ("ENTER  Confirm").
static func make_key_hint(key_text: String, caption: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var cap := PanelContainer.new()
	cap.add_theme_stylebox_override("panel", make_flat_box(Color(0.0, 0.0, 0.0, 0.35), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.55), 1, 3, 7, 1))
	var k := Label.new()
	k.text = key_text
	k.add_theme_font_override("font", UITheme.body_font())
	k.add_theme_font_size_override("font_size", 17)
	k.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	cap.add_child(k)
	row.add_child(cap)
	var c := Label.new()
	c.text = caption
	c.add_theme_font_override("font", UITheme.body_font())
	c.add_theme_font_size_override("font_size", 18)
	c.add_theme_color_override("font_color", Color(0.78, 0.78, 0.82, 0.75))
	row.add_child(c)
	return row


static func style_title(lbl: Label, font_size: int = 30, color: Color = GOLD_TEXT) -> void:
	lbl.add_theme_font_override("font", UITheme.display_font())
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.04, 0.95))
	lbl.add_theme_color_override("font_shadow_color", Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.28))
	lbl.add_theme_constant_override("shadow_offset_x", 0)
	lbl.add_theme_constant_override("shadow_offset_y", 0)
	lbl.add_theme_constant_override("shadow_outline_size", 10)
	lbl.add_theme_constant_override("outline_size", 4)


static func style_label(lbl: Label, font_size: int = 17, color: Color = MUTED_TEXT) -> void:
	lbl.add_theme_font_override("font", UITheme.body_font())
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)


## Italic flavour-text label (quotes, taglines).
static func style_flavor(lbl: Label, font_size: int = 20, color: Color = MUTED_TEXT) -> void:
	lbl.add_theme_font_override("font", UITheme.flavor_font())
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)


static func style_divider(parent: Node) -> void:
	parent.add_child(UIDivider.new())


## Full-screen vignette + grain + embers overlay (non-interactive). Add last so it sits on top.
static func add_atmosphere(parent: Control, vignette: float = 0.65, motes: float = 0.6) -> ColorRect:
	var r := ColorRect.new()
	r.name = "AtmosphereOverlay"
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enforce_full_rect(r)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/ui/ui_vignette_grain.gdshader") as Shader
	mat.set_shader_parameter("vignette", vignette)
	mat.set_shader_parameter("motes", motes)
	r.material = mat
	parent.add_child(r)
	return r


## Full-screen amber|cyan mirror-crack tint. realm_mix 0 = Reality, 1 = Mirror.
static func add_mirror_crack(parent: Control, realm_mix: float = 0.5, tint: float = 0.22) -> ColorRect:
	var r := ColorRect.new()
	r.name = "MirrorCrackOverlay"
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enforce_full_rect(r)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/ui/ui_mirror_crack.gdshader") as Shader
	mat.set_shader_parameter("realm_mix", realm_mix)
	mat.set_shader_parameter("tint_strength", tint)
	r.material = mat
	parent.add_child(r)
	return r


static func build_centered_modal(
	parent: Control,
	dimmer_name: String,
	panel_name: String,
	target_size: Vector2,
	dimmer_alpha: float = 0.84,
	pad_h: int = 28,
	pad_v: int = 24,
	margin_pad: int = 24
) -> Dictionary:
	enforce_full_rect(parent)
	UITheme.apply(parent)

	var bg := ColorRect.new()
	bg.name = dimmer_name
	bg.color = Color(DIMMER_RGB.r, DIMMER_RGB.g, DIMMER_RGB.b, dimmer_alpha)
	enforce_full_rect(bg)
	parent.add_child(bg)
	add_mirror_crack(parent, 0.5, 0.20)

	var margin := MarginContainer.new()
	margin.name = panel_name + "Margin"
	enforce_full_rect(margin)
	margin.add_theme_constant_override("margin_left", margin_pad)
	margin.add_theme_constant_override("margin_right", margin_pad)
	margin.add_theme_constant_override("margin_top", margin_pad)
	margin.add_theme_constant_override("margin_bottom", margin_pad)
	parent.add_child(margin)

	var center := CenterContainer.new()
	center.name = panel_name + "Center"
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(center)

	var panel := UIFrame.new()
	panel.name = panel_name
	panel.custom_minimum_size = target_size
	style_panel(panel, pad_h, pad_v)
	center.add_child(panel)

	bind_responsive_panel(parent, panel, target_size, float(margin_pad))
	add_atmosphere(parent, 0.7, 0.5)

	return {
		"dimmer": bg,
		"margin": margin,
		"center": center,
		"panel": panel,
	}


static func bind_responsive_panel(host: Control, panel: PanelContainer, target_size: Vector2, margin_pad: float = 24.0) -> void:
	var panel_ref: WeakRef = weakref(panel)
	var host_ref: WeakRef = weakref(host)
	var update_fn := func() -> void:
		var h: Control = host_ref.get_ref() as Control
		var p: PanelContainer = panel_ref.get_ref() as PanelContainer
		if h == null or p == null or not is_instance_valid(h) or not is_instance_valid(p):
			return
		var avail: Vector2 = h.size
		if (avail.x <= 1.0 or avail.y <= 1.0) and h.is_inside_tree() and h.get_viewport() != null:
			avail = h.get_viewport_rect().size
		if avail.x <= 1.0 or avail.y <= 1.0:
			return
		var max_w: float = maxf(260.0, avail.x - margin_pad * 2.0)
		var max_h: float = maxf(220.0, avail.y - margin_pad * 2.0)
		p.custom_minimum_size = Vector2(minf(target_size.x, max_w), minf(target_size.y, max_h))
	if not host.resized.is_connected(update_fn):
		host.resized.connect(update_fn)
	if host.is_inside_tree() and host.get_viewport() != null:
		var vp: Viewport = host.get_viewport()
		if not vp.size_changed.is_connected(update_fn):
			vp.size_changed.connect(update_fn)
	update_fn.call_deferred()
