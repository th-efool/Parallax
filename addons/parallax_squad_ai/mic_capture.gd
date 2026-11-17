class_name SquadMicCapture
extends Node
## Push-to-talk microphone capture: AudioStreamMicrophone -> muted "SquadMic" bus with an AudioEffectCapture.
## `stop_and_encode()` returns a 16 kHz mono 16-bit WAV ready for Whisper. Needs project setting
## `audio/driver/enable_input = true` (the plugin turns it on). Emits a live RMS level for the HUD mic meter.

signal level_changed(rms: float)

const BUS_NAME: String = "SquadMic"
const TARGET_RATE: int = 16000
const MAX_SECONDS: float = 20.0

var is_recording: bool = false
var _player: AudioStreamPlayer = null
var _capture: AudioEffectCapture = null
var _frames: PackedVector2Array = PackedVector2Array()
var _mix_rate: float = 44100.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mix_rate = AudioServer.get_mix_rate()


func is_supported() -> bool:
	return bool(ProjectSettings.get_setting("audio/driver/enable_input", false)) and DisplayServer.get_name() != "headless"


func _ensure_bus() -> void:
	var idx: int = AudioServer.get_bus_index(BUS_NAME)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS_NAME)
		AudioServer.add_bus_effect(idx, AudioEffectCapture.new())
		AudioServer.set_bus_mute(idx, true)
	_capture = AudioServer.get_bus_effect(idx, 0) as AudioEffectCapture
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.name = "MicInput"
		_player.stream = AudioStreamMicrophone.new()
		_player.bus = BUS_NAME
		add_child(_player)


func start() -> bool:
	if is_recording:
		return true
	if not is_supported():
		return false
	_ensure_bus()
	if _capture == null:
		return false
	_capture.clear_buffer()
	_frames = PackedVector2Array()
	_player.play()
	is_recording = true
	return true


func cancel() -> void:
	if _player != null:
		_player.stop()
	is_recording = false
	_frames = PackedVector2Array()


func _process(_delta: float) -> void:
	if not is_recording or _capture == null:
		return
	var avail: int = _capture.get_frames_available()
	if avail > 0:
		var buf: PackedVector2Array = _capture.get_buffer(avail)
		_frames.append_array(buf)
		var acc: float = 0.0
		var step: int = maxi(1, buf.size() / 256)
		var n: int = 0
		for i in range(0, buf.size(), step):
			var s: float = (buf[i].x + buf[i].y) * 0.5
			acc += s * s
			n += 1
		level_changed.emit(sqrt(acc / float(maxi(1, n))))
	if float(_frames.size()) / _mix_rate > MAX_SECONDS:
		pass  # keep the first MAX_SECONDS; extra audio is dropped in encode


## Stops recording and returns WAV bytes (empty when nothing usable was captured).
func stop_and_encode() -> PackedByteArray:
	if not is_recording:
		return PackedByteArray()
	if _capture != null:
		var avail: int = _capture.get_frames_available()
		if avail > 0:
			_frames.append_array(_capture.get_buffer(avail))
	_player.stop()
	is_recording = false
	var max_frames: int = int(_mix_rate * MAX_SECONDS)
	var src: PackedVector2Array = _frames.slice(0, mini(_frames.size(), max_frames))
	_frames = PackedVector2Array()
	if float(src.size()) / _mix_rate < 0.3:
		return PackedByteArray()
	return encode_wav(src, _mix_rate)


## Downmix + linear resample to 16 kHz, 16-bit PCM WAV.
static func encode_wav(src: PackedVector2Array, src_rate: float) -> PackedByteArray:
	var ratio: float = src_rate / float(TARGET_RATE)
	var out_n: int = int(float(src.size()) / ratio)
	var pcm := PackedByteArray()
	pcm.resize(out_n * 2)
	for i in range(out_n):
		var pos: float = float(i) * ratio
		var i0: int = int(pos)
		var i1: int = mini(i0 + 1, src.size() - 1)
		var t: float = pos - float(i0)
		var a: float = (src[i0].x + src[i0].y) * 0.5
		var b: float = (src[i1].x + src[i1].y) * 0.5
		var v: int = clampi(int(lerpf(a, b, t) * 32767.0), -32768, 32767)
		pcm.encode_s16(i * 2, v)
	var wav := PackedByteArray()
	wav.append_array("RIFF".to_ascii_buffer())
	wav.append_array(_u32(36 + pcm.size()))
	wav.append_array("WAVEfmt ".to_ascii_buffer())
	wav.append_array(_u32(16))
	wav.append_array(_u16(1))
	wav.append_array(_u16(1))
	wav.append_array(_u32(TARGET_RATE))
	wav.append_array(_u32(TARGET_RATE * 2))
	wav.append_array(_u16(2))
	wav.append_array(_u16(16))
	wav.append_array("data".to_ascii_buffer())
	wav.append_array(_u32(pcm.size()))
	wav.append_array(pcm)
	return wav


static func _u32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, v)
	return b


static func _u16(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(2)
	b.encode_u16(0, v)
	return b
