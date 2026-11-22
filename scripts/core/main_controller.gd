class_name MainController
extends Node
## Root scene orchestrator for `scenes/main/main.tscn`:
## Wires `PlayerController`, `ColosseumGreyboxBuilder` (`TheWarden`), `HUDController`,
## `AudioManager`, `RealmEnvironmentController`, and the 6 UI menu/overlay screens.

@export var level_root_path: NodePath = NodePath("LevelRoot")
@export var player_path: NodePath = NodePath("Player")
@export var hud_path: NodePath = NodePath("HUD")
@export var audio_manager_path: NodePath = NodePath("AudioManager")
@export var title_screen_path: NodePath = NodePath("MenusLayer/TitleScreen")
@export var pause_menu_path: NodePath = NodePath("MenusLayer/PauseMenu")
@export var results_screen_path: NodePath = NodePath("MenusLayer/ResultsScreen")
@export var leaderboard_screen_path: NodePath = NodePath("MenusLayer/LeaderboardScreen")
@export var options_screen_path: NodePath = NodePath("MenusLayer/OptionsScreen")
@export var death_overlay_path: NodePath = NodePath("MenusLayer/DeathOverlay")
## Launch flow: the title (main menu) comes first; "Start" / "Continue" then show the loading screen while the
## level is generated step by step, and the run begins when it is ready.
@export var start_on_title_screen: bool = true

## Set right before a scene reload so the rebooted scene skips the title and starts a fresh run at once.
static var pending_auto_start: bool = false
static var pending_continue: bool = false

signal level_ready_changed(ready: bool)
var level_ready: bool = false
var _run_started_once: bool = false
var _building: bool = false
var _pending_continue: bool = false
var _loading: LoadingScreen = null

## QA-D01: OS cursor is captured during active gameplay and released whenever a menu is up.
@export var manage_mouse_capture: bool = true

const MENU_GROUPS: Array[String] = ["title_screen", "pause_menu", "options_screen", "leaderboard_screen", "results_screen"]

var _previous_menu: Control = null


func _enter_tree() -> void:
	add_to_group("main_controller")


func _ready() -> void:
	add_to_group("main_controller")
	# NOTE: Main is the scene root, so we must NOT set PROCESS_MODE_ALWAYS here (every child would ignore pause).
	# SceneTree.process_frame keeps firing while paused, which is exactly what cursor management needs.
	if get_tree() != null and not get_tree().process_frame.is_connected(_on_tree_process_frame):
		get_tree().process_frame.connect(_on_tree_process_frame)
	call_deferred("_wire_all_subsystems")
	if get_node_or_null("PerformanceGovernor") == null:
		var gov: Node = (load("res://scripts/core/performance_governor.gd") as GDScript).new()
		gov.name = "PerformanceGovernor"
		add_child(gov)


func _exit_tree() -> void:
	if get_tree() != null:
		if get_tree().root != null:
			get_tree().root.disable_3d = false
		if get_tree().process_frame.is_connected(_on_tree_process_frame):
			get_tree().process_frame.disconnect(_on_tree_process_frame)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_tree_process_frame() -> void:
	if manage_mouse_capture:
		_update_mouse_mode()


func is_gameplay_active() -> bool:
	if not is_inside_tree() or get_tree() == null:
		return false
	if get_tree().paused or not level_ready or _building or _loading != null:
		return false
	for grp in MENU_GROUPS:
		for n in get_tree().get_nodes_in_group(grp):
			if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
				return false
	var player: PlayerController = get_node_or_null(player_path) as PlayerController
	if player != null and (player.current_state == PlayerController.State.DEAD or player.process_mode == Node.PROCESS_MODE_DISABLED):
		return false
	return true


func _get_audio_manager() -> AudioManager:
	var audio_mgr: AudioManager = get_node_or_null(audio_manager_path) as AudioManager
	if audio_mgr == null and is_inside_tree() and get_tree() != null and get_tree().root != null:
		audio_mgr = get_tree().root.get_node_or_null("GameAudio") as AudioManager
	if audio_mgr == null:
		audio_mgr = AudioManager.instance as AudioManager
	return audio_mgr


func get_desired_mouse_mode() -> Input.MouseMode:
	# The squad chat bar needs a visible cursor (send / push-to-talk buttons) while it is open.
	if PlayerController.ui_input_locked:
		return Input.MOUSE_MODE_VISIBLE
	return Input.MOUSE_MODE_CAPTURED if is_gameplay_active() else Input.MOUSE_MODE_VISIBLE


func _update_mouse_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var desired: Input.MouseMode = get_desired_mouse_mode()
	# Only grab the cursor while our window has focus, so alt-tabbing never fights the OS.
	if desired == Input.MOUSE_MODE_CAPTURED and not DisplayServer.window_is_focused():
		return
	if Input.mouse_mode != desired:
		Input.mouse_mode = desired


func _wire_all_subsystems() -> void:
	PlayerController.ui_input_locked = false
	var player: Node = get_node_or_null(player_path)
	var level_root: Node = get_node_or_null(level_root_path)
	var hud: HUDController = get_node_or_null(hud_path) as HUDController
	var audio_mgr: AudioManager = _get_audio_manager()
	var death_ui: DeathOverlayController = get_node_or_null(death_overlay_path) as DeathOverlayController
	var title_ui: TitleScreenController = get_node_or_null(title_screen_path) as TitleScreenController
	var pause_ui: PauseMenuController = get_node_or_null(pause_menu_path) as PauseMenuController
	var results_ui: ResultsScreenController = get_node_or_null(results_screen_path) as ResultsScreenController
	var lb_ui: LeaderboardScreenController = get_node_or_null(leaderboard_screen_path) as LeaderboardScreenController
	var opts_ui: OptionsScreenController = get_node_or_null(options_screen_path) as OptionsScreenController

	if hud != null:
		hud.bind_singletons()
		if player != null:
			hud.bind_player(player)

	if get_tree() != null and get_tree().root != null:
		var store: Node = get_tree().root.get_node_or_null("LeaderboardStore")
		if store != null and store.has_method("apply_settings"):
			store.call("apply_settings")

	if death_ui != null and player != null:
		death_ui.bind_player(player)

	# The player stays inactive (no falling into a void that isn't built yet) until the run begins, and the
	# in-game HUD stays hidden so the title / loading screens are clean.
	_set_player_active(false)
	if hud != null:
		hud.visible = false

	if title_ui != null:
		title_ui.visible = start_on_title_screen
		if not title_ui.start_run_requested.is_connected(_on_start_run_requested):
			title_ui.start_run_requested.connect(_on_start_run_requested)
		if not title_ui.continue_run_requested.is_connected(_on_continue_requested):
			title_ui.continue_run_requested.connect(_on_continue_requested)
		if not title_ui.leaderboard_requested.is_connected(_on_open_leaderboard.bind(title_ui)):
			title_ui.leaderboard_requested.connect(_on_open_leaderboard.bind(title_ui))
		if not title_ui.options_requested.is_connected(_on_open_options.bind(title_ui)):
			title_ui.options_requested.connect(_on_open_options.bind(title_ui))
		if not title_ui.quit_requested.is_connected(_on_quit_requested):
			title_ui.quit_requested.connect(_on_quit_requested)

	if pause_ui != null:
		if not pause_ui.options_requested.is_connected(_on_open_options.bind(pause_ui)):
			pause_ui.options_requested.connect(_on_open_options.bind(pause_ui))
		if not pause_ui.main_menu_requested.is_connected(_on_return_to_title):
			pause_ui.main_menu_requested.connect(_on_return_to_title)

	if pause_ui != null and not pause_ui.full_run_restarted.is_connected(_on_start_run_requested):
		pause_ui.full_run_restarted.connect(_on_start_run_requested)

	if results_ui != null:
		if not results_ui.results_presented.is_connected(_on_results_presented):
			results_ui.results_presented.connect(_on_results_presented)
		if not results_ui.leaderboard_requested.is_connected(_on_open_leaderboard.bind(results_ui)):
			results_ui.leaderboard_requested.connect(_on_open_leaderboard.bind(results_ui))
		if not results_ui.main_menu_requested.is_connected(_on_return_to_title):
			results_ui.main_menu_requested.connect(_on_return_to_title)
		if not results_ui.replay_requested.is_connected(_on_start_run_requested):
			results_ui.replay_requested.connect(_on_start_run_requested)

	if lb_ui != null:
		lb_ui.visible = false
		if not lb_ui.back_requested.is_connected(_on_close_subscreen.bind(lb_ui)):
			lb_ui.back_requested.connect(_on_close_subscreen.bind(lb_ui))

	if opts_ui != null:
		opts_ui.visible = false
		if not opts_ui.back_requested.is_connected(_on_close_subscreen.bind(opts_ui)):
			opts_ui.back_requested.connect(_on_close_subscreen.bind(opts_ui))

	# Coming back from a reload (Replay / Restart Run / Continue): skip the title and start right away.
	if pending_auto_start:
		pending_auto_start = false
		_pending_continue = pending_continue
		pending_continue = false
		if title_ui != null:
			title_ui.visible = false
		call_deferred("_begin_run_loading")
	elif not start_on_title_screen:
		call_deferred("_begin_run_loading")


## Level-dependent wiring: the boss bar and interact prompts exist only once the level is built.
func _wire_level_dependent() -> void:
	var hud: HUDController = get_node_or_null(hud_path) as HUDController
	var level_root: Node = get_node_or_null(level_root_path)
	var warden: Node = level_root.get_node_or_null("Stage05_ExecutionArena/Enemies/TheWarden") if level_root != null else null
	if hud != null:
		if warden != null:
			hud.bind_boss(warden)
		if get_tree() != null:
			for sw in get_tree().get_nodes_in_group("interactable_switch"):
				if sw != null and sw.has_signal("prompt_changed") and not sw.is_connected("prompt_changed", hud.set_interact_prompt):
					sw.connect("prompt_changed", hud.set_interact_prompt)
	var audio_mgr: AudioManager = _get_audio_manager()
	if audio_mgr != null:
		audio_mgr.bind_to_world(self)
	var wd: Node = get_node_or_null("WeatherDirector")
	if wd == null and get_tree() != null:
		wd = get_tree().get_first_node_in_group("weather_director")
	if wd != null and wd.has_method("bind_warden"):
		wd.call("bind_warden", warden)


func _set_player_active(active: bool) -> void:
	var p: Node = get_node_or_null(player_path)
	if p != null:
		p.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


## Title "Start", a pause-menu restart, or the results screen's Replay.
func _on_start_run_requested() -> void:
	if _building:
		return
	if _run_started_once:
		# A run already exists in this scene: reload it so the world (enemies, gates, breakables, checkpoints)
		# is rebuilt from scratch instead of carrying over the finished level.
		_reload_for_new_run(false)
		return
	_begin_run_loading()


func _on_continue_requested() -> void:
	if _building:
		return
	if _run_started_once:
		_reload_for_new_run(true)
		return
	_pending_continue = true
	_begin_run_loading()


func _reload_for_new_run(continue_saved: bool) -> void:
	pending_auto_start = true
	pending_continue = continue_saved
	if get_tree() != null:
		get_tree().paused = false
		# Clean up root-level lazy singletons & static FX caches before tearing down the scene so no
		# freed object pointers or stale GPU resources survive into reload_current_scene().
		if get_tree().root != null:
			var sq: Node = get_tree().root.get_node_or_null("SquadCoordinator")
			if sq != null and sq.has_method("clear_for_scene_reload"):
				sq.call("clear_for_scene_reload")
			var fd: Node = get_tree().root.get_node_or_null("FaunaDirector")
			if fd != null and fd.has_method("reset_for_scene_reload"):
				fd.call("reset_for_scene_reload")
		var gore_script: GDScript = load("res://scripts/core/gore_fx.gd") as GDScript
		if gore_script != null and gore_script.has_method("cleanup_all_fx"):
			gore_script.call("cleanup_all_fx")
		var game_feel: GDScript = load("res://scripts/core/game_feel.gd") as GDScript
		if game_feel != null and game_feel.has_method("reset_time_scale"):
			game_feel.call("reset_time_scale")
		# Deferred: the old scene is still mid-call here, so the swap happens at the end of the frame.
		get_tree().call_deferred("reload_current_scene")


## Public entry for tests and tools: starts the run without going through the title screen.
func start_run_now() -> void:
	_on_start_run_requested()


func _begin_run_loading() -> void:
	if _building or level_ready:
		return
	_building = true
	_run_started_once = true
	PlayerController.ui_input_locked = false
	if is_inside_tree() and get_tree() != null:
		get_tree().paused = false
	_set_player_active(false)

	var ed_early: Node = get_tree().get_first_node_in_group("encounter_director") if get_tree() != null else null
	var prev_auto_save: bool = bool(ed_early.get("auto_save_on_checkpoint")) if ed_early != null else true
	if ed_early != null:
		ed_early.set("auto_save_on_checkpoint", false)

	_loading = LoadingScreen.new()
	add_child(_loading)
	_loading.set_progress(0.0, "Preparing the arena")
	# Suspend live 3D rendering while the opaque 2D loading screen builds the world so ULTRA
	# (MSAA_4X + 4-split shadows + SSAO) doesn't trigger cold-cache Vulkan TDR crashes mid-load.
	if get_tree() != null and get_tree().root != null:
		get_tree().root.disable_3d = true
	await get_tree().process_frame
	await get_tree().process_frame

	var level: Node = get_node_or_null(level_root_path)
	if level != null and level.has_method("build_greybox_progressive"):
		var on_level := func(frac: float, text: String) -> void:
			if is_instance_valid(_loading):
				_loading.set_progress(frac * 0.85, text)
		level.connect("build_progress", on_level)
		await level.call("build_greybox_progressive")
		level.disconnect("build_progress", on_level)

	var amb: Node = get_node_or_null("AmbientLife")
	if amb != null and amb.has_method("build_progressive"):
		var on_amb := func(frac: float, text: String) -> void:
			if is_instance_valid(_loading):
				_loading.set_progress(0.85 + frac * 0.12, text)
		amb.connect("build_progress", on_amb)
		await amb.call("build_progressive")
		amb.disconnect("build_progress", on_amb)

	_wire_level_dependent()
	if is_instance_valid(_loading):
		_loading.set_progress(0.97, "Gathering your squad")
	await get_tree().process_frame

	var ed: Node = get_tree().get_first_node_in_group("encounter_director") if get_tree() != null else null
	if _pending_continue:
		_pending_continue = false
		var store: Node = get_tree().root.get_node_or_null("LeaderboardStore")
		if store != null and store.has_method("apply_saved_world_state"):
			store.call("apply_saved_world_state")
	elif ed != null and ed.has_method("restart_full_run"):
		# Now that the enemies exist, set their section activation and the run state.
		ed.call("restart_full_run")

	await get_tree().process_frame
	var squad: Node = get_tree().get_first_node_in_group("squad_manager") if get_tree() != null else null
	if squad != null and squad.has_method("spawn_squad"):
		squad.call("spawn_squad")

	# Re-enable 3D rendering and let 2 frames settle behind the loading screen before fading it out.
	if get_tree() != null and get_tree().root != null:
		get_tree().root.disable_3d = false
	await get_tree().process_frame
	await get_tree().process_frame

	_set_player_active(true)
	var hud_node: HUDController = get_node_or_null(hud_path) as HUDController
	if hud_node != null:
		hud_node.visible = true
	if ed != null:
		ed.set("auto_save_on_checkpoint", prev_auto_save)
	level_ready = true
	_building = false
	level_ready_changed.emit(true)
	if is_instance_valid(_loading):
		await _loading.finish()
	_loading = null


func _on_open_leaderboard(from_menu: Control) -> void:
	_previous_menu = from_menu
	if from_menu != null:
		if from_menu is TitleScreenController and from_menu.has_method("set_menu_content_visible"):
			from_menu.call("set_menu_content_visible", false)
		else:
			from_menu.visible = false
	var lb_ui: LeaderboardScreenController = get_node_or_null(leaderboard_screen_path) as LeaderboardScreenController
	if lb_ui != null:
		lb_ui.refresh_entries()
		lb_ui.visible = true


func _on_open_options(from_menu: Control) -> void:
	_previous_menu = from_menu
	if from_menu != null:
		if from_menu is TitleScreenController and from_menu.has_method("set_menu_content_visible"):
			from_menu.call("set_menu_content_visible", false)
		else:
			from_menu.visible = false
	var opts_ui: OptionsScreenController = get_node_or_null(options_screen_path) as OptionsScreenController
	if opts_ui != null:
		opts_ui.reload_from_store()
		opts_ui.visible = true


func _on_close_subscreen(subscreen: Control) -> void:
	if subscreen != null:
		subscreen.visible = false
	if _previous_menu != null:
		if _previous_menu is TitleScreenController and _previous_menu.has_method("set_menu_content_visible"):
			_previous_menu.visible = true
			_previous_menu.call("set_menu_content_visible", true)
		else:
			_previous_menu.visible = true
		_previous_menu = null


func _on_results_presented(_summary: Dictionary) -> void:
	if is_inside_tree() and get_tree() != null:
		get_tree().paused = true
	_set_player_active(false)
	var hud_node: HUDController = get_node_or_null(hud_path) as HUDController
	if hud_node != null:
		hud_node.visible = false


func _on_return_to_title() -> void:
	PlayerController.ui_input_locked = false
	if is_inside_tree() and get_tree() != null:
		for sc in get_tree().get_nodes_in_group("squad_comms_hud"):
			if sc != null and sc.has_method("close_chat"):
				sc.call("close_chat")
		var hud_c: Node = get_node_or_null(hud_path)
		if hud_c != null:
			var sc2: Node = hud_c.find_child("SquadCommsHUD", true, false)
			if sc2 != null and sc2.has_method("close_chat"):
				sc2.call("close_chat")
		if get_viewport() != null:
			get_viewport().gui_release_focus()
		get_tree().paused = true
		if get_tree().root != null:
			var run_state: Node = get_tree().root.get_node_or_null("RunState")
			if run_state != null and run_state.has_method("pause_timer"):
				run_state.call("pause_timer")
	_set_player_active(false)
	var hud_node: HUDController = get_node_or_null(hud_path) as HUDController
	if hud_node != null:
		hud_node.visible = false
	var title_ui: TitleScreenController = get_node_or_null(title_screen_path) as TitleScreenController
	if title_ui != null:
		title_ui._sync_ui_nodes()
		title_ui.visible = true


func _on_quit_requested() -> void:
	if get_tree() != null:
		get_tree().quit()
