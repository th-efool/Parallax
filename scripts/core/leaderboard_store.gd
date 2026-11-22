class_name LeaderboardManager
extends Node
## Autoloaded as `LeaderboardStore`.
## Central persistence & configuration authority for PARALLAX:
## 1. Top-5 Local Leaderboard (`user://leaderboard.cfg`)
## 2. Comprehensive Settings & Live Control Rebinding (`user://settings.cfg`)
## 3. Run Checkpoint, World State & Extensible Profile Save System (`user://savegame.cfg`)

signal leaderboard_updated(entries: Array[Dictionary])
signal settings_changed(settings: Dictionary)
signal controls_rebound(action_name: String, display_label: String, all_bindings: Dictionary)
signal rebind_rejected(action_name: String, attempted_code: String, conflict_action: String, reason: String)
signal game_saved(save_data: Dictionary)
signal game_loaded(save_data: Dictionary)
signal save_cleared()

const LEADERBOARD_PATH: String = "user://leaderboard.cfg"
const SETTINGS_PATH: String = "user://settings.cfg"
const SAVEGAME_PATH: String = "user://savegame.cfg"
const MAX_ENTRIES: int = 5

const REBINDABLE_ACTIONS: Array[String] = [
	"move_forward",
	"move_back",
	"move_left",
	"move_right",
	"jump",
	"dodge",
	"light_attack",
	"heavy_attack",
	"dimension_shift",
	"landing_attack",
	"interact",
]

const ACTION_DISPLAY_NAMES: Dictionary = {
	"move_forward": "Move Forward",
	"move_back": "Move Back",
	"move_left": "Move Left",
	"move_right": "Move Right",
	"jump": "Jump",
	"dodge": "Dodge",
	"light_attack": "Light Attack",
	"heavy_attack": "Heavy Attack",
	"dimension_shift": "Dimension Shift",
	"landing_attack": "Landing Attack",
	"interact": "Interact",
}

## Contextual shared action pairs (empty now that Jump [SPACE] and Dodge [SHIFT] are separate).
const ALLOWED_SHARED_ACTION_PAIRS: Array[Array] = []

## System keys that cannot be bound to gameplay actions.
const RESERVED_KEYCODES: Array[int] = [
	KEY_ESCAPE,
]

const SUPPORTED_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

var leaderboard_path: String = LEADERBOARD_PATH
var settings_path: String = SETTINGS_PATH
var savegame_path: String = SAVEGAME_PATH

var _entries: Array[Dictionary] = []
var _settings: Dictionary = {}
var _save_data: Dictionary = {}
var _muted_by_focus: bool = false
var last_save_error: Error = OK


func _ready() -> void:
	_ensure_audio_buses()
	_load_leaderboard_from_disk()
	_load_settings_from_disk()
	_load_savegame_from_disk()
	apply_settings()


func _notification(what: int) -> void:
	## QA-A01: honour `mute_when_unfocused` on OS window focus changes.
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			if bool(_settings.get("mute_when_unfocused", false)):
				_muted_by_focus = true
				_set_master_mute(true)
		NOTIFICATION_APPLICATION_FOCUS_IN:
			if _muted_by_focus:
				_muted_by_focus = false
				# Restore the user's Master level (re-mutes only if their volume is ~0).
				_apply_bus_volume("Master", float(_settings.get("master_volume", 1.0)))


func is_muted_by_focus() -> bool:
	return _muted_by_focus


func _set_master_mute(muted: bool) -> void:
	var idx: int = AudioServer.get_bus_index("Master")
	if idx >= 0:
		AudioServer.set_bus_mute(idx, muted)


# ============================================================================
# 1. TOP-5 LEADERBOARD PERSISTENCE (`user://leaderboard.cfg`)
# ============================================================================

func sanitize_initials(raw: String) -> String:
	var cleaned: String = ""
	var upper: String = raw.strip_edges().to_upper()
	for i in range(upper.length()):
		var ch: String = upper.substr(i, 1)
		var code: int = ch.unicode_at(0)
		var is_alpha: bool = (code >= 65 and code <= 90)
		var is_digit: bool = (code >= 48 and code <= 57)
		if is_alpha or is_digit:
			cleaned += ch
			if cleaned.length() == 3:
				break
	if cleaned.is_empty():
		return "WAR"
	return cleaned


func qualifies_for_top_five(score: int, time_sec: float) -> bool:
	if _entries.size() < MAX_ENTRIES:
		return true
	var fifth: Dictionary = _entries[MAX_ENTRIES - 1]
	var fifth_score: int = int(fifth.get("score", 0))
	var fifth_time: float = float(fifth.get("time_sec", 999999.0))
	if score > fifth_score:
		return true
	if score == fifth_score and time_sec < fifth_time:
		return true
	return false


func save_run(initials: String, score: int, time_sec: float, rank: String) -> int:
	var entry: Dictionary = {
		"initials": sanitize_initials(initials),
		"score": maxi(0, score),
		"time_sec": maxf(0.0, time_sec),
		"rank": rank if not rank.is_empty() else "C",
		"timestamp": Time.get_datetime_string_from_system(false, true),
		"_order": _entries.size(),
	}
	_entries.append(entry)
	_sort_entries()
	if _entries.size() > MAX_ENTRIES:
		_entries.resize(MAX_ENTRIES)

	var placed_index: int = -1
	for i in range(_entries.size()):
		if _entries[i] == entry:
			placed_index = i + 1
		_entries[i]["_order"] = i

	_save_leaderboard_to_disk()
	leaderboard_updated.emit(get_top_five())
	return placed_index


func get_top_five() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for e in _entries:
		result.append({
			"initials": String(e.get("initials", "WAR")),
			"score": int(e.get("score", 0)),
			"time_sec": float(e.get("time_sec", 0.0)),
			"rank": String(e.get("rank", "C")),
			"timestamp": String(e.get("timestamp", "")),
		})
	return result


func reset_leaderboard() -> void:
	_entries.clear()
	_save_leaderboard_to_disk()
	leaderboard_updated.emit(get_top_five())


static func format_time(time_sec: float) -> String:
	var total_sec: int = maxi(0, int(floor(time_sec)))
	var mins: int = int(total_sec / 60.0)
	var secs: int = total_sec % 60
	return "%02d:%02d" % [mins, secs]


# ============================================================================
# 2. COMPREHENSIVE SETTINGS & LIVE APPLICATION (`user://settings.cfg`)
# ============================================================================

func get_default_keybindings() -> Dictionary:
	return {
		"move_forward": "KEY:%d" % KEY_W,
		"move_back": "KEY:%d" % KEY_S,
		"move_left": "KEY:%d" % KEY_A,
		"move_right": "KEY:%d" % KEY_D,
		"jump": "KEY:%d" % KEY_SPACE,
		"dodge": "KEY:%d" % KEY_SHIFT,
		"light_attack": "MOUSE:%d" % MOUSE_BUTTON_LEFT,
		"heavy_attack": "MOUSE:%d" % MOUSE_BUTTON_RIGHT,
		"dimension_shift": "KEY:%d" % KEY_Q,
		"landing_attack": "KEY:%d" % KEY_F,
		"interact": "KEY:%d" % KEY_E,
	}


func get_default_settings() -> Dictionary:
	return {
		# Audio
		"master_volume": 1.0,
		"music_volume": 0.85,
		"sfx_volume": 0.90,
		"mute_when_unfocused": false,
		# Display / Screen Type
		"screen_mode": "windowed", # "windowed", "borderless", "fullscreen"
		"fullscreen": false,
		"resolution": Vector2i(1280, 720),
		"vsync_mode": DisplayServer.VSYNC_ENABLED,
		"max_fps": 0, # 0 = unlimited
		# Graphics Quality
		"graphics_preset": "high", # "low", "medium", "high", "ultra", "custom"
		"msaa_3d": Viewport.MSAA_2X,
		"screen_space_aa": Viewport.SCREEN_SPACE_AA_FXAA,
		"shadow_quality": 2, # 0=Off, 1=Low, 2=Medium, 3=High
		"glow_enabled": true,
		"fog_enabled": true,
		"brightness": 1.0, # 0.5 .. 1.5 tonemap_exposure
		"render_scale": 1.0, # 0.5 .. 1.0 3D resolution (FSR 1 upscale below 1.0)
		"adaptive_resolution": true, # PerformanceGovernor lowers the 3D scale when FPS drops
		"hw_autodetected": false, # first launch on integrated / software GPUs picks the Low preset
		"finisher_window_enabled": true, # critical-hit slow-mo finisher window
		# Gameplay & Camera
		"mouse_sensitivity": 0.0025,
		"invert_y": false,
		"camera_fov": 65.0,
		"camera_shake_intensity": 1.0,
		"hit_stop_enabled": true,
		# Controls
		"keybindings": get_default_keybindings(),
	}


func get_settings() -> Dictionary:
	var copy: Dictionary = _settings.duplicate(true)
	if not copy.has("keybindings") or not (copy["keybindings"] is Dictionary):
		copy["keybindings"] = get_default_keybindings()
	return copy


func save_settings(new_settings: Dictionary) -> void:
	var defaults: Dictionary = get_default_settings()
	for k in defaults.keys():
		if k == "keybindings":
			var default_binds: Dictionary = get_default_keybindings()
			var current_binds: Dictionary = (_settings.get("keybindings", default_binds) as Dictionary).duplicate()
			if new_settings.has("keybindings") and new_settings["keybindings"] is Dictionary:
				var incoming_binds: Dictionary = new_settings["keybindings"]
				for act in default_binds.keys():
					if incoming_binds.has(act):
						current_binds[act] = String(incoming_binds[act])
			for act in default_binds.keys():
				if not current_binds.has(act):
					current_binds[act] = default_binds[act]
			_settings["keybindings"] = current_binds
		elif new_settings.has(k):
			_settings[k] = new_settings[k]
		elif not _settings.has(k):
			_settings[k] = defaults[k]

	# Synchronize `fullscreen` bool and `screen_mode` string if only one was modified
	if new_settings.has("screen_mode") and not new_settings.has("fullscreen"):
		_settings["fullscreen"] = (String(_settings["screen_mode"]) in ["fullscreen", "borderless"])
	elif new_settings.has("fullscreen") and not new_settings.has("screen_mode"):
		_settings["screen_mode"] = "fullscreen" if bool(_settings["fullscreen"]) else "windowed"

	_save_settings_to_disk()
	apply_settings()
	settings_changed.emit(get_settings())
	controls_rebound.emit("", "", get_all_action_display_labels())


func apply_graphics_preset(preset_name: String) -> Dictionary:
	var p: String = preset_name.to_lower()
	_settings["graphics_preset"] = p
	match p:
		"low":
			_settings["msaa_3d"] = Viewport.MSAA_DISABLED
			_settings["screen_space_aa"] = Viewport.SCREEN_SPACE_AA_DISABLED
			_settings["shadow_quality"] = 0
			_settings["glow_enabled"] = false
			_settings["fog_enabled"] = false
			_settings["render_scale"] = 0.7
		"medium":
			_settings["msaa_3d"] = Viewport.MSAA_2X
			_settings["screen_space_aa"] = Viewport.SCREEN_SPACE_AA_DISABLED
			_settings["shadow_quality"] = 1
			_settings["glow_enabled"] = true
			_settings["fog_enabled"] = true
			_settings["render_scale"] = 0.85
		"high":
			_settings["msaa_3d"] = Viewport.MSAA_2X
			_settings["screen_space_aa"] = Viewport.SCREEN_SPACE_AA_FXAA
			_settings["shadow_quality"] = 2
			_settings["glow_enabled"] = true
			_settings["fog_enabled"] = true
			_settings["render_scale"] = 1.0
		"ultra":
			_settings["msaa_3d"] = Viewport.MSAA_4X
			_settings["screen_space_aa"] = Viewport.SCREEN_SPACE_AA_FXAA
			_settings["shadow_quality"] = 3
			_settings["glow_enabled"] = true
			_settings["fog_enabled"] = true
			_settings["render_scale"] = 1.0
	return get_settings()


func restore_default_settings() -> Dictionary:
	_settings = get_default_settings()
	_save_settings_to_disk()
	apply_settings()
	settings_changed.emit(get_settings())
	controls_rebound.emit("all", "", get_all_action_display_labels())
	return get_settings()


## True on integrated / virtual / software GPUs (laptops and PCs without a graphics card).
static func is_low_end_gpu() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var t: int = int(RenderingServer.get_video_adapter_type())
	if t == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU or t == RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU or t == RenderingDevice.DEVICE_TYPE_CPU:
		return true
	var nm: String = RenderingServer.get_video_adapter_name().to_lower()
	for k in ["intel", "uhd", "iris", "basic render", "llvmpipe", "swiftshader", "radeon(tm) graphics", "radeon graphics", "vega 8", "vega 6"]:
		if nm.contains(k):
			return true
	return false


func apply_settings() -> void:
	# First launch on a weak GPU: pick the Low preset (70% 3D scale) before anything renders heavily.
	if not bool(_settings.get("hw_autodetected", false)) and DisplayServer.get_name() != "headless":
		_settings["hw_autodetected"] = true
		if is_low_end_gpu():
			apply_graphics_preset("low")
			print("[Parallax] Integrated/low-end GPU detected (%s): Low preset applied." % RenderingServer.get_video_adapter_name())
		_save_settings_to_disk()
	_ensure_audio_buses()
	_apply_bus_volume("Master", float(_settings.get("master_volume", 1.0)))
	_apply_bus_volume("Music", float(_settings.get("music_volume", 0.85)))
	_apply_bus_volume("SFX", float(_settings.get("sfx_volume", 0.90)))
	if _muted_by_focus:
		if bool(_settings.get("mute_when_unfocused", false)):
			_set_master_mute(true)
		else:
			_muted_by_focus = false

	# Apply input bindings to InputMap
	_apply_keybindings_to_input_map()

	# Apply FPS cap
	var fps_cap: int = maxi(0, int(_settings.get("max_fps", 0)))
	Engine.max_fps = fps_cap

	# Apply Viewport / WorldEnvironment / DirectionalLight3D / Camera3D settings
	_apply_scene_graphics_and_camera()

	if DisplayServer.get_name() != "headless":
		var mode_str: String = String(_settings.get("screen_mode", "windowed")).to_lower()
		if bool(_settings.get("fullscreen", false)) and mode_str == "windowed":
			mode_str = "fullscreen"

		if mode_str == "fullscreen":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif mode_str == "borderless":
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		else:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			var res_val: Variant = _settings.get("resolution", Vector2i(1280, 720))
			if res_val is Vector2i:
				var res: Vector2i = res_val as Vector2i
				var usable: Vector2i = DisplayServer.screen_get_usable_rect().size
				if usable.x >= 640 and usable.y >= 360:
					res.x = mini(res.x, usable.x - 16)
					res.y = mini(res.y, usable.y - 40)
				if res.x >= 640 and res.y >= 360:
					DisplayServer.window_set_size(res)

		var vsync: int = clampi(int(_settings.get("vsync_mode", DisplayServer.VSYNC_ENABLED)), 0, 3)
		DisplayServer.window_set_vsync_mode(vsync as DisplayServer.VSyncMode)


func _apply_scene_graphics_and_camera() -> void:
	if get_tree() == null or get_tree().root == null:
		return

	var root_vp: Viewport = get_tree().root
	root_vp.msaa_3d = clampi(int(_settings.get("msaa_3d", Viewport.MSAA_2X)), 0, 3) as Viewport.MSAA
	root_vp.screen_space_aa = clampi(int(_settings.get("screen_space_aa", Viewport.SCREEN_SPACE_AA_FXAA)), 0, 1) as Viewport.ScreenSpaceAA
	# 3D render scale (FSR 1 upscaling below 100%); the PerformanceGovernor may lower it further at runtime.
	var rscale: float = clampf(float(_settings.get("render_scale", 1.0)), 0.5, 1.0)
	root_vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if rscale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	root_vp.scaling_3d_scale = rscale
	# Low preset: more aggressive mesh LOD and shorter ambient-creature simulation range.
	var low: bool = String(_settings.get("graphics_preset", "high")) == "low"
	root_vp.mesh_lod_threshold = 4.0 if low else 1.0
	if low:
		for c in get_tree().get_nodes_in_group("ambient_creature"):
			var ld: Variant = c.get("lod_distance")
			if ld != null:
				c.set("lod_distance", minf(float(ld), 22.0))

	var shadow_q: int = clampi(int(_settings.get("shadow_quality", 2)), 0, 3)
	if DisplayServer.get_name() != "headless":
		var rs_quality: RenderingServer.ShadowQuality = RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
		match shadow_q:
			0, 1:
				rs_quality = RenderingServer.SHADOW_QUALITY_SOFT_LOW
			2:
				rs_quality = RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
			3:
				rs_quality = RenderingServer.SHADOW_QUALITY_SOFT_HIGH
		RenderingServer.directional_soft_shadow_filter_set_quality(rs_quality)

	# Update DirectionalLight3D shadows & WorldEnvironment glow/fog/exposure if loaded
	var main_node: Node = get_tree().get_first_node_in_group("main_controller")
	if main_node != null:
		var sun: DirectionalLight3D = main_node.get_node_or_null("SunLight") as DirectionalLight3D
		if sun != null:
			sun.shadow_enabled = (shadow_q > 0)
			if ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality") <= 0:
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
				sun.directional_shadow_split_1 = 0.1
				sun.directional_shadow_split_2 = 0.3
				sun.directional_shadow_max_distance = 65.0
			else:
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if shadow_q <= 1 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
				sun.directional_shadow_max_distance = 65.0 if shadow_q <= 1 else 120.0
		var we: WorldEnvironment = main_node.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if we != null and we.environment != null:
			we.environment.glow_enabled = bool(_settings.get("glow_enabled", true))
			we.environment.fog_enabled = bool(_settings.get("fog_enabled", true))
			we.environment.tonemap_exposure = clampf(float(_settings.get("brightness", 1.0)), 0.5, 1.5)
			# Scale the expensive passes with the preset: volumetric light shafts only on High/Ultra, SSAO from Low up.
			we.environment.volumetric_fog_enabled = false   # stylized look: never re-enabled by the preset
			we.environment.ssao_enabled = shadow_q >= 1

	# Update Player Camera3D FOV & sensitivity
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p):
			if p.has_method("_load_mouse_settings_from_store"):
				p.call("_load_mouse_settings_from_store")
			var cam: Camera3D = p.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
			if cam != null:
				cam.fov = clampf(float(_settings.get("camera_fov", 65.0)), 55.0, 95.0)


# ============================================================================
# 3. DYNAMIC CONTROL REBINDING & CONFLICT VALIDATION
# ============================================================================

static func event_to_binding_code(event: InputEvent) -> String:
	if event is InputEventKey:
		var kev: InputEventKey = event as InputEventKey
		var code: int = int(kev.physical_keycode) if int(kev.physical_keycode) != 0 else int(kev.keycode)
		if code != 0:
			return "KEY:%d" % code
	elif event is InputEventMouseButton:
		var mev: InputEventMouseButton = event as InputEventMouseButton
		var bidx: int = int(mev.button_index)
		if bidx > 0:
			return "MOUSE:%d" % bidx
	return ""


static func binding_code_to_event(binding_code: String) -> InputEvent:
	if binding_code.begins_with("KEY:"):
		var code: int = int(binding_code.trim_prefix("KEY:"))
		if code > 0:
			var ev := InputEventKey.new()
			ev.physical_keycode = code as Key
			ev.keycode = code as Key
			return ev
	elif binding_code.begins_with("MOUSE:"):
		var bidx: int = int(binding_code.trim_prefix("MOUSE:"))
		if bidx > 0:
			var mev := InputEventMouseButton.new()
			mev.button_index = bidx as MouseButton
			return mev
	return null


static func format_binding_code(binding_code: String) -> String:
	if binding_code.begins_with("MOUSE:"):
		var bidx: int = int(binding_code.trim_prefix("MOUSE:"))
		match bidx:
			MOUSE_BUTTON_LEFT:
				return "LMB"
			MOUSE_BUTTON_RIGHT:
				return "RMB"
			MOUSE_BUTTON_MIDDLE:
				return "MMB"
			MOUSE_BUTTON_WHEEL_UP:
				return "MWU"
			MOUSE_BUTTON_WHEEL_DOWN:
				return "MWD"
			MOUSE_BUTTON_XBUTTON1:
				return "MB4"
			MOUSE_BUTTON_XBUTTON2:
				return "MB5"
			_:
				return "MOUSE %d" % bidx
	elif binding_code.begins_with("KEY:"):
		var code: int = int(binding_code.trim_prefix("KEY:"))
		match code:
			KEY_SPACE:
				return "SPACE"
			KEY_SHIFT:
				return "SHIFT"
			KEY_CTRL:
				return "CTRL"
			KEY_ALT:
				return "ALT"
			KEY_TAB:
				return "TAB"
			KEY_ENTER, KEY_KP_ENTER:
				return "ENTER"
			KEY_BACKSPACE:
				return "BACKSPACE"
			KEY_ESCAPE:
				return "ESC"
			KEY_UP:
				return "UP"
			KEY_DOWN:
				return "DOWN"
			KEY_LEFT:
				return "LEFT"
			KEY_RIGHT:
				return "RIGHT"
			_:
				var s: String = OS.get_keycode_string(code as Key).to_upper()
				return s if not s.is_empty() else ("KEY %d" % code)
	return binding_code


func get_action_binding_code(action_name: String) -> String:
	var binds: Dictionary = _settings.get("keybindings", {}) as Dictionary
	if binds.has(action_name):
		return String(binds[action_name])
	var defaults: Dictionary = get_default_keybindings()
	return String(defaults.get(action_name, ""))


func get_action_display_label(action_name: String) -> String:
	return format_binding_code(get_action_binding_code(action_name))


func get_all_action_display_labels() -> Dictionary:
	var result: Dictionary = {}
	for act in REBINDABLE_ACTIONS:
		result[act] = get_action_display_label(act)
	return result


func is_shared_pair_allowed(action_a: String, action_b: String) -> bool:
	if action_a == action_b:
		return true
	for pair in ALLOWED_SHARED_ACTION_PAIRS:
		if pair.has(action_a) and pair.has(action_b):
			return true
	return false


func validate_binding(action_name: String, binding_code: String) -> Dictionary:
	if not REBINDABLE_ACTIONS.has(action_name):
		return {
			"valid": false,
			"conflict_action": "",
			"reason": "UNKNOWN ACTION: %s" % action_name,
		}
	if binding_code.is_empty() or (not binding_code.begins_with("KEY:") and not binding_code.begins_with("MOUSE:")):
		return {
			"valid": false,
			"conflict_action": "",
			"reason": "INVALID INPUT BINDING",
		}
	if binding_code.begins_with("KEY:"):
		var kcode: int = int(binding_code.trim_prefix("KEY:"))
		if RESERVED_KEYCODES.has(kcode):
			return {
				"valid": false,
				"conflict_action": "pause",
				"reason": "RESERVED KEY: %s CANNOT BE REBOUND" % format_binding_code(binding_code),
			}
	elif binding_code.begins_with("MOUSE:"):
		var bidx: int = int(binding_code.trim_prefix("MOUSE:"))
		if bidx == MOUSE_BUTTON_WHEEL_UP or bidx == MOUSE_BUTTON_WHEEL_DOWN:
			return {
				"valid": false,
				"conflict_action": "",
				"reason": "MOUSE WHEEL CANNOT BE BOUND TO CONTINUOUS ACTIONS",
			}

	var binds: Dictionary = _settings.get("keybindings", get_default_keybindings()) as Dictionary
	for other_action in REBINDABLE_ACTIONS:
		if other_action == action_name:
			continue
		if is_shared_pair_allowed(action_name, other_action):
			continue
		var other_code: String = String(binds.get(other_action, ""))
		if other_code == binding_code:
			var other_title: String = String(ACTION_DISPLAY_NAMES.get(other_action, other_action)).to_upper()
			var key_label: String = format_binding_code(binding_code)
			return {
				"valid": false,
				"conflict_action": other_action,
				"reason": "CONFLICT: %s IS ALREADY BOUND TO %s" % [key_label, other_title],
			}

	return {
		"valid": true,
		"conflict_action": "",
		"reason": "",
	}


func rebind_action(action_name: String, binding_code: String, swap_on_conflict: bool = false) -> Dictionary:
	var check: Dictionary = validate_binding(action_name, binding_code)
	var binds: Dictionary = (_settings.get("keybindings", get_default_keybindings()) as Dictionary).duplicate()

	if not bool(check.get("valid", false)):
		var conflict_act: String = String(check.get("conflict_action", ""))
		if swap_on_conflict and not conflict_act.is_empty() and REBINDABLE_ACTIONS.has(conflict_act):
			var prev_code: String = String(binds.get(action_name, ""))
			binds[conflict_act] = prev_code
			binds[action_name] = binding_code
			_settings["keybindings"] = binds
			_save_settings_to_disk()
			_apply_keybindings_to_input_map()
			var lbl_swapped: String = get_action_display_label(action_name)
			settings_changed.emit(get_settings())
			controls_rebound.emit(action_name, lbl_swapped, get_all_action_display_labels())
			return {
				"valid": true,
				"swapped_with": conflict_act,
				"reason": "",
			}
		rebind_rejected.emit(action_name, binding_code, conflict_act, String(check.get("reason", "")))
		return check

	binds[action_name] = binding_code
	_settings["keybindings"] = binds
	_save_settings_to_disk()
	_apply_keybindings_to_input_map()
	var new_label: String = get_action_display_label(action_name)
	settings_changed.emit(get_settings())
	controls_rebound.emit(action_name, new_label, get_all_action_display_labels())
	return check


func rebind_action_from_event(action_name: String, event: InputEvent, swap_on_conflict: bool = false) -> Dictionary:
	var code: String = event_to_binding_code(event)
	return rebind_action(action_name, code, swap_on_conflict)


func reset_keybindings_to_default() -> Dictionary:
	_settings["keybindings"] = get_default_keybindings()
	_save_settings_to_disk()
	_apply_keybindings_to_input_map()
	var labels: Dictionary = get_all_action_display_labels()
	settings_changed.emit(get_settings())
	controls_rebound.emit("all", "", labels)
	return labels


func _apply_keybindings_to_input_map() -> void:
	var binds: Dictionary = _settings.get("keybindings", get_default_keybindings()) as Dictionary
	for act in REBINDABLE_ACTIONS:
		if not InputMap.has_action(act):
			InputMap.add_action(act)
		InputMap.action_erase_events(act)
		var code: String = String(binds.get(act, get_default_keybindings().get(act, "")))
		var ev: InputEvent = binding_code_to_event(code)
		if ev != null:
			InputMap.action_add_event(act, ev)


# ============================================================================
# 4. CHECKPOINT, WORLD STATE & PROFILE SAVE SYSTEM (`user://savegame.cfg`)
# ============================================================================

func get_default_save_data() -> Dictionary:
	return {
		"has_active_run": false,
		"timestamp": "",
		"current_section": 0,
		"checkpoint_section": 0,
		"checkpoint_position": Vector3(0.0, 0.0, -3.0),
		"checkpoint_rotation_y": PI,
		"checkpoint_realm": 0,
		"completed_sections": {},
		"completed_encounters": {},
		"score": 0,
		"banked_score": 0,
		"elapsed_seconds": 0.0,
		"encounter_no_hit_awarded": {},
		"awarded_event_ids": {},
		"banked_event_ids": {},
		"checkpoint_history": [],
		"player_health": 100,
		"layout_version": 1,   # JourneyLayout.VERSION of the save; files without the key are the old layout
		"world_flags": {
			"entry_switch_activated": false,
			"hall_pillar_broken": false,
			"gallery_support_broken": false,
			"gallery_bridge_repaired": false,
			"mechanism_puzzle_solved": false,
		},
		"dismissed_tutorials": {},
		"profile_stats": {
			"total_runs_started": 0,
			"total_runs_completed": 0,
			"total_deaths": 0,
			"total_kills": 0,
			"best_score": 0,
			"fastest_time_sec": 0.0,
		},
		"custom_claude_data": {},
	}


func has_saved_run() -> bool:
	return bool(_save_data.get("has_active_run", false))


func get_saved_run_data() -> Dictionary:
	return _save_data.duplicate(true)


func save_run_checkpoint(checkpoint_dict: Dictionary) -> Dictionary:
	if _save_data.is_empty():
		_save_data = get_default_save_data()

	for k in checkpoint_dict.keys():
		if k in ["world_flags", "profile_stats", "custom_claude_data"] and _save_data.get(k) is Dictionary and checkpoint_dict[k] is Dictionary:
			var merged: Dictionary = (_save_data[k] as Dictionary).duplicate(true)
			var incoming: Dictionary = checkpoint_dict[k]
			for sub_k in incoming.keys():
				merged[sub_k] = incoming[sub_k]
			_save_data[k] = merged
		else:
			_save_data[k] = checkpoint_dict[k]

	_save_data["timestamp"] = Time.get_datetime_string_from_system(false, true)
	var err: Error = _save_savegame_to_disk()
	var saved_copy: Dictionary = get_saved_run_data()
	saved_copy["_save_ok"] = (err == OK)
	if err == OK:
		game_saved.emit(saved_copy)
	return saved_copy


func capture_and_save_world_state(root_node: Node = null) -> Dictionary:
	var tree_root: Node = root_node
	if tree_root == null and get_tree() != null:
		tree_root = get_tree().get_first_node_in_group("main_controller")
		if tree_root == null:
			tree_root = get_tree().root

	var ed: Node = get_tree().get_first_node_in_group("encounter_director") if get_tree() != null else null
	var rm: Node = get_tree().get_first_node_in_group("realm_manager") if get_tree() != null else null
	var run_state: Node = get_tree().root.get_node_or_null("RunState") if (get_tree() != null and get_tree().root != null) else null
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D if get_tree() != null else null
	var hud: Node = get_tree().get_first_node_in_group("hud") if get_tree() != null else null

	var snapshot: Dictionary = {
		"has_active_run": true,
		"layout_version": JourneyLayout.VERSION,
	}

	if ed != null:
		var cur_sec: int = int(ed.get("current_section"))
		var chk_sec: int = int(ed.get("checkpoint_section"))
		var chk_xform: Transform3D = ed.get("checkpoint_transform") as Transform3D
		snapshot["current_section"] = cur_sec
		snapshot["checkpoint_section"] = chk_sec
		snapshot["checkpoint_position"] = chk_xform.origin
		snapshot["checkpoint_rotation_y"] = chk_xform.basis.get_euler().y
		snapshot["checkpoint_realm"] = int(ed.get("checkpoint_realm"))
		snapshot["completed_sections"] = (ed.get("completed_sections") as Dictionary).duplicate()
		snapshot["completed_encounters"] = (ed.get("completed_encounters") as Dictionary).duplicate()
		var raw_hist: Variant = ed.get("_checkpoint_history")
		var serialized_hist: Array = []
		if raw_hist is Array:
			for item in (raw_hist as Array):
				if item is Dictionary:
					var hd: Dictionary = item as Dictionary
					var hx: Transform3D = hd.get("transform", Transform3D.IDENTITY) as Transform3D
					serialized_hist.append({
						"section": int(hd.get("section", 0)),
						"position": hx.origin,
						"rotation_y": hx.basis.get_euler().y,
						"realm": int(hd.get("realm", 0)),
						"manual": bool(hd.get("manual", false)),
					})
		snapshot["checkpoint_history"] = serialized_hist
		if cur_sec == 5: # COMPLETE
			snapshot["has_active_run"] = false

	if rm != null and ed == null:
		snapshot["checkpoint_realm"] = int(rm.get("current_realm"))

	if run_state != null:
		snapshot["score"] = int(run_state.get("score"))
		snapshot["banked_score"] = int(run_state.get("banked_score"))
		snapshot["elapsed_seconds"] = float(run_state.get("elapsed_seconds"))
		var no_hit: Variant = run_state.get("encounter_no_hit_awarded")
		if no_hit is Dictionary:
			snapshot["encounter_no_hit_awarded"] = (no_hit as Dictionary).duplicate()
		var live_ids: Variant = run_state.get("awarded_event_ids")
		if live_ids is Dictionary:
			snapshot["awarded_event_ids"] = (live_ids as Dictionary).duplicate()
		var banked_ids: Variant = run_state.get("_banked_event_ids")
		if banked_ids is Dictionary:
			snapshot["banked_event_ids"] = (banked_ids as Dictionary).duplicate()

	if player != null and player.get("health") != null:
		snapshot["player_health"] = maxi(1, int(player.get("health")))

	if hud != null and hud.get("dismissed_tutorials") is Dictionary:
		snapshot["dismissed_tutorials"] = (hud.get("dismissed_tutorials") as Dictionary).duplicate()

	if tree_root != null:
		var level_root: Node = tree_root.get_node_or_null("LevelRoot")
		if level_root == null and tree_root.has_method("build_greybox"):
			level_root = tree_root
		if level_root != null:
			var sw1: Node = level_root.get_node_or_null("Stage01_EntryVestibule/EntryMirrorSwitch")
			var pil: Node = level_root.get_node_or_null("Stage02_HallOfEchoes/CrackedCentralPillar")
			var sup: Node = level_root.get_node_or_null("Stage03_CollapsedGallery/WeakStoneSupport")
			var brg: Node = level_root.get_node_or_null("Stage03_CollapsedGallery/GallerySpectralBridge")
			var puz: Node = level_root.get_node_or_null("Stage04_MechanismChamber/ChamberMechanismPuzzle")
			snapshot["world_flags"] = {
				"entry_switch_activated": sw1 != null and bool(sw1.get("is_activated")),
				"hall_pillar_broken": pil != null and int(pil.get("current_state")) == 2,
				"gallery_support_broken": sup != null and int(sup.get("current_state")) == 2,
				"gallery_bridge_repaired": brg != null and bool(brg.get("is_permanently_repaired")),
				"mechanism_puzzle_solved": puz != null and bool(puz.get("is_solved")),
			}

	return save_run_checkpoint(snapshot)


func apply_saved_world_state(root_node: Node = null) -> bool:
	_load_savegame_from_disk()
	if not has_saved_run():
		return false

	var tree_root: Node = root_node
	if tree_root == null and get_tree() != null:
		tree_root = get_tree().get_first_node_in_group("main_controller")
		if tree_root == null:
			tree_root = get_tree().root

	var ed: Node = get_tree().get_first_node_in_group("encounter_director") if get_tree() != null else null
	var rm: Node = get_tree().get_first_node_in_group("realm_manager") if get_tree() != null else null
	var run_state: Node = get_tree().root.get_node_or_null("RunState") if (get_tree() != null and get_tree().root != null) else null
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D if get_tree() != null else null
	var hud: Node = get_tree().get_first_node_in_group("hud") if get_tree() != null else null

	var saved_sec: int = int(_save_data.get("checkpoint_section", _save_data.get("current_section", 0)))
	var saved_pos: Vector3 = _save_data.get("checkpoint_position", Vector3(0.0, 0.0, -3.0))
	# Saves written before the 2026-11-18 layout rework hold old (story) coordinates: carry them over.
	if int(_save_data.get("layout_version", 1)) < JourneyLayout.VERSION:
		saved_pos = JourneyLayout.to_world(saved_pos)
	var saved_rot_y: float = float(_save_data.get("checkpoint_rotation_y", PI))
	var saved_realm: int = int(_save_data.get("checkpoint_realm", 0))
	var spawn_xform := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, saved_rot_y), saved_pos)

	if run_state != null:
		if run_state.has_method("start_new_run"):
			run_state.call("start_new_run")
		var b_score: int = int(_save_data.get("banked_score", 0))
		var live_score: int = maxi(b_score, int(_save_data.get("score", b_score)))
		run_state.set("banked_score", b_score)
		run_state.set("score", live_score)
		run_state.set("elapsed_seconds", float(_save_data.get("elapsed_seconds", 0.0)))
		var saved_no_hit: Variant = _save_data.get("encounter_no_hit_awarded", {})
		if saved_no_hit is Dictionary:
			run_state.set("encounter_no_hit_awarded", (saved_no_hit as Dictionary).duplicate())
		var saved_ids: Variant = _save_data.get("banked_event_ids", {})
		var saved_live_ids: Variant = _save_data.get("awarded_event_ids", saved_ids)
		if saved_ids is Dictionary:
			run_state.set("_banked_event_ids", (saved_ids as Dictionary).duplicate())
		if saved_live_ids is Dictionary:
			run_state.set("awarded_event_ids", (saved_live_ids as Dictionary).duplicate())
		elif saved_ids is Dictionary:
			run_state.set("awarded_event_ids", (saved_ids as Dictionary).duplicate())
		if run_state.has_signal("score_changed"):
			run_state.emit_signal("score_changed", live_score, 0, "loaded_save")

	if rm != null and rm.has_method("force_realm"):
		rm.call("force_realm", saved_realm, false)

	var legacy_save: bool = int(_save_data.get("layout_version", 1)) < JourneyLayout.VERSION
	var restored_hist: Array = []
	var raw_hist: Variant = _save_data.get("checkpoint_history", [])
	if raw_hist is Array:
		for item in (raw_hist as Array):
			if item is Dictionary:
				var hd: Dictionary = item as Dictionary
				var h_pos: Vector3 = hd.get("position", Vector3(0.0, 0.0, -136.0))
				if legacy_save:
					h_pos = JourneyLayout.to_world(h_pos)
				var h_rot: float = float(hd.get("rotation_y", PI))
				restored_hist.append({
					"section": int(hd.get("section", 0)),
					"transform": Transform3D(Basis.IDENTITY.rotated(Vector3.UP, h_rot), h_pos),
					"realm": int(hd.get("realm", 0)),
					"manual": bool(hd.get("manual", false)),
				})

	if ed != null:
		ed.set("completed_sections", (_save_data.get("completed_sections", {}) as Dictionary).duplicate())
		ed.set("completed_encounters", (_save_data.get("completed_encounters", {}) as Dictionary).duplicate())
		ed.set("checkpoint_section", saved_sec)
		ed.set("checkpoint_transform", spawn_xform)
		ed.set("checkpoint_realm", saved_realm)
		if ed.has_method("advance_to_section"):
			ed.call("advance_to_section", saved_sec, spawn_xform, false)
		if ed.has_method("restore_checkpoint_history"):
			ed.call("restore_checkpoint_history", restored_hist, saved_sec, spawn_xform, saved_realm)

	if tree_root != null:
		var level_root: Node = tree_root.get_node_or_null("LevelRoot")
		if level_root == null and tree_root.has_method("build_greybox"):
			level_root = tree_root
		if level_root != null:
			var flags: Dictionary = _save_data.get("world_flags", {}) as Dictionary
			if bool(flags.get("entry_switch_activated", false)):
				var sw1: Node = level_root.get_node_or_null("Stage01_EntryVestibule/EntryMirrorSwitch")
				var gate1: Node = level_root.get_node_or_null("Stage01_EntryVestibule/Gate01_EntryToHall")
				if sw1 != null:
					sw1.set("is_activated", true)
				if gate1 != null and gate1.has_method("unlock_and_open"):
					gate1.call("unlock_and_open")
			var empty_nodes: Array[Node] = []
			if bool(flags.get("hall_pillar_broken", false)):
				var pil: Node = level_root.get_node_or_null("Stage02_HallOfEchoes/CrackedCentralPillar")
				if pil != null and pil.has_method("complete_break_now"):
					pil.call("complete_break_now", empty_nodes, false)
			if bool(flags.get("gallery_support_broken", false)):
				var sup: Node = level_root.get_node_or_null("Stage03_CollapsedGallery/WeakStoneSupport")
				if sup != null and sup.has_method("complete_break_now"):
					sup.call("complete_break_now", empty_nodes, false)
			if bool(flags.get("gallery_bridge_repaired", false)):
				var brg: Node = level_root.get_node_or_null("Stage03_CollapsedGallery/GallerySpectralBridge")
				var sw3: Node = level_root.get_node_or_null("Stage03_CollapsedGallery/BridgeAnchorSwitch")
				if brg != null and brg.has_method("repair_for_reality"):
					brg.call("repair_for_reality")
				if sw3 != null:
					sw3.set("is_activated", true)
			if bool(flags.get("mechanism_puzzle_solved", false)):
				var puz: Node = level_root.get_node_or_null("Stage04_MechanismChamber/ChamberMechanismPuzzle")
				var gate4: Node = level_root.get_node_or_null("Stage04_MechanismChamber/Gate04_MechanismToArena")
				if puz != null:
					if puz.has_method("force_solve_bypass"):
						puz.call("force_solve_bypass")
					else:
						puz.set("is_solved", true)
						puz.set("is_plate_pressed", true)
				if gate4 != null and gate4.has_method("unlock_and_open"):
					gate4.call("unlock_and_open")

			# Mark cleared enemies as dead in already-completed encounters
			if ed != null:
				var comp_enc: Dictionary = ed.get("completed_encounters") as Dictionary
				if bool(comp_enc.get("hall_of_echoes", false)):
					var hall_enemies: Array = []
					var hall_group: Node = level_root.get_node_or_null("Stage02_HallOfEchoes/Enemies")
					if hall_group != null:
						hall_enemies = hall_group.get_children()
					for en in hall_enemies:
						if en != null:
							en.set("is_dead", true)
							if en.has_method("_refresh_active_state"):
								en.call("_refresh_active_state")
					var gate2: Node = level_root.get_node_or_null("Stage02_HallOfEchoes/Gate02_HallToGallery")
					if gate2 != null and gate2.has_method("unlock_and_open"):
						gate2.call("unlock_and_open")
				if bool(comp_enc.get("shielded_guard", false)):
					var sg: Node = level_root.get_node_or_null("Stage03_CollapsedGallery/Enemies/ShieldedGuard_1")
					if sg != null:
						sg.set("is_dead", true)
						if sg.has_method("_refresh_active_state"):
							sg.call("_refresh_active_state")
					var gate3: Node = level_root.get_node_or_null("Stage03_CollapsedGallery/Gate03_GalleryToMechanism")
					if gate3 != null and gate3.has_method("unlock_and_open"):
						gate3.call("unlock_and_open")
				if bool(comp_enc.get("the_warden", false)):
					var warden: Node = level_root.get_node_or_null("Stage05_ExecutionArena/Enemies/TheWarden")
					if warden != null:
						warden.set("is_dead", true)
						if warden.has_method("_refresh_active_state"):
							warden.call("_refresh_active_state")
					var mplane: Node = level_root.get_node_or_null("Stage05_ExecutionArena/CentralMirrorPlane")
					if mplane != null and mplane.has_method("complete_break_now"):
						mplane.call("complete_break_now", empty_nodes, false)
					var gate5: Node = level_root.get_node_or_null("Stage05_ExecutionArena/Gate05_ArenaExit")
					if gate5 != null and gate5.has_method("unlock_and_open"):
						gate5.call("unlock_and_open")
					if AudioManager.instance != null:
						AudioManager.instance.set("_warden_dead", true)
					if is_inside_tree() and get_tree() != null:
						var wd_c: Node = get_tree().get_first_node_in_group("weather_director")
						if wd_c != null:
							wd_c.set("warden_dead", true)

				# Prevent passed triggers from re-firing; seal and resume an active mid-section encounter if saved inside one.
				if is_inside_tree() and get_tree() != null:
					for trig in get_tree().get_nodes_in_group("section_trigger"):
						if trig == null:
							continue
						if bool(trig.get("complete_run_on_enter")) and saved_sec < 5:
							continue
						var t_sec: int = int(trig.get("target_section"))
						var enc_id: String = String(trig.get("encounter_id"))
						if t_sec < saved_sec:
							trig.set("has_triggered", true)
						elif t_sec == saved_sec:
							var inside_or_past: bool = false
							if trig is Node3D:
								inside_or_past = (trig as Node3D).global_position.z <= saved_pos.z + 2.0
							if not inside_or_past and trig.has_method("is_point_inside_trigger"):
								inside_or_past = bool(trig.call("is_point_inside_trigger", saved_pos))
							if not enc_id.is_empty() and bool(comp_enc.get(enc_id, false)):
								trig.set("has_triggered", true)
							elif inside_or_past:
								trig.set("has_triggered", true)
								if not enc_id.is_empty() and not bool(comp_enc.get(enc_id, false)):
									var seal_path: NodePath = trig.get("entry_gate_to_seal_path") as NodePath
									if not seal_path.is_empty():
										var seal_gate: Node = trig.get_node_or_null(seal_path)
										if seal_gate != null and seal_gate.has_method("seal_gate_for_encounter"):
											seal_gate.call("seal_gate_for_encounter")
									var e_cnt: int = int(trig.get("encounter_enemy_count"))
									if e_cnt > 0 and ed.has_method("begin_combat_encounter"):
										ed.call("begin_combat_encounter", enc_id, e_cnt)

	if player != null:
		if player.has_method("respawn_at"):
			player.call("respawn_at", spawn_xform)
		var saved_hp: int = clampi(int(_save_data.get("player_health", 100)), 1, 100)
		player.set("health", saved_hp)
		if player.has_signal("health_changed"):
			player.emit_signal("health_changed", saved_hp, int(player.get("max_health")))

	if is_inside_tree() and get_tree() != null:
		var squad: Node = get_tree().get_first_node_in_group("squad_manager")
		if squad != null and squad.has_method("regroup"):
			var ally_list: Variant = squad.get("allies")
			if ally_list is Array and not (ally_list as Array).is_empty():
				squad.call("regroup", true)

	if hud != null:
		var tuts: Variant = _save_data.get("dismissed_tutorials", {})
		if tuts is Dictionary:
			hud.set("dismissed_tutorials", (tuts as Dictionary).duplicate())
		if hud.has_method("_sync_ui_nodes"):
			hud.call("_sync_ui_nodes")

	game_loaded.emit(get_saved_run_data())
	return true


func clear_saved_run(preserve_profile_and_custom: bool = true) -> void:
	var old_profile: Dictionary = (_save_data.get("profile_stats", {}) as Dictionary).duplicate(true)
	var old_custom: Dictionary = (_save_data.get("custom_claude_data", {}) as Dictionary).duplicate(true)
	_save_data = get_default_save_data()
	if preserve_profile_and_custom:
		if not old_profile.is_empty():
			_save_data["profile_stats"] = old_profile
		if not old_custom.is_empty():
			_save_data["custom_claude_data"] = old_custom
	_save_savegame_to_disk()
	save_cleared.emit()


func update_profile_stat(stat_key: String, delta_or_val: Variant, accumulate: bool = true) -> void:
	if _save_data.is_empty():
		_save_data = get_default_save_data()
	var stats: Dictionary = (_save_data.get("profile_stats", {}) as Dictionary).duplicate()
	if accumulate and stats.has(stat_key) and (stats[stat_key] is int or stats[stat_key] is float):
		stats[stat_key] = stats[stat_key] + delta_or_val
	else:
		stats[stat_key] = delta_or_val
	_save_data["profile_stats"] = stats
	_save_savegame_to_disk()


func set_custom_save_value(key: String, value: Variant) -> void:
	if _save_data.is_empty():
		_save_data = get_default_save_data()
	var custom: Dictionary = (_save_data.get("custom_claude_data", {}) as Dictionary).duplicate(true)
	custom[key] = value
	_save_data["custom_claude_data"] = custom
	_save_savegame_to_disk()


func get_custom_save_value(key: String, default_value: Variant = null) -> Variant:
	var custom: Dictionary = _save_data.get("custom_claude_data", {}) as Dictionary
	return custom.get(key, default_value)


# ============================================================================
# 5. INTERNAL DISK I/O & AUDIO BUS HELPERS
# ============================================================================

func _ensure_audio_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			var idx: int = AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func _apply_bus_volume(bus_name: String, linear_vol: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		var vol: float = clampf(linear_vol, 0.0, 1.0)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(vol, 0.0001)))
		AudioServer.set_bus_mute(idx, vol <= 0.001)


func _sort_entries() -> void:
	_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: int = int(a.get("score", 0))
		var sb: int = int(b.get("score", 0))
		if sa != sb:
			return sa > sb
		var ta: float = float(a.get("time_sec", 999999.0))
		var tb: float = float(b.get("time_sec", 999999.0))
		if not is_equal_approx(ta, tb):
			return ta < tb
		return int(a.get("_order", 0)) < int(b.get("_order", 0))
	)


func _load_leaderboard_from_disk() -> void:
	_entries.clear()
	var cfg := ConfigFile.new()
	if cfg.load(leaderboard_path) != OK:
		return
	var count: int = mini(MAX_ENTRIES, int(cfg.get_value("meta", "count", 0)))
	for i in range(count):
		var sec: String = "entry_%d" % i
		if cfg.has_section(sec):
			_entries.append({
				"initials": sanitize_initials(String(cfg.get_value(sec, "initials", "WAR"))),
				"score": int(cfg.get_value(sec, "score", 0)),
				"time_sec": float(cfg.get_value(sec, "time_sec", 0.0)),
				"rank": String(cfg.get_value(sec, "rank", "C")),
				"timestamp": String(cfg.get_value(sec, "timestamp", "")),
				"_order": i,
			})
	_sort_entries()


func _save_leaderboard_to_disk() -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "count", _entries.size())
	for i in range(_entries.size()):
		var sec: String = "entry_%d" % i
		var e: Dictionary = _entries[i]
		cfg.set_value(sec, "initials", String(e.get("initials", "WAR")))
		cfg.set_value(sec, "score", int(e.get("score", 0)))
		cfg.set_value(sec, "time_sec", float(e.get("time_sec", 0.0)))
		cfg.set_value(sec, "rank", String(e.get("rank", "C")))
		cfg.set_value(sec, "timestamp", String(e.get("timestamp", "")))
	var err: Error = cfg.save(leaderboard_path)
	last_save_error = err
	if err != OK:
		push_warning("Failed to save leaderboard to '%s' (err=%d)" % [leaderboard_path, int(err)])
	return err


func _load_settings_from_disk() -> void:
	_settings = get_default_settings()
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	for k in _settings.keys():
		if k == "keybindings":
			var binds: Dictionary = get_default_keybindings()
			if cfg.has_section("keybindings"):
				for act in REBINDABLE_ACTIONS:
					if cfg.has_section_key("keybindings", act):
						binds[act] = String(cfg.get_value("keybindings", act, binds[act]))
			elif cfg.has_section_key("settings", "keybindings"):
				var raw_b: Variant = cfg.get_value("settings", "keybindings", {})
				if raw_b is Dictionary:
					for act in REBINDABLE_ACTIONS:
						if (raw_b as Dictionary).has(act):
							binds[act] = String((raw_b as Dictionary)[act])
			if String(binds.get("dodge", "")) == ("KEY:%d" % KEY_SPACE) and String(binds.get("jump", "")) == ("KEY:%d" % KEY_SPACE):
				binds["dodge"] = "KEY:%d" % KEY_SHIFT
			_settings["keybindings"] = binds
		elif cfg.has_section_key("settings", k):
			_settings[k] = cfg.get_value("settings", k, _settings[k])


func _save_settings_to_disk() -> Error:
	var cfg := ConfigFile.new()
	for k in _settings.keys():
		if k == "keybindings":
			var binds: Dictionary = _settings["keybindings"] as Dictionary
			for act in binds.keys():
				cfg.set_value("keybindings", String(act), String(binds[act]))
		else:
			cfg.set_value("settings", k, _settings[k])
	var err: Error = cfg.save(settings_path)
	last_save_error = err
	if err != OK:
		push_warning("Failed to save settings to '%s' (err=%d)" % [settings_path, int(err)])
	return err


func _load_savegame_from_disk() -> void:
	_save_data = get_default_save_data()
	var cfg := ConfigFile.new()
	if cfg.load(savegame_path) != OK:
		return
	for k in _save_data.keys():
		if k == "custom_claude_data":
			var custom: Dictionary = {}
			if cfg.has_section("custom"):
				for ck in cfg.get_section_keys("custom"):
					custom[ck] = cfg.get_value("custom", ck)
			_save_data["custom_claude_data"] = custom
		elif k == "profile_stats":
			var stats: Dictionary = (_save_data["profile_stats"] as Dictionary).duplicate()
			if cfg.has_section("profile"):
				for pk in cfg.get_section_keys("profile"):
					stats[pk] = cfg.get_value("profile", pk)
			_save_data["profile_stats"] = stats
		elif cfg.has_section_key("run", k):
			_save_data[k] = cfg.get_value("run", k, _save_data[k])


func _save_savegame_to_disk() -> Error:
	var cfg := ConfigFile.new()
	for k in _save_data.keys():
		if k == "custom_claude_data":
			var custom: Dictionary = _save_data["custom_claude_data"] as Dictionary
			for ck in custom.keys():
				cfg.set_value("custom", String(ck), custom[ck])
		elif k == "profile_stats":
			var stats: Dictionary = _save_data["profile_stats"] as Dictionary
			for pk in stats.keys():
				cfg.set_value("profile", String(pk), stats[pk])
		else:
			cfg.set_value("run", k, _save_data[k])
	var err: Error = cfg.save(savegame_path)
	last_save_error = err
	if err != OK:
		push_warning("Failed to save run data to '%s' (err=%d)" % [savegame_path, int(err)])
	return err
