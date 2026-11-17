class_name LoadingScreen
extends CanvasLayer
## Full-screen loading overlay shown between "Start" on the title and the first frame of the run.
## MainController drives it with set_progress(); the bar eases toward the target so it never looks frozen.

const TIPS: Array[String] = [
	"Mirror mode shows every enemy's weak point. Their cracks take 25% more damage there.",
	"Tap LMB in rhythm to build FLOW: on-beat hits crit more often.",
	"A critical hit opens a short slow-motion window: press LMB, RMB, Shift, Q or F to finish.",
	"Hold your squad's attention with orders: \"Sera, bait it and run in circles\".",
	"Taunted enemies chase their taunter until it falls. Pull them away from the squad.",
	"Press Q to shift realms. Some paths only exist in one of them.",
]
const TIP_SECONDS: float = 4.0
const FADE_SECONDS: float = 0.35

var _root: Control = null
var _bar: ProgressBar = null
var _pct: Label = null
var _label: Label = null
var _tip: Label = null
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

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.05, 1.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -300.0
	box.offset_right = 300.0
	box.offset_top = -130.0
	box.offset_bottom = 130.0
	box.add_theme_constant_override("separation", 14)
	_root.add_child(box)

	var title := Label.new()
	title.text = "THE MIRROR IS BEING BUILT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_font_override("font", UITheme.display_font())
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42))
	box.add_child(title)

	_label = Label.new()
	_label.text = "Stepping through the mirror"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", UITheme.body_font())
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.82))
	box.add_child(_label)

	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 12)
	box.add_child(bar_row)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(480, 22)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.95, 0.72, 0.32)
	_bar.add_theme_stylebox_override("fill", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.12, 0.11, 0.1)
	back.border_color = Color(0.78, 0.66, 0.38)
	back.set_border_width_all(1)
	_bar.add_theme_stylebox_override("background", back)
	bar_row.add_child(_bar)

	_pct = Label.new()
	_pct.text = "0%"
	_pct.custom_minimum_size = Vector2(56, 0)
	_pct.add_theme_font_override("font", UITheme.body_font())
	_pct.add_theme_font_size_override("font_size", 20)
	bar_row.add_child(_pct)

	_tip = Label.new()
	_tip.text = TIPS[0]
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.add_theme_font_override("font", UITheme.flavor_font())
	_tip.add_theme_font_size_override("font_size", 17)
	_tip.add_theme_color_override("font_color", Color(0.7, 0.68, 0.62))
	box.add_child(_tip)


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
		_tip.text = TIPS[_tip_index]


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
