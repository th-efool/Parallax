class_name PerformanceGovernor
extends Node
## Adaptive 3D resolution: watches the frame rate and lowers the root viewport's
## `scaling_3d_scale` (FSR 1) when the game struggles (integrated GPUs, laptops),
## then restores it toward the user's chosen Render Scale when there is headroom.
## Controlled by the `adaptive_resolution` setting; never goes above the user's scale.

const MIN_SCALE: float = 0.55
const LOW_FPS: float = 45.0
const HIGH_FPS: float = 75.0
const STEP_DOWN: float = 0.08
const STEP_UP: float = 0.04
const SAMPLE_SEC: float = 1.5

var _acc: float = 0.0
var _frames: int = 0
var _warmup: float = 3.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("performance_governor")


func _store() -> Node:
	return get_node_or_null("/root/LeaderboardStore")


func _user_scale() -> float:
	var s: Node = _store()
	if s == null or not s.has_method("get_settings"):
		return 1.0
	return clampf(float((s.get_settings() as Dictionary).get("render_scale", 1.0)), 0.5, 1.0)


func _enabled() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var s: Node = _store()
	if s == null or not s.has_method("get_settings"):
		return true
	return bool((s.get_settings() as Dictionary).get("adaptive_resolution", true))


func _process(delta: float) -> void:
	if _warmup > 0.0:
		_warmup -= delta
		return
	_acc += delta
	_frames += 1
	if _acc < SAMPLE_SEC:
		return
	var fps: float = float(_frames) / maxf(_acc, 0.001)
	_acc = 0.0
	_frames = 0
	if not _enabled():
		return
	var vp: Viewport = get_tree().root
	var cap: float = _user_scale()
	var cur: float = vp.scaling_3d_scale
	var target: float = cur
	if fps < LOW_FPS:
		target = maxf(MIN_SCALE, cur - STEP_DOWN)
	elif fps > HIGH_FPS:
		target = minf(cap, cur + STEP_UP)
	if cur > cap:
		target = cap
	if absf(target - cur) > 0.001:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if target < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = target
