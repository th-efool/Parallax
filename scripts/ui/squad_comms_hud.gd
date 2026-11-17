class_name SquadCommsHUD
extends Control
## Squad comms layer of the single shared HUD (added by HUDController like FinisherPrompt). Owns the
## `SquadComms` hub from the Squad AI plugin and draws, in the Cracked Mirror UI kit style:
##   - squad roster plates (name, role glyph, HP, live state; DOWN plates pulse red with the revive hint)
##   - mic indicator / on-screen push-to-talk button (hold), live level ring, transcribing spinner
##   - toggleable chat bar (Enter opens/sends, Esc closes) — same `submit_utterance` path as voice
##   - subtitles (speaker-coloured, streaming), notifications (API errors etc.), optional command log
##   - cinematic mode (F10): hides the whole HUD plus enemy / ally overhead labels.

const ACTIONS: Dictionary = {
	"squad_chat": [KEY_ENTER, KEY_KP_ENTER],
	"push_to_talk": [KEY_V],
	"toggle_command_log": [KEY_L],
	"cinematic_mode": [KEY_F10],
}
const ROLE_GLYPH: Dictionary = {"vanguard": "◆", "skirmisher": "➶", "artillery": "✦"}

var comms: SquadComms = null
var _chat_panel: UIFrame = null
var _chat_edit: LineEdit = null
var _chat_open: bool = false
var _mic_btn: Control = null
var _roster: Array = []
var _roster_timer: float = 0.0
var _subs: Array[Dictionary] = []        # {speaker, text, color, t, final}
var _notes: Array[Dictionary] = []       # {text, level, t}
var _log: Array[Dictionary] = []
var _log_visible: bool = true
var _mic_level: float = 0.0
var _cinematic: bool = false
var _ptt_held_key: bool = false
var _ptt_held_mouse: bool = false


func _ready() -> void:
	name = "SquadCommsHUD"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ensure_actions()
	SquadAIConfig.ensure_loaded()
	_log_visible = SquadAIConfig.show_command_log
	comms = SquadComms.new()
	comms.name = "SquadComms"
	add_child(comms)
	comms.notify.connect(_on_notify)
	comms.subtitle.connect(_on_subtitle)
	comms.log_entry.connect(_on_log)
	comms.mic_level.connect(func(r: float) -> void: _mic_level = maxf(_mic_level, clampf(r * 6.0, 0.0, 1.0)))
	comms.mic_state_changed.connect(func(_s: String) -> void: queue_redraw())
	comms.roster_prompt_updated.connect(func(_t: String) -> void: _refresh_roster())
	_build_chat_bar()
	_build_mic_button()


static func _ensure_actions() -> void:
	for a in ACTIONS.keys():
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a)
		for k in (ACTIONS[a] as Array):
			var ev := InputEventKey.new()
			ev.physical_keycode = int(k)
			InputMap.action_add_event(a, ev)


# ------------------------------------------------------------------ widgets

func _build_chat_bar() -> void:
	_chat_panel = UIFrame.new()
	_chat_panel.name = "ChatBar"
	_chat_panel.pad_h = 22
	_chat_panel.pad_v = 12
	_chat_panel.chamfer = 12.0
	_chat_panel.visible = false
	_chat_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_chat_panel)
	UITheme.apply(_chat_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_chat_panel.add_child(row)
	var lbl := Label.new()
	lbl.text = "ORDER ›"
	lbl.add_theme_font_override("font", UITheme.display_font())
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	row.add_child(lbl)
	_chat_edit = LineEdit.new()
	_chat_edit.name = "ChatEdit"
	_chat_edit.placeholder_text = "e.g.  Sera, kite the brute  ·  everyone massacre  ·  Brannoc guard Ivo  ·  jump 3 times"
	_chat_edit.custom_minimum_size = Vector2(640, 40)
	_chat_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_edit.add_theme_font_size_override("font_size", 20)
	_chat_edit.max_length = 280
	_chat_edit.text_submitted.connect(_on_chat_submitted)
	row.add_child(_chat_edit)
	var send := Button.new()
	send.text = "SEND"
	MenuStyle.style_button(send, 16, 40.0)
	send.pressed.connect(func() -> void: _on_chat_submitted(_chat_edit.text))
	row.add_child(send)


func _build_mic_button() -> void:
	_mic_btn = Control.new()
	_mic_btn.name = "MicButton"
	_mic_btn.custom_minimum_size = Vector2(64, 64)
	_mic_btn.size = Vector2(64, 64)
	_mic_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_mic_btn.tooltip_text = "Hold to talk (or hold V)"
	_mic_btn.gui_input.connect(_on_mic_gui_input)
	_mic_btn.draw.connect(_draw_mic)
	add_child(_mic_btn)


func _on_mic_gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if ev.is_pressed() and not _ptt_held_mouse:
			_ptt_held_mouse = true
			comms.begin_voice()
		elif not ev.is_pressed() and _ptt_held_mouse:
			_ptt_held_mouse = false
			comms.end_voice()
		_mic_btn.accept_event()


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if comms == null:
		return
	if event.is_action_pressed("cinematic_mode") and not _chat_open:
		set_cinematic(not _cinematic)
		get_viewport().set_input_as_handled()
		return
	if _chat_open:
		if event is InputEventKey and event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
			close_chat()
			get_viewport().set_input_as_handled()
		return
	if _blocked_by_menu():
		return
	if event.is_action_pressed("squad_chat") and not event.is_echo():
		open_chat()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("push_to_talk") and not event.is_echo():
		_ptt_held_key = true
		comms.begin_voice()
		get_viewport().set_input_as_handled()
	elif event.is_action_released("push_to_talk") and _ptt_held_key:
		_ptt_held_key = false
		comms.end_voice()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_command_log") and not event.is_echo():
		_log_visible = not _log_visible
		SquadAIConfig.show_command_log = _log_visible
		SquadAIConfig.save()
		queue_redraw()


func _blocked_by_menu() -> bool:
	if get_tree().paused:
		return true
	for grp in ["title_screen", "pause_menu", "options_screen", "leaderboard_screen", "results_screen"]:
		for n in get_tree().get_nodes_in_group(grp):
			if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
				return true
	return false


func open_chat() -> void:
	if not SquadAIConfig.chat_allowed():
		_on_notify("Chat is disabled (Squad Comms mode: voice only). Hold V to talk.", "warn")
		return
	_chat_open = true
	_chat_panel.visible = true
	_chat_edit.text = ""
	_chat_edit.grab_focus()
	PlayerController.ui_input_locked = true
	if _cinematic:
		set_cinematic(false)


func close_chat() -> void:
	_chat_open = false
	_chat_panel.visible = false
	_chat_edit.release_focus()
	PlayerController.ui_input_locked = false


func is_chat_open() -> bool:
	return _chat_open


func _on_chat_submitted(t: String) -> void:
	var text: String = t.strip_edges()
	close_chat()
	if not text.is_empty():
		comms.submit_utterance(text, "chat")


## Test / automation hook: exactly what the chat bar does on Enter.
func submit_chat_text(t: String) -> void:
	_on_chat_submitted(t)


func set_cinematic(on: bool) -> void:
	_cinematic = on
	var hud: CanvasLayer = get_parent().get_parent() as CanvasLayer if get_parent() != null else null
	if hud != null:
		hud.visible = not on
	for e in get_tree().get_nodes_in_group("enemy"):
		for nm in ["FloatingHPBar", "StateIcon", "IntelTag"]:
			var l: Node3D = (e as Node).get_node_or_null(nm) as Node3D
			if l != null:
				l.set_meta("cinematic_hidden", on)
				if on:
					l.visible = false
				elif nm == "FloatingHPBar":
					l.visible = true
	for a in get_tree().get_nodes_in_group("squad_ally"):
		for c in (a as Node).get_children():
			if c is Label3D or (c is MeshInstance3D and (c as MeshInstance3D).mesh is TorusMesh):
				(c as Node3D).set_meta("cinematic_hidden", on)
				(c as Node3D).visible = not on


# ------------------------------------------------------------------ feeds

func _on_notify(text: String, level: String) -> void:
	_notes.append({"text": text, "level": level, "t": 0.0})
	while _notes.size() > 3:
		_notes.pop_front()


func _on_subtitle(speaker: String, text: String, color: Color, final: bool) -> void:
	if not SquadAIConfig.show_subtitles:
		return
	# Streaming update replaces this speaker's live (non-final) line.
	for s in _subs:
		if String(s["speaker"]) == speaker and not bool(s["final"]):
			s["text"] = text
			s["final"] = final
			s["t"] = 0.0
			return
	_subs.append({"speaker": speaker, "text": text, "color": color, "t": 0.0, "final": final})
	while _subs.size() > 3:
		_subs.pop_front()


func _on_log(entry: Dictionary) -> void:
	_log.append(entry)
	while _log.size() > 9:
		_log.pop_front()


func _refresh_roster() -> void:
	var m: AllySquadManager = AllySquadManager.instance
	_roster = m.get_roster() if m != null else []


# ------------------------------------------------------------------ frame

func _process(delta: float) -> void:
	var real_dt: float = delta / maxf(0.05, Engine.time_scale)
	_roster_timer -= real_dt
	if _roster_timer <= 0.0:
		_roster_timer = 0.2
		_refresh_roster()
	for s in _subs:
		s["t"] = float(s["t"]) + real_dt
	_subs = _subs.filter(func(s: Dictionary) -> bool: return float(s["t"]) < (6.5 if bool(s["final"]) else 12.0))
	for n in _notes:
		n["t"] = float(n["t"]) + real_dt
	_notes = _notes.filter(func(n: Dictionary) -> bool: return float(n["t"]) < 5.0)
	_mic_level = maxf(0.0, _mic_level - real_dt * 1.5)
	# Layout (virtual 1920x1080, aspect expand).
	var s: Vector2 = size
	if _chat_panel != null:
		_chat_panel.size = Vector2(minf(900.0, s.x - 80.0), 0)
		_chat_panel.position = Vector2((s.x - _chat_panel.size.x) * 0.5, s.y - 238.0)
	if _mic_btn != null:
		_mic_btn.position = Vector2(s.x - 108.0, s.y * 0.5 + 60.0)
		_mic_btn.visible = SquadAIConfig.voice_allowed()
		_mic_btn.queue_redraw()
	queue_redraw()


func _draw() -> void:
	if _cinematic:
		return
	var s: Vector2 = size
	_draw_roster(Vector2(28.0, s.y * 0.30))
	_draw_subtitles(s)
	_draw_notes(s)
	if _log_visible:
		_draw_log(Vector2(s.x - 470.0, s.y * 0.30))
	if not _chat_open and SquadAIConfig.chat_allowed():
		var hint: String = "ENTER  orders" + ("   ·   V  talk" if SquadAIConfig.voice_allowed() else "") + "   ·   L  log   ·   F10  cinematic"
		_text(UITheme.body_font(), Vector2(28.0, s.y * 0.30 - 14.0), hint, 16, Color(0.95, 0.9, 0.78, 0.92), 4)


# ------------------------------------------------------------------ drawing

func _draw_roster(origin: Vector2) -> void:
	var disp: Font = UITheme.display_font()
	var body: Font = UITheme.body_font()
	var y: float = origin.y
	var now: float = float(Time.get_ticks_msec()) * 0.001
	var m: AllySquadManager = AllySquadManager.instance
	if m != null and not m.active_strategy.is_empty():
		_text(disp, Vector2(origin.x, y - 40.0), "STRATEGY · " + m.active_strategy.to_upper(), 17, Color(1.0, 0.93, 0.72, 1.0), 6)
	for r_v in _roster:
		var r: Dictionary = r_v as Dictionary
		var col: Color = r.get("color", UITheme.GOLD) as Color
		var down: bool = bool(r.get("downed", false))
		var rect := Rect2(origin.x, y, 300.0, 78.0)
		var c: float = 9.0
		var poly := _chamfer(rect, c)
		draw_colored_polygon(poly, Color(0.035, 0.04, 0.065, 0.80))
		var edge: Color = col if not down else Color(1.0, 0.3, 0.25).lerp(Color(0.5, 0.1, 0.1), 0.5 + 0.5 * sin(now * 6.0))
		poly.append(poly[0])
		draw_polyline(poly, Color(edge.r, edge.g, edge.b, 0.9), 1.5, true)
		draw_rect(Rect2(rect.position.x + 3.0, rect.position.y + 8.0, 3.0, rect.size.y - 16.0), Color(col.r, col.g, col.b, 0.95))
		var glyph: String = String(ROLE_GLYPH.get(String(r.get("role", "")), "◆"))
		_text(disp, rect.position + Vector2(16.0, 24.0), glyph + "  " + String(r.get("name", "")).to_upper(), 19, Color(col.r, col.g, col.b, 1.0), 4)
		_text(body, rect.position + Vector2(rect.size.x - 12.0 - body.get_string_size(String(r.get("role", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, 21.0), String(r.get("role", "")).to_upper(), 13, Color(0.75, 0.75, 0.8, 0.8), 2)
		var ratio: float = clampf(float(r.get("hp", 0)) / maxf(1.0, float(r.get("max_hp", 1))), 0.0, 1.0)
		var bar := Rect2(rect.position.x + 16.0, rect.position.y + 32.0, 180.0, 6.0)
		draw_rect(bar, Color(0, 0, 0, 0.6))
		var hp_col: Color = Color(0.45, 0.95, 0.55) if ratio > 0.5 else (Color(1.0, 0.8, 0.3) if ratio > 0.25 else Color(1.0, 0.3, 0.25))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), hp_col)
		var st: String = "DOWN — E to revive" if down else String(r.get("state", ""))
		if int(r.get("queued", 0)) > 0 and not down:
			st += "  +%d queued" % int(r.get("queued", 0))
		_text(body, rect.position + Vector2(16.0, 53.0), _fit(body, st, 14, 270.0), 14, Color(1, 0.55, 0.5) if down else Color(0.88, 0.88, 0.92, 0.9), 2)
		var buffs: String = String(r.get("buffs", ""))
		if not buffs.is_empty() and not down:
			_text(body, rect.position + Vector2(204.0, 39.0), buffs.strip_edges(), 12, Color(1.0, 0.85, 0.45, 0.95), 2)
		# Skill pills: lit when ready, dim with seconds while cooling down.
		var sx: float = rect.position.x + 16.0
		for sk_v in (r.get("skills", []) as Array):
			var sk: Dictionary = sk_v as Dictionary
			var rem: float = float(sk.get("remaining", 0.0))
			var scol: Color = sk.get("color", UITheme.GOLD) as Color
			var label: String = String(sk.get("name", "")).get_slice(" ", 0).left(7).to_upper()
			if rem > 0.0:
				label += " %d" % int(ceil(rem))
			var w: float = body.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 10.0
			var pill := Rect2(sx, rect.position.y + 60.0, w, 13.0)
			var ready: bool = rem <= 0.0 and not down
			draw_rect(pill, Color(scol.r, scol.g, scol.b, 0.28 if ready else 0.08))
			draw_rect(pill, Color(scol.r, scol.g, scol.b, 0.9 if ready else 0.3), false, 1.0)
			_text(body, Vector2(sx + 5.0, rect.position.y + 71.0), label, 11, Color(1, 1, 1, 0.95) if ready else Color(0.7, 0.7, 0.75, 0.7), 0)
			sx += w + 4.0
			if sx > rect.end.x - 30.0:
				break
		y += 84.0


func _draw_subtitles(s: Vector2) -> void:
	var body: Font = UITheme.body_font()
	var disp: Font = UITheme.display_font()
	var base_y: float = s.y - 286.0
	var i: int = 0
	for k in range(_subs.size() - 1, -1, -1):
		var sub: Dictionary = _subs[k]
		var a: float = clampf((6.5 - float(sub["t"])) / 0.8, 0.0, 1.0) if bool(sub["final"]) else 1.0
		var col: Color = sub["color"] as Color
		var name_s: String = String(sub["speaker"]).to_upper() + "  "
		var text_s: String = String(sub["text"])
		if text_s.length() > 110:
			text_s = text_s.left(108) + "…"
		var nw: float = disp.get_string_size(name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		var tw: float = body.get_string_size(text_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		var x0: float = (s.x - nw - tw) * 0.5
		var y: float = base_y - float(i) * 36.0
		draw_rect(Rect2(x0 - 16.0, y - 26.0, nw + tw + 32.0, 34.0), Color(0, 0, 0, 0.42 * a))
		_text(disp, Vector2(x0, y), name_s, 20, Color(col.r, col.g, col.b, a), 4)
		_text(body, Vector2(x0 + nw, y), text_s, 24, Color(0.97, 0.96, 0.92, a), 4)
		i += 1


func _draw_notes(s: Vector2) -> void:
	var body: Font = UITheme.body_font()
	var y: float = 158.0
	for n in _notes:
		var lv: String = String(n["level"])
		var col: Color = Color(1.0, 0.92, 0.7) if lv == "info" else (Color(1.0, 0.75, 0.3) if lv == "warn" else Color(1.0, 0.42, 0.36))
		var a: float = clampf((5.0 - float(n["t"])) / 0.6, 0.0, 1.0) * clampf(float(n["t"]) / 0.15, 0.0, 1.0)
		var txt: String = ("⚠  " if lv != "info" else "◆  ") + String(n["text"])
		var w: float = body.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var r := Rect2((s.x - w) * 0.5 - 18.0, y - 22.0, w + 36.0, 32.0)
		var poly := _chamfer(r, 8.0)
		draw_colored_polygon(poly, Color(0.04, 0.04, 0.06, 0.82 * a))
		poly.append(poly[0])
		draw_polyline(poly, Color(col.r, col.g, col.b, 0.85 * a), 1.2, true)
		_text(body, Vector2((s.x - w) * 0.5, y), txt, 18, Color(col.r, col.g, col.b, a), 3)
		y += 38.0


func _draw_log(origin: Vector2) -> void:
	if _log.is_empty():
		return
	var body: Font = UITheme.body_font()
	var disp: Font = UITheme.display_font()
	var h: float = 34.0 + float(_log.size()) * 24.0
	var r := Rect2(origin, Vector2(440.0, h))
	var poly := _chamfer(r, 10.0)
	draw_colored_polygon(poly, Color(0.03, 0.035, 0.055, 0.62))
	poly.append(poly[0])
	draw_polyline(poly, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.55), 1.0, true)
	_text(disp, origin + Vector2(14.0, 22.0), "COMMAND LOG", 15, UITheme.GOLD_BRIGHT, 3)
	var y: float = origin.y + 46.0
	for e in _log:
		var src: String = String(e.get("source", ""))
		var who: String = String(e.get("who", ""))
		var what: String = String(e.get("what", ""))
		var res: String = String(e.get("result", ""))
		var col := Color(0.85, 0.86, 0.9, 0.9)
		if who == "YOU":
			col = UITheme.GOLD_BRIGHT
		elif src == "combo":
			col = Color(0.8, 0.65, 1.0)
		elif src == "event":
			col = Color(1.0, 0.55, 0.45)
		var tag: String = "[%s] " % src.left(5) if who != "YOU" else ("» " if src == "chat" else "🎙 ")
		var line: String = tag + (who + ": " if who != "YOU" and not who.is_empty() and src != "combo" else "") + what
		if not res.is_empty() and who != "YOU":
			line += "  → " + res
		_text(body, Vector2(origin.x + 14.0, y), _fit(body, line, 15, r.size.x - 28.0), 15, col, 2)
		y += 24.0


## Truncates `t` with an ellipsis so it fits `max_w` pixels at `fsize`.
func _fit(font: Font, t: String, fsize: int, max_w: float) -> String:
	if font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x <= max_w:
		return t
	var lo: int = 0
	var hi: int = t.length()
	while lo < hi:
		var mid: int = (lo + hi + 1) / 2
		if font.get_string_size(t.left(mid) + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x <= max_w:
			lo = mid
		else:
			hi = mid - 1
	return t.left(lo) + "…"


func _draw_mic() -> void:
	var c: Vector2 = _mic_btn.size * 0.5
	var st: String = comms.mic_state if comms != null else "idle"
	var now: float = float(Time.get_ticks_msec()) * 0.001
	var col: Color = UITheme.GOLD
	match st:
		"recording":
			col = Color(1.0, 0.32, 0.25)
		"transcribing":
			col = Color(0.35, 0.85, 1.0)
		"unavailable":
			col = Color(0.5, 0.5, 0.55)
	if not SquadAIConfig.is_online():
		col = Color(0.55, 0.55, 0.6)
	_mic_btn.draw_circle(c, 28.0, Color(0.03, 0.035, 0.055, 0.85))
	_mic_btn.draw_arc(c, 28.0, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.95), 2.0, true)
	if st == "recording":
		var rr: float = 30.0 + _mic_level * 14.0
		_mic_btn.draw_arc(c, rr, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.55 + 0.3 * sin(now * 10.0)), 3.0, true)
	elif st == "transcribing":
		var a0: float = now * 6.0
		_mic_btn.draw_arc(c, 33.0, a0, a0 + 2.0, 20, col, 3.0, true)
	# Mic glyph.
	_mic_btn.draw_rect(Rect2(c.x - 6.0, c.y - 15.0, 12.0, 18.0), col)
	_mic_btn.draw_circle(c + Vector2(0, -15.0), 6.0, col)
	_mic_btn.draw_circle(c + Vector2(0, 3.0), 6.0, col)
	_mic_btn.draw_arc(c + Vector2(0, 1.0), 11.0, 0.15, PI - 0.15, 14, col, 2.0, true)
	_mic_btn.draw_line(c + Vector2(0, 12.0), c + Vector2(0, 18.0), col, 2.0)
	_mic_btn.draw_line(c + Vector2(-6, 18.0), c + Vector2(6, 18.0), col, 2.0)
	if not SquadAIConfig.is_online():
		_mic_btn.draw_line(c + Vector2(-16, -16), c + Vector2(16, 16), Color(1.0, 0.4, 0.35, 0.9), 2.5, true)
	var label: String = "V"
	var body: Font = UITheme.body_font()
	var lw: float = body.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	_mic_btn.draw_string_outline(body, Vector2(c.x - lw * 0.5, c.y + 46.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 3, Color(0, 0, 0, 0.8))
	_mic_btn.draw_string(body, Vector2(c.x - lw * 0.5, c.y + 46.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.95, 0.85, 0.9))


func _chamfer(r: Rect2, c: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(r.position.x + c, r.position.y), Vector2(r.end.x - c, r.position.y), Vector2(r.end.x, r.position.y + c),
		Vector2(r.end.x, r.end.y - c), Vector2(r.end.x - c, r.end.y), Vector2(r.position.x + c, r.end.y),
		Vector2(r.position.x, r.end.y - c), Vector2(r.position.x, r.position.y + c),
	])


func _text(font: Font, pos: Vector2, t: String, fsize: int, col: Color, outline: int) -> void:
	if outline > 0:
		draw_string_outline(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, outline, Color(0, 0, 0, 0.75 * col.a))
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
