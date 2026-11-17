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
