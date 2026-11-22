class_name AudioManager
extends Node
## Signal-driven audio router for PARALLAX (GDD Section 10.4).
## - Buses: Master, Music, SFX, Ambience (created if missing).
## - SFX "banks": every folder under res://assets/audio/sfx/<group>/<bank>/ becomes an AudioStreamRandomizer
##   (random clip, no repeats, pitch/volume jitter). play_sfx(key) prefers a bank, falls back to the legacy
##   procedural .wav cues in SFX_PATHS, then to tiny synth stand-ins.
## - Adaptive music: explore / interior / combat / boss / ending tracks, equal-power crossfade between two players.
## - Enemy vocals: a positional "Voice" AudioStreamPlayer3D is attached to every EnemyBase (idle growls, alert/attack
##   barks, hurt, death) chosen by type (Skeleton / Phantom / ShieldedGuard / Warden).
## - Fire crackle loops are attached to every "BrazierLight"; an interior room tone plays inside the tower/hall band.
## Weather loops (rain/wind/thunder) live in WeatherDirector.

signal sfx_played(sfx_key: String)
signal music_state_changed(is_playing: bool)
signal music_track_changed(track: String)

const MUSIC_DRONE_PATH: String = "res://assets/audio/music/colosseum_drone_loop.wav"
const BANK_ROOT: String = "res://assets/audio/sfx/"
const AMBIENCE_DIR: String = "res://assets/audio/ambience/"

const MUSIC_TRACKS: Dictionary = {
	"explore": "res://assets/audio/music/journey_explore.mp3",
	"interior": "res://assets/audio/music/interior_explore.ogg",
	"combat": "res://assets/audio/music/combat_war.ogg",
	"boss": "res://assets/audio/music/boss_epic_loop.wav",
	"ending": "res://assets/audio/music/ending_fallen_dawn.wav",
}
## Per-track trim so the mix sits consistently (dB).
const MUSIC_TRIM: Dictionary = {"explore": -4.0, "interior": -2.0, "combat": -5.0, "boss": -4.0, "ending": -3.0, "drone": 0.0}

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

## Gameplay cue -> bank name (folder path below BANK_ROOT). Missing banks fall back to SFX_PATHS.
const CUE_BANKS: Dictionary = {
	"sword_light": "player/sword_light",
	"sword_heavy": "player/sword_heavy",
	"landing_slam": "combat/landing_slam",
	"enemy_hit": "combat/hit_flesh",
	"hit_bone": "combat/hit_bone",
	"hit_metal": "combat/hit_metal",
	"shield_deflect": "combat/shield_block",
	"body_fall": "combat/body_fall",
	"pillar_crack": "world/stone_crack",
	"pillar_collapse": "world/stone_collapse",
	"glass_shatter": "world/glass_shatter",
	"gate_open": "world/gate_iron",
	"switch": "world/switch",
	"mirror_whisper": "world/mirror_whisper",
	"footstep": "player/footstep_stone",
	"footstep_sand": "player/footstep_sand",
	"footstep_wet": "player/footstep_wet",
	"armor_foley": "player/armor_foley",
	"dodge": "player/dodge",
	"jump": "player/dodge",
	"player_hurt": "player/hurt",
	"attack_shout": "player/attack_shout",
	"player_death": "player/death",
	"ui_click": "ui/click",
	"ui_confirm": "ui/confirm",
	"ui_back": "ui/back",
}
## Per-cue playback trim (dB).
const CUE_DB: Dictionary = {
	"footstep": -11.0, "footstep_sand": -11.0, "footstep_wet": -10.0, "armor_foley": -20.0, "dodge": -6.0, "jump": -9.0,
	"sword_light": -4.0, "sword_heavy": -2.0, "attack_shout": -9.0, "enemy_hit": -2.0, "hit_bone": -3.0, "hit_metal": -5.0,
	"player_hurt": -4.0, "ui_click": -8.0, "body_fall": -4.0, "mirror_whisper": -6.0,
}

@export var auto_start_music: bool = true
@export var sfx_pool_size: int = 14
@export var music_crossfade_sec: float = 2.5
@export var enemy_idle_vocal_interval: Vector2 = Vector2(5.0, 11.0)

@export_group("Dynamic Mix (Claude Pass C)")
@export var music_base_db: float = -3.0
@export var combat_duck_db: float = -4.0
@export var duck_speed_db_per_sec: float = 10.0
@export var lowpass_open_hz: float = 20500.0
@export var lowpass_paused_hz: float = 700.0
@export var lowpass_low_hp_hz: float = 1400.0
@export var low_hp_threshold: int = 25
@export var lowpass_smoothing: float = 8.0

static var instance: AudioManager = null

var last_played_sfx: String = ""
var played_sfx_history: Array[String] = []
var is_music_playing: bool = false
var current_track: String = ""

var _sfx_streams: Dictionary = {}
var _banks: Dictionary = {}   # bank name -> AudioStreamRandomizer
var _music_player: AudioStreamPlayer = null   # currently audible music player
var _music_players: Array[AudioStreamPlayer] = []
var _music_fade: float = 1.0
var _music_eval_timer: float = 0.0
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0
var _footstep_timer: float = 0.0
var _foley_toggle: bool = false
var _tracked_player: WeakRef = null
var _warden_dead: bool = false
var _room_tone: AudioStreamPlayer = null
var _voices: Array = []   # [WeakRef(enemy), AudioStreamPlayer3D, kind, next_idle_time]
var _cue_cooldowns: Dictionary = {}

var is_music_ducked: bool = false
var current_lowpass_hz: float = 20500.0
var _player_hp: int = 100
var _lowpass: AudioEffectLowPassFilter = null
var _lowpass_effect_idx: int = -1


func _enter_tree() -> void:
	if instance == null or not is_instance_valid(instance):
		instance = self


func _exit_tree() -> void:
	if is_inside_tree() and get_tree() != null:
		if get_tree().node_added.is_connected(_bind_recursive):
			get_tree().node_added.disconnect(_bind_recursive)
	if instance == self:
		instance = null
		_release_master_lowpass()
	for mp in _music_players:
		if is_instance_valid(mp):
			mp.stop()
			mp.stream = null
	_music_players.clear()
	for sp in _sfx_players:
		if is_instance_valid(sp):
			sp.stop()
			sp.stream = null
	_sfx_players.clear()
	_sfx_streams.clear()
	_banks.clear()
	_voices.clear()
	_music_player = null
	_tracked_player = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if instance != null and instance != self and is_instance_valid(instance):
		return
	add_to_group("audio_manager")
	_ensure_buses()
	_load_streams()
	_build_players()
	instance = self
	bind_singletons()
	_ensure_master_lowpass()
	if is_inside_tree() and get_tree() != null:
		if not get_tree().node_added.is_connected(_bind_recursive):
			get_tree().node_added.connect(_bind_recursive)
	call_deferred("_deferred_bind_tree")
	if auto_start_music:
		start_ambient_drone()


func _deferred_bind_tree() -> void:
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		bind_to_world(get_tree().root)


func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


func _process(delta: float) -> void:
	if instance != self:
		return
	var real_dt: float = minf(delta / maxf(Engine.time_scale, 0.01), 0.1)
	_update_dynamic_mix(real_dt)
	_update_music(real_dt)
	if is_inside_tree() and get_tree() != null and get_tree().paused:
		return
	var pc: PlayerController = _get_player()
	_update_voices()
	_update_room_tone(pc, real_dt)
	if pc == null:
		_footstep_timer = 0.0
		return
	var horiz_speed: float = Vector2(pc.velocity.x, pc.velocity.z).length()
	if pc.is_on_floor() and pc.current_state == PlayerController.State.LOCOMOTION and horiz_speed > 2.2:
		_footstep_timer += delta
		# Cadence follows speed: ~0.42 s at a walk, ~0.30 s at a sprint.
		var interval: float = clampf(1.75 / horiz_speed, 0.27, 0.46)
		if _footstep_timer >= interval:
			_footstep_timer = 0.0
			play_sfx(_footstep_cue(pc))
			_foley_toggle = not _foley_toggle
			if _foley_toggle:
				play_sfx("armor_foley")
	else:
		_footstep_timer = 0.24


func _get_player() -> PlayerController:
	var pc: PlayerController = null
	if _tracked_player != null:
		pc = _tracked_player.get_ref() as PlayerController
	if pc == null or not is_instance_valid(pc):
		if is_inside_tree() and get_tree() != null:
			pc = get_tree().get_first_node_in_group("player") as PlayerController
			if pc != null:
				_tracked_player = weakref(pc)
	if pc == null or not is_instance_valid(pc) or not pc.is_inside_tree():
		return null
	return pc


func _footstep_cue(pc: PlayerController) -> String:
	var wd: Node = get_tree().get_first_node_in_group("weather_director") if is_inside_tree() else null
	var wet: float = float(wd.call("get_wetness")) if wd != null and wd.has_method("get_wetness") else 0.0
	if wet > 0.45:
		return "footstep_wet"
	# Sandy causeway / beach approach before the first gate.
	if JourneyLayout.story_z(pc.global_position.z) < -40.0:
		return "footstep_sand"
	return "footstep"


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
	_warden_dead = false
	_player_hp = 100
	_bind_recursive(root_node)


## Plays a cue (bank first, legacy wav second). Returns false if the cue is unknown.
func play_sfx(sfx_key: String, volume_offset_db: float = 0.0) -> bool:
	var stream: AudioStream = _cue_stream(sfx_key)
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
		player.volume_db = float(CUE_DB.get(sfx_key, 0.0)) + volume_offset_db
		if not _headless():
			player.play()
	sfx_played.emit(sfx_key)
	return true


func _cue_stream(sfx_key: String) -> AudioStream:
	var bank: String = String(CUE_BANKS.get(sfx_key, ""))
	if bank != "" and _banks.has(bank):
		return _banks[bank] as AudioStream
	if _banks.has(sfx_key):
		return _banks[sfx_key] as AudioStream
	return _sfx_streams.get(sfx_key, null) as AudioStream


func has_bank(bank: String) -> bool:
	return _banks.has(bank)


## Plays a bank positionally at a world point (one-shot node, auto-freed).
func play_at(bank_or_cue: String, world_pos: Vector3, volume_db: float = 0.0, max_distance: float = 40.0) -> void:
	var stream: AudioStream = _cue_stream(bank_or_cue)
	if stream == null or _headless() or not is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = &"SFX"
	p.volume_db = volume_db
	p.max_distance = max_distance
	p.unit_size = 6.0
	var host: Node = get_tree().current_scene if get_tree().current_scene != null else self
	host.add_child(p)
	p.global_position = world_pos
	p.finished.connect(p.queue_free)
	p.play()


# ---------------------------------------------------------------- Music

func start_ambient_drone() -> void:
	if instance != null and instance != self and is_instance_valid(instance) and instance.is_music_playing:
		return
	if _music_players.is_empty():
		return
	if current_track == "":
		_switch_track(_pick_track(), true)
	is_music_playing = true
	music_state_changed.emit(true)


func stop_ambient_drone() -> void:
	for mp in _music_players:
		if mp.playing:
			mp.stop()
	is_music_playing = false
	current_track = ""
	music_state_changed.emit(false)


var _music_cache: Dictionary = {}


func _track_stream(track: String) -> AudioStream:
	if _music_cache.has(track):
		return _music_cache[track] as AudioStream
	var path: String = String(MUSIC_TRACKS.get(track, MUSIC_DRONE_PATH))
	if not ResourceLoader.exists(path):
		path = MUSIC_DRONE_PATH
	if not ResourceLoader.exists(path):
		return null
	var st: AudioStream = _make_looping(load(path) as AudioStream)
	_music_cache[track] = st
	return st


static func _make_looping(stream: AudioStream) -> AudioStream:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		var w: AudioStreamWAV = stream as AudioStreamWAV
		if w.loop_mode == AudioStreamWAV.LOOP_DISABLED or w.loop_end <= w.loop_begin:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * float(w.mix_rate))
	return stream


func _pick_track() -> String:
	if _warden_dead:
		return "ending"
	var ed: EncounterDirector = EncounterDirector.instance as EncounterDirector
	var pc: PlayerController = _get_player()
	var z: float = JourneyLayout.story_z(pc.global_position.z) if pc != null else -60.0
	if ed != null and int(ed.current_section) == int(EncounterDirector.Section.EXECUTION_ARENA):
		return "boss"
	if is_in_combat():
		return "combat"
	if z >= 44.0:
		return "interior"
	return "explore"


func _switch_track(track: String, instant: bool = false) -> void:
	if track == current_track or _music_players.size() < 2:
		return
	var stream: AudioStream = _track_stream(track)
	if stream == null:
		return
	var next: AudioStreamPlayer = _music_players[0] if _music_player == _music_players[1] else _music_players[1]
	if _music_player != null and _music_player.stream == stream:
		current_track = track
		return
	next.stream = stream
	next.set_meta("trim", float(MUSIC_TRIM.get(track, 0.0)))
	next.volume_db = -80.0
	if not _headless():
		next.play()
	_music_player = next
	_music_fade = 1.0 if instant else 0.0
	current_track = track
	music_track_changed.emit(track)


func _update_music(real_dt: float) -> void:
	if not is_music_playing or _music_players.size() < 2:
		return
	_music_eval_timer -= real_dt
	if _music_eval_timer <= 0.0:
		_music_eval_timer = 0.5
		_switch_track(_pick_track())
	_music_fade = minf(1.0, _music_fade + real_dt / maxf(0.1, music_crossfade_sec))
	var duck: float = combat_duck_db if (is_music_ducked and current_track != "combat" and current_track != "boss") else 0.0
	for mp in _music_players:
		var w: float = _music_fade if mp == _music_player else 1.0 - _music_fade
		w = sin(w * PI * 0.5)   # equal-power
		if mp != _music_player and w <= 0.001:
			if mp.playing:
				mp.stop()
			continue
		mp.volume_db = music_base_db + duck + float(mp.get_meta("trim", 0.0)) + linear_to_db(maxf(w, 0.0001))


# ---------------------------------------------------------------- Ambience

func _update_room_tone(pc: PlayerController, real_dt: float) -> void:
	if _room_tone == null:
		return
	var target: float = 0.0
	if pc != null:
		var z: float = JourneyLayout.story_z(pc.global_position.z)
		# Enclosed hall / tower interior band (story z).
		if z > 52.0 and z < 104.0:
			target = 1.0
	var cur: float = db_to_linear(_room_tone.volume_db + 8.0)
	cur = move_toward(cur, target, real_dt * 0.5)
	_room_tone.volume_db = linear_to_db(maxf(cur, 0.0001)) - 8.0


func _attach_fire(light: Node3D) -> void:
	if light.get_node_or_null("FireCrackle") != null or not _banks.has("ambience/fire"):
		return
	var p := AudioStreamPlayer3D.new()
	p.name = "FireCrackle"
	p.stream = _banks["ambience/fire"]
	p.bus = &"Ambience"
	p.volume_db = -10.0
	p.unit_size = 2.0
	p.max_distance = 14.0
	p.autoplay = not _headless()
	light.add_child(p)


# ---------------------------------------------------------------- Enemy voices

func _enemy_kind(e: EnemyBase) -> String:
	if e is WardenBoss:
		return "warden"
	if e is ShieldedGuard:
		return "guard"
	if e is PhantomTwin:
		return "phantom"
	return "skeleton"


func _attach_voice(e: EnemyBase) -> void:
	if e.get_node_or_null("Voice") != null:
		return
	var kind: String = _enemy_kind(e)
	var v := AudioStreamPlayer3D.new()
	v.name = "Voice"
	v.bus = &"SFX"
	v.unit_size = 9.0 if kind == "warden" else 4.0
	v.max_distance = 70.0 if kind == "warden" else 30.0
	v.volume_db = 2.0 if kind == "warden" else -2.0
	v.position = Vector3(0, 1.6, 0)
	e.add_child(v)
	_voices.append([weakref(e), v, kind, Time.get_ticks_msec() * 0.001 + randf_range(2.0, 8.0)])
	if e.has_signal("alerted"):
		e.connect("alerted", func(_by: Node) -> void: _enemy_vocal(e, "attack"))
	if e.has_signal("attack_telegraphed"):
		e.connect("attack_telegraphed", func(_n: String, _w: float) -> void: _enemy_vocal(e, "attack", 0.55))
	e.died.connect(func(_en: Node, _ctx: Dictionary) -> void:
		_enemy_vocal(e, "death", 0.0, true)
		if is_instance_valid(e):
			play_at("body_fall", e.global_position, -2.0))
	if e is WardenBoss:
		var wb: WardenBoss = e as WardenBoss
		wb.boss_phase_changed.connect(func(_p: int) -> void: _enemy_vocal(e, "roar", 0.0, true))
		wb.boss_defeated.connect(func() -> void: _warden_dead = true)
		wb.health_changed.connect(func(hp: int, max_hp: int) -> void:
			if hp >= max_hp:
				_warden_dead = false)


func _enemy_vocal(e: EnemyBase, cue: String, chance: float = 1.0, force: bool = false) -> void:
	if e == null or not is_instance_valid(e) or not e.is_inside_tree() or _headless():
		return
	if chance < 1.0 and randf() > chance:
		return
	var v: AudioStreamPlayer3D = e.get_node_or_null("Voice") as AudioStreamPlayer3D
	if v == null or not v.is_inside_tree():
		return
	var bank: String = "enemy/%s_%s" % [_enemy_kind(e), cue]
	if not _banks.has(bank):
		return
	if v.playing and not force:
		return
	v.stream = _banks[bank]
	v.play()


func _update_voices() -> void:
	if _voices.is_empty() or _headless():
		return
	var now: float = Time.get_ticks_msec() * 0.001
	for i in range(_voices.size() - 1, -1, -1):
		var entry: Array = _voices[i]
		var e: EnemyBase = (entry[0] as WeakRef).get_ref() as EnemyBase
		if e == null or not is_instance_valid(e) or not e.is_inside_tree():
			_voices.remove_at(i)
			continue
		if now < float(entry[3]):
			continue
		entry[3] = now + randf_range(enemy_idle_vocal_interval.x, enemy_idle_vocal_interval.y)
		if e.is_active and not e.is_dead and e.is_visible_in_tree():
			_enemy_vocal(e, "idle")


# ---------------------------------------------------------------- Binding

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
		if pc.has_signal("player_died") and not pc.is_connected("player_died", _on_player_died):
			pc.connect("player_died", _on_player_died)
		if pc.has_signal("landed") and not pc.is_connected("landed", _on_player_landed):
			pc.connect("landed", _on_player_landed)
		if not pc.health_changed.is_connected(_on_player_health_changed):
			pc.health_changed.connect(_on_player_health_changed)
		_player_hp = pc.health
	elif node is BaseButton:
		var btn: BaseButton = node as BaseButton
		if not btn.pressed.is_connected(_on_ui_button_pressed):
			btn.pressed.connect(_on_ui_button_pressed)
	elif node is EnemyBase:
		var eb: EnemyBase = node as EnemyBase
		if not eb.damaged.is_connected(_on_enemy_damaged.bind(eb)):
			eb.damaged.connect(_on_enemy_damaged.bind(eb))
		_attach_voice(eb)
		if node is ShieldedGuard:
			var sg: ShieldedGuard = node as ShieldedGuard
			if not sg.shield_deflected.is_connected(_on_shield_deflected):
				sg.shield_deflected.connect(_on_shield_deflected)
		if node is WardenBoss:
			var wb: WardenBoss = node as WardenBoss
			if wb.is_dead:
				_warden_dead = true
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
	elif node is OmniLight3D and String(node.name).begins_with("BrazierLight"):
		_attach_fire(node as Node3D)

	for child in node.get_children():
		_bind_recursive(child)


func _on_realm_changed(new_realm: int) -> void:
	if new_realm == RealmManager.Realm.MIRROR:
		play_sfx("shift_to_mirror")
		play_sfx("mirror_whisper", -4.0)
	else:
		play_sfx("shift_to_reality")


func _on_shift_rejected(_reason: String) -> void:
	play_sfx("shift_rejected")


func _on_realms_merged() -> void:
	play_sfx("mirror_shatter")
	play_sfx("glass_shatter")


func _on_player_attack_executed(_attack_name: String, combo_step: int, _damage: int, is_heavy: bool) -> void:
	if is_heavy:
		play_sfx("sword_heavy")
		play_sfx("attack_shout", -2.0)
	else:
		play_sfx("sword_light")
		if combo_step >= 3 and randf() < 0.5:
			play_sfx("attack_shout", -5.0)


func _on_player_landing_slam(_pos: Vector3, _radius: float, _dmg: int) -> void:
	play_sfx("landing_slam")


func _on_player_jumped() -> void:
	play_sfx("jump")


func _on_player_dodge_started(_dir: Vector3, _dur: float = 0.0) -> void:
	play_sfx("dodge")


func _on_player_damaged(_amount: int) -> void:
	play_sfx("player_hurt")


func _on_player_died() -> void:
	play_sfx("player_death")


func _on_player_landed(impact_speed: float) -> void:
	if impact_speed > 7.0:
		play_sfx(_footstep_cue(_get_player()) if _get_player() != null else "footstep", 4.0)
		play_sfx("armor_foley", 6.0)


func _on_player_health_changed(current_hp: int, _max_hp: int) -> void:
	_player_hp = current_hp


# --- Dynamic mix: combat ducking + Master low-pass (Claude Pass C) ---

func is_in_combat() -> bool:
	var ed: EncounterDirector = EncounterDirector.instance as EncounterDirector
	return ed != null and not ed.current_encounter_id.is_empty()


func get_target_lowpass_hz() -> float:
	if is_inside_tree() and get_tree() != null and get_tree().paused:
		return lowpass_paused_hz
	if _player_hp > 0 and _player_hp < low_hp_threshold:
		return lowpass_low_hp_hz
	return lowpass_open_hz


func _update_dynamic_mix(real_dt: float) -> void:
	is_music_ducked = is_in_combat()
	var target_hz: float = get_target_lowpass_hz()
	var cur_log: float = log(maxf(current_lowpass_hz, 20.0))
	var tgt_log: float = log(maxf(target_hz, 20.0))
	cur_log = lerpf(cur_log, tgt_log, clampf(lowpass_smoothing * real_dt, 0.0, 1.0))
	current_lowpass_hz = exp(cur_log)
	if absf(current_lowpass_hz - target_hz) < 1.0:
		current_lowpass_hz = target_hz
	_apply_lowpass(current_lowpass_hz)


func _ensure_master_lowpass() -> void:
	var master_idx: int = AudioServer.get_bus_index("Master")
	if master_idx < 0:
		return
	for i in range(AudioServer.get_bus_effect_count(master_idx)):
		var fx: AudioEffect = AudioServer.get_bus_effect(master_idx, i)
		if fx is AudioEffectLowPassFilter and fx.resource_name == "ParallaxDynamicLowPass":
			_lowpass = fx as AudioEffectLowPassFilter
			_lowpass_effect_idx = i
			break
	if _lowpass == null:
		_lowpass = AudioEffectLowPassFilter.new()
		_lowpass.resource_name = "ParallaxDynamicLowPass"
		_lowpass.resonance = 0.5
		AudioServer.add_bus_effect(master_idx, _lowpass)
		_lowpass_effect_idx = AudioServer.get_bus_effect_count(master_idx) - 1
	current_lowpass_hz = lowpass_open_hz
	_apply_lowpass(current_lowpass_hz)


func _apply_lowpass(hz: float) -> void:
	if _lowpass == null:
		return
	_lowpass.cutoff_hz = hz
	var master_idx: int = AudioServer.get_bus_index("Master")
	if master_idx >= 0 and _lowpass_effect_idx >= 0 and _lowpass_effect_idx < AudioServer.get_bus_effect_count(master_idx):
		AudioServer.set_bus_effect_enabled(master_idx, _lowpass_effect_idx, hz < lowpass_open_hz - 1.0)


func _release_master_lowpass() -> void:
	if _lowpass == null:
		return
	current_lowpass_hz = lowpass_open_hz
	_apply_lowpass(lowpass_open_hz)
	_lowpass = null


func _on_ui_button_pressed() -> void:
	play_sfx("ui_click")


func _on_enemy_damaged(_amount: int, is_heavy: bool, _source_type: String, enemy: EnemyBase = null) -> void:
	var kind: String = _enemy_kind(enemy) if enemy != null and is_instance_valid(enemy) else ""
	play_sfx("enemy_hit", 2.0 if is_heavy else 0.0)
	match kind:
		"skeleton":
			play_sfx("hit_bone")
		"guard", "warden":
			play_sfx("hit_metal", -3.0)
	if enemy != null:
		_enemy_vocal(enemy, "hurt", 0.7 if kind != "warden" else 0.45)


func _on_shield_deflected(_is_heavy: bool) -> void:
	play_sfx("shield_deflect")


func _on_mirror_plane_shattered() -> void:
	play_sfx("mirror_shatter")
	play_sfx("glass_shatter")


func _on_prop_warning(_warning_sec: float) -> void:
	play_sfx("pillar_crack")


func _on_prop_broken(prop: Node) -> void:
	if prop != null and int(prop.get("prop_kind")) == BreakableProp.PropKind.CENTRAL_MIRROR_PLANE:
		play_sfx("mirror_shatter")
		play_sfx("glass_shatter")
	else:
		play_sfx("pillar_collapse")


func _on_gate_opened(_gate: Node) -> void:
	play_sfx("gate_open")


func _ensure_buses() -> void:
	for bus_name in ["Music", "SFX", "Ambience"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			var idx: int = AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


## Builds one AudioStreamRandomizer per sfx/<group>/<bank>/ folder, plus a few ambience loops.
func _load_streams() -> void:
	_sfx_streams.clear()
	_banks.clear()
	for k in SFX_PATHS.keys():
		var path: String = String(SFX_PATHS[k])
		if ResourceLoader.exists(path):
			_sfx_streams[k] = load(path)
	for group in _list_dirs(BANK_ROOT):
		for bank in _list_dirs(BANK_ROOT + group + "/"):
			var rnd: AudioStreamRandomizer = _build_bank(BANK_ROOT + group + "/" + bank + "/", group)
			if rnd != null:
				_banks[group + "/" + bank] = rnd
	var fire: String = AMBIENCE_DIR + "fire_loop.wav"
	if ResourceLoader.exists(fire):
		_banks["ambience/fire"] = _make_looping(load(fire) as AudioStream)
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


func _list_dirs(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not path.begins_with("res://") and not DirAccess.dir_exists_absolute(path):
		return out
	for entry in ResourceLoader.list_directory(path):
		if entry.ends_with("/"):
			out.append(entry.trim_suffix("/"))
	return out


func _build_bank(dir: String, group: String) -> AudioStreamRandomizer:
	var rnd := AudioStreamRandomizer.new()
	rnd.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	# Voices tolerate less pitch drift than impacts/footsteps.
	rnd.random_pitch = 1.06 if group == "enemy" else 1.12
	rnd.random_volume_offset_db = 2.0
	var i: int = 0
	for entry in ResourceLoader.list_directory(dir):
		if entry.ends_with("/"):
			continue
		var ext: String = entry.get_extension().to_lower()
		if ext not in ["ogg", "wav", "mp3"]:
			continue
		var s: AudioStream = load(dir + entry) as AudioStream
		if s == null:
			continue
		rnd.add_stream(i, s, 1.0)
		i += 1
	return rnd if i > 0 else null


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
	for i in range(2):
		var mp := AudioStreamPlayer.new()
		mp.name = "MusicPlayer" if i == 0 else "MusicPlayerB"
		mp.bus = "Music"
		mp.volume_db = -80.0
		add_child(mp)
		_music_players.append(mp)
	_music_player = _music_players[0]
	# Legacy drone stays on player A until the first track pick.
	if ResourceLoader.exists(MUSIC_DRONE_PATH):
		_music_player.stream = load(MUSIC_DRONE_PATH)

	var tone_path: String = AMBIENCE_DIR + "interior_room_tone.ogg"
	if ResourceLoader.exists(tone_path):
		_room_tone = AudioStreamPlayer.new()
		_room_tone.name = "RoomTone"
		_room_tone.bus = "Ambience"
		_room_tone.stream = _make_looping(load(tone_path) as AudioStream)
		_room_tone.volume_db = -80.0
		_room_tone.autoplay = not _headless()
		add_child(_room_tone)

	for i in range(maxi(1, sfx_pool_size)):
		var sp := AudioStreamPlayer.new()
		sp.name = "SFXPlayer_%d" % i
		sp.bus = "SFX"
		add_child(sp)
		_sfx_players.append(sp)
