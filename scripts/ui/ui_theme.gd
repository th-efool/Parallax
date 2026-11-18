class_name UITheme
extends RefCounted
## PARALLAX UI palette, fonts and the project-wide Theme ("The Cracked Mirror").
## Fonts: drop OFL files into res://assets/fonts/ (names below) and they are picked up automatically;
## until then we fall back to the best installed system faces so nothing breaks.

const FONT_DISPLAY_PATHS: PackedStringArray = [
	"res://assets/fonts/Cinzel-Bold.ttf", "res://assets/fonts/Cinzel-Bold.otf",
	"res://assets/fonts/Cinzel-Regular.ttf", "res://assets/fonts/CinzelDecorative-Bold.ttf",
]
const FONT_FLAVOR_PATHS: PackedStringArray = [
	"res://assets/fonts/CormorantGaramond-Italic.ttf", "res://assets/fonts/CormorantGaramond-MediumItalic.ttf",
]
const FONT_BODY_PATHS: PackedStringArray = [
	"res://assets/fonts/Rajdhani-SemiBold.ttf", "res://assets/fonts/Rajdhani-Medium.ttf",
	"res://assets/fonts/BarlowSemiCondensed-Medium.ttf",
]

# Realm accents (match 05_UI_SCORING_AND_AUDIO.md palette).
const REALITY_ACCENT := Color(0.902, 0.600, 0.220)   # #E69938
const MIRROR_ACCENT := Color(0.200, 0.710, 1.000)    # #33B5FF
const GOLD := Color(0.784, 0.659, 0.376)             # #C8A860
const GOLD_BRIGHT := Color(1.0, 0.92, 0.70)
const INK := Color(0.030, 0.034, 0.055)

static var _display: Font = null
static var _flavor: Font = null
static var _body: Font = null
static var _theme: Theme = null


static func _first_existing(paths: PackedStringArray) -> Font:
	for p: String in paths:
		if ResourceLoader.exists(p):
			var f: Resource = load(p)
			if f is Font:
				return f as Font
	return null


static func _system(names: PackedStringArray, weight: int, italic: bool = false) -> Font:
	var sf := SystemFont.new()
	sf.font_names = names
	sf.font_weight = weight
	sf.font_italic = italic
	return sf


## Engraved-stone serif for logo and headings.
static func _variable(base: Font, wght: float) -> Font:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {"wght": wght}
	return fv


static func display_font() -> Font:
	if _display == null:
		_display = _first_existing(FONT_DISPLAY_PATHS)
		if _display != null:
			_display = _variable(_display, 700.0)
		else:
			_display = _system(PackedStringArray(["Cinzel", "Trajan Pro", "Palatino Linotype", "Georgia", "Times New Roman"]), 700)
	return _display


## Italic serif for quotes and flavour text.
static func flavor_font() -> Font:
	if _flavor == null:
		_flavor = _first_existing(FONT_FLAVOR_PATHS)
		if _flavor != null:
			_flavor = _variable(_flavor, 500.0)
		else:
			_flavor = _system(PackedStringArray(["Cormorant Garamond", "Palatino Linotype", "Georgia", "Times New Roman"]), 500, true)
	return _flavor


## Crisp condensed face for numbers, HUD and body copy.
static func body_font() -> Font:
	if _body == null:
		_body = _first_existing(FONT_BODY_PATHS)
		if _body != null:
			_body = _variable(_body, 700.0)
		else:
			_body = _system(PackedStringArray(["Rajdhani", "Barlow Semi Condensed", "Bahnschrift", "Segoe UI", "Arial"]), 700)
	return _body


static func realm_color(mirror_mix: float) -> Color:
	return REALITY_ACCENT.lerp(MIRROR_ACCENT, clampf(mirror_mix, 0.0, 1.0))


## One shared Theme for every menu root (apply via UITheme.apply(control)).
static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 18
	for cls: String in ["Label", "Button", "CheckButton", "CheckBox", "OptionButton", "LineEdit", "TabContainer", "TabBar"]:
		t.set_font("font", cls, body_font())
	t.set_color("font_color", "Label", Color(0.80, 0.83, 0.90))
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.7))
	t.set_constant("outline_size", "Label", 2)

	# Sliders: thin gold groove + diamond-ish grabber (square rotated look via small box).
	var groove := StyleBoxFlat.new()
	groove.bg_color = Color(0.10, 0.10, 0.14, 0.95)
	groove.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.5)
	groove.set_border_width_all(1)
	groove.content_margin_top = 3
	groove.content_margin_bottom = 3
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.85)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", groove)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)

	# Tabs.
	var tab_idle := _box(Color(0.06, 0.07, 0.10, 0.9), Color(GOLD.r, GOLD.g, GOLD.b, 0.25), 1, 14, 8)
	var tab_sel := _box(Color(0.14, 0.12, 0.09, 0.98), GOLD, 1, 14, 8)
	tab_sel.border_width_bottom = 3
	tab_sel.border_color = GOLD
	t.set_stylebox("tab_unselected", "TabContainer", tab_idle)
	t.set_stylebox("tab_hovered", "TabContainer", _box(Color(0.12, 0.10, 0.08, 0.95), Color(GOLD.r, GOLD.g, GOLD.b, 0.6), 1, 14, 8))
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("panel", "TabContainer", _box(Color(0.05, 0.06, 0.09, 0.6), Color(GOLD.r, GOLD.g, GOLD.b, 0.25), 1, 12, 10))
	t.set_color("font_selected_color", "TabContainer", GOLD_BRIGHT)
	t.set_color("font_unselected_color", "TabContainer", Color(0.62, 0.64, 0.70))
	t.set_color("font_hovered_color", "TabContainer", GOLD_BRIGHT)

	# Scrollbars: slim gold.
	var sb_grab := StyleBoxFlat.new()
	sb_grab.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.55)
	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color(0, 0, 0, 0.25)
	t.set_stylebox("grabber", "VScrollBar", sb_grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb_grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", sb_grab)
	t.set_stylebox("scroll", "VScrollBar", sb_bg)

	# Line edit (initials entry).
	t.set_stylebox("normal", "LineEdit", _box(Color(0.05, 0.06, 0.09, 0.95), Color(GOLD.r, GOLD.g, GOLD.b, 0.5), 1, 12, 8))
	t.set_stylebox("focus", "LineEdit", _box(Color(0.08, 0.08, 0.11, 1.0), GOLD_BRIGHT, 2, 12, 8))
	t.set_color("font_color", "LineEdit", GOLD_BRIGHT)
	_theme = t
	return t


static func _box(bg: Color, border: Color, bw: int, pad_h: int, pad_v: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(bw)
	b.content_margin_left = pad_h
	b.content_margin_right = pad_h
	b.content_margin_top = pad_v
	b.content_margin_bottom = pad_v
	return b


static func apply(ctrl: Control) -> void:
	if ctrl != null:
		ctrl.theme = get_theme()
