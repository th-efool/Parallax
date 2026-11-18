class_name FinisherPrompt
extends Control
## Critical-hit finisher prompt (child of the shared HUD). Listens to PlayerController
## finisher_window_opened / finisher_window_closed / finisher_executed. All timing is real time
## because the window runs in slow motion.

const KIND_COLORS: Dictionary = {
	"rend": Color(1.0, 0.74, 0.32),
	"sunder": Color(1.0, 0.42, 0.20),
	"phantom": Color(0.38, 0.86, 1.0),
	"mirror": Color(0.55, 0.95, 1.0),
	"execution": Color(0.95, 0.18, 0.22),
}
const KIND_HINTS: Dictionary = {
	"rend": "flurry",
	"sunder": "shockwave",
	"phantom": "blink strike",
	"mirror": "shatter all around",
	"execution": "kills weakened foes",
}
## Finisher attack name -> prompt kind (for the "chosen" title card).
const FIN_KIND: Dictionary = {
	"fin_rend": "rend", "fin_sunder": "sunder", "fin_phantom": "phantom",
	"fin_mirror_break": "mirror", "fin_execution": "execution",
}
## First windows of a session also show a plain-language tutorial line.
static var _windows_seen: int = 0

var _player: Node = null
var _options: Array = []
var _open_ms: int = 0
var _end_ms: int = 0
var _dur_ms: int = 1
var _state: String = "idle"   # idle | open | chosen | closing
var _chosen_kind: String = ""
var _chosen_name: String = ""
var _state_ms: int = 0


func _ready() -> void:
	name = "FinisherPrompt"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_bind()
	if _state != "idle":
		var now: int = Time.get_ticks_msec()
		if _state == "chosen" and now - _state_ms > 900:
			_state = "idle"
		elif _state == "closing" and now - _state_ms > 220:
			_state = "idle"
		queue_redraw()


func _bind() -> void:
	if not is_inside_tree():
		return
	var p: Node = get_tree().get_first_node_in_group("player")
	if p == null or not p.has_signal("finisher_window_opened"):
		return
	_player = p
	p.connect("finisher_window_opened", _on_opened)
	p.connect("finisher_window_closed", _on_closed)


func _on_opened(duration: float, options: Array) -> void:
	_options = options
	_open_ms = Time.get_ticks_msec()
	_dur_ms = maxi(1, int(duration * 1000.0))
	_end_ms = _open_ms + _dur_ms
	_state = "open"
	_windows_seen += 1
	queue_redraw()


func _on_closed(chosen: String) -> void:
	_state_ms = Time.get_ticks_msec()
	if chosen.is_empty():
		_state = "closing"
		return
	_state = "chosen"
	_chosen_kind = String(FIN_KIND.get(chosen, chosen.trim_prefix("fin_")))
	_chosen_name = _chosen_kind.to_upper()
	for o: Variant in _options:
		var od: Dictionary = o as Dictionary
		if String(od.get("kind", "")) == _chosen_kind:
			_chosen_name = String(od.get("name", _chosen_name))


static func key_text(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventMouseButton:
			match (ev as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT: return "LMB"
				MOUSE_BUTTON_RIGHT: return "RMB"
				MOUSE_BUTTON_MIDDLE: return "MMB"
		if ev is InputEventKey:
			var k: InputEventKey = ev as InputEventKey
			var code: Key = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			return OS.get_keycode_string(code).to_upper()
	return "?"


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if _state == "idle":
		return
	var now: int = Time.get_ticks_msec()
	var s: Vector2 = size
	var t_open: float = clampf(float(now - _open_ms) / 160.0, 0.0, 1.0)
	var remain: float = clampf(float(_end_ms - now) / float(_dur_ms), 0.0, 1.0)
	var fade: float = 1.0
	if _state == "closing":
		fade = 1.0 - clampf(float(now - _state_ms) / 220.0, 0.0, 1.0)
	elif _state == "chosen":
		fade = 1.0 - clampf(float(now - _state_ms) / 900.0, 0.0, 1.0)

	var gold := Color(1.0, 0.84, 0.42)
	# Gold edge vignette pulse (stronger as time runs out).
	if _state == "open" or _state == "closing":
		var pulse: float = 0.55 + 0.45 * sin(float(now) * 0.018)
		var a: float = (0.18 + 0.22 * (1.0 - remain)) * pulse * fade * t_open
		_edge_glow(s, Color(gold.r, gold.g, gold.b, a), 120.0)

	var disp: Font = UITheme.display_font()
	var body: Font = UITheme.body_font()
	var cy: float = s.y * 0.68

	if _state == "chosen":
		var k: float = clampf(float(now - _state_ms) / 140.0, 0.0, 1.0)
		var col: Color = KIND_COLORS.get(_chosen_kind, gold)
		var sz: int = int(lerpf(120.0, 76.0, _ease_out(k)))
		_edge_glow(s, Color(col.r, col.g, col.b, 0.35 * fade), 160.0)
		var y: float = s.y * 0.42
		_text_centered(disp, Vector2(s.x * 0.5, y), _chosen_name, sz, Color(col.r, col.g, col.b, fade), 10)
		_rule(Vector2(s.x * 0.5, y + 26.0), 260.0, Color(col.r, col.g, col.b, 0.8 * fade))
		return

	var appear: float = _ease_out(t_open)
	_draw_target_reticle(now, remain, Color(gold.r, gold.g, gold.b, fade * appear))
	# Header: ◆── CRITICAL ──◆
	var hy: float = cy - 92.0 + (1.0 - appear) * 14.0
	_text_centered(disp, Vector2(s.x * 0.5, hy), "CRITICAL", 40, Color(gold.r, gold.g, gold.b, fade * appear), 8)
	_rule(Vector2(s.x * 0.5, hy + 18.0), 220.0, Color(gold.r, gold.g, gold.b, 0.85 * fade * appear))
	if _windows_seen <= 2:
		_text_centered(body, Vector2(s.x * 0.5, hy - 44.0), "Time slowed — press one key below for a finisher", 20, Color(1, 0.97, 0.9, 0.95 * fade * appear), 6)

	# Options row (+20% diamonds).
	var n: int = _options.size()
	var spacing: float = 260.0 if n <= 3 else minf(240.0, (s.x - 80.0) / float(n))
	for i in n:
		var od: Dictionary = _options[i] as Dictionary
		var kind: String = String(od.get("kind", ""))
		var col: Color = KIND_COLORS.get(kind, gold)
		var delay: float = clampf(float(now - _open_ms - 50 * i) / 180.0, 0.0, 1.0)
		var ap: float = _ease_out(delay) * fade
		var cx: float = s.x * 0.5 + (float(i) - float(n - 1) * 0.5) * spacing
		var c := Vector2(cx, cy + (1.0 - _ease_out(delay)) * 20.0)
		var r: float = 43.0 + 4.3 * sin(float(now) * 0.02 + float(i))
		# Diamond plate.
		_diamond(c, r + 6.0, Color(0.03, 0.03, 0.05, 0.78 * ap))
		_diamond_outline(c, r + 6.0, Color(col.r, col.g, col.b, ap), 2.0)
		_diamond_outline(c, r - 2.0, Color(col.r, col.g, col.b, 0.35 * ap), 1.0)
		_glyph(kind, c, r * 0.55, Color(col.r, col.g, col.b, ap))
		# Keycap.
		var key: String = key_text(String(od.get("input", "")))
		var kw: float = maxf(44.0, body.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 18.0)
		var kr := Rect2(c.x - kw * 0.5, c.y + r + 14.0, kw, 26.0)
		draw_rect(kr, Color(0.06, 0.06, 0.08, 0.9 * ap))
		draw_rect(kr, Color(col.r, col.g, col.b, 0.9 * ap), false, 1.5)
		draw_rect(Rect2(kr.position.x, kr.end.y - 3.0, kr.size.x, 3.0), Color(col.r, col.g, col.b, 0.6 * ap))
		_text_centered(body, Vector2(c.x, kr.position.y + 19.0), key, 18, Color(1, 0.97, 0.9, ap), 0)
		# Name + hint.
		_text_centered(disp, Vector2(c.x, kr.end.y + 30.0), String(od.get("name", kind)), 22, Color(col.r, col.g, col.b, ap), 5)
		_text_centered(UITheme.flavor_font(), Vector2(c.x, kr.end.y + 54.0), String(KIND_HINTS.get(kind, "")), 20, Color(0.97, 0.95, 0.9, 0.95 * ap), 6)

	# Draining timer bar.
	var bw: float = spacing * float(maxi(1, n)) * 0.9
	var by: float = cy + 128.0
	draw_rect(Rect2(s.x * 0.5 - bw * 0.5, by, bw, 4.0), Color(0, 0, 0, 0.55 * fade))
	var urgent: Color = gold.lerp(Color(1.0, 0.3, 0.2), 1.0 - remain)
	draw_rect(Rect2(s.x * 0.5 - bw * 0.5 * remain, by, bw * remain, 4.0), Color(urgent.r, urgent.g, urgent.b, fade))
	_diamond(Vector2(s.x * 0.5 - bw * 0.5 * remain, by + 2.0), 5.0, Color(1, 1, 1, fade))
	_diamond(Vector2(s.x * 0.5 + bw * 0.5 * remain, by + 2.0), 5.0, Color(1, 1, 1, fade))


## Rotating gold lock-on brackets around the crit target (projected each frame), shrinking as time runs out.
func _draw_target_reticle(now: int, remain: float, col: Color) -> void:
	if _player == null or not is_instance_valid(_player) or not _player.has_method("get_finisher_target"):
		return
	var tgt: Node3D = _player.call("get_finisher_target") as Node3D
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
	if tgt == null or cam == null:
		return
	var wp: Vector3 = tgt.global_position + Vector3.UP * 1.1
	if cam.is_position_behind(wp):
		return
	var sp: Vector2 = cam.unproject_position(wp)
	var r: float = 34.0 + 26.0 * remain
	var spin: float = float(now) * 0.004
	for i in 4:
		var a0: float = spin + TAU * float(i) / 4.0
		draw_arc(sp, r, a0, a0 + 0.9, 10, col, 3.0, true)
	_diamond(sp, 4.0, col)
	var exec_col: Color = KIND_COLORS["execution"]
	if tgt is EnemyBase and float((tgt as EnemyBase).health) <= float((tgt as EnemyBase).max_health) * 0.35:
		_text_centered(UITheme.body_font(), sp + Vector2(0, -r - 10.0), "EXECUTABLE", 16, Color(exec_col.r, exec_col.g, exec_col.b, col.a), 4)


func _ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)


func _text_centered(font: Font, pos: Vector2, text: String, fsize: int, col: Color, outline: int) -> void:
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var p := Vector2(pos.x - w * 0.5, pos.y)
	if outline > 0:
		draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, outline, Color(0, 0, 0, 0.8 * col.a))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


func _rule(center: Vector2, half: float, col: Color) -> void:
	var fade_c := Color(col.r, col.g, col.b, 0.0)
	draw_polyline_colors(PackedVector2Array([center - Vector2(half, 0), center - Vector2(10, 0)]), PackedColorArray([fade_c, col]), 1.5, true)
	draw_polyline_colors(PackedVector2Array([center + Vector2(10, 0), center + Vector2(half, 0)]), PackedColorArray([col, fade_c]), 1.5, true)
	_diamond(center, 5.0, col)


func _diamond(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)


func _diamond_outline(c: Vector2, r: float, col: Color, w: float) -> void:
	draw_polyline(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)]), col, w, true)


func _edge_glow(s: Vector2, col: Color, depth: float) -> void:
	var clear := Color(col.r, col.g, col.b, 0.0)
	# top, bottom, left, right gradient strips
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, depth), Vector2(0, depth)]), PackedColorArray([col, col, clear, clear]))
	draw_polygon(PackedVector2Array([Vector2(0, s.y - depth), Vector2(s.x, s.y - depth), Vector2(s.x, s.y), Vector2(0, s.y)]), PackedColorArray([clear, clear, col, col]))
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(depth, 0), Vector2(depth, s.y), Vector2(0, s.y)]), PackedColorArray([col, clear, clear, col]))
	draw_polygon(PackedVector2Array([Vector2(s.x - depth, 0), Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(s.x - depth, s.y)]), PackedColorArray([clear, col, col, clear]))


## Simple vector glyphs: crossed slashes (rend), downward strike (sunder), crescent dash (phantom).
func _glyph(kind: String, c: Vector2, r: float, col: Color) -> void:
	match kind:
		"rend":
			for k: float in [-0.5, 0.0, 0.5]:
				draw_line(c + Vector2(-r + k * r * 0.6, r * 0.8), c + Vector2(r + k * r * 0.6, -r * 0.8), col, 2.5, true)
		"sunder":
			draw_line(c + Vector2(0, -r), c + Vector2(0, r * 0.5), col, 3.0, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.45, r * 0.25), c + Vector2(r * 0.45, r * 0.25), c + Vector2(0, r)]), col)
			draw_line(c + Vector2(-r, r), c + Vector2(r, r), col, 2.0, true)
		"phantom":
			draw_arc(c + Vector2(r * 0.15, 0), r * 0.8, PI * 0.6, PI * 1.4, 18, col, 2.5, true)
			draw_line(c + Vector2(-r * 0.2, 0), c + Vector2(r, 0), col, 2.0, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(r, -r * 0.3), c + Vector2(r * 1.35, 0), c + Vector2(r, r * 0.3)]), col)
		"mirror":
			# Cracked pane: diamond with fracture lines radiating from an off-center point.
			_diamond_outline(c, r, col, 2.0)
			var o: Vector2 = c + Vector2(r * 0.15, -r * 0.1)
			for ang: float in [0.3, 1.5, 2.6, 3.9, 5.1]:
				draw_line(o, o + Vector2(cos(ang), sin(ang)) * r * 0.85, col, 1.8, true)
		"execution":
			# Downward blade over a skull-ish bar.
			draw_line(c + Vector2(0, -r), c + Vector2(0, r * 0.6), col, 3.0, true)
			draw_line(c + Vector2(-r * 0.5, -r * 0.55), c + Vector2(r * 0.5, -r * 0.55), col, 2.5, true)
			draw_circle(c + Vector2(0, r * 0.8), r * 0.22, col)
		_:
			_diamond(c, r * 0.5, col)
