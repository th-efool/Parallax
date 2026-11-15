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
	panel.add_theme_stylebox_override("panel", make_panel_box(PANEL_BG, BORDER_GOLD, radius, 2, pad_h, pad_v))


static func style_button(btn: BaseButton, font_size: int = 18, min_height: float = 42.0) -> void:
	btn.custom_minimum_size.y = maxf(btn.custom_minimum_size.y, min_height)
	btn.add_theme_stylebox_override("normal", make_flat_box(BTN_BG_NORMAL, BORDER_SUBTLE, 1, 6))
	btn.add_theme_stylebox_override("hover", make_flat_box(BTN_BG_HOVER, BORDER_GOLD, 2, 6))
	btn.add_theme_stylebox_override("pressed", make_flat_box(BTN_BG_PRESSED, BORDER_GOLD, 2, 6))
	btn.add_theme_stylebox_override("focus", make_flat_box(BTN_BG_HOVER, BORDER_GOLD, 2, 6))
	btn.add_theme_stylebox_override("disabled", make_flat_box(BTN_BG_DISABLED, Color(0.25, 0.25, 0.30, 0.4), 1, 6))
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", GOLD_TEXT)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.82, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.98, 0.90, 1.0))
	btn.add_theme_color_override("font_focus_color", Color(1.0, 0.96, 0.82, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.50, 0.52, 0.58, 0.7))


static func style_title(lbl: Label, font_size: int = 30, color: Color = GOLD_TEXT) -> void:
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.04, 0.95))
	lbl.add_theme_constant_override("outline_size", 4)


static func style_label(lbl: Label, font_size: int = 17, color: Color = MUTED_TEXT) -> void:
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)


static func style_divider(parent: Node) -> void:
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.color = Color(BORDER_GOLD.r, BORDER_GOLD.g, BORDER_GOLD.b, 0.35)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(sep)


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

	var bg := ColorRect.new()
	bg.name = dimmer_name
	bg.color = Color(DIMMER_RGB.r, DIMMER_RGB.g, DIMMER_RGB.b, dimmer_alpha)
	enforce_full_rect(bg)
	parent.add_child(bg)

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

	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.custom_minimum_size = target_size
	style_panel(panel, pad_h, pad_v)
	center.add_child(panel)

	bind_responsive_panel(parent, panel, target_size, float(margin_pad))

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
