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
var shift_key_text: String = "Q"
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

# --- Visual-state (Phase 3 restyle): ghost bars, flashes, chip sweeps, combo bar, popups ---
const GOLD := Color(0.784, 0.659, 0.376)
const GOLD_HI := Color(1.0, 0.92, 0.70)
const REALITY_COL := Color(0.902, 0.600, 0.220)
const MIRROR_COL := Color(0.200, 0.710, 1.000)
const MERGED_COL := Color(0.68, 0.45, 1.0)
const COMBO_WINDOW_SEC: float = 4.0
var _hp_bar: ProgressBar = null
var _boss_bar: ProgressBar = null
var _hp_ghost: float = 1.0
var _hp_ratio: float = 1.0
var _hp_ghost_delay: float = 0.0
var _hp_flash: float = 0.0
var _boss_ghost: float = 1.0
var _boss_ghost_delay: float = 0.0
var _chip_sweep: Dictionary = {"reality": 1.0, "mirror": 1.0}
var _merged_label: Label = null
var _score_lbl: Label = null
var _combo_lbl: Label = null
var _combo_bar: ProgressBar = null
var _combo_mult: int = 1
var _combo_left: float = 0.0
var _last_score: int = 0
var _last_toast_text: String = ""
var _toast_label: Label = null
var _root_ctrl: Control = null


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
	_wire_visuals()
	bind_singletons()
	refresh_input_prompts()
	_sync_ui_nodes()


func _style_hud_label(lbl: Label, display: bool, size: int) -> void:
	if lbl == null:
		return
	lbl.add_theme_font_override("font", UITheme.display_font() if display else UITheme.body_font())
	lbl.add_theme_font_size_override("font_size", size)


func _empty_box(pad_h: int = 0, pad_v: int = 0) -> StyleBoxEmpty:
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	return sb


## Applies fonts, custom-drawn frames, combo bar, merged label, toast banner. Idempotent; works for
## both the generated tree and a scene-authored HUD (uses the *_path exports / known node names).
## Gameplay readability: no title logo in the HUD (MEMORY/05 §2.1), the solid header band becomes a
## soft top fade, and dark corner scrims sit behind the top-left/top-right clusters so text reads on bright skies.
func _apply_readability_pass() -> void:
	if _root_ctrl.has_meta("hud_readability"):
		return
	_root_ctrl.set_meta("hud_readability", true)
	if _root_ctrl.get_node_or_null("FinisherPrompt") == null:
		_root_ctrl.add_child(FinisherPrompt.new())
	# Squad comms (roster, mic, chat bar, subtitles, command log) live in this same shared HUD.
	if _root_ctrl.get_node_or_null("SquadCommsHUD") == null:
		_root_ctrl.add_child(SquadCommsHUD.new())
	if _root_ctrl.get_node_or_null("ChainCounter") == null:
		_root_ctrl.add_child(ChainCounter.new())
	if _root_ctrl.get_node_or_null("ObjectiveTracker") == null:
		_root_ctrl.add_child(ObjectiveTracker.new())
	# In-world labels drawn as 2D text. Index 0 now; the corner scrims below are moved to 0..3 after it,
	# so the overlay ends up above the scrims and below every HUD panel.
	if _root_ctrl.get_node_or_null("WorldLabelOverlay") == null:
		var wlo := WorldLabelOverlay.new()
		_root_ctrl.add_child(wlo)
		_root_ctrl.move_child(wlo, 0)
	var brand: CanvasItem = get_node_or_null("RootControl/TopHeaderBand/HeaderMargin/HeaderHBox/BrandTitleLabel") as CanvasItem
	if brand != null:
		brand.visible = false
	var header_rule: CanvasItem = find_child("HeaderRule", true, false) as CanvasItem
	if header_rule != null:
		header_rule.visible = false
	var band: PanelContainer = get_node_or_null("RootControl/TopHeaderBand") as PanelContainer
	if band != null:
		var grad := Gradient.new()
		grad.set_color(0, Color(0.02, 0.02, 0.04, 0.55))
		grad.set_color(1, Color(0.02, 0.02, 0.04, 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.fill_from = Vector2(0.5, 0.0)
		gt.fill_to = Vector2(0.5, 1.0)
		gt.width = 4
		gt.height = 64
		var sbt := StyleBoxTexture.new()
		sbt.texture = gt
		band.add_theme_stylebox_override("panel", sbt)
		band.offset_bottom = 40.0
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var g := Gradient.new()
		var a0: float = 0.78 if corner.y == 0.0 else 0.6
		g.set_color(0, Color(0.0, 0.0, 0.02, a0))
		g.set_color(1, Color(0.0, 0.0, 0.02, 0.0))
		g.add_point(0.55, Color(0.0, 0.0, 0.02, a0 * 0.55))
		var rt := GradientTexture2D.new()
		rt.gradient = g
		rt.fill = GradientTexture2D.FILL_RADIAL
		rt.fill_from = corner
		# Radius = 1 texture unit, so the fade reaches zero exactly at the far edges (no hard rectangle).
		rt.fill_to = corner + Vector2(1.0 if corner.x == 0.0 else -1.0, 0.0)
		rt.width = 128
		rt.height = 128
		var scrim_rect := TextureRect.new()
		scrim_rect.name = "CornerScrim_%d%d" % [int(corner.x), int(corner.y)]
		scrim_rect.texture = rt
		scrim_rect.stretch_mode = TextureRect.STRETCH_SCALE
		scrim_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		scrim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scrim_rect.anchor_left = corner.x
		scrim_rect.anchor_right = corner.x
		scrim_rect.anchor_top = corner.y
		scrim_rect.anchor_bottom = corner.y
		var w: float = 620.0
		var h: float = 260.0 if corner.y == 0.0 else 230.0
		scrim_rect.offset_left = -w if corner.x == 1.0 else 0.0
		scrim_rect.offset_right = 0.0 if corner.x == 1.0 else w
		scrim_rect.offset_top = -h if corner.y == 1.0 else 0.0
		scrim_rect.offset_bottom = 0.0 if corner.y == 1.0 else h
		_root_ctrl.add_child(scrim_rect)
		_root_ctrl.move_child(scrim_rect, 0)
	# Larger, outlined vitals and score text.
	var hpb: Control = get_node_or_null(hp_bar_path) as Control if not hp_bar_path.is_empty() else null
	if hpb != null:
		hpb.custom_minimum_size = Vector2(340, 22)
	for p: NodePath in [score_label_path, combo_label_path, timer_label_path, hp_label_path]:
		var l: Label = get_node_or_null(p) as Label if not p.is_empty() else null
		if l != null:
			l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
			l.add_theme_constant_override("outline_size", 7)
	var wl: Label = get_node_or_null("RootControl/BottomLeftWeapon/SwordSlotLabel") as Label
	if wl != null:
		wl.add_theme_font_size_override("font_size", 17)
		wl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		wl.add_theme_constant_override("outline_size", 6)
	var qk: Label = get_node_or_null(shift_key_label_path) as Label if not shift_key_label_path.is_empty() else null
	if qk != null:
		qk.add_theme_stylebox_override("normal", _keycap_style())
		qk.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _wire_visuals() -> void:
	_root_ctrl = get_node_or_null("RootControl") as Control
	if _root_ctrl == null:
		return
	_apply_readability_pass()
	# --- Fonts ---
	_style_hud_label(get_node_or_null("RootControl/TopHeaderBand/HeaderMargin/HeaderHBox/BrandTitleLabel") as Label, true, 30)
	_style_hud_label(_section_title_label, true, 16)
	_style_hud_label(get_node_or_null(hp_label_path) as Label, false, 17)
	_style_hud_label(get_node_or_null(shift_key_label_path) as Label, false, 14)
	_style_hud_label(get_node_or_null(timer_label_path) as Label, false, 19)
	_style_hud_label(_reality_pill_label, false, 17)
	_style_hud_label(_mirror_pill_label, false, 17)
	_style_hud_label(get_node_or_null(interact_prompt_path) as Label, false, 18)
	_style_hud_label(get_node_or_null(boss_label_path) as Label, true, 20)
	var boss_lbl: Label = get_node_or_null(boss_label_path) as Label
	if boss_lbl != null:
		boss_lbl.add_theme_color_override("font_outline_color", Color(0.35, 0.04, 0.06, 0.9))
		boss_lbl.add_theme_constant_override("outline_size", 5)
	_score_lbl = get_node_or_null(score_label_path) as Label
	_combo_lbl = get_node_or_null(combo_label_path) as Label
	_style_hud_label(_score_lbl, false, 26)
	_style_hud_label(_combo_lbl, false, 20)

	# --- Health + boss bars (painted by _paint_bar) ---
	_hp_bar = get_node_or_null(hp_bar_path) as ProgressBar if not hp_bar_path.is_empty() else null
	_boss_bar = get_node_or_null(boss_bar_path) as ProgressBar if not boss_bar_path.is_empty() else null
	for entry: Array in [[_hp_bar, false], [_boss_bar, true]]:
		var pb: ProgressBar = entry[0] as ProgressBar
		if pb == null:
			continue
		pb.add_theme_stylebox_override("background", StyleBoxEmpty.new())
		pb.add_theme_stylebox_override("fill", StyleBoxEmpty.new())
		if not pb.has_meta("hud_painted"):
			pb.set_meta("hud_painted", true)
			var boss_flag: bool = bool(entry[1])
			pb.draw.connect(func() -> void: _paint_bar(pb, boss_flag))
	if _hp_bar != null:
		_hp_bar.custom_minimum_size = Vector2(340, 22)
	if _boss_bar != null:
		_boss_bar.custom_minimum_size = Vector2(560, 22)
	if _stamina_bar != null:
		var st_fill := StyleBoxFlat.new()
		st_fill.bg_color = Color(0.82, 0.76, 0.58, 0.95)
		_stamina_bar.add_theme_stylebox_override("fill", st_fill)

	# --- Realm chips (painted by _paint_chip) ---
	for entry2: Array in [[_reality_pill_panel, "reality"], [_mirror_pill_panel, "mirror"]]:
		var cp: PanelContainer = entry2[0] as PanelContainer
		if cp == null:
			continue
		cp.add_theme_stylebox_override("panel", _empty_box(40, 7))
		cp.custom_minimum_size = Vector2(166, 44)
		if not cp.has_meta("hud_painted"):
			cp.set_meta("hud_painted", true)
			var kind: String = String(entry2[1])
			cp.draw.connect(func() -> void: _paint_chip(cp, kind))
			cp.resized.connect(func() -> void: cp.pivot_offset = cp.size * 0.5)
	# "REALMS MERGED" split label under the chips.
	var key_row: Node = get_node_or_null("RootControl/TopCenterRealmCluster")
	if key_row != null and _merged_label == null:
		_merged_label = key_row.get_node_or_null("MergedLabel") as Label
		if _merged_label == null:
			_merged_label = Label.new()
			_merged_label.name = "MergedLabel"
			_merged_label.text = "◆ REALMS MERGED ◆"
			_merged_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_merged_label.visible = false
			_merged_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_merged_label.add_theme_color_override("font_color", Color(0.86, 0.72, 1.0))
			_merged_label.add_theme_color_override("font_outline_color", Color(0.25, 0.1, 0.4, 0.9))
			_merged_label.add_theme_constant_override("outline_size", 4)
			key_row.add_child(_merged_label)
		_style_hud_label(_merged_label, true, 14)

	# --- Combo timeout bar ---
	var top_right_panel: Node = get_node_or_null("RootControl/TopRightPanel")
	if top_right_panel != null and _combo_bar == null:
		_combo_bar = top_right_panel.get_node_or_null("ComboTimerBar") as ProgressBar
		if _combo_bar == null:
			_combo_bar = ProgressBar.new()
			_combo_bar.name = "ComboTimerBar"
			_combo_bar.custom_minimum_size = Vector2(150, 4)
			_combo_bar.size_flags_horizontal = Control.SIZE_SHRINK_END
			_combo_bar.show_percentage = false
			_combo_bar.value = 0.0
			_combo_bar.modulate.a = 0.0
			_combo_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var cbg := StyleBoxFlat.new()
			cbg.bg_color = Color(0, 0, 0, 0.45)
			_combo_bar.add_theme_stylebox_override("background", cbg)
			top_right_panel.add_child(_combo_bar)
			top_right_panel.move_child(_combo_bar, _combo_lbl.get_index() + 1 if _combo_lbl != null else top_right_panel.get_child_count() - 1)
		_style_combo()

	# --- Keycap look for action labels + bigger action icons (80 px diamonds, was 54) ---
	var br_cluster: Control = _root_ctrl.get_node_or_null("BottomRightActionsCluster") as Control
	if br_cluster != null:
		# 5 slots x 80 px + 4 gaps x 16 px = 464 px wide; extra height for the larger keycaps.
		br_cluster.offset_left = -640.0
		br_cluster.offset_top = -184.0
	for act: String in _action_slots.keys():
		var badge: Control = (_action_slots[act] as Dictionary).get("badge") as Control
		if badge != null:
			badge.custom_minimum_size = Vector2(96, 96)
		var klbl: Label = (_action_slots[act] as Dictionary).get("key") as Label
		if klbl != null:
			klbl.add_theme_stylebox_override("normal", _keycap_style())
			klbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			_style_hud_label(klbl, false, 18)
		var vlbl: Label = (_action_slots[act] as Dictionary).get("verb") as Label
		_style_hud_label(vlbl, false, 16)
		if vlbl != null:
			vlbl.add_theme_color_override("font_color", Color(0.93, 0.88, 0.76, 0.95))
			vlbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			vlbl.add_theme_constant_override("outline_size", 4)

	# --- Interact plate (chamfered, painted) ---
	if _interact_panel != null:
		_interact_panel.add_theme_stylebox_override("panel", _empty_box(22, 7))
		if not _interact_panel.has_meta("hud_painted"):
			_interact_panel.set_meta("hud_painted", true)
			_interact_panel.draw.connect(func() -> void: _paint_plate(_interact_panel))

	# --- Toast banner ---
	_toast_label = get_node_or_null(toast_label_path) as Label
	if _toast_label != null:
		_style_hud_label(_toast_label, true, 24)
		var tb := StyleBoxFlat.new()
		tb.bg_color = Color(0.03, 0.03, 0.05, 0.82)
		tb.border_color = GOLD
		tb.border_width_top = 2
		tb.border_width_bottom = 2
		tb.content_margin_top = 6
		tb.content_margin_bottom = 6
		_toast_label.add_theme_stylebox_override("normal", tb)
		_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_toast_label.visible = not active_toast_text.is_empty()


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

	_animate_visuals(delta)

	if is_instance_valid(_player_ref):
		if _player_ref.has_method("is_currently_airborne"):
			var now_airborne: bool = bool(_player_ref.call("is_currently_airborne"))
			if now_airborne != landing_prompt_bright:
				landing_prompt_bright = now_airborne
				_sync_ui_nodes()
		if _stamina_bar != null:
			var stamina: float = float(_player_ref.get("stamina")) if _player_ref.get("stamina") != null else 100.0
			var max_stamina: float = float(_player_ref.get("max_stamina")) if _player_ref.get("max_stamina") != null else 100.0
			_stamina_bar.value = (stamina / max_stamina) * 100.0


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

	shift_key_text = shift_lbl
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
	var prev_ratio: float = _hp_ratio
	displayed_hp = maxi(0, current_hp)
	displayed_max_hp = maxi(1, max_hp)
	hp_text = "%d / %d" % [displayed_hp, displayed_max_hp]
	_hp_ratio = clampf(float(displayed_hp) / float(displayed_max_hp), 0.0, 1.0)
	if _hp_ratio < prev_ratio - 0.001:
		_hp_flash = 0.28
		_hp_ghost = maxf(_hp_ghost, prev_ratio)
		_hp_ghost_delay = 0.45
	else:
		_hp_ghost = maxf(_hp_ghost if _hp_ratio < _hp_ghost else _hp_ratio, _hp_ratio)
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
	_start_chip_sweep()
	_sync_ui_nodes()


func _start_chip_sweep() -> void:
	var key: String = "mirror" if active_realm_chip == "MIRROR" else ("merged" if active_realm_chip == "REALMS MERGED" else "reality")
	if key == "merged":
		_chip_sweep["reality"] = 0.0
		_chip_sweep["mirror"] = 0.0
	else:
		_chip_sweep[key] = 0.0


func _on_shift_rejected(reason: String) -> void:
	last_shift_rejection_reason = reason
	shift_rejection_flash_timer = 0.35
	active_toast_text = "SHIFT LOCKED"
	toast_timer = 0.9
	if _reality_pill_panel != null and _mirror_pill_panel != null and is_inside_tree():
		for p: PanelContainer in [_reality_pill_panel, _mirror_pill_panel]:
			p.pivot_offset = p.size * 0.5
			UIFx.shake(p, 14.0, 0.3)
	_sync_ui_nodes()


func _on_realms_merged() -> void:
	active_realm_chip = "REALMS MERGED"
	active_toast_text = "REALMS MERGED"
	toast_timer = 2.5
	_trigger_realm_pulse(true)
	_start_chip_sweep()
	_sync_ui_nodes()


func _on_score_changed(new_score: int, _delta: int, _event_type: String) -> void:
	score_text = "SCORE %06d" % maxi(0, new_score)
	var gained: int = new_score - _last_score
	_last_score = new_score
	if gained > 0 and _score_lbl != null and is_inside_tree() and _delta != 0:
		_score_lbl.pivot_offset = Vector2(_score_lbl.size.x, _score_lbl.size.y * 0.5)
		UIFx.pop(_score_lbl, 1.18, 0.22)
		_spawn_score_popup(gained)
	_sync_ui_nodes()


func _spawn_score_popup(amount: int) -> void:
	if _root_ctrl == null or _score_lbl == null:
		return
	var pop := Label.new()
	pop.text = "+%d" % amount
	pop.add_theme_font_override("font", UITheme.body_font())
	pop.add_theme_font_size_override("font_size", 20)
	pop.add_theme_color_override("font_color", GOLD_HI)
	pop.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	pop.add_theme_constant_override("outline_size", 4)
	pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root_ctrl.add_child(pop)
	var origin: Vector2 = _score_lbl.global_position + Vector2(-78.0, 2.0)
	pop.global_position = origin
	pop.size = Vector2(70, 24)
	var tw: Tween = pop.create_tween().set_parallel(true)
	tw.tween_property(pop, "global_position:y", origin.y + 26.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(pop, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.chain().tween_callback(pop.queue_free)


func _on_combo_changed(multiplier: int, hits: int, time_remaining: float) -> void:
	var m: int = maxi(1, multiplier)
	combo_text = "COMBO x%d" % m
	if m > _combo_mult and _combo_lbl != null and is_inside_tree():
		_combo_lbl.pivot_offset = Vector2(_combo_lbl.size.x, _combo_lbl.size.y * 0.5)
		UIFx.pop(_combo_lbl, 1.3, 0.25)
	_combo_mult = m
	_combo_left = time_remaining if (hits > 0 and time_remaining > 0.0) else 0.0
	_style_combo()
	_sync_ui_nodes()


func _style_combo() -> void:
	if _combo_lbl == null:
		return
	var col: Color = Color(0.92, 0.70, 0.30)
	var glow: float = 0.0
	if _combo_mult >= 3:
		col = Color(1.0, 0.45, 0.25)
		glow = 0.85
	elif _combo_mult == 2:
		col = Color(1.0, 0.80, 0.34)
		glow = 0.5
	_combo_lbl.add_theme_color_override("font_color", col)
	_combo_lbl.add_theme_color_override("font_outline_color", Color(col.r, col.g, col.b, glow * 0.7))
	_combo_lbl.add_theme_constant_override("outline_size", int(glow * 7.0))
	if _combo_bar != null:
		var fill := StyleBoxFlat.new()
		fill.bg_color = col
		_combo_bar.add_theme_stylebox_override("fill", fill)


func _on_no_hit_awarded(_encounter_id: String, bonus_points: int) -> void:
	active_toast_text = "+%d NO-HIT ENCOUNTER" % bonus_points
	toast_timer = 2.5
	_sync_ui_nodes()


func _on_run_timer_updated(elapsed_sec: float) -> void:
	var total_sec: int = maxi(0, int(elapsed_sec))
	timer_text = "%02d:%02d" % [int(total_sec / 60.0), total_sec % 60]
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
	var prev_pct: float = boss_hp_percent
	boss_hp_percent = clampf((float(current_hp) / float(m_hp)) * 100.0, 0.0, 100.0)
	if boss_hp_percent < prev_pct - 0.01:
		_boss_ghost = maxf(_boss_ghost, prev_pct / 100.0)
		_boss_ghost_delay = 0.5
	else:
		_boss_ghost = boss_hp_percent / 100.0
	# Health updates never reveal the bar on their own: it appears only once the run is in the Execution Arena
	# (bind_boss() at level load sends the starting HP and used to show the bar from the first second).
	boss_bar_visible = current_hp > 0 and _boss_in_play()
	_sync_ui_nodes()


func _boss_in_play() -> bool:
	var director: EncounterDirector = EncounterDirector.instance as EncounterDirector
	return director != null and director.current_section == EncounterDirector.Section.EXECUTION_ARENA


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
	_sync_toast_banner()

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

	# Chips are painted by _paint_chip() via the panel's draw signal; just request a redraw.
	if _reality_pill_panel != null:
		_reality_pill_panel.queue_redraw()
	if _mirror_pill_panel != null:
		_mirror_pill_panel.queue_redraw()
	if _merged_label != null:
		_merged_label.visible = is_merged
	if _crest_badge != null:
		_crest_badge.highlighted = false

	if _reality_pill_label != null:
		_reality_pill_label.modulate = Color(1.0, 0.96, 0.86, 1.0) if (not is_mirror or is_merged) else Color(0.68, 0.66, 0.62, 0.78)
	if _mirror_pill_label != null:
		_mirror_pill_label.modulate = Color(0.88, 0.97, 1.0, 1.0) if (is_mirror or is_merged) else Color(0.68, 0.70, 0.76, 0.78)

	var accent: Color = Color(0.32, 0.84, 1.0, 0.95) if is_mirror else Color(0.80, 0.66, 0.42, 0.94)
	if is_merged:
		accent = Color(MERGED_COL.r, MERGED_COL.g, MERGED_COL.b, 0.95)
	if _crest_badge != null:
		_crest_badge.border_color = accent
	if _swap_badge != null:
		_swap_badge.border_color = accent
	if _weapon_badge != null:
		_weapon_badge.border_color = accent


func _sync_toast_banner() -> void:
	if _toast_label == null:
		return
	var has_text: bool = not active_toast_text.is_empty()
	_toast_label.visible = has_text
	if has_text and active_toast_text != _last_toast_text and _toast_label.is_inside_tree():
		_toast_label.modulate.a = 0.0
		_toast_label.offset_left = -380.0
		_toast_label.offset_right = 140.0
		var tw: Tween = _toast_label.create_tween().set_parallel(true)
		tw.tween_property(_toast_label, "offset_left", -260.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_toast_label, "offset_right", 260.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_toast_label, "modulate:a", 1.0, 0.2)
	_last_toast_text = active_toast_text


func _animate_visuals(delta: float) -> void:
	var dirty_hp: bool = false
	if _hp_flash > 0.0:
		_hp_flash = maxf(0.0, _hp_flash - delta)
		dirty_hp = true
	if _hp_ghost_delay > 0.0:
		_hp_ghost_delay = maxf(0.0, _hp_ghost_delay - delta)
	elif _hp_ghost > _hp_ratio:
		_hp_ghost = maxf(_hp_ratio, _hp_ghost - delta * 0.55)
		dirty_hp = true
	if _hp_ratio > 0.0 and _hp_ratio < 0.25:
		dirty_hp = true
	if dirty_hp and _hp_bar != null:
		_hp_bar.queue_redraw()
		if _crest_badge != null:
			_crest_badge.highlighted = _hp_ratio > 0.0 and _hp_ratio < 0.25 and fmod(Time.get_ticks_msec() / 1000.0, 0.8) < 0.4

	if _boss_ghost_delay > 0.0:
		_boss_ghost_delay = maxf(0.0, _boss_ghost_delay - delta)
	elif _boss_ghost > boss_hp_percent / 100.0:
		_boss_ghost = maxf(boss_hp_percent / 100.0, _boss_ghost - delta * 0.35)
		if _boss_bar != null:
			_boss_bar.queue_redraw()

	for key: String in ["reality", "mirror"]:
		var v: float = float(_chip_sweep[key])
		if v < 1.0:
			_chip_sweep[key] = minf(1.0, v + delta / 0.55)
			var panel: PanelContainer = _reality_pill_panel if key == "reality" else _mirror_pill_panel
			if panel != null:
				panel.queue_redraw()
	if shift_rejection_flash_timer > 0.0:
		if _reality_pill_panel != null:
			_reality_pill_panel.queue_redraw()
		if _mirror_pill_panel != null:
			_mirror_pill_panel.queue_redraw()

	if _combo_bar != null:
		if _combo_left > 0.0:
			_combo_left = maxf(0.0, _combo_left - delta)
		_combo_bar.value = clampf(_combo_left / COMBO_WINDOW_SEC, 0.0, 1.0) * 100.0
		_combo_bar.modulate.a = 1.0 if _combo_left > 0.0 else 0.0


## Parallelogram polygon: top edge [l+c, r], bottom edge [l, r-c], filled to fraction f (0..1).
func _para(r: Rect2, c: float, f: float) -> PackedVector2Array:
	var l: float = r.position.x
	var t: float = r.position.y
	var rr: float = r.end.x
	var b: float = r.end.y
	var xt: float = (l + c) + f * (rr - l - c)
	var xb: float = l + f * (rr - c - l)
	return PackedVector2Array([Vector2(l + c, t), Vector2(xt, t), Vector2(xb, b), Vector2(l, b)])


func _paint_bar(bar: ProgressBar, is_boss: bool) -> void:
	var s: Vector2 = bar.size
	if s.x < 12.0 or s.y < 4.0:
		return
	var c: float = minf(s.y * 0.9, 12.0)
	var frame := Rect2(Vector2(1, 1), s - Vector2(2, 2))
	var inner := frame.grow(-2.5)
	var ratio: float
	var ghost: float
	if is_boss:
		ratio = clampf(boss_hp_percent / 100.0, 0.0, 1.0)
		ghost = _boss_ghost
	else:
		ratio = _hp_ratio
		ghost = _hp_ghost
	bar.draw_colored_polygon(_para(frame, c, 1.0), Color(0.045, 0.030, 0.040, 0.92))
	# Ghost (recent damage) bar.
	if ghost > ratio + 0.002:
		bar.draw_colored_polygon(_para(inner, c, clampf(ghost, 0.0, 1.0)), Color(0.96, 0.92, 0.88, 0.85))
	# Main fill: darker lower half, brighter top half.
	if ratio > 0.002:
		var top_col: Color = Color(0.96, 0.24, 0.22) if not is_boss else Color(0.92, 0.18, 0.24)
		var bot_col: Color = Color(0.60, 0.08, 0.11)
		var low_pulse: float = 0.0
		if not is_boss and ratio < 0.25:
			low_pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 8.0)
			top_col = top_col.lerp(Color(1.0, 0.55, 0.45), low_pulse * 0.6)
		bar.draw_colored_polygon(_para(inner, c, ratio), bot_col)
		var half := Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.5))
		bar.draw_colored_polygon(_para(half, c * 0.5, ratio), top_col)
	# Segment ticks every 25% (boss: phase pip at 50%).
	var ticks: PackedFloat32Array = PackedFloat32Array([0.5]) if is_boss else PackedFloat32Array([0.25, 0.5, 0.75])
	for tk: float in ticks:
		var xt: float = (inner.position.x + c) + tk * (inner.end.x - inner.position.x - c)
		var xb: float = inner.position.x + tk * (inner.end.x - c - inner.position.x)
		bar.draw_line(Vector2(xt, inner.position.y), Vector2(xb, inner.end.y), Color(0, 0, 0, 0.55), 1.5)
	# Damage flash.
	if not is_boss and _hp_flash > 0.0:
		bar.draw_colored_polygon(_para(frame, c, 1.0), Color(1, 1, 1, _hp_flash / 0.28 * 0.55))
	# Gold frame.
	var outline: PackedVector2Array = _para(frame, c, 1.0)
	outline.append(outline[0])
	var frame_col: Color = GOLD
	if not is_boss and ratio > 0.0 and ratio < 0.25:
		frame_col = GOLD.lerp(Color(1.0, 0.3, 0.25), 0.6)
	bar.draw_polyline(outline, frame_col, 2.0, true)
	if is_boss:
		# Ornate end caps: gems at both ends of the frame.
		for gp: Vector2 in [Vector2(frame.position.x + 2.0, s.y * 0.5), Vector2(frame.end.x - 2.0, s.y * 0.5)]:
			bar.draw_colored_polygon(PackedVector2Array([gp + Vector2(0, -7), gp + Vector2(7, 0), gp + Vector2(0, 7), gp + Vector2(-7, 0)]), GOLD_HI)


func _paint_chip(panel: PanelContainer, kind: String) -> void:
	var s: Vector2 = panel.size
	if s.x < 20.0:
		return
	var is_mirror: bool = (active_realm_chip == "MIRROR")
	var is_merged: bool = (active_realm_chip == "REALMS MERGED")
	var active: bool = is_merged or (is_mirror if kind == "mirror" else not is_mirror)
	var accent: Color = MIRROR_COL if kind == "mirror" else REALITY_COL
	var c: float = 9.0
	var r := Rect2(Vector2(1, 1), s - Vector2(2, 2))
	var poly := PackedVector2Array([
		Vector2(r.position.x + c, r.position.y), Vector2(r.end.x - c, r.position.y), Vector2(r.end.x, r.position.y + c),
		Vector2(r.end.x, r.end.y - c), Vector2(r.end.x - c, r.end.y), Vector2(r.position.x + c, r.end.y),
		Vector2(r.position.x, r.end.y - c), Vector2(r.position.x, r.position.y + c),
	])
	var rejected: bool = shift_rejection_flash_timer > 0.0
	var fill: Color = Color(0.05, 0.055, 0.085, 0.80)
	var border: Color = Color(0.40, 0.38, 0.34, 0.55)
	if rejected:
		fill = Color(0.42, 0.08, 0.08, 0.90)
		border = Color(1.0, 0.32, 0.28)
	elif active:
		fill = Color(accent.r * 0.34, accent.g * 0.34, accent.b * 0.34, 0.92)
		border = accent.lerp(GOLD_HI, 0.25)
	panel.draw_colored_polygon(poly, fill)
	if active and not rejected:
		# Soft inner glow along the bottom.
		panel.draw_colored_polygon(PackedVector2Array([
			Vector2(r.position.x + 2, r.end.y - 9), Vector2(r.end.x - 2, r.end.y - 9),
			Vector2(r.end.x - c, r.end.y - 1), Vector2(r.position.x + c, r.end.y - 1)]), Color(accent.r, accent.g, accent.b, 0.22))
	# Light sweep on switch.
	var sw: float = float(_chip_sweep[kind])
	if sw < 1.0 and active:
		var cx: float = lerpf(-20.0, s.x + 20.0, sw)
		var band := PackedVector2Array([
			Vector2(clampf(cx - 8, r.position.x, r.end.x), r.position.y + 1), Vector2(clampf(cx + 14, r.position.x, r.end.x), r.position.y + 1),
			Vector2(clampf(cx + 4, r.position.x, r.end.x), r.end.y - 1), Vector2(clampf(cx - 18, r.position.x, r.end.x), r.end.y - 1)])
		if absf(band[0].x - band[1].x) > 0.5 or absf(band[2].x - band[3].x) > 0.5:
			panel.draw_colored_polygon(band, Color(1, 1, 1, 0.45 * (1.0 - sw)))
	var pl: PackedVector2Array = poly.duplicate()
	pl.append(poly[0])
	panel.draw_polyline(pl, border, 2.0 if active else 1.0, true)
	# Sun / moon glyph on the left.
	var gc := Vector2(20.0, s.y * 0.5)
	var gcol: Color = (GOLD_HI if active else Color(0.55, 0.54, 0.52, 0.8))
	if kind == "reality":
		panel.draw_circle(gc, 4.2, gcol)
		for i in 8:
			var a: float = TAU * float(i) / 8.0
			panel.draw_line(gc + Vector2(cos(a), sin(a)) * 6.5, gc + Vector2(cos(a), sin(a)) * 9.0, gcol, 1.6, true)
	else:
		panel.draw_circle(gc, 7.0, gcol)
		panel.draw_circle(gc + Vector2(3.4, -2.2), 6.2, fill if active else Color(0.05, 0.055, 0.085, 0.95))


func _paint_plate(panel: PanelContainer) -> void:
	var s: Vector2 = panel.size
	if s.x < 20.0:
		return
	var c: float = 9.0
	var r := Rect2(Vector2(1, 1), s - Vector2(2, 2))
	var poly := PackedVector2Array([
		Vector2(r.position.x + c, r.position.y), Vector2(r.end.x - c, r.position.y), Vector2(r.end.x, r.position.y + c),
		Vector2(r.end.x, r.end.y - c), Vector2(r.end.x - c, r.end.y), Vector2(r.position.x + c, r.end.y),
		Vector2(r.position.x, r.end.y - c), Vector2(r.position.x, r.position.y + c),
	])
	panel.draw_colored_polygon(poly, Color(0.045, 0.05, 0.075, 0.92))
	var pl: PackedVector2Array = poly.duplicate()
	pl.append(poly[0])
	panel.draw_polyline(pl, GOLD, 2.0, true)
	panel.draw_polyline(_inset_outline(r.grow(-5.0), c - 4.0), Color(GOLD.r, GOLD.g, GOLD.b, 0.3), 1.0, true)


func _inset_outline(r: Rect2, c: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(r.position.x + c, r.position.y), Vector2(r.end.x - c, r.position.y), Vector2(r.end.x, r.position.y + c),
		Vector2(r.end.x, r.end.y - c), Vector2(r.end.x - c, r.end.y), Vector2(r.position.x + c, r.end.y),
		Vector2(r.position.x, r.end.y - c), Vector2(r.position.x, r.position.y + c), Vector2(r.position.x + c, r.position.y),
	])


func _keycap_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.11, 0.15, 0.95)
	sb.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.85)
	sb.set_border_width_all(1)
	sb.border_width_bottom = 3
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	return sb


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
	header_bg.bg_color = Color(0.03, 0.03, 0.05, 0.62)
	header_bg.border_width_bottom = 2
	header_bg.border_color = Color(0.784, 0.659, 0.376, 0.55)
	header_bg.shadow_color = Color(0, 0, 0, 0.45)
	header_bg.shadow_size = 8
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

	var rule_line := UIDivider.new()
	rule_line.name = "HeaderRule"
	rule_line.custom_minimum_size = Vector2(340, 14)
	rule_line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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
	shift_key_lbl.text = "Q"
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
