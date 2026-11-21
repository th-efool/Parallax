class_name LoadingScreen
extends CanvasLayer
## Full-screen loading overlay shown between "Start" on the title and the first frame of the run.
## MainController drives it with set_progress(); the bar eases toward the target so it never looks frozen.
## Layout: dimmed title backdrop, logo top-left, one large readable tip card, slim progress rail at the bottom.

## [heading, body] pairs. Keep each body to one or two short sentences.
const TIPS: Array = [
	["REALM SHIFT", "Press Q to swap realms. Some paths, platforms and enemies exist in only one of them."],
	["WEAK POINTS", "In the Mirror, enemies show glowing cracks. Hits on a crack deal 25% more damage."],
	["FLOW", "Keep your light attacks in rhythm. On-beat hits build FLOW and land critical hits more often."],
	["FINISHERS", "A critical hit slows time. Press LMB, RMB, Shift, Q or F to choose a finisher."],
	["SQUAD ORDERS", "Talk to your squad in plain words, like \"Sera, draw it away and keep moving.\""],
	["TAUNTS", "A taunted enemy chases its taunter until it falls. Use that to pull it off your squad."],
]
const TIP_SECONDS: float = 5.5
const FADE_SECONDS: float = 0.45

var _root: Control = null
var _bar: ProgressBar = null
var _pct: Label = null
var _label: Label = null
var _tip: Label = null
var _tip_head: Label = null
var _tip_box: Control = null
var _target: float = 0.0
var _shown: float = 0.0
var _tip_index: int = 0
var _tip_t: float = 0.0
var _finishing: bool = false


func _init() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader: Shader = load("res://assets/shaders/ui/ui_title_backdrop.gdshader") as Shader
	if shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("intro", 0.42)
		mat.set_shader_parameter("menu_shade", 0.5)
		bg.material = mat
	_root.add_child(bg)

	var logo := Label.new()
	logo.text = "PARALLAX"
	logo.add_theme_font_override("font", UITheme.spaced(UITheme.display_font(), 8, 0.3))
	logo.add_theme_font_size_override("font_size", 34)
	logo.add_theme_color_override("font_color", Color(1.0, 0.92, 0.74, 0.92))
	logo.position = Vector2(72, 56)
	_root.add_child(logo)

	# Tip card: left-aligned, generous size and line spacing so it reads at a glance.
	var tip_box := VBoxContainer.new()
	tip_box.anchor_left = 0.0
	tip_box.anchor_right = 0.0
	tip_box.anchor_top = 1.0
	tip_box.anchor_bottom = 1.0
	tip_box.offset_left = 72.0
	tip_box.offset_right = 72.0 + 760.0
	tip_box.offset_top = -270.0
	tip_box.offset_bottom = -130.0
	tip_box.alignment = BoxContainer.ALIGNMENT_END
	tip_box.add_theme_constant_override("separation", 10)
	_root.add_child(tip_box)
	_tip_box = tip_box

	_tip_head = Label.new()
	_tip_head.add_theme_font_override("font", UITheme.spaced(UITheme.body_font(), 5))
	_tip_head.add_theme_font_size_override("font_size", 17)
	_tip_head.add_theme_color_override("font_color", UITheme.GOLD)
	tip_box.add_child(_tip_head)

	_tip = Label.new()
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size = Vector2(760, 0)
	_tip.add_theme_font_override("font", UITheme.body_font())
	_tip.add_theme_font_size_override("font_size", 27)
	_tip.add_theme_constant_override("line_spacing", 6)
	_tip.add_theme_color_override("font_color", Color(0.93, 0.92, 0.88))
	_tip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_tip.add_theme_constant_override("outline_size", 4)
	tip_box.add_child(_tip)

	# Bottom rail: status text left, percent right, thin gold bar underneath.
	var rail := VBoxContainer.new()
	rail.anchor_left = 0.0
	rail.anchor_right = 1.0
	rail.anchor_top = 1.0
	rail.anchor_bottom = 1.0
	rail.offset_left = 72.0
	rail.offset_right = -72.0
	rail.offset_top = -92.0
	rail.offset_bottom = -52.0
	rail.add_theme_constant_override("separation", 10)
	_root.add_child(rail)

	var status_row := HBoxContainer.new()
	rail.add_child(status_row)

	_label = Label.new()
	_label.text = "Preparing the arena"
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.add_theme_font_override("font", UITheme.spaced(UITheme.body_font(), 2))
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.80, 0.80, 0.84, 0.85))
	status_row.add_child(_label)

	_pct = Label.new()
	_pct.text = "0%"
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pct.custom_minimum_size = Vector2(72, 0)
	_pct.add_theme_font_override("font", UITheme.spaced(UITheme.body_font(), 2))
	_pct.add_theme_font_size_override("font_size", 18)
	_pct.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	status_row.add_child(_pct)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 4)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.98, 0.76, 0.38)
	fill.shadow_color = Color(1.0, 0.65, 0.25, 0.45)
	fill.shadow_size = 6
	_bar.add_theme_stylebox_override("fill", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1.0, 1.0, 1.0, 0.10)
	_bar.add_theme_stylebox_override("background", back)
	rail.add_child(_bar)

	_show_tip(0, false)


func _show_tip(index: int, animate: bool) -> void:
	var tip: Array = TIPS[index % TIPS.size()] as Array
	if not animate or _tip_box == null:
		_tip_head.text = String(tip[0])
		_tip.text = String(tip[1])
		return
	var tw := create_tween()
	tw.tween_property(_tip_box, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func() -> void:
		_tip_head.text = String(tip[0])
		_tip.text = String(tip[1]))
	tw.tween_property(_tip_box, "modulate:a", 1.0, 0.35)


## fraction 0..1 of the whole load; text names the step being built.
func set_progress(fraction: float, text: String = "") -> void:
	_target = clampf(fraction, 0.0, 1.0)
	if not text.is_empty() and _label != null:
		_label.text = text


func _process(delta: float) -> void:
	if _bar == null:
		return
	_shown = move_toward(_shown, _target, delta * 2.5)
	_bar.value = _shown * 100.0
	_pct.text = "%d%%" % int(round(_shown * 100.0))
	_tip_t += delta
	if _tip_t >= TIP_SECONDS:
		_tip_t = 0.0
		_tip_index = (_tip_index + 1) % TIPS.size()
		_show_tip(_tip_index, true)


## Snaps to 100 %, fades out and frees itself.
func finish() -> void:
	if _finishing:
		return
	_finishing = true
	set_progress(1.0, "Ready")
	_shown = 1.0
	await get_tree().create_timer(0.25).timeout
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_SECONDS)
	await tw.finished
	queue_free()
