class_name ResultsScreenController
extends Control
## Results screen controller (GDD Section 9.2):
## Listens to `RunState.run_finalized`, displays Score, Time, Time Bonus, Rank (S/A/B/C),
## checks `LeaderboardStore.qualifies_for_top_five()`, and handles 3-letter uppercase initials submission.

signal results_presented(summary: Dictionary)
signal score_submitted(placed_rank: int, initials: String)
signal leaderboard_requested()
signal replay_requested()
signal main_menu_requested()

@export_group("Optional Scene Node Bindings")
@export var build_default_ui_if_empty: bool = true
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
var current_initials: String = "WAR"


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

	visible = true
	_sync_ui_nodes()
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
		_sync_ui_nodes()
		score_submitted.emit(placed_leaderboard_rank, current_initials)
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
	if EncounterDirector.instance != null:
		EncounterDirector.instance.restart_full_run()
	replay_requested.emit()


func press_main_menu() -> void:
	visible = false
	main_menu_requested.emit()
	if main_menu_requested.get_connections().is_empty() and is_inside_tree() and get_tree() != null:
		var title: Node = get_tree().get_first_node_in_group("title_screen")
		if title is CanvasItem:
			(title as CanvasItem).visible = true


func _build_default_ui() -> void:
	var modal := MenuStyle.build_centered_modal(self, "ResultsDimmer", "ResultsPanel", Vector2(560, 520), 0.88, 32, 26)
	var panel: PanelContainer = modal["panel"] as PanelContainer

	var scroll := ScrollContainer.new()
	scroll.name = "ResultsScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.name = "ResultsVBox"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.name = "ResultsTitleLabel"
	title_lbl.text = "RUN COMPLETE"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuStyle.style_title(title_lbl, 32)
	vbox.add_child(title_lbl)

	MenuStyle.style_divider(vbox)

	var grid := GridContainer.new()
	grid.name = "StatsGrid"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)

	score_label_path = _add_stat_row(grid, "FINAL SCORE", "000000", "ScoreValueLabel")
	time_label_path = _add_stat_row(grid, "CLEAR TIME", "00:00", "TimeValueLabel")
	time_bonus_label_path = _add_stat_row(grid, "TIME BONUS", "+0", "TimeBonusValueLabel")
	rank_label_path = _add_stat_row(grid, "TRIAL RANK", "C", "RankValueLabel", true)

	MenuStyle.style_divider(vbox)

	var init_row := HBoxContainer.new()
	init_row.name = "InitialsRow"
	init_row.add_theme_constant_override("separation", 10)
	vbox.add_child(init_row)

	var init_lbl := Label.new()
	init_lbl.text = "INITIALS"
	init_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuStyle.style_label(init_lbl, 18)
	init_row.add_child(init_lbl)

	var init_input := LineEdit.new()
	init_input.name = "InitialsLineEdit"
	init_input.text = current_initials
	init_input.max_length = 3
	init_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	init_input.custom_minimum_size = Vector2(96, 40)
	init_input.add_theme_font_size_override("font_size", 20)
	init_input.add_theme_color_override("font_color", MenuStyle.GOLD_TEXT)
	init_input.add_theme_stylebox_override("normal", MenuStyle.make_flat_box(MenuStyle.BTN_BG_NORMAL, MenuStyle.BORDER_GOLD, 1, 6))
	init_row.add_child(init_input)
	initials_input_path = get_path_to(init_input)

	var submit_btn := Button.new()
	submit_btn.name = "SubmitScoreButton"
	submit_btn.text = "Submit Score"
	submit_btn.custom_minimum_size = Vector2(160, 40)
	MenuStyle.style_button(submit_btn, 17, 40.0)
	init_row.add_child(submit_btn)
	submit_button_path = get_path_to(submit_btn)

	var lb_btn := Button.new()
	lb_btn.name = "LeaderboardButton"
	lb_btn.text = "View Leaderboard"
	MenuStyle.style_button(lb_btn, 18, 42.0)
	vbox.add_child(lb_btn)
	leaderboard_button_path = get_path_to(lb_btn)

	var replay_btn := Button.new()
	replay_btn.name = "ReplayButton"
	replay_btn.text = "Play Again"
	MenuStyle.style_button(replay_btn, 18, 42.0)
	vbox.add_child(replay_btn)
	replay_button_path = get_path_to(replay_btn)

	var menu_btn := Button.new()
	menu_btn.name = "MainMenuButton"
	menu_btn.text = "Main Menu"
	MenuStyle.style_button(menu_btn, 18, 42.0)
	vbox.add_child(menu_btn)
	main_menu_button_path = get_path_to(menu_btn)


func _add_stat_row(grid: GridContainer, label_text: String, initial_val: String, node_name: String, highlight: bool = false) -> NodePath:
	var k := Label.new()
	k.text = label_text
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuStyle.style_label(k, 18, MenuStyle.MUTED_TEXT)
	grid.add_child(k)

	var v := Label.new()
	v.name = node_name
	v.text = initial_val
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	MenuStyle.style_title(v, 24 if highlight else 20, MenuStyle.GOLD_TEXT)
	grid.add_child(v)
	return get_path_to(v)


func _on_run_finalized(summary: Dictionary) -> void:
	populate_from_summary(summary)


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

	if not submit_button_path.is_empty():
		var sbtn: BaseButton = get_node_or_null(submit_button_path) as BaseButton
		if sbtn != null:
			sbtn.disabled = (not qualifies_for_top_five) or has_submitted_score


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
