class_name PerformanceGovernor
extends Node
## Adaptive 3D resolution: watches the frame rate and lowers the root viewport's
## `scaling_3d_scale` (FSR 1) when the game struggles (integrated GPUs, laptops),
## then restores it toward the user's chosen Render Scale when there is headroom.
## Controlled by the `adaptive_resolution` setting; never goes above the user's scale.

const MIN_SCALE: float = 0.55
const LOW_FPS: float = 42.0
const HIGH_FPS: float = 78.0
const STEP_DOWN: float = 0.08
const STEP_UP: float = 0.04
const SAMPLE_SEC: float = 2.0
const CHANGE_COOLDOWN_SEC: float = 6.0

var _acc: float = 0.0
var _frames: int = 0
var _warmup: float = 5.0
var _cooldown: float = 0.0
var _low_streak: int = 0
var _high_streak: int = 0
var _cached_enabled: bool = true
var _cached_cap: float = 1.0
var _settings_bound: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("performance_governor")
	_refresh_settings()


func _store() -> Node:
	return get_node_or_null("/root/LeaderboardStore")


func _refresh_settings(_s: Dictionary = {}) -> void:
	var s: Node = _store()
	if s == null:
		return
	if not _settings_bound and s.has_signal("settings_changed"):
		s.connect("settings_changed", _refresh_settings)
		_settings_bound = true
	if s.has_method("get_settings"):
		var d: Dictionary = s.get_settings() as Dictionary
		_cached_cap = clampf(float(d.get("render_scale", 1.0)), 0.5, 1.0)
		_cached_enabled = bool(d.get("adaptive_resolution", true))


func _level_is_ready() -> bool:
	if not is_inside_tree() or get_tree() == null:
		return false
	var mc: Node = get_tree().get_first_node_in_group("main_controller")
	return mc != null and mc.get("level_ready") == true


func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Never reallocate 3D render targets (MSAA/FSR) while the title screen or loading screen is active!
	if not _level_is_ready():
		_warmup = 4.0
		_acc = 0.0
		_frames = 0
		_low_streak = 0
		_high_streak = 0
		return
	if _warmup > 0.0:
		_warmup -= delta
		return
	if _cooldown > 0.0:
		_cooldown -= delta
		return
	_acc += delta
	_frames += 1
	if _acc < SAMPLE_SEC:
		return
	var fps: float = float(_frames) / maxf(_acc, 0.001)
	_acc = 0.0
	_frames = 0
	if not _cached_enabled:
		return
	var vp: Viewport = get_tree().root
	var cap: float = _cached_cap
	var cur: float = vp.scaling_3d_scale
	var target: float = cur
	if fps < LOW_FPS:
		_low_streak += 1
		_high_streak = 0
		if _low_streak >= 2:
			target = maxf(MIN_SCALE, cur - STEP_DOWN)
			_low_streak = 0
	elif fps > HIGH_FPS:
		_high_streak += 1
		_low_streak = 0
		if _high_streak >= 3:
			target = minf(cap, cur + STEP_UP)
			_high_streak = 0
	else:
		_low_streak = 0
		_high_streak = 0
	if cur > cap:
		target = cap
	if absf(target - cur) > 0.001:
		# Use BILINEAR scaling when MSAA is active to avoid live MSAA+FSR Vulkan pipeline reallocations.
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if vp.msaa_3d != Viewport.MSAA_DISABLED else (Viewport.SCALING_3D_MODE_FSR if target < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR)
		vp.scaling_3d_scale = target
		_cooldown = CHANGE_COOLDOWN_SEC
