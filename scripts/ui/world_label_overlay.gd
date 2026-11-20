class_name WorldLabelOverlay
extends Control
## Draws every in-world text label as crisp 2D HUD text at the label's projected screen position.
## Label3D text is hard to read in this game: it is tiny at fixed size, softened by bloom, tinted by
## fog and depth-sorted with transparent VFX. Instead, code "adopts" a Label3D: the node keeps its
## text / modulate / visible / position (so every existing script that updates it keeps working), it stops
## rendering in 3D (transparency = 1), and this overlay draws it with the UI theme font, an outline and a
## distance fade. Child of the shared HUD's RootControl (added by HUDController), drawn under the HUD panels.

const GROUP: String = "world_label_2d"
const FADE_M: float = 4.0

## opts:
##   px: int font size in HUD pixels (default 18)
##   offset: Vector2 extra screen offset (default 0,0), e.g. to stack several labels on one enemy
##   font: "body" | "display" | "flavor" (default "body")
##   max_dist: float metres from the camera beyond which the label is hidden (default 40)
##   kind: "text" | "bar" | "mark" | "mark_nearby"
static func adopt(l: Label3D, opts: Dictionary = {}) -> void:
	if l == null:
		return
	l.add_to_group(GROUP)
	l.set_meta("wl_px", int(opts.get("px", 18)))
	l.set_meta("wl_offset", opts.get("offset", Vector2.ZERO))
	l.set_meta("wl_font", String(opts.get("font", "body")))
	l.set_meta("wl_max_dist", float(opts.get("max_dist", 40.0)))
	l.set_meta("wl_kind", String(opts.get("kind", "text")))
	l.transparency = 1.0
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _ready() -> void:
	name = "WorldLabelOverlay"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not is_inside_tree():
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var s: Vector2 = size
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var k: Vector2 = s / vp
	var cam_pos: Vector3 = cam.global_position
	var items: Array = []
	for n in get_tree().get_nodes_in_group(GROUP):
		var l: Label3D = n as Label3D
		if l == null or not l.is_visible_in_tree():
			continue
		var kind: String = String(l.get_meta("wl_kind", "text"))
		if kind == "text" and l.text.is_empty():
			continue
		var wp: Vector3 = l.global_position
		if cam.is_position_behind(wp):
			continue
		var dist: float = cam_pos.distance_to(wp)
		var max_d: float = float(l.get_meta("wl_max_dist", 40.0))
		if dist > max_d:
			continue
		var p: Vector2 = cam.unproject_position(wp) * k + (l.get_meta("wl_offset", Vector2.ZERO) as Vector2)
		if p.x < -200.0 or p.y < -200.0 or p.x > s.x + 200.0 or p.y > s.y + 200.0:
			continue
		var fade_span: float = 20.0 if max_d > 80.0 else FADE_M
		var fade: float = clampf((max_d - dist) / fade_span, 0.0, 1.0)
		items.append([dist, l, p, fade])
	# Far labels first so near ones draw on top.
	items.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	for it in items:
		_draw_label(it[1] as Label3D, it[2] as Vector2, float(it[3]))


func _font_for(l: Label3D) -> Font:
	match String(l.get_meta("wl_font", "body")):
		"display":
			return UITheme.display_font()
		"flavor":
			return UITheme.flavor_font()
	return UITheme.body_font()


func _draw_label(l: Label3D, p: Vector2, fade: float) -> void:
	var font: Font = _font_for(l)
	var px: int = int(l.get_meta("wl_px", 18))
	var col: Color = l.modulate
	col.a *= fade
	var ocol: Color = l.outline_modulate
	ocol.a = 0.85 * col.a
	var kind: String = String(l.get_meta("wl_kind", "text"))
	if kind == "bar":
		var ratio: float = clampf(float(l.get_meta("hp_ratio", 1.0)), 0.0, 1.0)
		var r := Rect2(p.x - 48.0, p.y - 4.0, 96.0, 8.0)
		draw_rect(r.grow(1.0), Color(0, 0, 0, 0.75 * col.a))
		draw_rect(Rect2(r.position, Vector2(r.size.x * ratio, r.size.y)), Color(col.r, col.g, col.b, col.a))
		if not l.text.is_empty():
			_line(font, Vector2(r.end.x + 6.0, p.y + float(px) * 0.38), l.text, px, Color(1, 1, 1, 0.9 * col.a), ocol, false)
		return
	if kind == "mark":
		var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.0055)
		var rr: float = 9.0 + pulse * 2.5
		var ring := PackedVector2Array([
			Vector2(p.x, p.y - rr),
			Vector2(p.x + rr, p.y),
			Vector2(p.x, p.y + rr),
			Vector2(p.x - rr, p.y),
			Vector2(p.x, p.y - rr),
		])
		draw_polyline(ring, Color(0.0, 0.0, 0.0, 0.78 * col.a), 4.2, true)
		draw_polyline(ring, col, 2.0, true)
		var core := PackedVector2Array([
			Vector2(p.x, p.y - 4.2),
			Vector2(p.x + 4.2, p.y),
			Vector2(p.x, p.y + 4.2),
			Vector2(p.x - 4.2, p.y),
		])
		draw_colored_polygon(core, col)
		var chev := PackedVector2Array([
			Vector2(p.x - 6.0, p.y + rr + 3.0),
			Vector2(p.x, p.y + rr + 8.5),
			Vector2(p.x + 6.0, p.y + rr + 3.0),
		])
		draw_polyline(chev, Color(0.0, 0.0, 0.0, 0.8 * col.a), 4.0, true)
		draw_polyline(chev, col, 2.0, true)
		if not l.text.is_empty():
			_line(font, Vector2(p.x, p.y - rr - 6.0), l.text, px, col, ocol, true)
		return
	if kind == "mark_nearby":
		var dr: float = 6.2
		var pip := PackedVector2Array([
			Vector2(p.x, p.y - dr),
			Vector2(p.x + dr, p.y),
			Vector2(p.x, p.y + dr),
			Vector2(p.x - dr, p.y),
			Vector2(p.x, p.y - dr),
		])
		draw_polyline(pip, Color(0.0, 0.0, 0.0, 0.7 * col.a), 3.4, true)
		draw_polyline(pip, col, 1.6, true)
		return
	var lines: PackedStringArray = l.text.split("\n")
	var lh: float = float(px) * 1.15
	var y0: float = p.y - lh * float(lines.size() - 1)
	var max_w: float = 0.0
	for line in lines:
		max_w = maxf(max_w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
	var backing := Rect2(p.x - max_w * 0.5 - 8.0, y0 - float(px) * 0.8, max_w + 16.0, lh * float(lines.size()) + 4.0)
	draw_rect(backing, Color(0.02, 0.02, 0.03, 0.6 * fade))
	for i in range(lines.size()):
		_line(font, Vector2(p.x, y0 + lh * float(i)), lines[i], px, col, ocol, true)


func _line(font: Font, pos: Vector2, t: String, px: int, col: Color, ocol: Color, centered: bool) -> void:
	var x: float = pos.x
	if centered:
		x -= font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x * 0.5
	draw_string_outline(font, Vector2(x, pos.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, maxi(5, int(px / 3.0)), ocol)
	draw_string(font, Vector2(x, pos.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
