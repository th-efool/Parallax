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
@export var start_on_title_screen: bool = false

## QA-D01: OS cursor is captured during active gameplay and released whenever a menu is up.
@export var manage_mouse_capture: bool = true

const MENU_GROUPS: Array[String] = ["title_screen", "pause_menu", "options_screen", "leaderboard_screen", "results_screen"]

var _previous_menu: Control = null


func _ready() -> void:
	add_to_group("main_controller")
	# NOTE: Main is the scene root, so we must NOT set PROCESS_MODE_ALWAYS here (every child would ignore pause).
	# SceneTree.process_frame keeps firing while paused, which is exactly what cursor management needs.
	if get_tree() != null and not get_tree().process_frame.is_connected(_on_tree_process_frame):
		get_tree().process_frame.connect(_on_tree_process_frame)
	call_deferred("_wire_all_subsystems")


func _exit_tree() -> void:
	if get_tree() != null and get_tree().process_frame.is_connected(_on_tree_process_frame):
		get_tree().process_frame.disconnect(_on_tree_process_frame)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_tree_process_frame() -> void:
	if manage_mouse_capture:
		_update_mouse_mode()


func is_gameplay_active() -> bool:
	if not is_inside_tree() or get_tree() == null:
		return false
	if get_tree().paused:
		return false
	for grp in MENU_GROUPS:
		for n in get_tree().get_nodes_in_group(grp):
			if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
				return false
	var player: PlayerController = get_node_or_null(player_path) as PlayerController
	if player != null and player.current_state == PlayerController.State.DEAD:
		return false
	return true


func get_desired_mouse_mode() -> Input.MouseMode:
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
	var player: Node = get_node_or_null(player_path)
	var level_root: Node = get_node_or_null(level_root_path)
	var hud: HUDController = get_node_or_null(hud_path) as HUDController
	var audio_mgr: AudioManager = get_node_or_null(audio_manager_path) as AudioManager
	var death_ui: DeathOverlayController = get_node_or_null(death_overlay_path) as DeathOverlayController
	var title_ui: TitleScreenController = get_node_or_null(title_screen_path) as TitleScreenController
	var pause_ui: PauseMenuController = get_node_or_null(pause_menu_path) as PauseMenuController
	var results_ui: ResultsScreenController = get_node_or_null(results_screen_path) as ResultsScreenController
	var lb_ui: LeaderboardScreenController = get_node_or_null(leaderboard_screen_path) as LeaderboardScreenController
	var opts_ui: OptionsScreenController = get_node_or_null(options_screen_path) as OptionsScreenController

	var warden: Node = null
	if level_root != null:
		warden = level_root.get_node_or_null("Stage05_ExecutionArena/Enemies/TheWarden")

	if hud != null:
		hud.bind_singletons()
		if player != null:
			hud.bind_player(player)
		if warden != null:
			hud.bind_boss(warden)
		if get_tree() != null:
			for sw in get_tree().get_nodes_in_group("interactable_switch"):
				if sw != null and sw.has_signal("prompt_changed") and not sw.is_connected("prompt_changed", hud.set_interact_prompt):
					sw.connect("prompt_changed", hud.set_interact_prompt)

	if get_tree() != null and get_tree().root != null:
		var store: Node = get_tree().root.get_node_or_null("LeaderboardStore")
		if store != null and store.has_method("apply_settings"):
			store.call("apply_settings")

	if death_ui != null and player != null:
		death_ui.bind_player(player)

	if audio_mgr != null:
		audio_mgr.bind_to_world(self)

	if title_ui != null:
		title_ui.visible = start_on_title_screen
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

	if results_ui != null:
		if not results_ui.leaderboard_requested.is_connected(_on_open_leaderboard.bind(results_ui)):
			results_ui.leaderboard_requested.connect(_on_open_leaderboard.bind(results_ui))
		if not results_ui.main_menu_requested.is_connected(_on_return_to_title):
			results_ui.main_menu_requested.connect(_on_return_to_title)

	if lb_ui != null:
		lb_ui.visible = false
		if not lb_ui.back_requested.is_connected(_on_close_subscreen.bind(lb_ui)):
			lb_ui.back_requested.connect(_on_close_subscreen.bind(lb_ui))

	if opts_ui != null:
		opts_ui.visible = false
		if not opts_ui.back_requested.is_connected(_on_close_subscreen.bind(opts_ui)):
			opts_ui.back_requested.connect(_on_close_subscreen.bind(opts_ui))

	if not start_on_title_screen:
		var run_state: Node = get_tree().root.get_node_or_null("RunState") if get_tree() != null else null
		if run_state != null and run_state.has_method("start_new_run"):
			run_state.call("start_new_run")


func _on_open_leaderboard(from_menu: Control) -> void:
	_previous_menu = from_menu
	if from_menu != null:
		from_menu.visible = false
	var lb_ui: LeaderboardScreenController = get_node_or_null(leaderboard_screen_path) as LeaderboardScreenController
	if lb_ui != null:
		lb_ui.refresh_entries()
		lb_ui.visible = true


func _on_open_options(from_menu: Control) -> void:
	_previous_menu = from_menu
	if from_menu != null:
		from_menu.visible = false
	var opts_ui: OptionsScreenController = get_node_or_null(options_screen_path) as OptionsScreenController
	if opts_ui != null:
		opts_ui.reload_from_store()
		opts_ui.visible = true


func _on_close_subscreen(subscreen: Control) -> void:
	if subscreen != null:
		subscreen.visible = false
	if _previous_menu != null:
		_previous_menu.visible = true
		_previous_menu = null


func _on_return_to_title() -> void:
	var title_ui: TitleScreenController = get_node_or_null(title_screen_path) as TitleScreenController
	if title_ui != null:
		title_ui._sync_ui_nodes()
		title_ui.visible = true


func _on_quit_requested() -> void:
	if get_tree() != null:
		get_tree().quit()
