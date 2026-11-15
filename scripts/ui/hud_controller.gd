class_name HUDController
extends CanvasLayer
## Persistent single-instance HUD state & signal controller bound to Player, RealmManager,
## EncounterDirector, RunState, LeaderboardStore (live control prompts), and The Warden.
## Renders the custom concept HUD: Header Banner, Top-Left Diamond Crest + Crimson HP & Sub-Bar,
## Top-Center Dual [REALITY] <-> [MIRROR] Switcher, Top-Right Score/Combo/Timer,
## Bottom-Left Sword Diamond, and Bottom-Right Diamond Action Slots with live rebind labels.

@export var build_default_ui_if_empty: bool = true

@export_group("Optional Scene Node Bindings")
@export var hp_label_path: NodePath
@export var hp_bar_path: NodePath
@export var realm_chip_label_path: NodePath
@export var shift_key_label_path: NodePath
@export var score_label_path: NodePath
@export var combo_label_path: NodePath
@export var timer_label_path: NodePath
@export var boss_container_path: NodePath
@export var boss_label_path: NodePath
@export var boss_bar_path: NodePath
@export var toast_label_path: NodePath
@export var attack_prompt_path: NodePath
@export var interact_prompt_path: NodePath
@export var landing_prompt_path: NodePath

var displayed_hp: int = 100
var displayed_max_hp: int = 100
var hp_text: String = "100 / 100"

var active_realm_chip: String = "REALITY"
var shift_key_text: String = "[Q]"
var shift_rejection_flash_timer: float = 0.0
var last_shift_rejection_reason: String = ""

var score_text: String = "SCORE 000000"
var combo_text: String = "COMBO x1"
var timer_text: String = "00:00"
var section_name_text: String = "The Sundering Entry"

var boss_bar_visible: bool = false
var boss_hp_percent: float = 100.0
var boss_label_text: String = "THE WARDEN"

var landing_prompt_bright: bool = false
var attack_prompt_text: String = "LMB ATTACK  |  RMB HEAVY  |  SHIFT DODGE  |  "
var landing_prompt_text: String = "F LAND"
var interact_prompt_visible: bool = false
var interact_action_verb: String = "Interact"
var interact_prompt_text: String = "E: Interact"
var active_toast_text: String = ""
var toast_timer: float = 0.0
var dismissed_tutorials: Dictionary = {}

var _player_ref: Node = null
var _boss_ref: Node = null

# Visual element references for rich HUD styling
var _section_title_label: Label = null
var _stamina_bar: ProgressBar = null
var _crest_badge: HudDiamondBadge = null
var _weapon_badge: HudDiamondBadge = null
var _swap_badge: HudDiamondBadge = null
var _reality_pill_panel: PanelContainer = null
var _reality_pill_label: Label = null
var _mirror_pill_panel: PanelContainer = null
var _mirror_pill_label: Label = null
var _interact_panel: PanelContainer = null
var _action_slots: Dictionary = {} # action_name -> { "badge": HudDiamondBadge, "key": Label, "verb": Label }
var _pulse_rect: ColorRect = null
var _pulse_mat: ShaderMaterial = null
var _pulse_timer: float = 0.0
var _ui_built: bool = false


func _exit_tree() -> void:
	var store: Node = _get_leaderboard_store()
	if store != null:
		if store.has_signal("controls_rebound") and store.is_connected("controls_rebound", _on_controls_rebound):
			store.disconnect("controls_rebound", _on_controls_rebound)
		if store.has_signal("settings_changed") and store.is_connected("settings_changed", _on_settings_changed):
			store.disconnect("settings_changed", _on_settings_changed)
	_player_ref = null
	_boss_ref = null
	_action_slots.clear()


func _ready() -> void:
	add_to_group("hud")
	if build_default_ui_if_empty and not _ui_built and get_node_or_null("RootControl/TopHeaderBand") == null:
		_build_styled_hud_tree()
	else:
		_discover_styled_nodes()
	bind_singletons()
	refresh_input_prompts()
	_sync_ui_nodes()


func _process(delta: float) -> void:
	if shift_rejection_flash_timer > 0.0:
		shift_rejection_flash_timer = maxf(0.0, shift_rejection_flash_timer - delta)
		if shift_rejection_flash_timer <= 0.0:
			last_shift_rejection_reason = ""
			_sync_realm_pills()

	if _pulse_timer > 0.0 and _pulse_mat != null and _pulse_rect != null:
		_pulse_timer = maxf(0.0, _pulse_timer - delta)
		var norm: float = 1.0 - (_pulse_timer / 0.28)
		_pulse_mat.set_shader_parameter("shift_progress", clampf(norm, 0.0, 1.0))
		_pulse_rect.visible = _pulse_timer > 0.0

	if toast_timer > 0.0:
		toast_timer = maxf(0.0, toast_timer - delta)
		if toast_timer <= 0.0:
			active_toast_text = ""
			_sync_ui_nodes()

	if is_instance_valid(_player_ref):
		if _player_ref.has_method("is_currently_airborne"):
			var now_airborne: bool = bool(_player_ref.call("is_currently_airborne"))
			if now_airborne != landing_prompt_bright:
				landing_prompt_bright = now_airborne
				_sync_ui_nodes()
		if _stamina_bar != null:
			var dodge_cd: float = float(_player_ref.get("_dodge_cooldown_timer")) if _player_ref.get("_dodge_cooldown_timer") != null else 0.0
			var ratio: float = 1.0 - clampf(dodge_cd / 0.25, 0.0, 1.0)
			if int(_player_ref.get("current_state")) == 1: # DODGE
				ratio = 0.25
			_stamina_bar.value = ratio * 100.0


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
		section_name_text = _format_section_title(director.current_section, director.get_section_name(director.current_section))
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

	var store: Node = _get_leaderboard_store()
	if store != null:
		if store.has_signal("controls_rebound") and not store.is_connected("controls_rebound", _on_controls_rebound):
			store.connect("controls_rebound", _on_controls_rebound)
		if store.has_signal("settings_changed") and not store.is_connected("settings_changed", _on_settings_changed):
			store.connect("settings_changed", _on_settings_changed)
	refresh_input_prompts()


func refresh_input_prompts() -> void:
	var store: Node = _get_leaderboard_store()
	var lmb_lbl: String = "LMB"
	var rmb_lbl: String = "RMB"
	var dodge_lbl: String = "SHIFT"
	var jump_lbl: String = "SPACE"
	var land_lbl: String = "F"
	var interact_lbl: String = "E"
	var shift_lbl: String = "Q"

	if store != null and store.has_method("get_action_display_label"):
		lmb_lbl = String(store.call("get_action_display_label", "light_attack"))
		rmb_lbl = String(store.call("get_action_display_label", "heavy_attack"))
		dodge_lbl = String(store.call("get_action_display_label", "dodge"))
		jump_lbl = String(store.call("get_action_display_label", "jump"))
		land_lbl = String(store.call("get_action_display_label", "landing_attack"))
		interact_lbl = String(store.call("get_action_display_label", "interact"))
		shift_lbl = String(store.call("get_action_display_label", "dimension_shift"))

	shift_key_text = "[%s]" % shift_lbl
	attack_prompt_text = "%s ATTACK  |  %s HEAVY  |  %s DODGE  |  " % [lmb_lbl, rmb_lbl, dodge_lbl]
	landing_prompt_text = "%s LAND" % land_lbl
	interact_prompt_text = "[%s] %s" % [interact_lbl, interact_action_verb]

	_update_action_slot("light_attack", lmb_lbl)
	_update_action_slot("heavy_attack", rmb_lbl)
	_update_action_slot("dodge", dodge_lbl)
	_update_action_slot("jump", jump_lbl)
	_update_action_slot("landing_attack", land_lbl)
	_sync_ui_nodes()


func get_tutorial_prompt_text(tutorial_id: String) -> String:
	var store: Node = _get_leaderboard_store()
	var w_lbl: String = "W"
	var a_lbl: String = "A"
	var s_lbl: String = "S"
	var d_lbl: String = "D"
	var shift_lbl: String = "Q"
	var interact_lbl: String = "E"
	var land_lbl: String = "F"

	if store != null and store.has_method("get_action_display_label"):
		w_lbl = String(store.call("get_action_display_label", "move_forward"))
		a_lbl = String(store.call("get_action_display_label", "move_left"))
		s_lbl = String(store.call("get_action_display_label", "move_back"))
		d_lbl = String(store.call("get_action_display_label", "move_right"))
		shift_lbl = String(store.call("get_action_display_label", "dimension_shift"))
		interact_lbl = String(store.call("get_action_display_label", "interact"))
		land_lbl = String(store.call("get_action_display_label", "landing_attack"))

	match tutorial_id:
		"move":
			return "%s/%s/%s/%s: Move" % [w_lbl, a_lbl, s_lbl, d_lbl]
		"q_shift":
			return "%s: Shift" % shift_lbl
		"e_interact":
			return "%s: Interact" % interact_lbl
		"f_landing":
			return "%s in Air: Landing Attack" % land_lbl
	return ""


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
		var colon_idx: int = text.find(":")
		if colon_idx >= 0 and colon_idx + 1 < text.length():
			interact_action_verb = text.substr(colon_idx + 1).strip_edges()
		else:
			interact_action_verb = text.strip_edges()
	refresh_input_prompts()


func mark_tutorial_completed(tutorial_id: String) -> void:
	if not tutorial_id.is_empty():
		dismissed_tutorials[tutorial_id] = true


func is_tutorial_visible(tutorial_id: String) -> bool:
	return not bool(dismissed_tutorials.get(tutorial_id, false))


func _on_controls_rebound(_action_name: String, _display_label: String, _all_bindings: Dictionary) -> void:
	refresh_input_prompts()


func _on_settings_changed(_new_settings: Dictionary) -> void:
	refresh_input_prompts()


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
	_trigger_realm_pulse(new_realm == RealmManager.Realm.MIRROR)
	_sync_ui_nodes()


func _on_shift_rejected(reason: String) -> void:
	last_shift_rejection_reason = reason
	shift_rejection_flash_timer = 0.35
	active_toast_text = "SHIFT LOCKED"
	toast_timer = 0.9
	_sync_ui_nodes()


func _on_realms_merged() -> void:
	active_realm_chip = "REALMS MERGED"
	active_toast_text = "REALMS MERGED"
	toast_timer = 2.5
	_trigger_realm_pulse(true)
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
	section_name_text = _format_section_title(section_id, sec_name)
	if section_id == EncounterDirector.Section.EXECUTION_ARENA:
		boss_bar_visible = true
	else:
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


func _format_section_title(section_id: int, fallback: String) -> String:
	match section_id:
		0:
			return "THE SUNDERING ENTRY"
		1:
			return "THE HALL OF ECHOES"
		2:
			return "THE COLLAPSED GALLERY"
		3:
			return "THE MECHANISM CHAMBER"
		4:
			return "SANCTUM OF THE WARDEN"
		5:
			return "SANCTUM CLEARED"
	return fallback.to_upper()


func _trigger_realm_pulse(to_mirror: bool) -> void:
	if _pulse_mat == null or _pulse_rect == null:
		return
	var pulse_col: Color = Color(0.24, 0.80, 1.0, 1.0) if to_mirror else Color(0.95, 0.65, 0.20, 1.0)
	_pulse_mat.set_shader_parameter("pulse_color", pulse_col)
	_pulse_mat.set_shader_parameter("shift_progress", 0.0)
	_pulse_timer = 0.28
	_pulse_rect.visible = true


func _sync_ui_nodes() -> void:
	_set_label_text(hp_label_path, hp_text)
	_set_label_text(realm_chip_label_path, active_realm_chip)
	_set_label_text(shift_key_label_path, shift_key_text)
	_set_label_text(score_label_path, score_text)
	_set_label_text(combo_label_path, combo_text)
	_set_label_text(timer_label_path, timer_text)
	_set_label_text(boss_label_path, boss_label_text)
	_set_label_text(toast_label_path, active_toast_text)
	_set_label_text(attack_prompt_path, attack_prompt_text)

	if _section_title_label != null:
		_section_title_label.text = section_name_text

	var t_lbl: Label = get_node_or_null(timer_label_path) as Label if not timer_label_path.is_empty() else null
	if t_lbl != null and t_lbl.get_parent() != null and t_lbl.get_parent().name == "TimerRow":
		t_lbl.text = timer_text

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
	if _interact_panel != null:
		_interact_panel.visible = interact_prompt_visible

	if not landing_prompt_path.is_empty():
		var lctrl: CanvasItem = get_node_or_null(landing_prompt_path) as CanvasItem
		if lctrl != null:
			lctrl.modulate = Color.WHITE if landing_prompt_bright else Color(1, 1, 1, 0.55)
			if lctrl is Label:
				(lctrl as Label).text = landing_prompt_text

	if _action_slots.has("landing_attack"):
		var slot: Dictionary = _action_slots["landing_attack"]
		var badge: HudDiamondBadge = slot.get("badge") as HudDiamondBadge
		if badge != null:
			badge.highlighted = landing_prompt_bright

	_sync_realm_pills()


func _sync_realm_pills() -> void:
	var is_mirror: bool = (active_realm_chip == "MIRROR")
	var is_merged: bool = (active_realm_chip == "REALMS MERGED")

	if _reality_pill_panel != null:
		var r_active: bool = (not is_mirror) or is_merged
		var r_style := StyleBoxFlat.new()
		r_style.corner_radius_top_left = 4
		r_style.corner_radius_top_right = 4
		r_style.corner_radius_bottom_left = 4
		r_style.corner_radius_bottom_right = 4
		r_style.content_margin_left = 14
		r_style.content_margin_right = 14
		r_style.content_margin_top = 6
		r_style.content_margin_bottom = 6
		if shift_rejection_flash_timer > 0.0:
			r_style.bg_color = Color(0.45, 0.12, 0.12, 0.90)
			r_style.border_color = Color(1.0, 0.35, 0.30, 1.0)
			r_style.set_border_width_all(2)
		elif r_active:
			r_style.bg_color = Color(0.55, 0.35, 0.10, 0.90)
			r_style.border_color = Color(0.98, 0.76, 0.34, 1.0)
			r_style.set_border_width_all(2)
		else:
			r_style.bg_color = Color(0.06, 0.07, 0.10, 0.76)
			r_style.border_color = Color(0.36, 0.34, 0.30, 0.55)
			r_style.set_border_width_all(1)
		_reality_pill_panel.add_theme_stylebox_override("panel", r_style)

	if _mirror_pill_panel != null:
		var m_active: bool = is_mirror or is_merged
		var m_style := StyleBoxFlat.new()
		m_style.corner_radius_top_left = 4
		m_style.corner_radius_top_right = 4
		m_style.corner_radius_bottom_left = 4
		m_style.corner_radius_bottom_right = 4
		m_style.content_margin_left = 14
		m_style.content_margin_right = 14
		m_style.content_margin_top = 6
		m_style.content_margin_bottom = 6
		if m_active:
			m_style.bg_color = Color(0.08, 0.38, 0.58, 0.92)
			m_style.border_color = Color(0.32, 0.86, 1.0, 1.0)
			m_style.set_border_width_all(2)
		else:
			m_style.bg_color = Color(0.06, 0.07, 0.10, 0.76)
			m_style.border_color = Color(0.36, 0.38, 0.44, 0.55)
			m_style.set_border_width_all(1)
		_mirror_pill_panel.add_theme_stylebox_override("panel", m_style)

	if _reality_pill_label != null:
		_reality_pill_label.modulate = Color(1.0, 0.96, 0.86, 1.0) if (not is_mirror or is_merged) else Color(0.68, 0.66, 0.62, 0.78)
	if _mirror_pill_label != null:
		_mirror_pill_label.modulate = Color(0.88, 0.97, 1.0, 1.0) if (is_mirror or is_merged) else Color(0.68, 0.70, 0.76, 0.78)

	var accent: Color = Color(0.32, 0.84, 1.0, 0.95) if is_mirror else Color(0.80, 0.66, 0.42, 0.94)
	if _crest_badge != null:
		_crest_badge.border_color = accent
	if _swap_badge != null:
		_swap_badge.border_color = accent
	if _weapon_badge != null:
		_weapon_badge.border_color = accent


func _update_action_slot(action_name: String, key_str: String) -> void:
	if _action_slots.has(action_name):
		var slot: Dictionary = _action_slots[action_name]
		var klbl: Label = slot.get("key") as Label
		if klbl != null:
			klbl.text = key_str


func _discover_styled_nodes() -> void:
	_section_title_label = get_node_or_null("RootControl/TopHeaderBand/HeaderMargin/HeaderHBox/SectionTitleLabel") as Label
	_stamina_bar = get_node_or_null("RootControl/TopLeftVitality/BarsVBox/StaminaBar") as ProgressBar
	_crest_badge = get_node_or_null("RootControl/TopLeftVitality/CrestBadge") as HudDiamondBadge
	_weapon_badge = get_node_or_null("RootControl/BottomLeftWeapon/WeaponDiamond") as HudDiamondBadge
	_swap_badge = get_node_or_null("RootControl/TopCenterRealmCluster/PillsRow/SwapMedallion") as HudDiamondBadge
	_reality_pill_panel = get_node_or_null("RootControl/TopCenterRealmCluster/PillsRow/RealityPillPanel") as PanelContainer
	_reality_pill_label = get_node_or_null("RootControl/TopCenterRealmCluster/PillsRow/RealityPillPanel/RealityLabel") as Label
	_mirror_pill_panel = get_node_or_null("RootControl/TopCenterRealmCluster/PillsRow/MirrorPillPanel") as PanelContainer
	_mirror_pill_label = get_node_or_null("RootControl/TopCenterRealmCluster/PillsRow/MirrorPillPanel/MirrorLabel") as Label
	_interact_panel = get_node_or_null("RootControl/BottomCenterInteractPanel") as PanelContainer
	_pulse_rect = get_node_or_null("RootControl/RealmPulseOverlay") as ColorRect
	if _pulse_rect != null and _pulse_rect.material is ShaderMaterial:
		_pulse_mat = _pulse_rect.material as ShaderMaterial

	var slots_root: Node = get_node_or_null("RootControl/BottomRightActionsCluster/SlotsRow")
	if slots_root != null:
		_action_slots.clear()
		for child in slots_root.get_children():
			var act: String = String(child.get_meta("action_name", ""))
			if act.is_empty():
				continue
			_action_slots[act] = {
				"badge": child.get_node_or_null("DiamondIcon") as HudDiamondBadge,
				"key": child.get_node_or_null("KeyLabel") as Label,
				"verb": child.get_node_or_null("VerbLabel") as Label,
			}


func _build_styled_hud_tree() -> void:
	_ui_built = true
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var root := Control.new()
	root.name = "RootControl"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# 0. Fullscreen Realm Shift Ripple Overlay
	_pulse_rect = ColorRect.new()
	_pulse_rect.name = "RealmPulseOverlay"
	_pulse_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pulse_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pulse_rect.visible = false
	if ResourceLoader.exists("res://assets/shaders/realm_shift_pulse.gdshader"):
		var sh: Shader = load("res://assets/shaders/realm_shift_pulse.gdshader") as Shader
		if sh != null:
			_pulse_mat = ShaderMaterial.new()
			_pulse_mat.shader = sh
			_pulse_rect.material = _pulse_mat
	root.add_child(_pulse_rect)

	# 1. Top Cinematic Header Band: PARALLAX ------ <SECTION TITLE>
	var header_band := PanelContainer.new()
	header_band.name = "TopHeaderBand"
	header_band.anchor_left = 0.0
	header_band.anchor_right = 1.0
	header_band.anchor_top = 0.0
	header_band.anchor_bottom = 0.0
	header_band.offset_bottom = 52.0
	header_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var header_bg := StyleBoxFlat.new()
	header_bg.bg_color = Color(0.03, 0.03, 0.05, 0.72)
	header_bg.border_width_bottom = 1
	header_bg.border_color = Color(0.55, 0.45, 0.28, 0.35)
	header_band.add_theme_stylebox_override("panel", header_bg)
	root.add_child(header_band)

	var header_margin := MarginContainer.new()
	header_margin.name = "HeaderMargin"
	header_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_margin.add_theme_constant_override("margin_left", 36)
	header_margin.add_theme_constant_override("margin_right", 36)
	header_margin.add_theme_constant_override("margin_top", 6)
	header_margin.add_theme_constant_override("margin_bottom", 6)
	header_band.add_child(header_margin)

	var header_hbox := HBoxContainer.new()
	header_hbox.name = "HeaderHBox"
	header_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_hbox.add_theme_constant_override("separation", 24)
	header_margin.add_child(header_hbox)

	var brand_lbl := Label.new()
	brand_lbl.name = "BrandTitleLabel"
	brand_lbl.text = "PARALLAX"
	brand_lbl.add_theme_font_size_override("font_size", 28)
	brand_lbl.add_theme_color_override("font_color", Color(0.95, 0.89, 0.76, 1.0))
	brand_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	header_hbox.add_child(brand_lbl)

	var rule_wrap := CenterContainer.new()
	rule_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_hbox.add_child(rule_wrap)

	var rule_line := ColorRect.new()
	rule_line.custom_minimum_size = Vector2(260, 1.5)
	rule_line.color = Color(0.76, 0.64, 0.42, 0.65)
	rule_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule_wrap.add_child(rule_line)

	_section_title_label = Label.new()
	_section_title_label.name = "SectionTitleLabel"
	_section_title_label.text = section_name_text
	_section_title_label.add_theme_font_size_override("font_size", 17)
	_section_title_label.add_theme_color_override("font_color", Color(0.88, 0.82, 0.70, 0.95))
	header_hbox.add_child(_section_title_label)

	# 2. Top-Left Vitality Cluster (Diamond Crest + Crimson HP Bar + Secondary Bar)
	var top_left := HBoxContainer.new()
	top_left.name = "TopLeftVitality"
	top_left.offset_left = 36.0
	top_left.offset_top = 68.0
	top_left.offset_right = 400.0
	top_left.offset_bottom = 136.0
	top_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_left.add_theme_constant_override("separation", 12)
	root.add_child(top_left)

	_crest_badge = HudDiamondBadge.new()
	_crest_badge.name = "CrestBadge"
	_crest_badge.icon_kind = "crest"
	_crest_badge.custom_minimum_size = Vector2(56, 56)
	top_left.add_child(_crest_badge)

	var bars_vbox := VBoxContainer.new()
	bars_vbox.name = "BarsVBox"
	bars_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars_vbox.add_theme_constant_override("separation", 5)
	top_left.add_child(bars_vbox)

	var hp_lbl := Label.new()
	hp_lbl.name = "HPLabel"
	hp_lbl.text = "100 / 100"
	hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_lbl.add_theme_font_size_override("font_size", 15)
	hp_lbl.add_theme_color_override("font_color", Color(0.95, 0.91, 0.82, 1.0))
	hp_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	bars_vbox.add_child(hp_lbl)
	hp_label_path = get_path_to(hp_lbl)

	var hp_bar := ProgressBar.new()
	hp_bar.name = "HPBar"
	hp_bar.custom_minimum_size = Vector2(270, 15)
	hp_bar.value = 100.0
	hp_bar.show_percentage = false
	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.08, 0.06, 0.07, 0.88)
	hp_bg.border_color = Color(0.62, 0.52, 0.36, 0.9)
	hp_bg.set_border_width_all(1)
	hp_bg.set_corner_radius_all(2)
	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.76, 0.16, 0.16, 1.0)
	hp_fill.set_corner_radius_all(1)
	hp_bar.add_theme_stylebox_override("background", hp_bg)
	hp_bar.add_theme_stylebox_override("fill", hp_fill)
	bars_vbox.add_child(hp_bar)
	hp_bar_path = get_path_to(hp_bar)

	_stamina_bar = ProgressBar.new()
	_stamina_bar.name = "StaminaBar"
	_stamina_bar.custom_minimum_size = Vector2(180, 5)
	_stamina_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_stamina_bar.value = 100.0
	_stamina_bar.show_percentage = false
	var st_bg := StyleBoxFlat.new()
	st_bg.bg_color = Color(0.08, 0.08, 0.10, 0.72)
	var st_fill := StyleBoxFlat.new()
	st_fill.bg_color = Color(0.92, 0.88, 0.76, 0.95)
	_stamina_bar.add_theme_stylebox_override("background", st_bg)
	_stamina_bar.add_theme_stylebox_override("fill", st_fill)
	bars_vbox.add_child(_stamina_bar)

	# 3. Top-Center Dual Realm Switcher ([ REALITY ] <-> [ MIRROR ] + [Q])
	var top_center := VBoxContainer.new()
	top_center.name = "TopCenterRealmCluster"
	top_center.anchor_left = 0.5
	top_center.anchor_right = 0.5
	top_center.offset_left = -180.0
	top_center.offset_right = 180.0
	top_center.offset_top = 66.0
	top_center.offset_bottom = 142.0
	top_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_center.add_theme_constant_override("separation", 4)
	root.add_child(top_center)

	var pills_row := HBoxContainer.new()
	pills_row.name = "PillsRow"
	pills_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pills_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pills_row.add_theme_constant_override("separation", 10)
	top_center.add_child(pills_row)

	_reality_pill_panel = PanelContainer.new()
	_reality_pill_panel.name = "RealityPillPanel"
	_reality_pill_panel.custom_minimum_size = Vector2(126, 34)
	_reality_pill_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pills_row.add_child(_reality_pill_panel)

	_reality_pill_label = Label.new()
	_reality_pill_label.name = "RealityLabel"
	_reality_pill_label.text = "REALITY"
	_reality_pill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reality_pill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reality_pill_label.add_theme_font_size_override("font_size", 15)
	_reality_pill_panel.add_child(_reality_pill_label)

	_swap_badge = HudDiamondBadge.new()
	_swap_badge.name = "SwapMedallion"
	_swap_badge.icon_kind = "swap"
	_swap_badge.circular_frame = true
	_swap_badge.custom_minimum_size = Vector2(38, 38)
	pills_row.add_child(_swap_badge)

	_mirror_pill_panel = PanelContainer.new()
	_mirror_pill_panel.name = "MirrorPillPanel"
	_mirror_pill_panel.custom_minimum_size = Vector2(126, 34)
	_mirror_pill_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pills_row.add_child(_mirror_pill_panel)

	_mirror_pill_label = Label.new()
	_mirror_pill_label.name = "MirrorLabel"
	_mirror_pill_label.text = "MIRROR"
	_mirror_pill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mirror_pill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mirror_pill_label.add_theme_font_size_override("font_size", 15)
	_mirror_pill_panel.add_child(_mirror_pill_label)

	var key_row := HBoxContainer.new()
	key_row.alignment = BoxContainer.ALIGNMENT_CENTER
	key_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_center.add_child(key_row)

	var shift_key_lbl := Label.new()
	shift_key_lbl.name = "ShiftKeyLabel"
	shift_key_lbl.text = "[Q]"
	shift_key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shift_key_lbl.add_theme_font_size_override("font_size", 13)
	shift_key_lbl.add_theme_color_override("font_color", Color(0.95, 0.90, 0.78, 0.95))
	shift_key_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	key_row.add_child(shift_key_lbl)
	shift_key_label_path = get_path_to(shift_key_lbl)

	var compat_chip := Label.new()
	compat_chip.name = "RealmChipLabel"
	compat_chip.visible = false
	compat_chip.text = "REALITY"
	top_center.add_child(compat_chip)
	realm_chip_label_path = get_path_to(compat_chip)

	# 4. Top-Right Score / Combo / Timer Cluster
	var top_right := VBoxContainer.new()
	top_right.name = "TopRightPanel"
	top_right.anchor_left = 1.0
	top_right.anchor_right = 1.0
	top_right.offset_left = -320.0
	top_right.offset_top = 66.0
	top_right.offset_right = -36.0
	top_right.offset_bottom = 160.0
	top_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_right.add_theme_constant_override("separation", 3)
	root.add_child(top_right)

	var score_lbl := Label.new()
	score_lbl.name = "ScoreLabel"
	score_lbl.text = "SCORE 000000"
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_lbl.add_theme_font_size_override("font_size", 22)
	score_lbl.add_theme_color_override("font_color", Color(0.96, 0.92, 0.84, 1.0))
	score_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	top_right.add_child(score_lbl)
	score_label_path = get_path_to(score_lbl)

	var combo_lbl := Label.new()
	combo_lbl.name = "ComboLabel"
	combo_lbl.text = "COMBO x1"
	combo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	combo_lbl.add_theme_font_size_override("font_size", 19)
	combo_lbl.add_theme_color_override("font_color", Color(0.92, 0.70, 0.30, 1.0))
	combo_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	top_right.add_child(combo_lbl)
	combo_label_path = get_path_to(combo_lbl)

	var timer_lbl := Label.new()
	timer_lbl.name = "TimerLabel"
	timer_lbl.text = "00:00"
	timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timer_lbl.add_theme_font_size_override("font_size", 17)
	timer_lbl.add_theme_color_override("font_color", Color(0.86, 0.83, 0.78, 0.95))
	timer_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	top_right.add_child(timer_lbl)
	timer_label_path = get_path_to(timer_lbl)

	# 5. Bottom-Left Equipped Weapon Diamond
	var bl_weapon := VBoxContainer.new()
	bl_weapon.name = "BottomLeftWeapon"
	bl_weapon.anchor_top = 1.0
	bl_weapon.anchor_bottom = 1.0
	bl_weapon.offset_left = 36.0
	bl_weapon.offset_top = -140.0
	bl_weapon.offset_right = 128.0
	bl_weapon.offset_bottom = -28.0
	bl_weapon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bl_weapon.add_theme_constant_override("separation", 4)
	root.add_child(bl_weapon)

	_weapon_badge = HudDiamondBadge.new()
	_weapon_badge.name = "WeaponDiamond"
	_weapon_badge.icon_kind = "weapon_sword"
	_weapon_badge.custom_minimum_size = Vector2(82, 82)
	_weapon_badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bl_weapon.add_child(_weapon_badge)

	var wpn_lbl := Label.new()
	wpn_lbl.name = "SwordSlotLabel"
	wpn_lbl.text = "SWORD"
	wpn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wpn_lbl.add_theme_font_size_override("font_size", 11)
	wpn_lbl.add_theme_color_override("font_color", Color(0.82, 0.76, 0.64, 0.9))
	bl_weapon.add_child(wpn_lbl)

	# 6. Bottom-Right Action Diamond Slots
	var br_cluster := VBoxContainer.new()
	br_cluster.name = "BottomRightActionsCluster"
	br_cluster.anchor_left = 1.0
	br_cluster.anchor_top = 1.0
	br_cluster.anchor_right = 1.0
	br_cluster.anchor_bottom = 1.0
	br_cluster.offset_left = -450.0
	br_cluster.offset_top = -128.0
	br_cluster.offset_right = -36.0
	br_cluster.offset_bottom = -24.0
	br_cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(br_cluster)

	var slots_row := HBoxContainer.new()
	slots_row.name = "SlotsRow"
	slots_row.alignment = BoxContainer.ALIGNMENT_END
	slots_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slots_row.add_theme_constant_override("separation", 16)
	br_cluster.add_child(slots_row)

	_action_slots.clear()
	var slot_defs: Array[Dictionary] = [
		{"action": "light_attack", "icon": "light_attack", "key": "LMB", "verb": "ATTACK"},
		{"action": "heavy_attack", "icon": "heavy_attack", "key": "RMB", "verb": "HEAVY"},
		{"action": "dodge", "icon": "dodge", "key": "SHIFT", "verb": "DODGE"},
		{"action": "jump", "icon": "jump", "key": "SPACE", "verb": "JUMP"},
		{"action": "landing_attack", "icon": "landing_attack", "key": "F", "verb": "LAND"},
	]
	for sd in slot_defs:
		var act_name: String = String(sd["action"])
		var slot_box := VBoxContainer.new()
		slot_box.name = "Slot_" + act_name
		slot_box.set_meta("action_name", act_name)
		slot_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_box.add_theme_constant_override("separation", 3)
		slots_row.add_child(slot_box)

		var badge := HudDiamondBadge.new()
		badge.name = "DiamondIcon"
		badge.icon_kind = String(sd["icon"])
		badge.custom_minimum_size = Vector2(54, 54)
		badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot_box.add_child(badge)

		var key_lbl := Label.new()
		key_lbl.name = "KeyLabel"
		key_lbl.text = String(sd["key"])
		key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_lbl.add_theme_font_size_override("font_size", 13)
		key_lbl.add_theme_color_override("font_color", Color(0.96, 0.92, 0.84, 1.0))
		key_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		slot_box.add_child(key_lbl)

		var verb_lbl := Label.new()
		verb_lbl.name = "VerbLabel"
		verb_lbl.text = String(sd["verb"])
		verb_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		verb_lbl.add_theme_font_size_override("font_size", 11)
		verb_lbl.add_theme_color_override("font_color", Color(0.76, 0.68, 0.54, 0.92))
		slot_box.add_child(verb_lbl)

		_action_slots[act_name] = {"badge": badge, "key": key_lbl, "verb": verb_lbl}

	# Compatibility labels synced silently with diamond badges
	var compat_attack := Label.new()
	compat_attack.name = "AttackPromptLabel"
	compat_attack.visible = false
	br_cluster.add_child(compat_attack)
	attack_prompt_path = get_path_to(compat_attack)

	var compat_land := Label.new()
	compat_land.name = "LandingPromptLabel"
	compat_land.visible = false
	br_cluster.add_child(compat_land)
	landing_prompt_path = get_path_to(compat_land)

	# 7. Contextual Bottom-Center Interact Pill
	_interact_panel = PanelContainer.new()
	_interact_panel.name = "BottomCenterInteractPanel"
	_interact_panel.visible = false
	_interact_panel.anchor_left = 0.5
	_interact_panel.anchor_right = 0.5
	_interact_panel.anchor_top = 1.0
	_interact_panel.anchor_bottom = 1.0
	_interact_panel.offset_left = -140.0
	_interact_panel.offset_right = 140.0
	_interact_panel.offset_top = -124.0
	_interact_panel.offset_bottom = -84.0
	_interact_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var i_style := StyleBoxFlat.new()
	i_style.bg_color = Color(0.08, 0.08, 0.11, 0.88)
	i_style.border_color = Color(0.92, 0.72, 0.32, 0.95)
	i_style.set_border_width_all(2)
	i_style.set_corner_radius_all(6)
	i_style.content_margin_left = 18
	i_style.content_margin_right = 18
	i_style.content_margin_top = 6
	i_style.content_margin_bottom = 6
	_interact_panel.add_theme_stylebox_override("panel", i_style)
	root.add_child(_interact_panel)

	var interact_lbl := Label.new()
	interact_lbl.name = "InteractPromptLabel"
	interact_lbl.text = "[E] Interact"
	interact_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interact_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	interact_lbl.add_theme_font_size_override("font_size", 16)
	interact_lbl.add_theme_color_override("font_color", Color(0.98, 0.90, 0.68, 1.0))
	_interact_panel.add_child(interact_lbl)
	interact_prompt_path = get_path_to(interact_lbl)

	# 8. Boss Health Bar (Bottom-Center above margin, Stage 05 Execution Arena)
	var boss_box := VBoxContainer.new()
	boss_box.name = "BottomCenterBossPanel"
	boss_box.visible = false
	boss_box.anchor_left = 0.5
	boss_box.anchor_right = 0.5
	boss_box.anchor_top = 1.0
	boss_box.anchor_bottom = 1.0
	boss_box.offset_left = -300.0
	boss_box.offset_right = 300.0
	boss_box.offset_top = -84.0
	boss_box.offset_bottom = -28.0
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(boss_box)
	boss_container_path = get_path_to(boss_box)

	var b_lbl := Label.new()
	b_lbl.name = "BossLabel"
	b_lbl.text = "THE WARDEN"
	b_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b_lbl.add_theme_font_size_override("font_size", 18)
	b_lbl.add_theme_color_override("font_color", Color(0.96, 0.85, 0.68, 1.0))
	b_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	boss_box.add_child(b_lbl)
	boss_label_path = get_path_to(b_lbl)

	var b_bar := ProgressBar.new()
	b_bar.name = "BossHPBar"
	b_bar.custom_minimum_size = Vector2(560, 18)
	b_bar.value = 100.0
	b_bar.show_percentage = false
	var b_bg := StyleBoxFlat.new()
	b_bg.bg_color = Color(0.08, 0.05, 0.06, 0.90)
	b_bg.border_color = Color(0.80, 0.64, 0.36, 0.95)
	b_bg.set_border_width_all(2)
	var b_fill := StyleBoxFlat.new()
	b_fill.bg_color = Color(0.76, 0.14, 0.18, 1.0)
	b_bar.add_theme_stylebox_override("background", b_bg)
	b_bar.add_theme_stylebox_override("fill", b_fill)
	boss_box.add_child(b_bar)
	boss_bar_path = get_path_to(b_bar)

	# 9. Center Toast Notification Banner
	var toast := Label.new()
	toast.name = "CenterToastLabel"
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.offset_left = -260.0
	toast.offset_right = 260.0
	toast.offset_top = 152.0
	toast.offset_bottom = 196.0
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 24)
	toast.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42, 1.0))
	toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast)
	toast_label_path = get_path_to(toast)


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
