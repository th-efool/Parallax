class_name SquadTTSPlayer
extends Node
## Ally voices: one line at a time, queued by priority (a higher-priority line interrupts the current one).
## Engines (SquadAIConfig.voice_engine):
##   cloud  — provider TTS streamed as 24 kHz s16le mono PCM (Gemini native / OpenAI pcm) into an
##            AudioStreamGenerator.
##   system — OS text-to-speech (DisplayServer.tts_*; needs project setting audio/general/text_to_speech).
##            Instant and unlimited; each ally gets its own OS voice + pitch + rate.
##   auto   — cloud while it works; the first cloud failure switches the REST OF THE SESSION to system voices,
##            so voices stay consistent instead of going randomly silent.
##   off    — never speaks.
## Every line emits exactly one of:
##   line_started(speaker, text) — the line is audible now (cloud: first audio chunk; system: speech start)
##   line_dropped(speaker, text) — it will not be voiced (no engine / queue overflow); show its subtitle now
## Lines that waited longer than STALE_SEC in the queue are skipped silently so speech never lags the action.

signal line_started(speaker: String, text: String)
signal line_finished(speaker: String)
signal line_dropped(speaker: String, text: String)

const RATE: float = 24000.0
const MAX_QUEUE: int = 4
const STALE_SEC: float = 4.0

var client: OpenAIClient = null
var _player: AudioStreamPlayer = null
var _gen: AudioStreamGenerator = null
var _playback: AudioStreamGeneratorPlayback = null
var _queue: Array[Dictionary] = []      # {speaker, text, voice, instructions, prio, pitch, rate, slot, t}
var _current: Dictionary = {}
var _req: int = -1
var _pending := PackedVector2Array()
var _stream_done: bool = false
var _idle_frames: int = 0
var _cloud_failed: bool = false
var _sys_voices: PackedStringArray = []
var _sys_checked: bool = false
var _sys_quiet: int = 0
var _last_sys_speak_ms: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_gen = AudioStreamGenerator.new()
	_gen.mix_rate = RATE
	_gen.buffer_length = 2.0
	_player = AudioStreamPlayer.new()
	_player.name = "SquadVoice"
	_player.stream = _gen
	_player.volume_db = 2.0
	if AudioServer.get_bus_index(&"SFX") >= 0:
		_player.bus = &"SFX"
	add_child(_player)


func _exit_tree() -> void:
	stop_all()
	if DisplayServer.get_name() != "headless":
		DisplayServer.tts_stop()


func bind_client(c: OpenAIClient) -> void:
	client = c
	if not client.tts_chunk.is_connected(_on_chunk):
		client.tts_chunk.connect(_on_chunk)
		client.tts_finished.connect(_on_done)
		client.request_failed.connect(_on_failed)


func is_speaking() -> bool:
	return not _current.is_empty()


func current_priority() -> int:
	return int(_current.get("prio", -1))


## "cloud" | "system" | "" (no voice) for the next line.
func engine() -> String:
	match SquadAIConfig.voice_engine:
		"off":
			return ""
		"cloud":
			return "cloud" if _cloud_ok() else ""
		"system":
			return "system" if _system_ok() else ""
	if _cloud_ok():
		return "cloud"
	return "system" if _system_ok() else ""


func _cloud_ok() -> bool:
	return client != null and SquadAIConfig.tts_enabled and SquadAIConfig.tts_available() and not _cloud_failed


func _system_ok() -> bool:
	if not SquadAIConfig.tts_enabled:
		return false
	if not bool(ProjectSettings.get_setting("audio/general/text_to_speech", false)):
		return false
	return not _system_voices().is_empty()


func _system_voices() -> PackedStringArray:
	if _sys_checked:
		return _sys_voices
	_sys_checked = true
	if DisplayServer.get_name() == "headless":
		return _sys_voices
	_sys_voices = DisplayServer.tts_get_voices_for_language("en")
	if _sys_voices.is_empty():
		for v in DisplayServer.tts_get_voices():
			_sys_voices.append(String((v as Dictionary).get("id", "")))
	return _sys_voices


## pitch / rate / slot are used by the system engine (slot picks a distinct OS voice per ally).
func speak(speaker: String, text: String, voice: String, instructions: String, prio: int, pitch: float = 1.0, rate: float = 1.0, slot: int = 0) -> void:
	if text.strip_edges().is_empty():
		return
	if engine().is_empty():
		line_dropped.emit(speaker, text)
		return
	var item: Dictionary = {"speaker": speaker, "text": text, "voice": voice, "instructions": instructions, "prio": prio,
		"pitch": pitch, "rate": rate, "slot": slot, "t": Time.get_ticks_msec()}
	if not _current.is_empty() and prio > int(_current.get("prio", 0)):
		interrupt()
	_queue.append(item)
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["prio"]) > int(b["prio"]))
	while _queue.size() > MAX_QUEUE:
		var dropped: Dictionary = _queue.pop_back()
		line_dropped.emit(String(dropped["speaker"]), String(dropped["text"]))
	if _current.is_empty():
		_next()


func interrupt() -> void:
	if _req >= 0 and client != null:
		client.cancel(_req)
	_req = -1
	_pending = PackedVector2Array()
	# Stopping the player discards its generator buffer (clear_buffer() errors while the stream is active).
	_player.stop()
	_playback = null
	if String(_current.get("engine", "")) == "system" and DisplayServer.get_name() != "headless":
		DisplayServer.tts_stop()
		_last_sys_speak_ms = Time.get_ticks_msec()
	if not _current.is_empty():
		line_finished.emit(String(_current["speaker"]))
	_current = {}


func stop_all() -> void:
	_queue.clear()
	interrupt()


func _next() -> void:
	var now: int = Time.get_ticks_msec()
	while not _queue.is_empty():
		var it: Dictionary = _queue.pop_front()
		if int(it["prio"]) < 3 and float(now - int(it["t"])) > STALE_SEC * 1000.0:
			continue   # stale: skip silently (never speak an outdated line)
		var eng: String = engine()
		if eng.is_empty():
			line_dropped.emit(String(it["speaker"]), String(it["text"]))
			continue
		_start(it, eng)
		return


func _start(it: Dictionary, eng: String) -> void:
	_current = it
	_current["engine"] = eng
	_current["announced"] = false
	_current["started_ms"] = Time.get_ticks_msec()
	if eng == "system":
		var voices: PackedStringArray = _system_voices()
		if voices.is_empty():
			line_dropped.emit(String(it["speaker"]), String(it["text"]))
			_current = {}
			_next()
			return
		var now_ms: int = Time.get_ticks_msec()
		if now_ms - _last_sys_speak_ms < 80 and is_inside_tree():
			await get_tree().process_frame
		_last_sys_speak_ms = Time.get_ticks_msec()
		var vid: String = voices[int(it["slot"]) % voices.size()]
		DisplayServer.tts_speak(String(it["text"]), vid, 80, float(it["pitch"]), float(it["rate"]), 0, false)
		_sys_quiet = 0
		_announce()
		return
	_stream_done = false
	_pending = PackedVector2Array()
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	_req = client.speak_stream(String(it["text"]), String(it["voice"]), String(it["instructions"]))


func _announce() -> void:
	if _current.is_empty() or bool(_current.get("announced", false)):
		return
	_current["announced"] = true
	line_started.emit(String(_current["speaker"]), String(_current["text"]))


func _on_chunk(id: int, pcm: PackedByteArray) -> void:
	if id != _req:
		return
	var n: int = pcm.size() / 2
	var frames := PackedVector2Array()
	frames.resize(n)
	for i in range(n):
		var v: float = float(pcm.decode_s16(i * 2)) / 32768.0
		frames[i] = Vector2(v, v)
	_pending.append_array(frames)
	_announce()


func _on_done(id: int) -> void:
	if id == _req:
		_stream_done = true


func _on_failed(id: int, kind: String, msg: String) -> void:
	if not OpenAIClient.is_tts_kind(kind) or id != _req:
		return
	# Quota spent on that model: retry this same line once on the next cloud TTS model in the fallback chain.
	if msg.begins_with("QUOTA") and SquadAIConfig.tts_available() and not bool(_current.get("retried", false)):
		_current["retried"] = true
		_req = client.speak_stream(String(_current["text"]), String(_current["voice"]), String(_current["instructions"]))
		return
	# Any other cloud failure: in auto mode the rest of the session uses system voices; replay this line there.
	_req = -1
	_pending = PackedVector2Array()
	_player.stop()
	_playback = null
	if SquadAIConfig.voice_engine == "auto":
		_cloud_failed = true
	var it: Dictionary = _current
	_current = {}
	if it.is_empty():
		return
	if engine() == "system" and not bool(it.get("announced", false)):
		_start(it, "system")
	else:
		if not bool(it.get("announced", false)):
			line_dropped.emit(String(it["speaker"]), String(it["text"]))
		line_finished.emit(String(it["speaker"]))
		_next()


func _process(_delta: float) -> void:
	if _current.is_empty():
		return
	if String(_current.get("engine", "")) == "system":
		# Finished once the OS reports silence for a few frames (after a short start-up grace period).
		if Time.get_ticks_msec() - int(_current.get("started_ms", 0)) < 400:
			return
		if DisplayServer.tts_is_speaking():
			_sys_quiet = 0
			return
		_sys_quiet += 1
		if _sys_quiet > 3:
			var sp0: String = String(_current["speaker"])
			_current = {}
			line_finished.emit(sp0)
			_next()
		return
	if _playback == null:
		return
	if not _pending.is_empty():
		var room: int = _playback.get_frames_available()
		var push: int = mini(room, _pending.size())
		if push > 0:
			_playback.push_buffer(_pending.slice(0, push))
			_pending = _pending.slice(push)
	if _stream_done and _pending.is_empty():
		# Wait for the generator to drain before moving on.
		if _playback.get_frames_available() >= int(RATE * _gen.buffer_length) - 64:
			_idle_frames += 1
			if _idle_frames > 3:
				_idle_frames = 0
				var sp: String = String(_current["speaker"])
				var heard: bool = bool(_current.get("announced", false))
				var txt: String = String(_current["text"])
				_current = {}
				_req = -1
				if not heard:
					line_dropped.emit(sp, txt)   # stream ended with no audio
				line_finished.emit(sp)
				_next()
		else:
			_idle_frames = 0
