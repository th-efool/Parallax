class_name LeaderboardScreenController
extends Control
## Leaderboard screen controller (GDD Section 9.2):
## Displays the offline Top 5 table (`# | Initials | Score | Time | Rank`) from `LeaderboardStore`.

signal leaderboard_refreshed(rows: Array[String])
signal back_requested()

@export_group("Optional Scene Node Bindings")
@export var rows_container_path: NodePath
@export var empty_state_label_path: NodePath
@export var back_button_path: NodePath

var entries: Array[Dictionary] = []
var rows_text: Array[String] = []


func _ready() -> void:
	add_to_group("leaderboard_screen")
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
