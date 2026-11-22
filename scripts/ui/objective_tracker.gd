class_name ObjectiveTracker
extends Control
## "What am I supposed to do?" — part of the shared HUD. Derives the current objective from live world state
## (gates, switches, bridge, mechanism, enemies, the Warden's phase), shows it under the realm chips with a
## one-line how-to hint, draws an on-screen waypoint marker (clamped to the screen edge with distance), labels
## the confusing glowing props in the world, and — Mirror only — floats an "echo inscription" over the
## objective (the Mirror reveals secrets). Objective changes pop with a chime.

const GOLD := Color(1.0, 0.86, 0.5)
const CYAN := Color(0.55, 0.9, 1.0)

var _level: Node = null
var _obj: Dictionary = {}
var _last_title: String = ""
var _pop: float = 0.0
var _timer: float = 0.0
var _labels_done: bool = false
var _inscription: Label3D = null


func _ready() -> void:
	name = "ObjectiveTracker"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func get_objective() -> Dictionary:
	return _obj


func _process(delta: float) -> void:
	var real_dt: float = delta / maxf(0.05, Engine.time_scale)
	_pop = maxf(0.0, _pop - real_dt * 1.6)
	_timer -= real_dt
	if _timer <= 0.0:
		_timer = 0.25
		_refresh()
	queue_redraw()


func _find_level() -> Node:
	if _level != null and is_instance_valid(_level):
		return _level
	var main: Node = get_tree().get_first_node_in_group("main_controller")
	_level = main.get_node_or_null("LevelRoot") if main != null else null
	return _level


func _n(path: String) -> Node:
	var lv: Node = _find_level()
	return lv.get_node_or_null(path) if lv != null else null


func _alive_in(path: String) -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	var g: Node = _n(path)
	if g == null:
		return out
	for c in g.get_children():
		if c is EnemyBase and not (c as EnemyBase).is_dead:
			out.append(c as EnemyBase)
	return out


## " — Wave 2/3" while a room's WaveDirector is running, "" otherwise.
func _wave_tag(path: String) -> String:
	var wd: WaveDirector = _n(path) as WaveDirector
	if wd == null or wd.get_display_wave() == 0:
		return ""
	return " — Wave %d/%d" % [wd.get_display_wave(), wd.get_total()]


func _refresh() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var main: Node = tree.get_first_node_in_group("main_controller")
	if main != null and "level_ready" in main and not bool(main.get("level_ready")):
		_obj = {}
		return
	var player: Node3D = tree.get_first_node_in_group("player") as Node3D
	if player == null or _find_level() == null:
		_obj = {}
		return
	if not _labels_done:
		_label_props()
		if _n("Stage01_EntryVestibule/EntryMirrorSwitch") != null:
			_labels_done = true
	_obj = _compute(player)
	var title: String = String(_obj.get("title", ""))
	if title != _last_title and not title.is_empty():
		if not _last_title.is_empty():
			_pop = 1.0
			if AudioManager.instance != null:
				AudioManager.instance.play_sfx("ui_confirm", -6.0)
		_last_title = title
	_update_inscription()


func _compute(player: Node3D) -> Dictionary:
	# Thresholds below are story z (the old compact layout); targets convert with JourneyLayout.
	var pz: float = JourneyLayout.story_z(player.global_position.z)
	var py: float = player.global_position.y
	_auto_clear_bypassed_stages(pz)
	var gate1: Node = _n("Stage01_EntryVestibule/Gate01_EntryToHall")
	var sw1: Node3D = _n("Stage01_EntryVestibule/EntryMirrorSwitch") as Node3D
	if gate1 != null and not bool(gate1.get("is_open")):
		if pz < -16.0:
			return {"title": "Follow the Pilgrim's Causeway to the gate", "hint": "Cross the winding causeway past both bastions to the gate.", "target": JourneyLayout.guide_target(player.global_position, Vector3(0, 0, -9))}
		return {"title": "Open the Gate of Reflections",
			"hint": "Beat the gate guards, press Q so the glowing stones turn solid, cross, then press E at the Mirror Switch left of the gate.",
			"target": sw1.global_position if sw1 != null else Vector3(0, 0, 4)}
	var hall_left: Array[EnemyBase] = _alive_in("Stage02_HallOfEchoes/Enemies")
	var gate2: Node = _n("Stage02_HallOfEchoes/Gate02_HallToGallery")
	if gate2 != null and not bool(gate2.get("is_open")):
		if pz < 24.0:
			return {"title": "Cross the Sunlit Bridges to the Hall of Echoes", "hint": "Through the gate and over the bridges, past both bastions, to the hall.", "target": JourneyLayout.guide_target(player.global_position, JourneyLayout.to_world(Vector3(0, 4, 26)))}
		var hall_waves: WaveDirector = _n("Stage02_HallOfEchoes/HallWaves") as WaveDirector
		if hall_waves != null and not hall_waves.finished:
			var wave_alive: Array[EnemyBase] = hall_waves.get_current_wave_alive()
			if not wave_alive.is_empty():
				return {"title": "Clear the Hall of Echoes",
					"sub": "Wave %d/%d  ·  %d left" % [hall_waves.get_display_wave(), hall_waves.get_total(), wave_alive.size()],
					"target": _nearest(wave_alive, player).global_position}
			if hall_waves.is_waiting_for_next_wave() or hall_waves.current_wave < hall_waves.get_total() - 1:
				var next_w: int = hall_waves.get_display_wave() if hall_waves.is_waiting_for_next_wave() else mini(hall_waves.get_display_wave() + 1, hall_waves.get_total())
				return {"title": "Clear the Hall of Echoes",
					"sub": "Wave %d/%d incoming..." % [next_w, hall_waves.get_total()],
					"target": JourneyLayout.HALL_CENTER}
		if not hall_left.is_empty():
			return {"title": "Clear the Hall of Echoes",
				"sub": "%d left" % hall_left.size(),
				"target": _nearest(hall_left, player).global_position}
	if pz < 64.0 and py < 5.5:
		return {"title": "Cross the Windswept Rampart", "hint": "Through the opened gate and over the rampart bridges, past both bastions, to the gallery.", "target": JourneyLayout.guide_target(player.global_position, JourneyLayout.to_world(Vector3(0, 6, 62)))}
	var brg: Node3D = _n("Stage03_CollapsedGallery/GallerySpectralBridge") as Node3D
	var gate3: Node = _n("Stage03_CollapsedGallery/Gate03_GalleryToMechanism")
	var guard: Array[EnemyBase] = _alive_in("Stage03_CollapsedGallery/Enemies")
	if not guard.is_empty() and pz <= 85.2 and not (gate3 != null and bool(gate3.get("is_open"))):
		if pz < 74.0 and brg != null and not bool(brg.get("is_permanently_repaired")):
			return {"title": "Cross the broken bridge",
				"hint": "The span only exists in the Mirror: press Q and cross to the guard's deck.",
				"target": brg.global_position}
		return {"title": "Defeat the Shielded Guard",
			"hint": "His shield only exists in Reality: fight him in the Mirror (Q). His fall opens the gate and rebuilds the bridge.",
			"target": guard[0].global_position}
	var puz: Node3D = _n("Stage04_MechanismChamber/ChamberMechanismPuzzle") as Node3D
	if puz != null and not bool(puz.get("is_solved")) and pz <= 101.5:
		if pz < 87.0:
			return {"title": "Enter the Clock-Tower Mechanism Chamber", "hint": "North through the gallery gate.", "target": JourneyLayout.to_world(Vector3(0, 6, 90))}
		var cw: WaveDirector = _n("Stage04_MechanismChamber/ChamberWaves") as WaveDirector
		var cw_sub: String = ("Wave %d/%d" % [cw.get_display_wave(), cw.get_total()]) if (cw != null and cw.get_display_wave() > 0) else ""
		return {"title": "Drop the Mirror weight onto the plate",
			"sub": cw_sub,
			"target": puz.global_position}
	var gate5: Node = _n("Stage05_ExecutionArena/Gate05_ArenaExit")
	var warden: WardenBoss = _n("Stage05_ExecutionArena/Enemies/TheWarden") as WardenBoss
	if warden != null and not warden.is_dead and pz <= 169.5 and not (gate5 != null and bool(gate5.get("is_open"))):
		if pz < 139.0:
			return {"title": "Cross the Processional to the Colosseum", "hint": "Over the bridges and past both bastions. The Warden waits at the top.", "target": JourneyLayout.guide_target(player.global_position, JourneyLayout.to_world(Vector3(0, 10, 140.5)))}
		if warden.current_phase == WardenBoss.Phase.PHASE_1_SPLIT:
			return {"title": "Defeat The Warden", "hint": "Hit his glowing chest rune in the Mirror after a strike or while he summons. Step through the mirror wall to shift instantly.", "target": warden.global_position}
		return {"title": "Finish The Warden", "hint": "The realms have merged — no more shifting. Hit him with everything.", "target": warden.global_position}
	return {"title": "Walk into the light", "hint": "Leave through the north gate to the summit.", "target": JourneyLayout.to_world(Vector3(0, 10, 194))}


func _auto_clear_bypassed_stages(pz: float) -> void:
	var ed: EncounterDirector = EncounterDirector.instance as EncounterDirector
	# Stage 01 Gate01_EntryToHall sits at story/world z = 5.0; north onto R2 at z >= 6.5 means bypassed.
	if pz > 6.5:
		var gate1: Node = _n("Stage01_EntryVestibule/Gate01_EntryToHall")
		if gate1 != null and not bool(gate1.get("is_open")) and gate1.has_method("open_gate"):
			gate1.call("open_gate", true)
	# Stage 02 Gate02_HallToGallery sits at world z = 116.0 (story z = 44.0); north onto R3 at pz > 45.2 means bypassed.
	if pz > 45.2:
		var gate2: Node = _n("Stage02_HallOfEchoes/Gate02_HallToGallery")
		if gate2 != null and not bool(gate2.get("is_open")) and gate2.has_method("open_gate"):
			gate2.call("open_gate", true)
		if ed != null and not bool(ed.completed_encounters.get("hall_of_echoes", false)):
			ed.complete_combat_encounter("hall_of_echoes")
	# Stage 03 Gate03_GalleryToMechanism sits at story z = 84.0 (world z = 188.0); past pz > 85.2 clears bridge, guard & gate.
	if pz > 85.2:
		var brg: Node = _n("Stage03_CollapsedGallery/GallerySpectralBridge")
		if brg != null and not bool(brg.get("is_permanently_repaired")) and brg.has_method("repair_for_reality"):
			brg.call("repair_for_reality")
		var gate3: Node = _n("Stage03_CollapsedGallery/Gate03_GalleryToMechanism")
		if gate3 != null and not bool(gate3.get("is_open")) and gate3.has_method("open_gate"):
			gate3.call("open_gate", true)
		if ed != null and not bool(ed.completed_encounters.get("shielded_guard", false)):
			ed.complete_combat_encounter("shielded_guard")
	# Stage 04 Gate04_MechanismToArena sits at world z = 228.0 (story z ~ 100.4); past pz > 101.5 resolves mechanism & gate.
	if pz > 101.5:
		var gate4: Node = _n("Stage04_MechanismChamber/Gate04_MechanismToArena")
		if gate4 != null and not bool(gate4.get("is_open")) and gate4.has_method("open_gate"):
			gate4.call("open_gate", true)
		var puz: Node = _n("Stage04_MechanismChamber/ChamberMechanismPuzzle")
		if puz != null and not bool(puz.get("is_solved")) and puz.has_method("force_solve_bypass"):
			puz.call("force_solve_bypass")
	# Stage 05 Gate05_ArenaExit sits at story z = 167.5 (world z = 327.5); past pz > 169.5 opens exit & clears warden.
	if pz > 169.5:
		var gate5: Node = _n("Stage05_ExecutionArena/Gate05_ArenaExit")
		if gate5 != null and not bool(gate5.get("is_open")) and gate5.has_method("open_gate"):
			gate5.call("open_gate", true)
		if ed != null and not bool(ed.completed_encounters.get("the_warden", false)):
			ed.complete_combat_encounter("the_warden")


func _nearest(list: Array[EnemyBase], player: Node3D) -> EnemyBase:
	var best: EnemyBase = list[0]
	for e in list:
		if e.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position):
			best = e
	return best


## Name the glowing props once so they stop being mystery cubes.
func _label_props() -> void:
	var specs: Array = [
		["Stage01_EntryVestibule/EntryMirrorSwitch", "MIRROR SWITCH\nuse in the Mirror (E)", 1.8],
		["Stage01_EntryVestibule/EntrySteppingStones", "MIRROR STONES\nsolid only in the Mirror (Q)", 1.2],
	]
	for s in specs:
		var n: Node3D = _n(String(s[0])) as Node3D
		if n == null or n.get_node_or_null("WorldHint") != null:
			continue
		var l := Label3D.new()
		l.name = "WorldHint"
		l.text = String(s[1])
		l.outline_modulate = Color(0, 0, 0, 0.9)
		l.modulate = Color(1.0, 0.92, 0.75, 1.0)
		l.position = Vector3(0, float(s[2]), 0)
		n.add_child(l)
		WorldLabelOverlay.adopt(l, {"px": 20, "font": "body", "max_dist": 26.0})


## Mirror only: the objective written in light over its target ("the reflection remembers the way").
func _update_inscription() -> void:
	var in_mirror: bool = RealmManager.instance != null and RealmManager.instance.current_realm == RealmManager.Realm.MIRROR and not RealmManager.instance.is_merged
	if _obj.is_empty():
		return
	if _inscription == null or not is_instance_valid(_inscription):
		_inscription = Label3D.new()
		_inscription.name = "MirrorInscription"
		_inscription.outline_modulate = Color(0.0, 0.05, 0.12, 0.9)
		_inscription.modulate = Color(CYAN.r, CYAN.g, CYAN.b, 1.0)
		var lv: Node = _find_level()
		if lv == null:
			return
		lv.add_child(_inscription)
		WorldLabelOverlay.adopt(_inscription, {"px": 24, "font": "flavor", "max_dist": 70.0})
	_inscription.visible = in_mirror
	_inscription.global_position = (_obj.get("target", Vector3.ZERO) as Vector3) + Vector3.UP * 2.6
	_inscription.text = "◇ " + String(_obj.get("title", "")) + " ◇"


func _draw() -> void:
	if _obj.is_empty():
		return
	var s: Vector2 = size
	var disp: Font = UITheme.display_font()
	var body: Font = UITheme.body_font()
	var title: String = String(_obj.get("title", "")).to_upper()
	var sub: String = String(_obj.get("sub", "")).to_upper()
	var k: float = 1.0 + 0.25 * _pop
	var tsz: int = int(19.0 * k)
	var tw: float = disp.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tsz).x
	var sw: float = body.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x if not sub.is_empty() else 0.0
	var sep_w: float = maxf(tw, sw) + 36.0
	var y: float = 176.0   # cleanly below the Reality/Mirror pills + [Q] keycap
	var glow: Color = GOLD.lerp(Color(1, 1, 1), _pop * 0.6)
	var cx: float = s.x * 0.5

	_draw_fractured_separator(cx, y - 26.0, sep_w, GOLD)
	var bot_y: float = (y + 38.0) if not sub.is_empty() else (y + 16.0)
	_draw_fractured_separator(cx, bot_y, sep_w, GOLD)

	# Diamond + title.
	_diamond(Vector2(cx - tw * 0.5 - 16.0, y - 7.0), 5.0, glow)
	_text(disp, Vector2(cx - tw * 0.5, y), title, tsz, glow, 8)

	# Second line: Wave X/3 · N left (when present); no verbose tip/hint clutter.
	if not sub.is_empty():
		_text(body, Vector2(cx - sw * 0.5, y + 23.0), sub, 15, Color(0.98, 0.94, 0.84, 0.96), 5)
	_draw_marker(s)

func _draw_fractured_separator(cx: float, y: float, w: float, col: Color) -> void:
	var hw := w * 0.5
	var points := PackedVector2Array([Vector2(cx - hw, y), Vector2(cx - hw * 0.3, y + 2.0), Vector2(cx + hw * 0.2, y - 1.0), Vector2(cx + hw, y)])
	draw_polyline(points, col, 1.5, true)


func _draw_marker(s: Vector2) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if cam == null or player == null or not _obj.has("target"):
		return
	var target: Vector3 = (_obj["target"] as Vector3) + Vector3.UP * 1.2
	var dist: float = player.global_position.distance_to(target)
	if dist < 2.2:
		return
	var behind: bool = cam.is_position_behind(target)
	var p: Vector2 = cam.unproject_position(target)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	# Viewport pixels -> this control's (stretched) coordinates.
	p *= s / vp
	var margin: float = 60.0
	var on_screen: bool = not behind and p.x > margin and p.x < s.x - margin and p.y > margin + 120.0 and p.y < s.y - margin
	var col: Color = CYAN if RealmManager.instance != null and RealmManager.instance.current_realm == RealmManager.Realm.MIRROR else GOLD
	var pulse: float = 0.75 + 0.25 * sin(float(Time.get_ticks_msec()) * 0.006)
	if on_screen:
		_diamond(p, 9.0 * pulse + 3.0, Color(col.r, col.g, col.b, 0.35))
		_diamond_outline(p, 11.0, Color(col.r, col.g, col.b, 0.95))
		var dt: String = "%dm" % int(round(dist))
		var dw: float = UITheme.body_font().get_string_size(dt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		_text(UITheme.body_font(), p + Vector2(-dw * 0.5, 30.0), dt, 15, Color(1, 1, 1, 0.9), 4)
		return
	# Off-screen: arrow on the screen edge pointing toward the target.
	var c: Vector2 = s * 0.5
	var d: Vector2 = p - c
	if behind:
		d = -d
	if d.length_squared() < 1.0:
		d = Vector2(0, -1)
	d = d.normalized()
	var ex: float = (s.x * 0.5 - margin) / maxf(0.001, absf(d.x))
	var ey: float = (s.y * 0.5 - margin) / maxf(0.001, absf(d.y))
	var edge: Vector2 = c + d * minf(ex, ey)
	var perp := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([edge + d * 14.0, edge - d * 6.0 + perp * 10.0, edge - d * 6.0 - perp * 10.0]), Color(col.r, col.g, col.b, 0.9 * pulse))
	var dt2: String = "%dm" % int(round(dist))
	_text(UITheme.body_font(), edge - d * 30.0 + Vector2(-12.0, 5.0), dt2, 14, Color(1, 1, 1, 0.85), 4)


func _wrap(font: Font, t: String, fsize: int, max_w: float) -> PackedStringArray:
	var out: PackedStringArray = []
	var cur: String = ""
	for w in t.split(" ", false):
		var trial: String = w if cur.is_empty() else cur + " " + w
		if font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > max_w and not cur.is_empty():
			out.append(cur)
			cur = w
		else:
			cur = trial
	if not cur.is_empty():
		out.append(cur)
	return out


func _diamond(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)


func _diamond_outline(c: Vector2, r: float, col: Color) -> void:
	draw_polyline(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)]), col, 2.0, true)


func _text(font: Font, pos: Vector2, t: String, fsize: int, col: Color, outline: int) -> void:
	if outline > 0:
		draw_string_outline(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, outline, Color(0, 0, 0, 0.8 * col.a))
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
