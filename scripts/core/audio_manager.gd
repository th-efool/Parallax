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

var last_played_sfx: String = ""
var played_sfx_history: Array[String] = []
var is_music_playing: bool = false

var _sfx_streams: Dictionary = {}
var _music_player: AudioStreamPlayer = null
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0


func _exit_tree() -> void:
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("audio_manager")
	_ensure_buses()
	_load_streams()
	_build_players()
	bind_singletons()
	if auto_start_music:
		start_ambient_drone()


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
		if not pc.attack_executed.is_connected(_on_player_attack_executed):
			pc.attack_executed.connect(_on_player_attack_executed)
		if not pc.landing_slam_triggered.is_connected(_on_player_landing_slam):
			pc.landing_slam_triggered.connect(_on_player_landing_slam)
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
