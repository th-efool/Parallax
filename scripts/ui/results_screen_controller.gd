class_name ResultsScreenController
extends Control
## Results screen controller (GDD Section 9.2):
## Listens to `RunState.run_finalized`, plays the VictoryOutro beat, then displays Score, Time, Time Bonus, Rank (S/A/B/C).
## If the run makes the local top 5, an arcade-style 3-slot initials picker appears:
## type letters directly, Up/Down cycles the active slot, Left/Right/Backspace moves, Enter carves the name.

signal results_presented(summary: Dictionary)
signal score_submitted(placed_rank: int, initials: String)
signal leaderboard_requested()
signal replay_requested()
signal main_menu_requested()

const LETTERS: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
const LAST_INITIALS_KEY: String = "last_initials"

@export_group("Optional Scene Node Bindings")
@export var build_default_ui_if_empty: bool = true
## Slow-motion + "THE WARDEN FALLS" card before the results appear (run_finalized path only).
@export var play_victory_outro: bool = true
@export var score_label_path: NodePath
@export var time_label_path: NodePath
@export var time_bonus_label_path: NodePath
@export var rank_label_path: NodePath
@export var initials_input_path: NodePath
@export var submit_button_path: NodePath
@export var leaderboard_button_path: NodePath
@export var replay_button_path: NodePath
@export var main_menu_button_path: NodePath

var final_score: int = 0
var elapsed_time_sec: float = 0.0
var time_bonus: int = 0
var warden_bonus: int = 0
var final_rank: String = "C"

var formatted_score_text: String = "000000"
var formatted_time_text: String = "00:00"
var formatted_bonus_text: String = "+0"
var rank_text: String = "C"

var qualifies_for_top_five: bool = false
var has_submitted_score: bool = false
var placed_leaderboard_rank: int = -1
var current_initials: String = "AAA"

var _outro: VictoryOutro = null
var _slot_labels: Array[Label] = []
var _slot_frames: Array[PanelContainer] = []
var _slot_index: int = 0
var _record_box: Control = null
var _record_title: Label = null
var _picker_row: Control = null
var _picker_hint: Control = null
var _record_note: Label = null
var _panel: Control = null


func _exit_tree() -> void:
	if visible or _outro != null:
		PlayerController.ui_input_locked = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("results_screen")
	MenuStyle.enforce_full_rect(self)
	visible = false
	if build_default_ui_if_empty and get_child_count() == 0:
		_build_default_ui()
	var run_state: Node = _get_run_state()
	if run_state != null and run_state.has_signal("run_finalized"):
		if not run_state.is_connected("run_finalized", _on_run_finalized):
			run_state.connect("run_finalized", _on_run_finalized)
	_bind_buttons()
	_sync_ui_nodes()


func populate_from_summary(summary: Dictionary) -> void:
	# A direct call (tests, tools) while the outro is still running wins: drop the outro.
	if _outro != null and is_instance_valid(_outro):
		_outro.queue_free()
	_outro = null

	final_score = int(summary.get("score", 0))
	elapsed_time_sec = float(summary.get("time_sec", 0.0))
	time_bonus = int(summary.get("time_bonus", 0))
	warden_bonus = int(summary.get("warden_bonus", 0))
	final_rank = String(summary.get("rank", "C"))

	formatted_score_text = "%06d" % maxi(0, final_score)
	formatted_time_text = LeaderboardManager.format_time(elapsed_time_sec)
	formatted_bonus_text = "+%d" % maxi(0, time_bonus)
	rank_text = final_rank

	has_submitted_score = false
	placed_leaderboard_rank = -1

	var store: Node = _get_leaderboard_store()
	if store != null and store.has_method("qualifies_for_top_five"):
		qualifies_for_top_five = bool(store.call("qualifies_for_top_five", final_score, elapsed_time_sec))
	else:
		qualifies_for_top_five = true
	current_initials = _default_initials()
	_slot_index = 0

	visible = true
	PlayerController.ui_input_locked = true
	_sync_ui_nodes()
	_play_reveal.call_deferred()
	results_presented.emit(summary)


func set_initials_input(raw: String) -> String:
	var store: Node = _get_leaderboard_store()
	if store != null and store.has_method("sanitize_initials"):
		current_initials = String(store.call("sanitize_initials", raw))
	else:
		current_initials = raw.strip_edges().to_upper().substr(0, 3)
		if current_initials.is_empty():
			current_initials = "WAR"
	_sync_ui_nodes()
	return current_initials


func submit_score(raw_initials: String = "") -> int:
	if has_submitted_score or not qualifies_for_top_five:
		return placed_leaderboard_rank

	if not raw_initials.is_empty():
		set_initials_input(raw_initials)
	elif not initials_input_path.is_empty():
		var le: LineEdit = get_node_or_null(initials_input_path) as LineEdit
		if le != null and not le.text.is_empty():
			set_initials_input(le.text)

	var store: Node = _get_leaderboard_store()
	if store != null and store.has_method("save_run"):
		placed_leaderboard_rank = int(store.call("save_run", current_initials, final_score, elapsed_time_sec, final_rank))
		has_submitted_score = true
		if store.has_method("set_custom_save_value"):
			store.call("set_custom_save_value", LAST_INITIALS_KEY, current_initials)
		_sync_ui_nodes()
		score_submitted.emit(placed_leaderboard_rank, current_initials)
		if _record_note != null:
			UIFx.pop(_record_note, 0.85, 0.25)
	return placed_leaderboard_rank


func press_leaderboard() -> void:
	leaderboard_requested.emit()
	if leaderboard_requested.get_connections().is_empty() and is_inside_tree() and get_tree() != null:
		var lb: Node = get_tree().get_first_node_in_group("leaderboard_screen")
		if lb is CanvasItem:
			visible = false
			if lb.has_method("refresh_entries"):
				lb.call("refresh_entries")
			(lb as CanvasItem).visible = true


func press_replay() -> void:
	visible = false
	PlayerController.ui_input_locked = false
	# MainController reloads the level for a fresh run (the world is rebuilt, not just the director reset).
	replay_requested.emit()


func press_main_menu() -> void:
	visible = false
	PlayerController.ui_input_locked = false
	main_menu_requested.emit()
	if main_menu_requested.get_connections().is_empty() and is_inside_tree() and get_tree() != null:
		var title: Node = get_tree().get_first_node_in_group("title_screen")
		if title is CanvasItem:
			(title as CanvasItem).visible = true


# ------------------------------------------------------------------ initials picker

func _entry_active() -> bool:
	return visible and qualifies_for_top_five and not has_submitted_score and _outro == null


## Keys go to the picker before any focused button sees them, so typing always lands in the slots.
func _input(event: InputEvent) -> void:
	if not _entry_active() or not (event is InputEventKey):
		return
	var k: InputEventKey = event as InputEventKey
	if not k.pressed:
		return
	var handled: bool = true
	match k.keycode:
		KEY_UP:
			_cycle_slot(_slot_index, -1)
		KEY_DOWN:
			_cycle_slot(_slot_index, 1)
		KEY_LEFT:
			_select_slot(_slot_index - 1)
		KEY_RIGHT, KEY_TAB:
			_select_slot(_slot_index + 1)
		KEY_BACKSPACE:
			_select_slot(_slot_index - 1)
		KEY_ENTER, KEY_KP_ENTER:
			if not k.echo:
				submit_score()
		_:
			handled = false
			if not k.echo and k.unicode > 0:
				var ch: String = String.chr(k.unicode).to_upper()
				if LETTERS.contains(ch):
					_set_slot_letter(_slot_index, ch)
					_select_slot(mini(_slot_index + 1, 2))
					handled = true
	if handled and get_viewport() != null:
		get_viewport().set_input_as_handled()


func _set_slot_letter(i: int, ch: String) -> void:
	var chars: PackedStringArray = _initials_chars()
	chars[clampi(i, 0, 2)] = ch
	current_initials = "".join(chars)
	_sync_slots()
	if i >= 0 and i < _slot_labels.size():
		UIFx.pop(_slot_labels[i], 1.18, 0.14)


func _cycle_slot(i: int, dir: int) -> void:
	var chars: PackedStringArray = _initials_chars()
	var idx: int = LETTERS.find(chars[clampi(i, 0, 2)])
	idx = posmod(idx + dir, LETTERS.length())
	_set_slot_letter(i, LETTERS[idx])
	if AudioManager.instance != null:
		AudioManager.instance.play_sfx("ui_click", -10.0)


func _select_slot(i: int) -> void:
	_slot_index = clampi(i, 0, 2)
	_sync_slots()


func _initials_chars() -> PackedStringArray:
	var s: String = (current_initials + "AAA").substr(0, 3)
	return PackedStringArray([s[0], s[1], s[2]])


func _default_initials() -> String:
	var store: Node = _get_leaderboard_store()
	if store != null and store.has_method("get_custom_save_value"):
		var last: String = String(store.call("get_custom_save_value", LAST_INITIALS_KEY, ""))
		if last.length() == 3:
			return last
	return "AAA"


func _projected_place() -> int:
	var store: Node = _get_leaderboard_store()
	if store == null or not store.has_method("get_top_five"):
		return -1
	var place: int = 1
	for e: Dictionary in store.call("get_top_five"):
		var s: int = int(e.get("score", 0))
		if s > final_score or (s == final_score and float(e.get("time_sec", 0.0)) <= elapsed_time_sec):
			place += 1
	return place


func _sync_slots() -> void:
	var chars: PackedStringArray = _initials_chars()
	var editing: bool = qualifies_for_top_five and not has_submitted_score
	for i in range(_slot_labels.size()):
		_slot_labels[i].text = chars[i]
		var active: bool = editing and i == _slot_index
		var frame: PanelContainer = _slot_frames[i]
		frame.add_theme_stylebox_override("panel", _slot_box(active, editing))
		_slot_labels[i].add_theme_color_override("font_color", UITheme.GOLD_BRIGHT if (active or not editing) else Color(0.85, 0.82, 0.74, 0.8))


func _slot_box(active: bool, editing: bool) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = Color(0.13, 0.11, 0.08, 0.95) if active else Color(0.04, 0.045, 0.07, 0.9)
	b.border_color = UITheme.GOLD_BRIGHT if active else Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.35 if editing else 0.6)
	b.set_border_width_all(1)
	b.border_width_bottom = 4 if active else 2
	b.content_margin_left = 6
	b.content_margin_right = 6
	if active:
		b.shadow_color = Color(1.0, 0.7, 0.3, 0.25)
		b.shadow_size = 10
	return b


# ------------------------------------------------------------------ layout

func _build_default_ui() -> void:
	var modal := MenuStyle.build_centered_modal(self, "ResultsDimmer", "ResultsPanel", Vector2(760, 660), 0.86, 44, 30)
	var panel: PanelContainer = modal["panel"] as PanelContainer
	_panel = panel

	var vbox := VBoxContainer.new()
	vbox.name = "ResultsVBox"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var eyebrow := Label.new()
	eyebrow.text = "TRIAL COMPLETE"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_font_override("font", UITheme.spaced(UITheme.body_font(), 8))
	eyebrow.add_theme_font_size_override("font_size", 17)
	eyebrow.add_theme_color_override("font_color", UITheme.GOLD)
	vbox.add_child(eyebrow)

	# Rank: the hero of the screen.
	var rank_lbl := Label.new()
	rank_lbl.name = "RankValueLabel"
	rank_lbl.text = "C"
	rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuStyle.style_title(rank_lbl, 120, MenuStyle.GOLD_TEXT)
	rank_lbl.add_theme_font_override("font", UITheme.spaced(UITheme.display_font(), 0, 0.4))
	rank_lbl.add_theme_constant_override("shadow_outline_size", 30)
	vbox.add_child(rank_lbl)
	rank_label_path = get_path_to(rank_lbl)

	var epithet := Label.new()
	epithet.name = "RankEpithetLabel"
	epithet.text = "The mirror has judged you."
	epithet.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuStyle.style_flavor(epithet, 28, MenuStyle.MUTED_TEXT)
	vbox.add_child(epithet)

	MenuStyle.style_divider(vbox)

	# Three stat columns.
	var stats := HBoxContainer.new()
	stats.name = "StatsRow"
	stats.add_theme_constant_override("separation", 0)
	vbox.add_child(stats)
	score_label_path = _add_stat_column(stats, "SCORE", "000000", "ScoreValueLabel")
	time_label_path = _add_stat_column(stats, "CLEAR TIME", "00:00", "TimeValueLabel")
	time_bonus_label_path = _add_stat_column(stats, "TIME BONUS", "+0", "TimeBonusValueLabel")

	MenuStyle.style_divider(vbox)

	# Hall of Champions entry.
	var record := VBoxContainer.new()
	record.name = "RecordBox"
	record.add_theme_constant_override("separation", 10)
	vbox.add_child(record)
	_record_box = record

	_record_title = Label.new()
	_record_title.name = "RecordTitleLabel"
	_record_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_record_title.add_theme_font_override("font", UITheme.spaced(UITheme.body_font(), 4))
	_record_title.add_theme_font_size_override("font_size", 19)
	_record_title.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	record.add_child(_record_title)

	var picker_center := CenterContainer.new()
	record.add_child(picker_center)
	var picker := HBoxContainer.new()
	picker.name = "InitialsPicker"
	picker.add_theme_constant_override("separation", 14)
	picker_center.add_child(picker)
	_picker_row = picker
	_slot_labels.clear()
	_slot_frames.clear()
	for i in range(3):
		picker.add_child(_make_slot(i))

	var hint_center := CenterContainer.new()
	record.add_child(hint_center)
	var hints := HBoxContainer.new()
	hints.add_theme_constant_override("separation", 22)
	hints.add_child(MenuStyle.make_key_hint("A–Z", "Type"))
	hints.add_child(MenuStyle.make_key_hint("↑ ↓", "Change letter"))
	hints.add_child(MenuStyle.make_key_hint("ENTER", "Carve your name"))
	hint_center.add_child(hints)
	_picker_hint = hint_center

	_record_note = Label.new()
	_record_note.name = "RecordNoteLabel"
	_record_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuStyle.style_flavor(_record_note, 24, MenuStyle.MUTED_TEXT)
	record.add_child(_record_note)

	var submit_center := CenterContainer.new()
	record.add_child(submit_center)
	var submit_btn := Button.new()
	submit_btn.name = "SubmitScoreButton"
	submit_btn.text = "Carve Name"
	submit_btn.custom_minimum_size = Vector2(220, 46)
	MenuStyle.style_button(submit_btn, 19, 46.0)
	submit_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	submit_center.add_child(submit_btn)
	submit_button_path = get_path_to(submit_btn)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(gap)

	# Actions in one row.
	var actions := HBoxContainer.new()
	actions.name = "ActionsRow"
	actions.add_theme_constant_override("separation", 12)
	vbox.add_child(actions)
	replay_button_path = _add_action(actions, "ReplayButton", "Play Again")
	leaderboard_button_path = _add_action(actions, "LeaderboardButton", "Hall of Champions")
	main_menu_button_path = _add_action(actions, "MainMenuButton", "Main Menu")


func _make_slot(i: int) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	var up := _make_arrow("▲", func() -> void:
		_select_slot(i)
		_cycle_slot(i, -1))
	col.add_child(up)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(74, 88)
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	frame.gui_input.connect(func(ev: InputEvent) -> void:
		if not _entry_active() or not (ev is InputEventMouseButton) or not ev.is_pressed():
			return
		var mb: InputEventMouseButton = ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_select_slot(i)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_select_slot(i)
			_cycle_slot(i, -1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_select_slot(i)
			_cycle_slot(i, 1))
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_override("font", UITheme.spaced(UITheme.display_font(), 0, 0.35))
	lbl.add_theme_font_size_override("font_size", 50)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.resized.connect(func() -> void: lbl.pivot_offset = lbl.size * 0.5)
	frame.add_child(lbl)
	col.add_child(frame)
	var down := _make_arrow("▼", func() -> void:
		_select_slot(i)
		_cycle_slot(i, 1))
	col.add_child(down)
	_slot_labels.append(lbl)
	_slot_frames.append(frame)
	return col


func _make_arrow(glyph: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = glyph
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(74, 22)
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.55))
	b.add_theme_color_override("font_hover_color", UITheme.GOLD_BRIGHT)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.pressed.connect(on_press)
	return b


func _add_action(row: HBoxContainer, node_name: String, text: String) -> NodePath:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuStyle.style_button(b, 18, 46.0)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(b)
	return get_path_to(b)


func _add_stat_column(row: HBoxContainer, label_text: String, initial_val: String, node_name: String) -> NodePath:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	var k := Label.new()
	k.text = label_text
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	k.add_theme_font_override("font", UITheme.spaced(UITheme.body_font(), 4))
	k.add_theme_font_size_override("font_size", 15)
	k.add_theme_color_override("font_color", Color(0.70, 0.72, 0.80))
	col.add_child(k)
	var v := Label.new()
	v.name = node_name
	v.text = initial_val
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_theme_font_override("font", UITheme.spaced(UITheme.body_font(), 2))
	v.add_theme_font_size_override("font_size", 36)
	v.add_theme_color_override("font_color", MenuStyle.GOLD_TEXT)
	v.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	v.add_theme_constant_override("outline_size", 3)
	col.add_child(v)
	return get_path_to(v)


const RANK_EPITHETS: Dictionary = {
	"S": "Flawless. Even the mirror bows.",
	"A": "A champion walks out alive.",
	"B": "The arena remembers your name.",
	"C": "Survived. The mirror is not impressed.",
}
const RANK_COLORS: Dictionary = {
	"S": Color(1.0, 0.86, 0.38), "A": Color(0.55, 0.88, 1.0), "B": Color(0.80, 0.84, 0.92), "C": Color(0.78, 0.55, 0.38),
}


func _play_reveal() -> void:
	if _panel != null:
		_panel.modulate.a = 0.0
		var ptw: Tween = _panel.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		ptw.tween_property(_panel, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
	var score_lbl: Label = get_node_or_null(score_label_path) as Label
	var rank_lbl: Label = get_node_or_null(rank_label_path) as Label
	var epi: Label = find_child("RankEpithetLabel", true, false) as Label
	if score_lbl != null:
		UIFx.count_up(score_lbl, maxi(0, final_score), 1.1, "%06d")
	var col: Color = RANK_COLORS.get(final_rank, MenuStyle.GOLD_TEXT)
	if epi != null:
		epi.text = String(RANK_EPITHETS.get(final_rank, RANK_EPITHETS["C"]))
		epi.add_theme_color_override("font_color", col)
	if rank_lbl != null:
		rank_lbl.add_theme_color_override("font_color", col)
		rank_lbl.add_theme_color_override("font_shadow_color", Color(col.r, col.g, col.b, 0.55))
		rank_lbl.modulate.a = 0.0
		rank_lbl.pivot_offset = rank_lbl.size * 0.5
		var tw: Tween = rank_lbl.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_interval(1.0)
		tw.tween_callback(func() -> void:
			rank_lbl.pivot_offset = rank_lbl.size * 0.5
			rank_lbl.scale = Vector2(2.2, 2.2)
			rank_lbl.modulate.a = 1.0
			if AudioManager.instance != null:
				AudioManager.instance.play_sfx("shift_rejected" if final_rank == "C" else "ui_confirm", -2.0))
		tw.tween_property(rank_lbl, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var replay: Control = get_node_or_null(replay_button_path) as Control
	if replay != null and not _entry_active():
		replay.grab_focus()


func _on_run_finalized(summary: Dictionary) -> void:
	if not play_victory_outro or not is_inside_tree():
		populate_from_summary(summary)
		return
	if _outro != null and is_instance_valid(_outro):
		return
	PlayerController.ui_input_locked = true
	_outro = VictoryOutro.new()
	get_tree().root.add_child(_outro)
	var outro: VictoryOutro = _outro
	outro.finished.connect(func() -> void:
		if _outro != outro:
			return   # populate_from_summary was called directly meanwhile.
		_outro = null
		populate_from_summary(summary)
		outro.reveal(), CONNECT_ONE_SHOT)
	outro.play()


func _bind_buttons() -> void:
	_connect_button(submit_button_path, func() -> void: submit_score())
	_connect_button(leaderboard_button_path, press_leaderboard)
	_connect_button(replay_button_path, press_replay)
	_connect_button(main_menu_button_path, press_main_menu)


func _connect_button(path: NodePath, callable_fn: Callable) -> void:
	if path.is_empty():
		return
	var btn: BaseButton = get_node_or_null(path) as BaseButton
	if btn != null and not btn.pressed.is_connected(callable_fn):
		btn.pressed.connect(callable_fn)


func _sync_ui_nodes() -> void:
	_set_label_text(score_label_path, formatted_score_text)
	_set_label_text(time_label_path, formatted_time_text)
	_set_label_text(time_bonus_label_path, formatted_bonus_text)
	_set_label_text(rank_label_path, rank_text)

	if not initials_input_path.is_empty():
		var le: LineEdit = get_node_or_null(initials_input_path) as LineEdit
		if le != null:
			le.editable = qualifies_for_top_five and not has_submitted_score
			if le.text != current_initials:
				le.text = current_initials

	var editing: bool = qualifies_for_top_five and not has_submitted_score
	if not submit_button_path.is_empty():
		var sbtn: BaseButton = get_node_or_null(submit_button_path) as BaseButton
		if sbtn != null:
			sbtn.disabled = not editing
			sbtn.visible = editing

	if _record_title != null:
		if has_submitted_score:
			_record_title.text = "CARVED INTO THE HALL OF CHAMPIONS"
		elif qualifies_for_top_five:
			var place: int = _projected_place()
			_record_title.text = ("NEW RECORD  ·  #%d IN THE HALL OF CHAMPIONS" % place) if place > 0 else "NEW RECORD  ·  HALL OF CHAMPIONS"
		else:
			_record_title.text = ""
		_record_title.visible = qualifies_for_top_five
	if _picker_row != null:
		_picker_row.visible = qualifies_for_top_five
	if _picker_hint != null:
		_picker_hint.visible = editing
	if _record_note != null:
		if has_submitted_score:
			_record_note.text = "%s holds place #%d." % [current_initials, placed_leaderboard_rank] if placed_leaderboard_rank > 0 else "Saved."
			_record_note.visible = true
		elif not qualifies_for_top_five:
			_record_note.text = "Not enough for the Hall of Champions this time."
			_record_note.visible = true
		else:
			_record_note.visible = false
	_sync_slots()


func _set_label_text(path: NodePath, value: String) -> void:
	if path.is_empty():
		return
	var lbl: Label = get_node_or_null(path) as Label
	if lbl != null:
		lbl.text = value


func _get_run_state() -> Node:
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		return get_tree().root.get_node_or_null("RunState")
	return null


func _get_leaderboard_store() -> Node:
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		return get_tree().root.get_node_or_null("LeaderboardStore")
	return null
