class_name VictoryOutro
extends CanvasLayer
## Short cinematic beat between the Warden's death and the results screen:
## slow motion + gold flash, letterbox bars slide in, "THE WARDEN FALLS" title card, then a fade to black.
## ResultsScreenController starts it, waits for `finished`, shows the results, then calls reveal() to fade the black away.
## Any key / click skips ahead once the title is on screen.

signal finished()

const TOTAL_SECONDS: float = 4.6
const SKIP_AFTER_SECONDS: float = 1.0

var _root: Control = null
var _flash: ColorRect = null
var _bar_top: ColorRect = null
var _bar_bottom: ColorRect = null
var _card: VBoxContainer = null
var _scrim: TextureRect = null
var _black: ColorRect = null
var _tween: Tween = null
var _elapsed: float = 0.0
var _done: bool = false


func _init() -> void:
	layer = 115
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	# delta is scaled by Engine.time_scale; undo it so the skip gate runs on real time during the slow motion.
	_elapsed += delta / maxf(Engine.time_scale, 0.01)


func _input(event: InputEvent) -> void:
	if _done or _elapsed < SKIP_AFTER_SECONDS:
		return
	var pressed: bool = (event is InputEventKey and event.is_pressed() and not event.is_echo()) \
		or (event is InputEventMouseButton and event.is_pressed()) \
		or (event is InputEventJoypadButton and event.is_pressed())
	if pressed:
		get_viewport().set_input_as_handled()
		_skip()


func play(title_text: String = "THE WARDEN FALLS", subtitle_text: String = "The mirror lets you go.") -> void:
	_build(title_text, subtitle_text)
	GameFeel.slowmo(self, 0.22, 1.7)
	if AudioManager.instance != null:
		AudioManager.instance.play_sfx("glass_shatter", -4.0)

	var vh: float = _root.get_viewport_rect().size.y
	var bar_h: float = vh * 0.11
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	_tween.set_parallel(true)
	_tween.tween_property(_flash, "color:a", 0.0, 0.7).from(0.55).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_bar_top, "offset_bottom", bar_h, 0.7).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_bar_bottom, "offset_top", -bar_h, 0.7).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_scrim, "modulate:a", 0.6, 0.9).set_delay(0.35).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_card, "modulate:a", 1.0, 0.9).set_delay(0.55).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_card, "scale", Vector2.ONE, 2.4).from(Vector2(1.06, 1.06)).set_delay(0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_black, "color:a", 1.0, 1.1).set_delay(TOTAL_SECONDS - 1.1).set_trans(Tween.TRANS_SINE)
	_tween.chain().tween_callback(_finish)

	_fade_hud()


## Called once the results screen is visible underneath: fade the black and the letterbox away, then free.
func reveal() -> void:
	var tw: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	tw.tween_property(_root, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(queue_free)


func _skip() -> void:
	if _done:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var tw: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	tw.tween_property(_black, "color:a", 1.0, 0.3)
	tw.tween_callback(_finish)


func _finish() -> void:
	if _done:
		return
	_done = true
	if _card != null:
		_card.visible = false
	if _scrim != null:
		_scrim.visible = false
	GameFeel.reset_time_scale()
	finished.emit()


func _fade_hud() -> void:
	if not is_inside_tree():
		return
	# The HUD is a CanvasLayer (no modulate): hide it under the opening flash.
	for n: Node in get_tree().get_nodes_in_group("hud"):
		if "visible" in n:
			n.set("visible", false)


func _build(title_text: String, subtitle_text: String) -> void:
	_root = Control.new()
	_root.name = "VictoryOutroRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_to_group("victory_outro")
	add_child(_root)

	_flash = ColorRect.new()
	_flash.color = Color(1.0, 0.86, 0.6, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_flash)

	_bar_top = ColorRect.new()
	_bar_top.color = Color(0, 0, 0, 1)
	_bar_top.anchor_right = 1.0
	_bar_top.offset_bottom = 0.0
	_root.add_child(_bar_top)

	_bar_bottom = ColorRect.new()
	_bar_bottom.color = Color(0, 0, 0, 1)
	_bar_bottom.anchor_top = 1.0
	_bar_bottom.anchor_right = 1.0
	_bar_bottom.anchor_bottom = 1.0
	_bar_bottom.offset_top = 0.0
	_root.add_child(_bar_bottom)

	# Dark band behind the title so it reads over a bright sky.
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0, 0, 0, 0))
	grad.add_point(0.5, Color(0, 0, 0, 1))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.width = 4
	gtex.height = 128
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(0, 1)
	_scrim = TextureRect.new()
	_scrim.texture = gtex
	_scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scrim.stretch_mode = TextureRect.STRETCH_SCALE
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.anchor_right = 1.0
	_scrim.anchor_top = 0.5
	_scrim.anchor_bottom = 0.5
	_scrim.offset_top = -170.0
	_scrim.offset_bottom = 170.0
	_scrim.modulate.a = 0.0
	_root.add_child(_scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_card = VBoxContainer.new()
	_card.alignment = BoxContainer.ALIGNMENT_CENTER
	_card.add_theme_constant_override("separation", 14)
	_card.modulate.a = 0.0
	center.add_child(_card)
	_card.resized.connect(func() -> void: _card.pivot_offset = _card.size * 0.5)

	var eyebrow := Label.new()
	eyebrow.text = "VICTORY"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_font_override("font", UITheme.spaced(UITheme.body_font(), 10))
	eyebrow.add_theme_font_size_override("font_size", 20)
	eyebrow.add_theme_color_override("font_color", UITheme.GOLD)
	_card.add_child(eyebrow)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UITheme.spaced(UITheme.display_font(), 10, 0.35))
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", Color(1.0, 0.93, 0.76))
	title.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.02, 0.9))
	title.add_theme_constant_override("outline_size", 4)
	title.add_theme_color_override("font_shadow_color", Color(1.0, 0.6, 0.22, 0.35))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)
	title.add_theme_constant_override("shadow_outline_size", 34)
	_card.add_child(title)

	_card.add_child(UIDivider.new())

	var sub := Label.new()
	sub.text = subtitle_text
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuStyle.style_flavor(sub, 32, Color(0.92, 0.90, 0.88))
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	sub.add_theme_constant_override("outline_size", 4)
	_card.add_child(sub)

	_black = ColorRect.new()
	_black.color = Color(0.0, 0.0, 0.0, 0.0)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_black)
