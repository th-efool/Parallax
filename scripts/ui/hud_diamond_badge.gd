class_name HudDiamondBadge
extends Control
## Custom-drawn rotated diamond emblem & vector weapon/action icon matching the PARALLAX HUD art direction.

@export var icon_kind: String = "weapon_sword" : set = set_icon_kind
@export var border_color: Color = Color(0.80, 0.66, 0.42, 0.94) : set = set_border_color
@export var fill_color: Color = Color(0.06, 0.07, 0.10, 0.84) : set = set_fill_color
@export var icon_color: Color = Color(0.95, 0.91, 0.82, 0.96) : set = set_icon_color
@export var circular_frame: bool = false : set = set_circular_frame
@export var highlighted: bool = false : set = set_highlighted


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(54.0, 54.0)
	queue_redraw()


func set_icon_kind(val: String) -> void:
	icon_kind = val
	queue_redraw()


func set_border_color(val: Color) -> void:
	border_color = val
	queue_redraw()


func set_fill_color(val: Color) -> void:
	fill_color = val
	queue_redraw()


func set_icon_color(val: Color) -> void:
	icon_color = val
	queue_redraw()


func set_circular_frame(val: bool) -> void:
	circular_frame = val
	queue_redraw()


func set_highlighted(val: bool) -> void:
	highlighted = val
	queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.46
	if r <= 2.0:
		return

	var b_col: Color = border_color
	var f_col: Color = fill_color
	var i_col: Color = icon_color
	if highlighted:
		b_col = Color(1.0, 0.82, 0.42, 1.0)
		f_col = Color(0.16, 0.12, 0.07, 0.92)
		i_col = Color(1.0, 0.96, 0.85, 1.0)

	if circular_frame:
		draw_circle(c, r, f_col)
		draw_arc(c, r, 0.0, TAU, 36, b_col, 2.0, true)
		draw_arc(c, r * 0.82, 0.0, TAU, 32, Color(b_col.r, b_col.g, b_col.b, 0.35), 1.0, true)
	else:
		var pts := PackedVector2Array([
			c + Vector2(0.0, -r),
			c + Vector2(r, 0.0),
			c + Vector2(0.0, r),
			c + Vector2(-r, 0.0),
		])
		draw_colored_polygon(pts, f_col)
		var ring_pts := PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]])
		draw_polyline(ring_pts, b_col, 2.0, true)

		var ri: float = r * 0.84
		var inner_pts := PackedVector2Array([
			c + Vector2(0.0, -ri),
			c + Vector2(ri, 0.0),
			c + Vector2(0.0, ri),
			c + Vector2(-ri, 0.0),
			c + Vector2(0.0, -ri),
		])
		draw_polyline(inner_pts, Color(b_col.r, b_col.g, b_col.b, 0.36), 1.0, true)
		# Outer echo outline + glow when active, and gems at the four tips.
		var ro: float = r + 3.5
		var echo := PackedVector2Array([
			c + Vector2(0.0, -ro), c + Vector2(ro, 0.0), c + Vector2(0.0, ro), c + Vector2(-ro, 0.0), c + Vector2(0.0, -ro),
		])
		draw_polyline(echo, Color(b_col.r, b_col.g, b_col.b, 0.5 if highlighted else 0.18), 1.0, true)
		if highlighted:
			for gi in 3:
				var rg: float = r + 5.0 + float(gi) * 3.0
				draw_polyline(PackedVector2Array([
					c + Vector2(0.0, -rg), c + Vector2(rg, 0.0), c + Vector2(0.0, rg), c + Vector2(-rg, 0.0), c + Vector2(0.0, -rg),
				]), Color(b_col.r, b_col.g, b_col.b, 0.16 / float(gi + 1)), 2.0, true)
		var gem_c := Color(1.0, 0.92, 0.70, 0.95)
		for tip: Vector2 in [Vector2(0.0, -r), Vector2(r, 0.0), Vector2(0.0, r), Vector2(-r, 0.0)]:
			var gp: Vector2 = c + tip
			draw_colored_polygon(PackedVector2Array([gp + Vector2(0, -3), gp + Vector2(3, 0), gp + Vector2(0, 3), gp + Vector2(-3, 0)]), gem_c)

	_draw_icon(c, r * 0.56, i_col, b_col)


func _draw_icon(c: Vector2, s: float, col: Color, accent: Color) -> void:
	match icon_kind:
		"crest":
			# Ornate vertical blade + inner diamond crest
			draw_line(c + Vector2(0.0, -s * 0.92), c + Vector2(0.0, s * 0.92), col, 2.4, true)
			draw_line(c + Vector2(-s * 0.52, -s * 0.15), c + Vector2(s * 0.52, -s * 0.15), col, 2.2, true)
			var mid_pts := PackedVector2Array([
				c + Vector2(0.0, -s * 0.45),
				c + Vector2(s * 0.36, 0.0),
				c + Vector2(0.0, s * 0.45),
				c + Vector2(-s * 0.36, 0.0),
				c + Vector2(0.0, -s * 0.45),
			])
			draw_polyline(mid_pts, accent, 1.8, true)

		"weapon_sword":
			# Angled broadsword from bottom-left hilt to top-right tip
			draw_line(c + Vector2(-s * 0.68, s * 0.68), c + Vector2(s * 0.72, -s * 0.72), col, 3.2, true)
			draw_line(c + Vector2(-s * 0.42, s * 0.16), c + Vector2(-s * 0.16, s * 0.42), accent, 2.8, true)
			draw_circle(c + Vector2(-s * 0.68, s * 0.68), 3.0, accent)

		"light_attack":
			# Diagonal swift blade + slash arc
			draw_line(c + Vector2(-s * 0.60, s * 0.60), c + Vector2(s * 0.65, -s * 0.65), col, 2.6, true)
			draw_line(c + Vector2(-s * 0.40, s * 0.12), c + Vector2(-s * 0.12, s * 0.40), col, 2.2, true)
			draw_arc(c, s * 0.72, deg_to_rad(-115.0), deg_to_rad(-25.0), 14, accent, 1.6, true)

		"heavy_attack":
			# Heavy greatsword diagonal + double cleave edge
			draw_line(c + Vector2(-s * 0.62, s * 0.62), c + Vector2(s * 0.68, -s * 0.68), col, 3.8, true)
			draw_line(c + Vector2(-s * 0.45, s * 0.05), c + Vector2(-s * 0.05, s * 0.45), accent, 3.0, true)
			draw_line(c + Vector2(-s * 0.10, -s * 0.72), c + Vector2(s * 0.72, s * 0.10), Color(accent.r, accent.g, accent.b, 0.72), 1.6, true)

		"dodge":
			# Forward dash silhouette + twin wind streaks
			draw_line(c + Vector2(-s * 0.78, -s * 0.25), c + Vector2(-s * 0.18, -s * 0.25), accent, 1.8, true)
			draw_line(c + Vector2(-s * 0.85, s * 0.10), c + Vector2(-s * 0.25, s * 0.10), accent, 1.8, true)
			draw_circle(c + Vector2(s * 0.22, -s * 0.36), s * 0.17, col)
			draw_line(c + Vector2(s * 0.16, -s * 0.16), c + Vector2(-s * 0.06, s * 0.34), col, 2.6, true)
			draw_line(c + Vector2(-s * 0.06, s * 0.34), c + Vector2(-s * 0.44, s * 0.62), col, 2.2, true)
			draw_line(c + Vector2(-s * 0.06, s * 0.34), c + Vector2(s * 0.48, s * 0.56), col, 2.2, true)

		"jump":
			# Twin upward wing chevrons
			var top_chev := PackedVector2Array([
				c + Vector2(-s * 0.55, s * 0.08),
				c + Vector2(0.0, -s * 0.55),
				c + Vector2(s * 0.55, s * 0.08),
			])
			draw_polyline(top_chev, col, 2.6, true)
			var low_chev := PackedVector2Array([
				c + Vector2(-s * 0.42, s * 0.52),
				c + Vector2(0.0, s * 0.02),
				c + Vector2(s * 0.42, s * 0.52),
			])
			draw_polyline(low_chev, accent, 2.0, true)

		"landing_attack":
			# Plunging vertical blade + radial ground burst rays
			draw_line(c + Vector2(0.0, -s * 0.75), c + Vector2(0.0, s * 0.35), col, 2.8, true)
			draw_line(c + Vector2(-s * 0.30, -s * 0.32), c + Vector2(s * 0.30, -s * 0.32), col, 2.2, true)
			draw_line(c + Vector2(-s * 0.72, s * 0.55), c + Vector2(s * 0.72, s * 0.55), accent, 2.2, true)
			draw_line(c + Vector2(-s * 0.45, s * 0.25), c + Vector2(-s * 0.65, s * 0.55), accent, 1.8, true)
			draw_line(c + Vector2(s * 0.45, s * 0.25), c + Vector2(s * 0.65, s * 0.55), accent, 1.8, true)

		"swap":
			# Dual oppose arrows (<->) inside central realm medallion
			draw_line(c + Vector2(-s * 0.62, -s * 0.24), c + Vector2(s * 0.52, -s * 0.24), col, 2.2, true)
			draw_line(c + Vector2(s * 0.26, -s * 0.48), c + Vector2(s * 0.56, -s * 0.24), col, 2.2, true)
			draw_line(c + Vector2(s * 0.26, 0.0), c + Vector2(s * 0.56, -s * 0.24), col, 2.2, true)
			draw_line(c + Vector2(s * 0.62, s * 0.24), c + Vector2(-s * 0.52, s * 0.24), col, 2.2, true)
			draw_line(c + Vector2(-s * 0.26, 0.0), c + Vector2(-s * 0.56, s * 0.24), col, 2.2, true)
			draw_line(c + Vector2(-s * 0.26, s * 0.48), c + Vector2(-s * 0.56, s * 0.24), col, 2.2, true)
