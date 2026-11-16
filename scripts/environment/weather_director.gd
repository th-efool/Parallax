class_name WeatherDirector
extends Node
## Zone-driven dynamic weather for "The Ascent". Reads the player's progress (Z along the route) plus boss
## state, picks a weather PROFILE, and smoothly blends sky (journey_sky.gdshader uniforms), fog, sun, ambient
## light, rain (GPU particles that follow the camera and stop at roofs) and lightning toward it.
##   golden   prologue + gate          clear golden hour, dust
##   haze     sunlit stair + hall      warm haze
##   storm    rampart + aqueduct       grey overcast, wind, light rain, distant lightning
##   tempest  clock tower + stair      heavy rain, frequent lightning
##   blood    colosseum (Warden alive) crimson sky, blood rain, red fog; Phase 2 = harder, redder
##   aftermath Warden slain / summit   rain stops, sky clears to gold
## Runs after RealmEnvironmentController each frame and layers on top of its realm palette (never fights it).
## Weather audio (rain loops, wind, thunder) plays from assets/audio/ambience/ when those files exist.

signal profile_changed(profile_name: String)
signal lightning_struck(distance_m: float)

const PROFILES: Dictionary = {
	"golden": {"overcast": 0.0, "blood": 0.0, "fog_mul": 1.0, "fog_color": Color(0.82, 0.66, 0.5), "fog_tint": 0.0,
		"light_mul": 1.0, "light_tint": Color(1, 0.78, 0.56), "light_tint_amt": 0.0, "ambient_mul": 1.0,
		"rain": 0.0, "rain_color": Color(0.7, 0.75, 0.85, 0.35), "lightning_per_min": 0.0, "wind": 0.25},
	"haze": {"overcast": 0.12, "blood": 0.0, "fog_mul": 1.6, "fog_color": Color(0.88, 0.72, 0.52), "fog_tint": 0.4,
		"light_mul": 0.95, "light_tint": Color(1, 0.8, 0.6), "light_tint_amt": 0.0, "ambient_mul": 1.0,
		"rain": 0.0, "rain_color": Color(0.7, 0.75, 0.85, 0.35), "lightning_per_min": 0.0, "wind": 0.35},
	"storm": {"overcast": 0.72, "blood": 0.0, "fog_mul": 2.6, "fog_color": Color(0.42, 0.45, 0.52), "fog_tint": 0.85,
		"light_mul": 0.42, "light_tint": Color(0.7, 0.78, 0.92), "light_tint_amt": 0.6, "ambient_mul": 0.75,
		"rain": 0.35, "rain_color": Color(0.72, 0.78, 0.9, 0.32), "lightning_per_min": 2.0, "wind": 0.75},
	"tempest": {"overcast": 0.9, "blood": 0.0, "fog_mul": 3.2, "fog_color": Color(0.32, 0.35, 0.42), "fog_tint": 0.9,
		"light_mul": 0.3, "light_tint": Color(0.62, 0.7, 0.88), "light_tint_amt": 0.75, "ambient_mul": 0.62,
		"rain": 0.85, "rain_color": Color(0.72, 0.78, 0.9, 0.38), "lightning_per_min": 5.0, "wind": 1.0},
	"blood": {"overcast": 0.35, "blood": 0.85, "fog_mul": 2.4, "fog_color": Color(0.45, 0.06, 0.04), "fog_tint": 0.9,
		"light_mul": 0.62, "light_tint": Color(1.0, 0.32, 0.22), "light_tint_amt": 0.85, "ambient_mul": 0.7,
		"rain": 0.55, "rain_color": Color(0.55, 0.02, 0.02, 0.55), "lightning_per_min": 3.0, "wind": 0.6},
	"blood_frenzy": {"overcast": 0.45, "blood": 1.0, "fog_mul": 3.0, "fog_color": Color(0.5, 0.04, 0.03), "fog_tint": 1.0,
		"light_mul": 0.55, "light_tint": Color(1.0, 0.22, 0.15), "light_tint_amt": 0.95, "ambient_mul": 0.62,
		"rain": 1.0, "rain_color": Color(0.6, 0.0, 0.0, 0.62), "lightning_per_min": 7.0, "wind": 0.9},
	"aftermath": {"overcast": 0.0, "blood": 0.0, "fog_mul": 1.2, "fog_color": Color(0.95, 0.78, 0.55), "fog_tint": 0.5,
		"light_mul": 1.15, "light_tint": Color(1.0, 0.84, 0.6), "light_tint_amt": 0.3, "ambient_mul": 1.1,
		"rain": 0.0, "rain_color": Color(0.7, 0.75, 0.85, 0.35), "lightning_per_min": 0.0, "wind": 0.2},
}

## Route Z where each profile begins (player feet Z), ascending.
const ZONES: Array = [[-1000.0, "golden"], [8.0, "haze"], [44.0, "storm"], [88.0, "tempest"], [137.0, "blood"], [186.0, "aftermath"]]

const AMBIENCE_DIR: String = "res://assets/audio/ambience/"

@export var blend_speed: float = 0.35          # fraction of the gap closed per second (~4 s to settle)
@export var base_fog_density: float = 0.00075
@export var rain_max_particles: int = 6000
@export var world_environment_path: NodePath
@export var sun_path: NodePath
@export var realm_controller_path: NodePath
@export var warden_path: NodePath

var current_profile: String = "golden"
var forced_profile: String = ""                # set by tests / scripted moments
var warden_dead: bool = false
var warden_phase2: bool = false

var _cur: Dictionary = {}
var _rain: GPUParticles3D = null
var _rain_mat: ParticleProcessMaterial = null
var _rain_draw: StandardMaterial3D = null
var _rain_collider: GPUParticlesCollisionHeightField3D = null
var _flash: float = 0.0
var _next_lightning: float = 6.0
var _last_sky: Dictionary = {}
var _rain_light: AudioStreamPlayer = null
var _rain_heavy: AudioStreamPlayer = null
var _wind: AudioStreamPlayer = null
var _thunder: Array[AudioStream] = []
var _thunder_player: AudioStreamPlayer = null
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_priority = 100 # after RealmEnvironmentController
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()
	add_to_group("weather_director")
	_cur = (PROFILES["golden"] as Dictionary).duplicate()
	_build_rain()
	_build_audio()
	_bind_warden.call_deferred()


func _bind_warden() -> void:
	var w: Node = get_node_or_null(warden_path)
	if w == null:
		return
	if w.has_signal("boss_defeated"):
		w.connect("boss_defeated", func() -> void: warden_dead = true)
	if w.has_signal("boss_phase_changed"):
		w.connect("boss_phase_changed", func(p: int) -> void: warden_phase2 = p >= 2)
	if w.has_signal("health_changed"):
		# Reset/respawn restores HP -> weather returns to the Phase 1 blood storm.
		w.connect("health_changed", func(hp: int, max_hp: int) -> void:
			if hp >= max_hp:
				warden_phase2 = false
				warden_dead = false)


## 0..1 surface wetness (same value pushed to the realm_wetness shader global). Used for wet footsteps.
func get_wetness() -> float:
	return clampf(float(_cur.get("rain", 0.0)) * 1.2, 0.0, 1.0)


func get_profile_for(z: float) -> String:
	var name: String = "golden"
	for zd in ZONES:
		if z >= float(zd[0]):
			name = String(zd[1])
	if name == "blood":
		if warden_dead:
			return "aftermath"
		if warden_phase2:
			return "blood_frenzy"
	return name


func _process(delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	var probe: Vector3 = player.global_position if player != null else (cam.global_position if cam != null else Vector3.ZERO)
	var target_name: String = forced_profile if forced_profile != "" else get_profile_for(probe.z)
	if target_name != current_profile:
		current_profile = target_name
		profile_changed.emit(current_profile)
	var target: Dictionary = PROFILES[current_profile]
	var k: float = 1.0 - pow(1.0 - clampf(blend_speed, 0.01, 1.0), delta)
	for key in target:
		var tv: Variant = target[key]
		if tv is Color:
			_cur[key] = (_cur[key] as Color).lerp(tv, k)
		else:
			_cur[key] = lerpf(float(_cur[key]), float(tv), k)
	_update_lightning(delta)
	_apply(cam)


func _update_lightning(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 5.0)
	var rate: float = float(_cur["lightning_per_min"])
	if rate < 0.2:
		return
	_next_lightning -= delta
	if _next_lightning <= 0.0:
		_next_lightning = _rng.randf_range(0.5, 2.0) * 60.0 / rate
		strike()


func strike() -> void:
	## Double-pulse sheet lightning + thunder delayed by distance (speed of sound ~343 m/s).
	_flash = _rng.randf_range(1.6, 2.6)
	var dist: float = _rng.randf_range(250.0, 1400.0)
	var tw := create_tween()
	tw.tween_interval(0.09)
	tw.tween_callback(func() -> void: _flash = maxf(_flash, _rng.randf_range(1.0, 2.0)))
	lightning_struck.emit(dist)
	if _thunder_player != null and not _thunder.is_empty():
		var t := get_tree().create_timer(dist / 343.0)
		t.timeout.connect(func() -> void:
			if is_instance_valid(_thunder_player):
				_thunder_player.stream = _thunder[_rng.randi() % _thunder.size()]
				_thunder_player.volume_db = lerpf(-2.0, -14.0, clampf((dist - 250.0) / 1150.0, 0.0, 1.0))
				_thunder_player.pitch_scale = _rng.randf_range(0.85, 1.05)
				_thunder_player.play())


func _apply(cam: Camera3D) -> void:
	var we: WorldEnvironment = get_node_or_null(world_environment_path) as WorldEnvironment
	var sun: DirectionalLight3D = get_node_or_null(sun_path) as DirectionalLight3D
	var rec: Node = get_node_or_null(realm_controller_path)
	if we != null and we.environment != null:
		var env: Environment = we.environment
		env.fog_density = base_fog_density * float(_cur["fog_mul"])
		var realm_fog: Color = rec.get("current_fog_color") if rec != null else Color(0.82, 0.66, 0.5)
		env.fog_light_color = realm_fog.lerp(_cur["fog_color"], float(_cur["fog_tint"]))
		env.ambient_light_energy = float(_cur["ambient_mul"]) + _flash * 0.35
		if env.sky != null and env.sky.sky_material is ShaderMaterial:
			var sm: ShaderMaterial = env.sky.sky_material as ShaderMaterial
			_set_sky(sm, "overcast", float(_cur["overcast"]))
			_set_sky(sm, "blood", float(_cur["blood"]))
			_set_sky(sm, "flash", _flash)
	if sun != null:
		var base_e: float = float(rec.get("current_sun_energy")) if rec != null else 1.6
		var base_c: Color = rec.get("current_light_color") if rec != null else Color(1, 0.78, 0.56)
		sun.light_energy = base_e * float(_cur["light_mul"]) + _flash * 1.4
		sun.light_color = base_c.lerp(_cur["light_tint"], float(_cur["light_tint_amt"])).lerp(Color(0.85, 0.9, 1.0), clampf(_flash * 0.4, 0.0, 1.0))
	RenderingServer.global_shader_parameter_set(&"realm_wetness", clampf(float(_cur["rain"]) * 1.2, 0.0, 1.0))
	_update_rain(cam)
	_update_audio()


func _set_sky(sm: ShaderMaterial, param: String, v: float) -> void:
	# Only push meaningful changes (each change re-renders the sky radiance incrementally).
	var last: float = float(_last_sky.get(param, -1.0))
	if absf(last - v) > 0.01 or (v == 0.0 and last != 0.0):
		sm.set_shader_parameter(param, v)
		_last_sky[param] = v


# --- Rain ----------------------------------------------------------------------------------------------

func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = rain_max_particles
	_rain.lifetime = 1.1
	_rain.preprocess = 1.0
	_rain.amount_ratio = 0.0
	_rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.collision_base_size = 0.05
	_rain_mat = ParticleProcessMaterial.new()
	_rain_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_mat.emission_box_extents = Vector3(22, 0.5, 22)
	_rain_mat.direction = Vector3(0.12, -1, 0.05)
	_rain_mat.spread = 3.0
	_rain_mat.initial_velocity_min = 26.0
	_rain_mat.initial_velocity_max = 32.0
	_rain_mat.gravity = Vector3(0, -9.8, 0)
	_rain_mat.particle_flag_align_y = true
	_rain_mat.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_rain.process_material = _rain_mat
	var streak := QuadMesh.new()
	streak.size = Vector2(0.025, 0.7)
	_rain_draw = StandardMaterial3D.new()
	_rain_draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain_draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_draw.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_rain_draw.billboard_keep_scale = true
	_rain_draw.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rain_draw.albedo_color = Color(0.7, 0.75, 0.85, 0.35)
	streak.material = _rain_draw
	_rain.draw_pass_1 = streak
	add_child(_rain)
	# Heightfield follows the camera so rain stops on roofs/arcades instead of falling indoors.
	_rain_collider = GPUParticlesCollisionHeightField3D.new()
	_rain_collider.name = "RainOcclusion"
	_rain_collider.size = Vector3(48, 60, 48)
	_rain_collider.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	_rain_collider.follow_camera_enabled = true
	_rain_collider.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	add_child(_rain_collider)


func _update_rain(cam: Camera3D) -> void:
	var r: float = clampf(float(_cur["rain"]), 0.0, 1.0)
	_rain.amount_ratio = r
	_rain.emitting = r > 0.01
	if cam != null:
		_rain.global_position = cam.global_position + Vector3(0, 14.0, 0)
	var rc: Color = _cur["rain_color"]
	_rain_draw.albedo_color = rc
	var wind: float = float(_cur["wind"])
	_rain_mat.direction = Vector3(0.1 + wind * 0.25, -1.0, 0.05 + wind * 0.08)


# --- Weather audio (optional assets) ---------------------------------------------------------------------

func _load(name: String) -> AudioStream:
	for ext in [".ogg", ".wav"]:
		var p: String = AMBIENCE_DIR + name + ext
		if ResourceLoader.exists(p):
			return load(p) as AudioStream
	return null


func _loop_player(stream: AudioStream, node_name: String) -> AudioStreamPlayer:
	if stream == null:
		return null
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.stream = stream
	p.bus = &"SFX" if AudioServer.get_bus_index("Ambience") < 0 else &"Ambience"
	p.volume_db = -80.0
	p.autoplay = DisplayServer.get_name() != "headless"
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		var w: AudioStreamWAV = stream as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * float(w.mix_rate))
	add_child(p)
	return p


func _build_audio() -> void:
	_rain_light = _loop_player(_load("rain_light_loop"), "RainLight")
	_rain_heavy = _loop_player(_load("rain_heavy_loop"), "RainHeavy")
	_wind = _loop_player(_load("wind_cliff_loop"), "Wind")
	for i in range(1, 7):
		var t: AudioStream = _load("thunder_%d" % i)
		if t != null:
			_thunder.append(t)
	if not _thunder.is_empty():
		_thunder_player = AudioStreamPlayer.new()
		_thunder_player.name = "Thunder"
		_thunder_player.bus = &"SFX" if AudioServer.get_bus_index("Ambience") < 0 else &"Ambience"
		add_child(_thunder_player)


func _update_audio() -> void:
	var r: float = clampf(float(_cur["rain"]), 0.0, 1.0)
	if _rain_light != null:
		_rain_light.volume_db = linear_to_db(maxf(0.0001, clampf(r * 2.0, 0.0, 1.0) * (1.0 - r * 0.5))) - 4.0
	if _rain_heavy != null:
		_rain_heavy.volume_db = linear_to_db(maxf(0.0001, clampf((r - 0.4) * 1.7, 0.0, 1.0))) - 3.0
	if _wind != null:
		_wind.volume_db = linear_to_db(maxf(0.0001, float(_cur["wind"]))) - 8.0
