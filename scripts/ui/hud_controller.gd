class_name HUDController
extends CanvasLayer
## Persistent single-instance HUD state & signal controller bound to Player, RealmManager,
## EncounterDirector, RunState, and The Warden. Holds deterministic display fields and optional
## Control/Label/ProgressBar node bindings for scene composition.

@export_group("Optional Scene Node Bindings")
@export var hp_label_path: NodePath
@export var hp_bar_path: NodePath
@export var realm_chip_label_path: NodePath
@export var score_label_path: NodePath
@export var combo_label_path: NodePath
@export var timer_label_path: NodePath
@export var boss_container_path: NodePath
@export var boss_label_path: NodePath
@export var boss_bar_path: NodePath
@export var toast_label_path: NodePath
@export var interact_prompt_path: NodePath
@export var landing_prompt_path: NodePath

var displayed_hp: int = 100
var displayed_max_hp: int = 100
var hp_text: String = "100 / 100"

var active_realm_chip: String = "REALITY"
var shift_rejection_flash_timer: float = 0.0
var last_shift_rejection_reason: String = ""

var score_text: String = "SCORE 000000"
var combo_text: String = "COMBO x1"
var timer_text: String = "00:00"
var section_name_text: String = "Entry Vestibule"

var boss_bar_visible: bool = false
var boss_hp_percent: float = 100.0
var boss_label_text: String = "THE WARDEN"

var landing_prompt_bright: bool = false
var interact_prompt_visible: bool = false
var interact_prompt_text: String = "E: Interact"
var active_toast_text: String = ""
var toast_timer: float = 0.0
var dismissed_tutorials: Dictionary = {}

var _player_ref: Node = null
var _boss_ref: Node = null


func _ready() -> void:
	add_to_group("hud")
	bind_singletons()
	_sync_ui_nodes()


func _process(delta: float) -> void:
	if shift_rejection_flash_timer > 0.0:
		shift_rejection_flash_timer = maxf(0.0, shift_rejection_flash_timer - delta)
		if shift_rejection_flash_timer <= 0.0:
			last_shift_rejection_reason = ""

	if toast_timer > 0.0:
		toast_timer = maxf(0.0, toast_timer - delta)
		if toast_timer <= 0.0:
			active_toast_text = ""
			_sync_ui_nodes()

	if is_instance_valid(_player_ref) and _player_ref.has_method("is_currently_airborne"):
		var now_airborne: bool = bool(_player_ref.call("is_currently_airborne"))
		if now_airborne != landing_prompt_bright:
			landing_prompt_bright = now_airborne
			_sync_ui_nodes()


func bind_singletons() -> void:
	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm != null:
		if not rm.realm_changed.is_connected(_on_realm_changed):
			rm.realm_changed.connect(_on_realm_changed)
		if not rm.shift_rejected.is_connected(_on_shift_rejected):
			rm.shift_rejected.connect(_on_shift_rejected)
		if not rm.realms_merged.is_connected(_on_realms_merged):
			rm.realms_merged.connect(_on_realms_merged)
		if rm.is_merged:
			active_realm_chip = "REALMS MERGED"
		else:
			active_realm_chip = "MIRROR" if rm.current_realm == RealmManager.Realm.MIRROR else "REALITY"

	var director: EncounterDirector = EncounterDirector.instance as EncounterDirector
	if director != null:
		if not director.section_changed.is_connected(_on_section_changed):
			director.section_changed.connect(_on_section_changed)
		if not director.encounter_started.is_connected(_on_encounter_started):
			director.encounter_started.connect(_on_encounter_started)
		if not director.encounter_cleared.is_connected(_on_encounter_cleared):
			director.encounter_cleared.connect(_on_encounter_cleared)
		section_name_text = director.get_section_name(director.current_section)
		boss_bar_visible = (director.current_section == EncounterDirector.Section.EXECUTION_ARENA)

	var run_state: Node = _get_run_state()
	if run_state != null:
		if run_state.has_signal("score_changed") and not run_state.is_connected("score_changed", _on_score_changed):
			run_state.connect("score_changed", _on_score_changed)
		if run_state.has_signal("combo_changed") and not run_state.is_connected("combo_changed", _on_combo_changed):
			run_state.connect("combo_changed", _on_combo_changed)
		if run_state.has_signal("no_hit_awarded") and not run_state.is_connected("no_hit_awarded", _on_no_hit_awarded):
			run_state.connect("no_hit_awarded", _on_no_hit_awarded)
		if run_state.has_signal("run_timer_updated") and not run_state.is_connected("run_timer_updated", _on_run_timer_updated):
			run_state.connect("run_timer_updated", _on_run_timer_updated)
		_on_score_changed(int(run_state.get("score")), 0, "init")
		var mult: int = int(run_state.call("get_combo_multiplier")) if run_state.has_method("get_combo_multiplier") else 1
		_on_combo_changed(mult, int(run_state.get("combo_hits")), float(run_state.get("combo_timer")))


func bind_player(player: Node) -> void:
	_player_ref = player
	if player == null:
		return
	if player.has_signal("health_changed") and not player.is_connected("health_changed", _on_player_health_changed):
		player.connect("health_changed", _on_player_health_changed)
	if player.has_signal("player_died") and not player.is_connected("player_died", _on_player_died):
		player.connect("player_died", _on_player_died)
	var cur_hp: Variant = player.get("health")
	var m_hp: Variant = player.get("max_health")
	if cur_hp != null and m_hp != null:
		_on_player_health_changed(int(cur_hp), int(m_hp))


func bind_boss(boss: Node) -> void:
	_boss_ref = boss
	if boss == null:
		boss_bar_visible = false
		_sync_ui_nodes()
		return
	if boss.has_signal("health_changed") and not boss.is_connected("health_changed", _on_boss_health_changed):
		boss.connect("health_changed", _on_boss_health_changed)
	if boss.has_signal("boss_defeated") and not boss.is_connected("boss_defeated", _on_boss_defeated):
		boss.connect("boss_defeated", _on_boss_defeated)
	var cur_hp: Variant = boss.get("health")
	var m_hp: Variant = boss.get("max_health")
	if cur_hp != null and m_hp != null:
		_on_boss_health_changed(int(cur_hp), int(m_hp))


func set_interact_prompt(visible_flag: bool, text: String = "E: Interact") -> void:
	interact_prompt_visible = visible_flag
	if not text.is_empty():
		interact_prompt_text = text
	_sync_ui_nodes()


func mark_tutorial_completed(tutorial_id: String) -> void:
	if not tutorial_id.is_empty():
		dismissed_tutorials[tutorial_id] = true


func is_tutorial_visible(tutorial_id: String) -> bool:
	return not bool(dismissed_tutorials.get(tutorial_id, false))


func _on_player_health_changed(current_hp: int, max_hp: int) -> void:
	displayed_hp = maxi(0, current_hp)
	displayed_max_hp = maxi(1, max_hp)
	hp_text = "%d / %d" % [displayed_hp, displayed_max_hp]
	_sync_ui_nodes()


func _on_player_died() -> void:
	_on_player_health_changed(0, displayed_max_hp)


func _on_realm_changed(new_realm: int) -> void:
	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm != null and rm.is_merged:
		active_realm_chip = "REALMS MERGED"
	else:
		active_realm_chip = "MIRROR" if new_realm == RealmManager.Realm.MIRROR else "REALITY"
	mark_tutorial_completed("q_shift")
	_sync_ui_nodes()


func _on_shift_rejected(reason: String) -> void:
	last_shift_rejection_reason = reason
	shift_rejection_flash_timer = 0.35
	_sync_ui_nodes()


func _on_realms_merged() -> void:
	active_realm_chip = "REALMS MERGED"
	active_toast_text = "REALMS MERGED"
	toast_timer = 2.5
	_sync_ui_nodes()


func _on_score_changed(new_score: int, _delta: int, _event_type: String) -> void:
	score_text = "SCORE %06d" % maxi(0, new_score)
	_sync_ui_nodes()


func _on_combo_changed(multiplier: int, _hits: int, _time_remaining: float) -> void:
	combo_text = "COMBO x%d" % maxi(1, multiplier)
	_sync_ui_nodes()


func _on_no_hit_awarded(_encounter_id: String, bonus_points: int) -> void:
	active_toast_text = "+%d NO-HIT ENCOUNTER" % bonus_points
	toast_timer = 2.5
	_sync_ui_nodes()


func _on_run_timer_updated(elapsed_sec: float) -> void:
	var total_sec: int = maxi(0, int(elapsed_sec))
	timer_text = "%02d:%02d" % [total_sec / 60, total_sec % 60]
	_sync_ui_nodes()


func _on_section_changed(section_id: int, sec_name: String) -> void:
	section_name_text = sec_name
	if section_id == EncounterDirector.Section.EXECUTION_ARENA:
		boss_bar_visible = true
	elif section_id != EncounterDirector.Section.EXECUTION_ARENA:
		boss_bar_visible = false
	_sync_ui_nodes()


func _on_encounter_started(encounter_id: String, _section_id: int) -> void:
	if encounter_id == "the_warden":
		boss_bar_visible = true
		_sync_ui_nodes()


func _on_encounter_cleared(encounter_id: String, _section_id: int) -> void:
	if encounter_id == "the_warden":
		boss_bar_visible = false
		_sync_ui_nodes()


func _on_boss_health_changed(current_hp: int, max_hp: int) -> void:
	var m_hp: int = maxi(1, max_hp)
	boss_hp_percent = clampf((float(current_hp) / float(m_hp)) * 100.0, 0.0, 100.0)
	boss_bar_visible = current_hp > 0
	_sync_ui_nodes()


func _on_boss_defeated() -> void:
	boss_hp_percent = 0.0
	boss_bar_visible = false
	_sync_ui_nodes()


func _sync_ui_nodes() -> void:
	_set_label_text(hp_label_path, hp_text)
	_set_label_text(realm_chip_label_path, active_realm_chip)
	_set_label_text(score_label_path, score_text)
	_set_label_text(combo_label_path, combo_text)
	_set_label_text(timer_label_path, timer_text)
	_set_label_text(boss_label_path, boss_label_text)
	_set_label_text(toast_label_path, active_toast_text)

	if not hp_bar_path.is_empty():
		var hp_bar: Range = get_node_or_null(hp_bar_path) as Range
		if hp_bar != null:
			hp_bar.max_value = float(displayed_max_hp)
			hp_bar.value = float(displayed_hp)

	if not boss_container_path.is_empty():
		var boss_ctrl: CanvasItem = get_node_or_null(boss_container_path) as CanvasItem
		if boss_ctrl != null:
			boss_ctrl.visible = boss_bar_visible

	if not boss_bar_path.is_empty():
		var b_bar: Range = get_node_or_null(boss_bar_path) as Range
		if b_bar != null:
			b_bar.max_value = 100.0
			b_bar.value = boss_hp_percent

	if not interact_prompt_path.is_empty():
		var ictrl: CanvasItem = get_node_or_null(interact_prompt_path) as CanvasItem
		if ictrl != null:
			ictrl.visible = interact_prompt_visible
			if ictrl is Label:
				(ictrl as Label).text = interact_prompt_text

	if not landing_prompt_path.is_empty():
		var lctrl: CanvasItem = get_node_or_null(landing_prompt_path) as CanvasItem
		if lctrl != null:
			lctrl.modulate = Color.WHITE if landing_prompt_bright else Color(1, 1, 1, 0.45)


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
