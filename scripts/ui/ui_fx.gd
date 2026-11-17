class_name UIFx
extends RefCounted
## Reusable UI motion + sound helpers. All tweens bind to the node so they die with it
## and use TWEEN_PAUSE_PROCESS so menus animate while the tree is paused.


static func _play(cue: String, db: float = 0.0) -> void:
	if AudioManager.instance != null:
		AudioManager.instance.play_sfx(cue, db)


## Hover nudge + click/confirm sounds. Safe to call twice on one button.
static func wire_button(btn: BaseButton, confirm_sound: bool = true) -> void:
	if btn == null or btn.has_meta("ui_fx_wired"):
		return
	btn.set_meta("ui_fx_wired", true)
	btn.pivot_offset = btn.size * 0.5
	btn.resized.connect(func() -> void: btn.pivot_offset = btn.size * 0.5)
	btn.mouse_entered.connect(func() -> void:
		if btn.disabled:
			return
		_play("ui_click", -6.0)
		_scale_to(btn, 1.025, 0.10))
	btn.mouse_exited.connect(func() -> void: _scale_to(btn, 1.0, 0.14))
	btn.focus_entered.connect(func() -> void:
		_play("ui_click", -9.0)
		_scale_to(btn, 1.025, 0.10))
	btn.focus_exited.connect(func() -> void: _scale_to(btn, 1.0, 0.14))
	btn.pressed.connect(func() -> void:
		if confirm_sound:
			_play("ui_confirm", -4.0)
		pop(btn, 0.94, 0.12))


static func _scale_to(node: Control, s: float, dur: float) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	var tw: Tween = node.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(node, "scale", Vector2(s, s), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Quick squash-and-rebound.
static func pop(node: Control, from_scale: float = 0.9, dur: float = 0.18) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	node.scale = Vector2(from_scale, from_scale)
	var tw: Tween = node.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(node, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Fade + slide children of a container in one after another.
static func stagger_in(items: Array, delay_each: float = 0.06, dur: float = 0.35) -> void:
	var i: int = 0
	for it: Variant in items:
		var c: Control = it as Control
		if c == null or not is_instance_valid(c) or not c.is_inside_tree():
			continue
		c.modulate.a = 0.0
		var tw: Tween = c.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_interval(delay_each * float(i))
		tw.tween_property(c, "modulate:a", 1.0, dur).set_trans(Tween.TRANS_SINE)
		i += 1


## Fade a whole screen in (use when making a screen visible).
static func fade_in(node: CanvasItem, dur: float = 0.25) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	node.modulate.a = 0.0
	var tw: Tween = node.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(node, "modulate:a", 1.0, dur).set_trans(Tween.TRANS_SINE)


## Horizontal shake for errors / rejected actions.
static func shake(node: Control, strength: float = 8.0, dur: float = 0.28) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	var base: float = node.rotation
	var tw: Tween = node.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var k: float = deg_to_rad(strength * 0.25)
	for sign_v: float in [1.0, -1.0, 0.7, -0.7, 0.0]:
		tw.tween_property(node, "rotation", base + k * sign_v, dur / 5.0)


## Animated count-up for score-style labels.
static func count_up(label: Label, to_value: int, dur: float = 0.8, fmt: String = "%d") -> void:
	if not is_instance_valid(label) or not label.is_inside_tree():
		return
	var tw: Tween = label.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_method(func(v: float) -> void: label.text = fmt % int(v), 0.0, float(to_value), dur).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
