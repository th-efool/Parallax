class_name LeaderboardScreenController
extends Control
## Leaderboard screen controller (GDD Section 9.2):
## Displays the offline Top 5 table (`# | Initials | Score | Time | Rank`) from `LeaderboardStore`.

signal leaderboard_refreshed(rows: Array[String])
signal back_requested()

@export_group("Optional Scene Node Bindings")
@export var build_default_ui_if_empty: bool = true
@export var rows_container_path: NodePath
@export var empty_state_label_path: NodePath
@export var back_button_path: NodePath

var entries: Array[Dictionary] = []
var rows_text: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("leaderboard_screen")
	MenuStyle.enforce_full_rect(self)
	if build_default_ui_if_empty and get_child_count() == 0:
		_build_default_ui()
	var store: Node = _get_leaderboard_store()
	if store != null and store.has_signal("leaderboard_updated"):
		if not store.is_connected("leaderboard_updated", _on_leaderboard_updated):
			store.connect("leaderboard_updated", _on_leaderboard_updated)
	if not back_button_path.is_empty():
		var btn: BaseButton = get_node_or_null(back_button_path) as BaseButton
		if btn != null and not btn.pressed.is_connected(press_back):
			btn.pressed.connect(press_back)
	refresh_entries()


func refresh_entries() -> void:
	entries.clear()
	rows_text.clear()

	var store: Node = _get_leaderboard_store()
	if store != null and store.has_method("get_top_five"):
		var raw: Array = store.call("get_top_five")
		for item in raw:
			if item is Dictionary:
				entries.append(item)

	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		var rank_idx: int = i + 1
		var initials: String = String(e.get("initials", "WAR"))
		var score_val: int = int(e.get("score", 0))
		var time_str: String = LeaderboardManager.format_time(float(e.get("time_sec", 0.0)))
		var grade: String = String(e.get("rank", "C"))
		rows_text.append("#%d  %-3s  %06d  %s  %s" % [rank_idx, initials, score_val, time_str, grade])

	_sync_ui_nodes()
	leaderboard_refreshed.emit(rows_text)


func press_back() -> void:
	back_requested.emit()
	if back_requested.get_connections().is_empty():
		visible = false
		if is_inside_tree() and get_tree() != null:
			var title: Node = get_tree().get_first_node_in_group("title_screen")
			if title is CanvasItem:
				(title as CanvasItem).visible = true


func _build_default_ui() -> void:
	var modal := MenuStyle.build_centered_modal(self, "LeaderboardDimmer", "LeaderboardPanel", Vector2(640, 480), 0.88, 32, 26)
	var panel: PanelContainer = modal["panel"] as PanelContainer

	var vbox := VBoxContainer.new()
	vbox.name = "LeaderboardVBox"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.name = "LeaderboardTitle"
	title_lbl.text = "HALL OF CHAMPIONS"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuStyle.style_title(title_lbl, 34)
	vbox.add_child(title_lbl)

	MenuStyle.style_divider(vbox)

	var cols_lbl := Label.new()
	cols_lbl.name = "ColumnsHeaderLabel"
	cols_lbl.text = "RANK   TAG   SCORE    TIME    GRADE"
	cols_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuStyle.style_label(cols_lbl, 15, MenuStyle.BORDER_GOLD)
	vbox.add_child(cols_lbl)

	var empty_lbl := Label.new()
	empty_lbl.name = "EmptyStateLabel"
	empty_lbl.text = "No recorded runs yet — claim victory to enter the Top 5."
	empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	MenuStyle.style_label(empty_lbl, 16, MenuStyle.MUTED_TEXT)
	vbox.add_child(empty_lbl)
	empty_state_label_path = get_path_to(empty_lbl)

	var scroll := ScrollContainer.new()
	scroll.name = "RowsScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var rows_vbox := VBoxContainer.new()
	rows_vbox.name = "RowsContainer"
	rows_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(rows_vbox)
	rows_container_path = get_path_to(rows_vbox)

	for i in range(5):
		var row_lbl := Label.new()
		row_lbl.name = "Row_%d" % (i + 1)
		row_lbl.text = "#%d  ---  ------  --:--  -" % (i + 1)
		row_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MenuStyle.style_label(row_lbl, 26 if i == 0 else 22, [Color(1.0, 0.86, 0.38), Color(0.82, 0.86, 0.92), Color(0.82, 0.55, 0.34), MenuStyle.MUTED_TEXT, MenuStyle.MUTED_TEXT][i])
		row_lbl.add_theme_font_override("font", UITheme.display_font() if i < 3 else UITheme.body_font())
		rows_vbox.add_child(row_lbl)

	var back_btn := Button.new()
	back_btn.name = "BackButton"
	back_btn.text = "Back"
	MenuStyle.style_button(back_btn, 18, 42.0)
	vbox.add_child(back_btn)
	back_button_path = get_path_to(back_btn)


func _on_leaderboard_updated(_updated_entries: Array) -> void:
	refresh_entries()


func _sync_ui_nodes() -> void:
	if not empty_state_label_path.is_empty():
		var empty_lbl: CanvasItem = get_node_or_null(empty_state_label_path) as CanvasItem
		if empty_lbl != null:
			empty_lbl.visible = rows_text.is_empty()

	if not rows_container_path.is_empty():
		var container: Node = get_node_or_null(rows_container_path)
		if container != null:
			for idx in range(container.get_child_count()):
				var child: Node = container.get_child(idx)
				if child is Label:
					var lbl: Label = child as Label
					if idx < rows_text.size():
						lbl.visible = true
						lbl.text = rows_text[idx]
					else:
						lbl.text = "#%d  ---  ------  --:--  -" % (idx + 1)


func _get_leaderboard_store() -> Node:
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		return get_tree().root.get_node_or_null("LeaderboardStore")
	return null
