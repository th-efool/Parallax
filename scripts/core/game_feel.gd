class_name GameFeel
extends Node
## Global "juice" director (lazy singleton, never an autoload):
##  - Stackable real-time hit-stop / slow-motion (`Engine.time_scale` = min of active effects).
##  - Camera trauma broadcast to every node in `feel_camera_rig` (PlayerFeelRig).
##  - Procedural one-shot 3D sound layers (flesh slice, bone crunch, splat, whoosh, clang, thud)
##    synthesized once at runtime, so no new audio assets are required.

const GROUP_CAMERA_RIG: String = "feel_camera_rig"
const SAMPLE_RATE: int = 22050

static var _instance: Node = null

var _effects: Array[Dictionary] = []
var _owns_time_scale: bool = false
var _streams: Dictionary = {}
var _rng := RandomNumberGenerator.new()


static func get_instance(context: Node) -> GameFeel:
	if _instance != null and is_instance_valid(_instance):
		return _instance as GameFeel
	if context == null or not context.is_inside_tree():
		return null
	var gf: GameFeel = (load("res://scripts/core/game_feel.gd") as GDScript).new() as GameFeel
	gf.name = "GameFeel"
	gf.process_mode = Node.PROCESS_MODE_ALWAYS
	context.get_tree().root.add_child.call_deferred(gf)
	_instance = gf
	return gf


# ---------------------------------------------------------------- time scale

## Near-freeze for `duration` real seconds. Respects the player's "hit stop" setting.
static func hitstop(context: Node, duration: float, time_scale: float = 0.03) -> void:
	if not _hit_stop_allowed(context):
		return
	var gf: GameFeel = get_instance(context)
	if gf != null:
		gf.push_time_effect(time_scale, duration)


## Dramatic slow motion (kill-cam, perfect dodge). Real seconds.
static func slowmo(context: Node, time_scale: float, duration: float) -> void:
	if not _hit_stop_allowed(context):
		return
	var gf: GameFeel = get_instance(context)
	if gf != null:
		gf.push_time_effect(time_scale, duration)


static func add_trauma(context: Node, amount: float, world_pos: Variant = null, falloff_radius: float = 18.0) -> void:
	if context == null or not context.is_inside_tree():
		return
	for rig in context.get_tree().get_nodes_in_group(GROUP_CAMERA_RIG):
		if not rig.has_method("add_trauma"):
			continue
		var k: float = 1.0
		if world_pos is Vector3 and rig is Node3D:
			var d: float = (rig as Node3D).global_position.distance_to(world_pos as Vector3)
			k = clampf(1.0 - d / maxf(0.1, falloff_radius), 0.0, 1.0)
		if k > 0.0:
			rig.call("add_trauma", amount * k)


static func _hit_stop_allowed(context: Node) -> bool:
	if context == null or not context.is_inside_tree():
		return false
	if DisplayServer.get_name() == "headless":
		return false
	var store: Node = context.get_tree().root.get_node_or_null("LeaderboardStore")
	if store != null and store.has_method("get_settings"):
		var s: Dictionary = store.call("get_settings")
		return bool(s.get("hit_stop_enabled", true))
	return true


func push_time_effect(time_scale: float, duration: float) -> void:
	if duration <= 0.0:
		return
	var end_usec: int = Time.get_ticks_usec() + int(duration * 1000000.0)
	_effects.append({"scale": clampf(time_scale, 0.01, 1.0), "end": end_usec})
	_apply_time_scale()


func clear_time_effects() -> void:
	_effects.clear()
	_apply_time_scale()


func _process(_delta: float) -> void:
	if not _effects.is_empty() or _owns_time_scale:
		_apply_time_scale()


func _apply_time_scale() -> void:
	var now: int = Time.get_ticks_usec()
	var lowest: float = 1.0
	var i: int = _effects.size() - 1
	while i >= 0:
		var e: Dictionary = _effects[i]
		if int(e["end"]) <= now:
			_effects.remove_at(i)
		else:
			lowest = minf(lowest, float(e["scale"]))
		i -= 1
	if _effects.is_empty():
		if _owns_time_scale:
			Engine.time_scale = 1.0
			_owns_time_scale = false
		return
	# A paused tree (menus) must not be held in slow motion when it resumes.
	if get_tree() != null and get_tree().paused:
		_effects.clear()
		Engine.time_scale = 1.0
		_owns_time_scale = false
		return
	_owns_time_scale = true
	Engine.time_scale = lowest


func _exit_tree() -> void:
	if _owns_time_scale:
		Engine.time_scale = 1.0
	if _instance == self:
		_instance = null
	# Drop static resource caches so nothing is reported as leaked at shutdown.
	var gore: GDScript = load("res://scripts/core/gore_fx.gd") as GDScript
	if gore != null:
		gore.call("clear_caches")
	var loadout: GDScript = load("res://scripts/core/character_loadout.gd") as GDScript
	if loadout != null:
		loadout.call("clear_caches")


# ---------------------------------------------------------------- audio

## Plays a procedural sound layer at a world position. Keys: slash_flesh, bone_crunch, splat,
## whoosh_light, whoosh_heavy, clang, thud, gib_burst, land_heavy.
static func play_sound(context: Node, key: String, world_pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0, pitch_jitter: float = 0.08) -> void:
	if context == null or not context.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var gf: GameFeel = get_instance(context)
	if gf == null:
		return
	var stream: AudioStream = gf.get_stream(key)
	if stream == null:
		return
	var host: Node = context.get_tree().current_scene
	if host == null:
		host = context.get_tree().root
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = maxf(0.1, pitch * (1.0 + gf._rng.randf_range(-pitch_jitter, pitch_jitter)))
	p.unit_size = 7.0
	p.max_distance = 45.0
	if AudioServer.get_bus_index("SFX") >= 0:
		p.bus = "SFX"
	host.add_child(p)
	p.global_position = world_pos
	p.finished.connect(p.queue_free)
	p.play()


func get_stream(key: String) -> AudioStream:
	if _streams.has(key):
		return _streams[key] as AudioStream
	var s: AudioStreamWAV = null
	match key:
		"slash_flesh":
			s = _synth_slash_flesh()
		"bone_crunch":
			s = _synth_crunch(0.24, 7)
		"splat":
			s = _synth_splat(0.28)
		"whoosh_light":
			s = _synth_whoosh(0.18, 1400.0, 3200.0, 0.30)
		"whoosh_heavy":
			s = _synth_whoosh(0.34, 500.0, 1800.0, 0.42)
		"clang":
			s = _synth_clang(0.42)
		"thud":
			s = _synth_thud(0.30, 85.0, 38.0)
		"land_heavy":
			s = _synth_thud(0.42, 70.0, 30.0)
		"gib_burst":
			s = _mix(_synth_crunch(0.32, 11), _synth_splat(0.34), 0.8, 0.9)
		# --- ambient life ---
		"caw":
			s = _synth_caw()
		"squeak":
			s = _synth_chirp(0.09, 2600.0, 3600.0, 0.28, 2)
		"chirp":
			s = _synth_chirp(0.06, 3400.0, 4800.0, 0.2, 3)
		"chime":
			s = _synth_chime()
		"flutter":
			s = _synth_crunch(0.18, 9)
		"spore_puff":
			s = _synth_whoosh(0.4, 300.0, 900.0, 0.22)
		_:
			return null
	_streams[key] = s
	return s


func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		bytes.encode_s16(i * 2, int(round(clampf(samples[i], -0.98, 0.98) * 32767.0)))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


func _buffer(duration: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(maxi(64, int(duration * SAMPLE_RATE)))
	return b


func _synth_slash_flesh() -> AudioStreamWAV:
	# Wet high "shk" (band-limited noise) + low meaty thump.
	var b: PackedFloat32Array = _buffer(0.22)
	var lp: float = 0.0
	var lp2: float = 0.0
	var phase: float = 0.0
	for i in range(b.size()):
		var t: float = float(i) / float(b.size())
		var n: float = _rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.55
		lp2 += (lp - lp2) * 0.08
		var band: float = lp - lp2
		var env_hi: float = pow(1.0 - t, 3.2) * minf(1.0, float(i) / 30.0)
		phase += TAU * lerpf(140.0, 55.0, t) / SAMPLE_RATE
		var thump: float = sin(phase) * pow(1.0 - t, 4.0)
		b[i] = band * 1.6 * env_hi + thump * 0.55
	return _to_wav(b)


func _synth_crunch(duration: float, clicks: int) -> AudioStreamWAV:
	var b: PackedFloat32Array = _buffer(duration)
	for c in range(clicks):
		var start: int = int(_rng.randf_range(0.0, 0.7) * b.size())
		var length: int = int(_rng.randf_range(0.008, 0.03) * SAMPLE_RATE)
		var amp: float = _rng.randf_range(0.35, 0.8) * (1.0 - float(start) / b.size())
		var lp: float = 0.0
		var cut: float = _rng.randf_range(0.25, 0.7)
		for k in range(length):
			var idx: int = start + k
			if idx >= b.size():
				break
			lp += (_rng.randf_range(-1.0, 1.0) - lp) * cut
			b[idx] += lp * amp * pow(1.0 - float(k) / length, 2.0)
	return _to_wav(b)


func _synth_splat(duration: float) -> AudioStreamWAV:
	var b: PackedFloat32Array = _buffer(duration)
	var lp: float = 0.0
	for i in range(b.size()):
		var t: float = float(i) / float(b.size())
		var cutoff: float = lerpf(0.35, 0.04, t) * (0.8 + 0.2 * sin(t * 90.0))
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * cutoff
		b[i] = lp * 1.9 * pow(1.0 - t, 2.2) * minf(1.0, float(i) / 60.0)
	return _to_wav(b)


func _synth_whoosh(duration: float, f_start: float, f_peak: float, amp: float) -> AudioStreamWAV:
	var b: PackedFloat32Array = _buffer(duration)
	var lp: float = 0.0
	var lp2: float = 0.0
	for i in range(b.size()):
		var t: float = float(i) / float(b.size())
		var f: float = lerpf(f_start, f_peak, sin(t * PI))
		var a1: float = clampf(TAU * f / SAMPLE_RATE, 0.01, 0.95)
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * a1
		lp2 += (lp - lp2) * a1 * 0.25
		var env: float = pow(sin(t * PI), 1.6)
		b[i] = (lp - lp2) * env * amp * 3.0
	return _to_wav(b)


func _synth_clang(duration: float) -> AudioStreamWAV:
	var b: PackedFloat32Array = _buffer(duration)
	var partials: Array[float] = [1.0, 2.76, 5.40, 8.93]
	var base_f: float = 820.0
	for i in range(b.size()):
		var t: float = float(i) / float(b.size())
		var tsec: float = float(i) / SAMPLE_RATE
		var v: float = 0.0
		for p_idx in range(partials.size()):
			v += sin(TAU * base_f * partials[p_idx] * tsec) * (0.5 / (p_idx + 1)) * exp(-tsec * (6.0 + p_idx * 5.0))
		var click: float = _rng.randf_range(-1.0, 1.0) * maxf(0.0, 1.0 - float(i) / 220.0)
		b[i] = v * 0.7 * (1.0 - t) + click * 0.5
	return _to_wav(b)


func _synth_thud(duration: float, f0: float, f1: float) -> AudioStreamWAV:
	var b: PackedFloat32Array = _buffer(duration)
	var phase: float = 0.0
	var lp: float = 0.0
	for i in range(b.size()):
		var t: float = float(i) / float(b.size())
		phase += TAU * lerpf(f0, f1, sqrt(t)) / SAMPLE_RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.12
		b[i] = (sin(phase) * 0.85 + lp * 0.6) * pow(1.0 - t, 2.6) * minf(1.0, float(i) / 40.0)
	return _to_wav(b)


func _synth_caw() -> AudioStreamWAV:
	# Harsh nasal "kraa": buzzy pulse with a falling pitch and noisy grit.
	var b: PackedFloat32Array = _buffer(0.32)
	var phase: float = 0.0
	for i in range(b.size()):
		var t: float = float(i) / float(b.size())
		var f: float = lerpf(720.0, 520.0, t) * (1.0 + 0.04 * sin(t * 90.0))
		phase += f / SAMPLE_RATE
		var saw: float = fmod(phase, 1.0) * 2.0 - 1.0
		var pulse: float = 1.0 if fmod(phase, 1.0) < 0.3 else -0.4
		var env: float = sin(clampf(t * 1.15, 0.0, 1.0) * PI) * minf(1.0, float(i) / 200.0)
		b[i] = (saw * 0.45 + pulse * 0.35 + _rng.randf_range(-0.25, 0.25)) * env * 0.42
	return _to_wav(b)


func _synth_chirp(duration: float, f0: float, f1: float, amp: float, notes: int) -> AudioStreamWAV:
	var b: PackedFloat32Array = _buffer(duration * notes + 0.04 * (notes - 1))
	var note_len: int = int(duration * SAMPLE_RATE)
	var gap: int = int(0.04 * SAMPLE_RATE)
	for n in range(notes):
		var start: int = n * (note_len + gap)
		var phase: float = 0.0
		var pitch_k: float = 1.0 + 0.08 * n
		for k in range(note_len):
			var idx: int = start + k
			if idx >= b.size():
				break
			var t: float = float(k) / note_len
			phase += TAU * lerpf(f0, f1, t) * pitch_k / SAMPLE_RATE
			b[idx] = sin(phase) * sin(t * PI) * amp
	return _to_wav(b)


func _synth_chime() -> AudioStreamWAV:
	# Soft glassy bell: two detuned partials, long gentle decay.
	var b: PackedFloat32Array = _buffer(0.9)
	var base_f: float = 1318.5
	for i in range(b.size()):
		var tsec: float = float(i) / SAMPLE_RATE
		var env: float = exp(-tsec * 4.5) * minf(1.0, float(i) / 120.0)
		b[i] = (sin(TAU * base_f * tsec) * 0.5 + sin(TAU * base_f * 2.01 * tsec) * 0.25 + sin(TAU * base_f * 2.99 * tsec) * 0.1) * env * 0.35
	return _to_wav(b)


func _mix(a: AudioStreamWAV, b: AudioStreamWAV, ga: float, gb: float) -> AudioStreamWAV:
	var da: PackedByteArray = a.data
	var db: PackedByteArray = b.data
	var n: int = maxi(da.size(), db.size()) / 2
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var va: float = float(da.decode_s16(i * 2)) / 32767.0 if i * 2 + 1 < da.size() else 0.0
		var vb: float = float(db.decode_s16(i * 2)) / 32767.0 if i * 2 + 1 < db.size() else 0.0
		out[i] = va * ga + vb * gb
	return _to_wav(out)
