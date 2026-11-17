class_name ChainCounter
extends Control
## LMB chain readout (child of the shared HUD): roman step + move name ("III · THRUST"), a FLOW streak tag
## when the tap landed in rhythm, and the Rising Arc branch callout. Fades ~1.1 s after the last swing.
## Listens to PlayerController.attack_started(name, timing) — timing carries chain_step / flow / branch.

const ROMAN: Array[String] = ["", "I", "II", "III", "IV", "V", "VI"]
const FLOW_COL := Color(1.0, 0.82, 0.38)
const BRANCH_COL := Color(0.55, 0.85, 1.0)

var _player: Node = null
var _step: int = 0
var _name: String = ""
var _flow: bool = false
var _streak: int = 0
var _branch: bool = false
var _t: float = 99.0
var _pop: float = 0.0


func _ready() -> void:
	name = "ChainCounter"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_bind()
	var real_dt: float = delta / maxf(0.05, Engine.time_scale)
	_t += real_dt
	_pop = maxf(0.0, _pop - real_dt * 5.0)
	if _t < 1.6:
		queue_redraw()


func _bind() -> void:
	if not is_inside_tree():
		return
	var p: Node = get_tree().get_first_node_in_group("player")
	if p == null or not p.has_signal("attack_started"):
		return
	_player = p
	p.connect("attack_started", _on_attack_started)


func _on_attack_started(attack_name: String, timing: Dictionary) -> void:
	if not attack_name.begins_with("light"):
		return
	_branch = String(timing.get("branch", "")) == "pause"
	_step = int(timing.get("chain_step", 0))
	_flow = bool(timing.get("flow", false))
	_streak = int(timing.get("flow_streak", 0))
	_name = String(timing.get("display", attack_name.to_upper()))
	_t = 0.0
	_pop = 1.0
	queue_redraw()


func _draw() -> void:
	if _t > 1.3 or _step <= 0 and not _branch:
		return
	var a: float = clampf((1.3 - _t) / 0.4, 0.0, 1.0)
	var s: Vector2 = size
	var c := Vector2(s.x * 0.5 + 150.0, s.y * 0.60)
	var disp: Font = UITheme.display_font()
	var body: Font = UITheme.body_font()
	var col: Color = BRANCH_COL if _branch else (FLOW_COL if _flow else Color(0.95, 0.93, 0.88))
	var big: int = int(38.0 + 14.0 * _pop)
	var numeral: String = "↑" if _branch else ROMAN[clampi(_step, 0, ROMAN.size() - 1)]
	_text(disp, c, numeral, big, Color(col.r, col.g, col.b, a), 7)
	var nw: float = disp.get_string_size(numeral, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	_text(body, c + Vector2(nw + 12.0, -4.0), _name, 20, Color(col.r, col.g, col.b, 0.92 * a), 4)
	# Chain pips: filled up to the current step out of 5.
	for i in range(5):
		var pc := c + Vector2(nw + 14.0 + float(i) * 14.0, 12.0)
		var filled: bool = i < _step
		draw_colored_polygon(PackedVector2Array([pc + Vector2(0, -5), pc + Vector2(5, 0), pc + Vector2(0, 5), pc + Vector2(-5, 0)]),
			Color(col.r, col.g, col.b, (0.95 if filled else 0.22) * a))
	if _flow:
		_text(disp, c + Vector2(nw + 90.0, 18.0), "FLOW" + (" ×%d" % _streak if _streak > 1 else ""), 18, Color(FLOW_COL.r, FLOW_COL.g, FLOW_COL.b, a), 4)
	elif _branch:
		_text(disp, c + Vector2(nw + 90.0, 18.0), "BRANCH", 16, Color(BRANCH_COL.r, BRANCH_COL.g, BRANCH_COL.b, a), 4)


func _text(font: Font, pos: Vector2, t: String, fsize: int, col: Color, outline: int) -> void:
	if outline > 0:
		draw_string_outline(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, outline, Color(0, 0, 0, 0.75 * col.a))
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
