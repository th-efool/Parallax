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
	add_to_group("results_screen")
	visible = false
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


func press_replay() -> void:
	visible = false
	if EncounterDirector.instance != null:
		EncounterDirector.instance.restart_full_run()
	replay_requested.emit()


func press_main_menu() -> void:
	visible = false
	main_menu_requested.emit()


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
