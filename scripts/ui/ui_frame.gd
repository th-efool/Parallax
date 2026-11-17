class_name UIFrame
extends PanelContainer
## Chamfered gothic panel: dark glass fill, double gold keyline, corner gems.
## Drop-in replacement for PanelContainer (content margins come from `pad_h` / `pad_v`).

@export var chamfer: float = 18.0
@export var accent: Color = UITheme.GOLD
@export var fill: Color = Color(0.050, 0.056, 0.088, 0.93)
@export var pad_h: int = 28:
	set(v):
		pad_h = v
		_apply_margins()
@export var pad_v: int = 24:
	set(v):
		pad_v = v
		_apply_margins()
@export var glow: float = 0.0   ## 0..1 soft outer accent glow (realm tint)


func _init() -> void:
	_apply_margins()


func _apply_margins() -> void:
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	add_theme_stylebox_override("panel", sb)


func set_accent(c: Color) -> void:
	accent = c
	queue_redraw()


func _outline(rect: Rect2, c: float) -> PackedVector2Array:
	var l: float = rect.position.x
	var t: float = rect.position.y
	var r: float = rect.end.x
	var b: float = rect.end.y
	return PackedVector2Array([
		Vector2(l + c, t), Vector2(r - c, t), Vector2(r, t + c), Vector2(r, b - c),
		Vector2(r - c, b), Vector2(l + c, b), Vector2(l, b - c), Vector2(l, t + c), Vector2(l + c, t),
	])


func _draw() -> void:
	var s: Vector2 = size
	if s.x < 8.0 or s.y < 8.0:
		return
	var c: float = minf(chamfer, minf(s.x, s.y) * 0.25)
	var outer := Rect2(Vector2(2, 2), s - Vector2(4, 4))
	# Soft drop shadow.
	var shadow := _outline(Rect2(outer.position + Vector2(0, 6), outer.size), c)
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.45))
	# Fill.
	var poly := _outline(outer, c)
	draw_colored_polygon(poly.slice(0, poly.size() - 1), fill)
	# Top-down subtle sheen.
	var sheen := PackedVector2Array([
		Vector2(outer.position.x + c, outer.position.y), Vector2(outer.end.x - c, outer.position.y),
		Vector2(outer.end.x, outer.position.y + c), Vector2(outer.end.x, outer.position.y + c + 40.0),
		Vector2(outer.position.x, outer.position.y + c + 40.0), Vector2(outer.position.x, outer.position.y + c),
	])
	draw_colored_polygon(sheen, Color(accent.r, accent.g, accent.b, 0.045))
	if glow > 0.0:
		for i in 4:
			var g := _outline(outer.grow(float(i) * 3.0), c + float(i) * 3.0)
			draw_polyline(g, Color(accent.r, accent.g, accent.b, glow * 0.10 / float(i + 1)), 2.0, true)
	# Outer keyline + inner hairline.
	draw_polyline(poly, Color(accent.r, accent.g, accent.b, 0.95), 2.0, true)
	var inner := _outline(outer.grow(-7.0), maxf(2.0, c - 5.0))
	draw_polyline(inner, Color(accent.r, accent.g, accent.b, 0.30), 1.0, true)
	# Corner gems on the chamfers.
	var gem_col := Color(UITheme.GOLD_BRIGHT.r, UITheme.GOLD_BRIGHT.g, UITheme.GOLD_BRIGHT.b, 0.95)
	for p: Vector2 in [
		Vector2(outer.position.x + c * 0.5, outer.position.y + c * 0.5), Vector2(outer.end.x - c * 0.5, outer.position.y + c * 0.5),
		Vector2(outer.end.x - c * 0.5, outer.end.y - c * 0.5), Vector2(outer.position.x + c * 0.5, outer.end.y - c * 0.5),
	]:
		_gem(p, 4.0, gem_col)
	# Top-centre notch ornament.
	var cx: float = s.x * 0.5
	_gem(Vector2(cx, outer.position.y), 5.0, gem_col)
	draw_line(Vector2(cx - 46, outer.position.y), Vector2(cx - 9, outer.position.y), gem_col, 2.0)
	draw_line(Vector2(cx + 9, outer.position.y), Vector2(cx + 46, outer.position.y), gem_col, 2.0)


func _gem(p: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), col)
