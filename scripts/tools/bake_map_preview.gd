extends SceneTree
## Bakes the runtime-generated level into a scene you can open in the editor viewport.
## The live game still builds the level in code (GrandJourneyBuilder / AmbientLife); this is a read-only
## snapshot for looking around, measuring and planning. Re-run after changing the builder:
##   godot --path . -s res://scripts/tools/bake_map_preview.gd
## Output: res://scenes/preview/map_preview.scn  (gitignored, regenerate any time)

const OUT_DIR: String = "res://scenes/preview"
const OUT_PATH: String = "res://scenes/preview/map_preview.scn"

var _main: Node = null


func _initialize() -> void:
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_bake()


func _bake() -> void:
	# Let the builder, set dressing, ambient life and static batching finish.
	for _i in range(90):
		await process_frame
	var preview := Node3D.new()
	preview.name = "MapPreview"
	for keep in ["WorldEnvironment", "SunLight"]:
		var n: Node = _main.get_node_or_null(keep)
		if n != null:
			var d: Node = n.duplicate()
			preview.add_child(d)
	for src_name in ["LevelRoot", "AmbientLife"]:
		var src: Node = _main.get_node_or_null(src_name)
		if src == null:
			continue
		var holder := Node3D.new()
		holder.name = src_name
		preview.add_child(holder)
		for c in src.get_children():
			if c is Node3D or c is Node:
				c.reparent(holder, true)
	# Weather / other runtime nodes the builder adds directly under Main.
	for c2 in _main.get_children():
		if String(c2.name).begins_with("Weather") and c2 is Node3D:
			c2.reparent(preview, true)
	var count: int = _claim(preview, preview)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var ps := PackedScene.new()
	var err: int = ps.pack(preview)
	if err != OK:
		print("[bake] pack failed: ", err)
		quit(1)
		return
	err = ResourceSaver.save(ps, OUT_PATH, ResourceSaver.FLAG_COMPRESS)
	print("[bake] saved %s (%d nodes) err=%d" % [OUT_PATH, count, err])
	quit(0 if err == OK else 1)


## Gives every generated node the preview root as owner so it is saved. Instanced sub-scenes (models, enemy
## scenes) are saved as instances: their own internals are not claimed. Gameplay scripts are stripped from
## generated nodes so nothing runs in the editor; the geometry, materials and lights stay.
func _claim(n: Node, owner_root: Node) -> int:
	var c: int = 0
	for ch in n.get_children():
		# Nodes owned by an instanced sub-scene inside the preview belong to that instance: leave them.
		if ch.owner != null and owner_root.is_ancestor_of(ch.owner):
			continue
		ch.owner = owner_root
		c += 1
		if ch.scene_file_path.is_empty():
			if ch.get_script() != null:
				ch.set_script(null)
			c += _claim(ch, owner_root)
	return c
