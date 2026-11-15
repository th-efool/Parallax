class_name AudioManager
extends Node
## Signal-driven audio router for PARALLAX (GDD Section 10.4):
## Ensures `Master`, `Music`, and `SFX` buses exist, plays `colosseum_drone_loop.wav` on the `Music` bus,
## and connects gameplay signals (`RealmManager`, `PlayerController`, `EnemyBase`, `ShieldedGuard`, `WardenBoss`,
## `BreakableProp`, `EncounterGate`) to the 12 procedural `.wav` SFX cues.

signal sfx_played(sfx_key: String)
signal music_state_changed(is_playing: bool)

const MUSIC_DRONE_PATH: String = "res://assets/audio/music/colosseum_drone_loop.wav"

const SFX_PATHS: Dictionary = {
	"shift_to_mirror": "res://assets/audio/sfx/shift_to_mirror.wav",
	"shift_to_reality": "res://assets/audio/sfx/shift_to_reality.wav",
	"shift_rejected": "res://assets/audio/sfx/shift_rejected.wav",
	"sword_light": "res://assets/audio/sfx/sword_light.wav",
	"sword_heavy": "res://assets/audio/sfx/sword_heavy.wav",
	"landing_slam": "res://assets/audio/sfx/landing_slam.wav",
	"enemy_hit": "res://assets/audio/sfx/enemy_hit.wav",
	"shield_deflect": "res://assets/audio/sfx/shield_deflect.wav",
	"pillar_crack": "res://assets/audio/sfx/pillar_crack.wav",
	"pillar_collapse": "res://assets/audio/sfx/pillar_collapse.wav",
	"mirror_shatter": "res://assets/audio/sfx/mirror_shatter.wav",
	"gate_open": "res://assets/audio/sfx/gate_open.wav",
}

@export var auto_start_music: bool = true
@export var sfx_pool_size: int = 8

static var instance: AudioManager = null

var last_played_sfx: String = ""
var played_sfx_history: Array[String] = []
var is_music_playing: bool = false

var _sfx_streams: Dictionary = {}
var _music_player: AudioStreamPlayer = null
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0
var _footstep_timer: float = 0.0
var _tracked_player: WeakRef = null


func _enter_tree() -> void:
	if instance == null or not is_instance_valid(instance):
		instance = self


func _exit_tree() -> void:
	if is_inside_tree() and get_tree() != null:
		if get_tree().node_added.is_connected(_bind_recursive):
			get_tree().node_added.disconnect(_bind_recursive)
	if instance == self:
		instance = null
	if _music_player != null:
		_music_player.stop()
		_music_player.stream = null
	for sp in _sfx_players:
		if is_instance_valid(sp):
			sp.stop()
			sp.stream = null
	_sfx_players.clear()
	_sfx_streams.clear()
	_music_player = null
	_tracked_player = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("audio_manager")
	_ensure_buses()
	_load_streams()
	_build_players()
	if instance == null or not is_instance_valid(instance):
		instance = self
	bind_singletons()
	if instance == self:
		if is_inside_tree() and get_tree() != null:
			if not get_tree().node_added.is_connected(_bind_recursive):
				get_tree().node_added.connect(_bind_recursive)
		call_deferred("_deferred_bind_tree")
		if auto_start_music:
			start_ambient_drone()


func _deferred_bind_tree() -> void:
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		bind_to_world(get_tree().root)


func _process(delta: float) -> void:
	if instance != self:
		return
	if is_inside_tree() and get_tree() != null and get_tree().paused:
		return
	var pc: PlayerController = null
	if _tracked_player != null:
		pc = _tracked_player.get_ref() as PlayerController
	if pc == null or not is_instance_valid(pc):
		if is_inside_tree() and get_tree() != null:
			pc = get_tree().get_first_node_in_group("player") as PlayerController
			if pc != null:
				_tracked_player = weakref(pc)
	if pc == null or not is_instance_valid(pc) or not pc.is_inside_tree():
		_footstep_timer = 0.0
		return
	var horiz_speed: float = Vector2(pc.velocity.x, pc.velocity.z).length()
	if pc.is_on_floor() and pc.current_state == PlayerController.State.LOCOMOTION and horiz_speed > 2.2:
		_footstep_timer += delta
		if _footstep_timer >= 0.36:
			_footstep_timer = 0.0
			play_sfx("footstep")
	else:
		_footstep_timer = 0.24


func bind_singletons() -> void:
	var rm: RealmManager = RealmManager.instance as RealmManager
	if rm != null:
		if not rm.realm_changed.is_connected(_on_realm_changed):
			rm.realm_changed.connect(_on_realm_changed)
		if not rm.shift_rejected.is_connected(_on_shift_rejected):
			rm.shift_rejected.connect(_on_shift_rejected)
		if not rm.realms_merged.is_connected(_on_realms_merged):
			rm.realms_merged.connect(_on_realms_merged)


func bind_to_world(root_node: Node) -> void:
	bind_singletons()
	if root_node == null:
		return
	_bind_recursive(root_node)


func play_sfx(sfx_key: String) -> bool:
	if not _sfx_streams.has(sfx_key):
		return false
	var stream: AudioStream = _sfx_streams[sfx_key] as AudioStream
	if stream == null:
		return false

	last_played_sfx = sfx_key
	played_sfx_history.append(sfx_key)
	if played_sfx_history.size() > 64:
		played_sfx_history.pop_front()

	if not _sfx_players.is_empty():
		var player: AudioStreamPlayer = _sfx_players[_sfx_cursor % _sfx_players.size()]
		_sfx_cursor += 1
		player.stream = stream
		if DisplayServer.get_name() != "headless":
			player.play()

	sfx_played.emit(sfx_key)
	return true


func start_ambient_drone() -> void:
	if instance != null and instance != self and is_instance_valid(instance) and instance.is_music_playing:
		return
	if _music_player == null or _music_player.stream == null:
		return
	if DisplayServer.get_name() != "headless" and not _music_player.playing:
		_music_player.play()
	is_music_playing = true
	music_state_changed.emit(true)


func stop_ambient_drone() -> void:
	if _music_player != null and _music_player.playing:
		_music_player.stop()
	is_music_playing = false
	music_state_changed.emit(false)


func _bind_recursive(node: Node) -> void:
	if node is PlayerController:
		var pc: PlayerController = node as PlayerController
		_tracked_player = weakref(pc)
		if not pc.attack_executed.is_connected(_on_player_attack_executed):
			pc.attack_executed.connect(_on_player_attack_executed)
		if not pc.landing_slam_triggered.is_connected(_on_player_landing_slam):
			pc.landing_slam_triggered.connect(_on_player_landing_slam)
		if pc.has_signal("jumped") and not pc.is_connected("jumped", _on_player_jumped):
			pc.connect("jumped", _on_player_jumped)
		if pc.has_signal("dodge_started") and not pc.is_connected("dodge_started", _on_player_dodge_started):
			pc.connect("dodge_started", _on_player_dodge_started)
		if pc.has_signal("player_damaged") and not pc.is_connected("player_damaged", _on_player_damaged):
			pc.connect("player_damaged", _on_player_damaged)
	elif node is BaseButton:
		var btn: BaseButton = node as BaseButton
		if not btn.pressed.is_connected(_on_ui_button_pressed):
			btn.pressed.connect(_on_ui_button_pressed)
	elif node is EnemyBase:
		var eb: EnemyBase = node as EnemyBase
		if not eb.damaged.is_connected(_on_enemy_damaged):
			eb.damaged.connect(_on_enemy_damaged)
		if node is ShieldedGuard:
			var sg: ShieldedGuard = node as ShieldedGuard
			if not sg.shield_deflected.is_connected(_on_shield_deflected):
				sg.shield_deflected.connect(_on_shield_deflected)
		if node is WardenBoss:
			var wb: WardenBoss = node as WardenBoss
			if not wb.mirror_plane_shattered.is_connected(_on_mirror_plane_shattered):
				wb.mirror_plane_shattered.connect(_on_mirror_plane_shattered)
	elif node is BreakableProp:
		var bp: BreakableProp = node as BreakableProp
		if not bp.break_warning_started.is_connected(_on_prop_warning):
			bp.break_warning_started.connect(_on_prop_warning)
		if not bp.prop_broken.is_connected(_on_prop_broken):
			bp.prop_broken.connect(_on_prop_broken)
	elif node is EncounterGate:
		var eg: EncounterGate = node as EncounterGate
		if not eg.gate_opened.is_connected(_on_gate_opened):
			eg.gate_opened.connect(_on_gate_opened)

	for child in node.get_children():
		_bind_recursive(child)


func _on_realm_changed(new_realm: int) -> void:
	if new_realm == RealmManager.Realm.MIRROR:
		play_sfx("shift_to_mirror")
	else:
		play_sfx("shift_to_reality")


func _on_shift_rejected(_reason: String) -> void:
	play_sfx("shift_rejected")


func _on_realms_merged() -> void:
	play_sfx("mirror_shatter")


func _on_player_attack_executed(_attack_name: String, _combo_step: int, _damage: int, is_heavy: bool) -> void:
	if is_heavy:
		play_sfx("sword_heavy")
	else:
		play_sfx("sword_light")


func _on_player_landing_slam(_pos: Vector3, _radius: float, _dmg: int) -> void:
	play_sfx("landing_slam")


func _on_player_jumped() -> void:
	play_sfx("jump")


func _on_player_dodge_started(_dir: Vector3, _dur: float = 0.0) -> void:
	play_sfx("dodge")


func _on_player_damaged(_amount: int) -> void:
	play_sfx("player_hurt")


func _on_ui_button_pressed() -> void:
	play_sfx("ui_click")


func _on_enemy_damaged(_amount: int, _is_heavy: bool, _source_type: String) -> void:
	play_sfx("enemy_hit")


func _on_shield_deflected(_is_heavy: bool) -> void:
	play_sfx("shield_deflect")


func _on_mirror_plane_shattered() -> void:
	play_sfx("mirror_shatter")


func _on_prop_warning(_warning_sec: float) -> void:
	play_sfx("pillar_crack")


func _on_prop_broken(prop: Node) -> void:
	if prop != null and int(prop.get("prop_kind")) == BreakableProp.PropKind.CENTRAL_MIRROR_PLANE:
		play_sfx("mirror_shatter")
	else:
		play_sfx("pillar_collapse")


func _on_gate_opened(_gate: Node) -> void:
	play_sfx("gate_open")


func _ensure_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			var idx: int = AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func _load_streams() -> void:
	_sfx_streams.clear()
	for k in SFX_PATHS.keys():
		var path: String = String(SFX_PATHS[k])
		if ResourceLoader.exists(path):
			_sfx_streams[k] = load(path)
	if not _sfx_streams.has("jump"):
		_sfx_streams["jump"] = _make_synth_wav(0.14, 190.0, 420.0, 0.34, 0.15, 1.5)
	if not _sfx_streams.has("dodge"):
		_sfx_streams["dodge"] = _make_synth_wav(0.16, 480.0, 130.0, 0.32, 0.55, 1.8)
	if not _sfx_streams.has("player_hurt"):
		_sfx_streams["player_hurt"] = _make_synth_wav(0.18, 175.0, 72.0, 0.44, 0.30, 1.6)
	if not _sfx_streams.has("ui_click"):
		_sfx_streams["ui_click"] = _make_synth_wav(0.055, 760.0, 520.0, 0.25, 0.05, 2.4)
	if not _sfx_streams.has("footstep"):
		_sfx_streams["footstep"] = _make_synth_wav(0.065, 128.0, 58.0, 0.22, 0.60, 2.8)


func _make_synth_wav(duration_sec: float, freq_start: float, freq_end: float, amplitude: float = 0.35, noise_mix: float = 0.0, decay_pow: float = 1.8) -> AudioStreamWAV:
	var sample_rate: int = 22050
	var count: int = maxi(64, int(round(duration_sec * float(sample_rate))))
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var phase: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(count)
		var freq: float = lerpf(freq_start, freq_end, t)
		phase += TAU * freq / float(sample_rate)
		var tone: float = sin(phase)
		var noise: float = sin(float(i) * 12.9898 + float((i % 97) * 78.233))
		var env: float = pow(1.0 - t, decay_pow) * minf(1.0, float(i) / 48.0)
		var sample: float = clampf(lerpf(tone, noise, noise_mix) * amplitude * env, -0.95, 0.95)
		bytes.encode_s16(i * 2, int(round(sample * 32767.0)))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = bytes
	return wav


func _build_players() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = "Music"
	if ResourceLoader.exists(MUSIC_DRONE_PATH):
		_music_player.stream = load(MUSIC_DRONE_PATH)
	add_child(_music_player)

	for i in range(maxi(1, sfx_pool_size)):
		var sp := AudioStreamPlayer.new()
		sp.name = "SFXPlayer_%d" % i
		sp.bus = "SFX"
		add_child(sp)
		_sfx_players.append(sp)
