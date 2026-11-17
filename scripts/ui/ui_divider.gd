class_name UIDivider
extends Control
## Gold rule with a centred gem: ──────◆──────

@export var color: Color = UITheme.GOLD


func _init() -> void:
	custom_minimum_size = Vector2(0, 14)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var y: float = size.y * 0.5
	var cx: float = size.x * 0.5
	var fade := Color(color.r, color.g, color.b, 0.0)
	var solid := Color(color.r, color.g, color.b, 0.75)
	# Gradient lines fading outward.
	var steps: int = 24
	for side: int in [-1, 1]:
		for i in steps:
			var t0: float = float(i) / float(steps)
			var t1: float = float(i + 1) / float(steps)
			var x0: float = cx + float(side) * (12.0 + t0 * (cx - 12.0))
			var x1: float = cx + float(side) * (12.0 + t1 * (cx - 12.0))
			draw_line(Vector2(x0, y), Vector2(x1, y), solid.lerp(fade, t0), 1.5)
	var r: float = 5.0
	draw_colored_polygon(PackedVector2Array([Vector2(cx, y - r), Vector2(cx + r, y), Vector2(cx, y + r), Vector2(cx - r, y)]), UITheme.GOLD_BRIGHT)
