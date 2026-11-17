extends SceneTree
## Headless boot smoke test: loads main.tscn, starts a run, simulates ~6 s, reports script errors via stderr.
## Usage: godot --headless --path . -s res://tests/boot_smoke.gd

var _frames: int = 0
var _start_ms: int = 0


func _init() -> void:
	_start_ms = Time.get_ticks_msec()
	var main: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		var title: Node = get_first_node_in_group("title_screen")
		if title != null:
			if "show_quote_on_start" in title:
				title.set("show_quote_on_start", false)
			if title.has_method("press_start"):
				title.call("press_start")
	if _frames == 300:
		var allies: Array[Node] = get_nodes_in_group("squad_ally")
		print("[boot_smoke] frames=%d allies=%d enemies=%d" % [_frames, allies.size(), get_nodes_in_group("enemy").size()])
		print("[boot_smoke] OK")
		quit(0)
	if Time.get_ticks_msec() - _start_ms > 90000:
		print("[boot_smoke] WATCHDOG TIMEOUT")
		quit(2)
	return false
