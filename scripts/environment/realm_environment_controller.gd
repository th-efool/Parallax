class_name RealmEnvironmentController
extends Node
## Tweens `WorldEnvironment` & `DirectionalLight3D` between Reality warm limestone/amber (`#9C8468` / `#FF9933`)
## and Mirror cold slate/cobalt (`#141D2E` / `#33B5FF`), and animates `realm_shift_pulse.gdshader`'s
## `shift_progress` (`0.0 -> 1.0` over `0.20s`) on every dimension shift.

signal environment_transition_started(target_state: String)
signal environment_transition_completed(active_state: String)

const REALITY_AMBIENT: Color = Color(0.612, 0.518, 0.408, 1.0) # #9C8468
const REALITY_LIGHT: Color = Color(1.000, 0.600, 0.200, 1.0)   # #FF9933
const REALITY_FOG: Color = Color(0.360, 0.294, 0.231, 1.0)     # Warm dust fog
const REALITY_ACCENT: Color = Color(0.902, 0.600, 0.220, 1.0)  # #E69938

const MIRROR_AMBIENT: Color = Color(0.078, 0.114, 0.180, 1.0)  # #141D2E
const MIRROR_LIGHT: Color = Color(0.200, 0.710, 1.000, 1.0)    # #33B5FF
const MIRROR_FOG: Color = Color(0.200, 0.333, 0.600, 1.0)      # #335599
const MIRROR_ACCENT: Color = Color(0.200, 0.710, 1.000, 1.0)   # #33B5FF

const MERGED_AMBIENT: Color = Color(0.345, 0.316, 0.294, 1.0)
const MERGED_LIGHT: Color = Color(0.750, 0.650, 0.850, 1.0)
const MERGED_FOG: Color = Color(0.450, 0.310, 0.480, 1.0)

const SHIFT_PULSE_SHADER_PATH: String = "res://assets/shaders/realm_shift_pulse.gdshader"

@export var transition_duration: float = 0.20
@export var world_environment_path: NodePath
@export var directional_light_path: NodePath
@export var pulse_overlay_rect_path: NodePath

var current_ambient_color: Color = REALITY_AMBIENT
var current_light_color: Color = REALITY_LIGHT
var current_fog_color: Color = REALITY_FOG
var current_accent_color: Color = REALITY_ACCENT

var _start_ambient: Color = REALITY_AMBIENT
var _start_light: Color = REALITY_LIGHT
var _start_fog: Color = REALITY_FOG
var _target_ambient: Color = REALITY_AMBIENT
var _target_light: Color = REALITY_LIGHT
var _target_fog: Color = REALITY_FOG

var active_palette_state: String = "REALITY"
var is_transitioning: bool = false
var shift_pulse_progress: float = 1.0
var _transition_elapsed: float = 0.0
var _pulse_material: ShaderMaterial = null


func _exit_tree() -> void:
	_pulse_material = null


func _ready() -> void:
	add_to_group("realm_environment")
	_setup_pulse_material()
	bind_realm_manager()
	apply_state_immediate(active_palette_state)


func bind_realm_manager() -> void:
	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm != null:
		if not rm.realm_changed.is_connected(_on_realm_changed):
			rm.realm_changed.connect(_on_realm_changed)
		if not rm.realms_merged.is_connected(_on_realms_merged):
			rm.realms_merged.connect(_on_realms_merged)
		if rm.is_merged:
			active_palette_state = "MERGED"
		else:
			active_palette_state = "MIRROR" if rm.current_realm == RealmManager.Realm.MIRROR else "REALITY"


func _process(delta: float) -> void:
	if not is_transitioning:
		return

	var dur: float = maxf(0.01, transition_duration)
	_transition_elapsed = minf(dur, _transition_elapsed + delta)
	var t: float = clampf(_transition_elapsed / dur, 0.0, 1.0)

	current_ambient_color = _start_ambient.lerp(_target_ambient, t)
	current_light_color = _start_light.lerp(_target_light, t)
	current_fog_color = _start_fog.lerp(_target_fog, t)
	shift_pulse_progress = t
	_apply_to_scene_nodes()

	if t >= 1.0:
		is_transitioning = false
		environment_transition_completed.emit(active_palette_state)


func transition_to_state(state_name: String) -> void:
	active_palette_state = state_name
	_start_ambient = current_ambient_color
	_start_light = current_light_color
	_start_fog = current_fog_color

	match state_name:
		"MIRROR":
			_target_ambient = MIRROR_AMBIENT
			_target_light = MIRROR_LIGHT
			_target_fog = MIRROR_FOG
			current_accent_color = MIRROR_ACCENT
		"MERGED":
			_target_ambient = MERGED_AMBIENT
			_target_light = MERGED_LIGHT
			_target_fog = MERGED_FOG
			current_accent_color = MIRROR_ACCENT.lerp(REALITY_ACCENT, 0.5)
		_:
			_target_ambient = REALITY_AMBIENT
			_target_light = REALITY_LIGHT
			_target_fog = REALITY_FOG
			current_accent_color = REALITY_ACCENT

	_transition_elapsed = 0.0
	shift_pulse_progress = 0.0
	is_transitioning = true
	_apply_to_scene_nodes()
	environment_transition_started.emit(active_palette_state)


func apply_state_immediate(state_name: String) -> void:
	transition_to_state(state_name)
	_transition_elapsed = maxf(0.01, transition_duration)
	_process(0.0)


func get_pulse_shader_material() -> ShaderMaterial:
	return _pulse_material


func _on_realm_changed(new_realm: int) -> void:
	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm != null and rm.is_merged:
		transition_to_state("MERGED")
	elif new_realm == RealmManager.Realm.MIRROR:
		transition_to_state("MIRROR")
	else:
		transition_to_state("REALITY")


func _on_realms_merged() -> void:
	transition_to_state("MERGED")


func _setup_pulse_material() -> void:
	if ResourceLoader.exists(SHIFT_PULSE_SHADER_PATH):
		var sh: Shader = load(SHIFT_PULSE_SHADER_PATH) as Shader
		if sh != null:
			_pulse_material = ShaderMaterial.new()
			_pulse_material.shader = sh
			_pulse_material.set_shader_parameter("shift_progress", 1.0)
			_pulse_material.set_shader_parameter("pulse_color", MIRROR_ACCENT)


func _apply_to_scene_nodes() -> void:
	if _pulse_material != null:
		_pulse_material.set_shader_parameter("shift_progress", shift_pulse_progress)
		_pulse_material.set_shader_parameter("pulse_color", current_accent_color)

	if not pulse_overlay_rect_path.is_empty():
		var rect: CanvasItem = get_node_or_null(pulse_overlay_rect_path) as CanvasItem
		if rect != null:
			if rect.material == null and _pulse_material != null:
				rect.material = _pulse_material
			rect.visible = is_transitioning

	if not directional_light_path.is_empty():
		var dlight: DirectionalLight3D = get_node_or_null(directional_light_path) as DirectionalLight3D
		if dlight != null:
			dlight.light_color = current_light_color

	if not world_environment_path.is_empty():
		var we: WorldEnvironment = get_node_or_null(world_environment_path) as WorldEnvironment
		if we != null and we.environment != null:
			we.environment.ambient_light_color = current_ambient_color
			we.environment.fog_light_color = current_fog_color
