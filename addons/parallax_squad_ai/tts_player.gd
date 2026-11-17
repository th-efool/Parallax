class_name SquadTTSPlayer
extends Node
## Streams OpenAI TTS PCM (24 kHz s16le mono) straight into an AudioStreamGenerator, one line at a time,
## each ally with its own voice. Lines are queued by priority; a higher-priority line (panic order, ally
## downed) interrupts the current one, cancelling its HTTP stream and flushing the buffer.

signal line_started(speaker: String, text: String)
signal line_finished(speaker: String)

const RATE: float = 24000.0
const MAX_QUEUE: int = 4

var client: OpenAIClient = null
var _player: AudioStreamPlayer = null
var _gen: AudioStreamGenerator = null
var _playback: AudioStreamGeneratorPlayback = null
var _queue: Array[Dictionary] = []      # {speaker, text, voice, instructions, prio}
var _current: Dictionary = {}
var _req: int = -1
var _pending := PackedVector2Array()
var _stream_done: bool = false
var _idle_frames: int = 0


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


func speak(speaker: String, text: String, voice: String, instructions: String, prio: int) -> void:
	if client == null or not SquadAIConfig.tts_enabled or not SquadAIConfig.is_online() or text.strip_edges().is_empty():
		return
	var item: Dictionary = {"speaker": speaker, "text": text, "voice": voice, "instructions": instructions, "prio": prio}
	if not _current.is_empty() and prio > int(_current.get("prio", 0)):
		interrupt()
	_queue.append(item)
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["prio"]) > int(b["prio"]))
	while _queue.size() > MAX_QUEUE:
		_queue.pop_back()
	if _current.is_empty():
		_next()


func interrupt() -> void:
	if _req >= 0 and client != null:
		client.cancel(_req)
	_req = -1
	_pending = PackedVector2Array()
	if _playback != null:
		_playback.clear_buffer()
	_player.stop()
	if not _current.is_empty():
		line_finished.emit(String(_current["speaker"]))
	_current = {}


func stop_all() -> void:
	_queue.clear()
	interrupt()


func _next() -> void:
	if _queue.is_empty():
		return
	_current = _queue.pop_front()
	_stream_done = false
	_pending = PackedVector2Array()
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	_req = client.speak_stream(String(_current["text"]), String(_current["voice"]), String(_current["instructions"]))
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


func _on_done(id: int) -> void:
	if id == _req:
		_stream_done = true


func _on_failed(id: int, kind: String, _msg: String) -> void:
	if kind == "tts" and id == _req:
		_stream_done = true
		_pending = PackedVector2Array()


func _process(_delta: float) -> void:
	if _current.is_empty() or _playback == null:
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
				_current = {}
				_req = -1
				line_finished.emit(sp)
				_next()
		else:
			_idle_frames = 0
