# IdiotHandOffGuide 03 — Squad voices: no random chatter, subtitles match speech, every line voiced

## A. Execution contract

- **Outcome:**
  - Allies stop talking randomly: idle lines, banter and combat barks are off by default.
  - What you read is what you hear: a subtitle appears only when its line actually starts playing (or immediately if it won't be voiced), and stale lines are dropped instead of being spoken seconds late.
  - The AI Director's spoken line is the only acknowledgement of its orders (no extra canned "Consider it done.").
  - Every voiced line gets a consistent voice. Cloud TTS (Gemini/OpenAI) is used while it works. After the first cloud failure (free-tier quota, network, no key) the whole session switches to the OS's built-in voices: a distinct voice/pitch per ally, instant and unlimited.
  - Cloud TTS is asked to speak at a brisk, natural pace.
- **Root:** `C:\Users\TLSB\Documents\Parallax`, branch `master`.
- **Baseline:** commit `2f37a1b`, plus guides 01/02 if they were applied.
  - Guide 01 changes `squad_ai_config.gd` only at the `show_command_log` lines. This guide's anchors in that file are different lines.
  - Guide 02 doesn't touch these files.
- **Shell:** PowerShell 5.1. `$g = "E:\game making workshop\Godot\Godot_v4.7.2-stable_win64_console.exe"`.
- **Readiness:** READY.
- **Close the Godot editor before G3-2.** It edits `project.godot`, and an open editor overwrites external edits.

**API facts used** (Godot 4 `DisplayServer`, documented in the Godot class reference under "DisplayServer — TTS"):
- `tts_get_voices_for_language(language: String) -> PackedStringArray` returns voice IDs.
- `tts_get_voices() -> Array[Dictionary]` (each has `"id"`).
- `tts_speak(text, voice, volume: int = 50, pitch: float = 1.0, rate: float = 1.0, utterance_id: int = 0, interrupt: bool = false)`.
- `tts_is_speaking() -> bool`, `tts_stop()`.
- TTS only works when the project setting `audio/general/text_to_speech` is `true`.

Operational sequence:
1. Check the baseline (G3-0).
2. Apply G3-1 … G3-7 in order. Every replace block must match exactly once; on a mismatch, stop the dependent steps and report.
3. Run G3-V1 … G3-V6.
4. Report as in section F.

## B. Requirements and acceptance map

| ID | Behaviour | Steps | Checks |
|---|---|---|---|
| R1 | Priority-0 ally lines (idle, banter, engage/kill barks, jump chatter) produce no subtitle and no voice unless `ambient_chatter` is true (default false). | G3-1, G3-5 | V3, V5 |
| R2 | For voiced lines, the subtitle is emitted on `line_started` (cloud: first audio chunk; system: when speech starts). Unvoiced lines emit `line_dropped` and show their subtitle immediately. Streaming LLM text is no longer shown as a growing subtitle. | G3-3, G3-5 | V3, V4 |
| R3 | Queued lines older than 4 s (priority < 3) are skipped, not spoken late. | G3-3 | V4 |
| R4 | Engine `auto`: cloud → after any cloud failure, OS voices for the rest of the session. `system` / `cloud` / `off` are selectable (`user://squad_ai.cfg` key `voice_engine`). The tests force `off`. | G3-1, G3-2, G3-3 | V3, V4 |
| R5 | Orders issued by the Director (source ending in `+llm`) don't trigger canned ack lines. The Director prompt requires every `say` line to describe only the orders actually issued to that ally. | G3-5, G3-6 | V3 |
| R6 | Gemini TTS prompt asks for a brisk, natural pace. | G3-4 | inspection V2 |
| R7 | No regressions (unit 74/74, windowed 53/53). | all | V5 |

## C. File-change manifest

| Path | Op | Step |
|---|---|---|
| `addons/parallax_squad_ai/squad_ai_config.gd` | modify | G3-1 |
| `project.godot` | modify (one line) | G3-2 |
| `addons/parallax_squad_ai/tts_player.gd` | replace entire file | G3-3 |
| `addons/parallax_squad_ai/openai_client.gd` | modify | G3-4 |
| `addons/parallax_squad_ai/squad_comms.gd` | modify | G3-5, G3-6 |
| `scripts/allies/ally_squad_manager.gd` | modify | G3-5 |
| `tests/voice_pipeline_test.gd` | create | G3-V4 |
| `MEMORY/05_UI_SCORING_AND_AUDIO.md`, `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md` | modify | G3-7 |

## D. Ordered implementation steps

### G3-0 — Baseline
```powershell
git status --short
(Get-Content addons/parallax_squad_ai/tts_player.gd).Count
```
**Expected:** `tts_player.gd` is about 128 lines and starts with `class_name SquadTTSPlayer` / `## Streams OpenAI TTS PCM`. If it has already been replaced (contains `line_dropped`), G3-3 is already applied.

Back up the save (the tests start runs):
```powershell
$bk = "$env:TEMP\parallax_save_bk_g3"; New-Item -ItemType Directory -Force $bk | Out-Null; Copy-Item "$env:APPDATA\Godot\app_userdata\PARALLAX\*.cfg" $bk -Force -ErrorAction SilentlyContinue
```

### G3-1 — Config: voice engine, ambient chatter, lower voice threshold, tests silent
File `addons/parallax_squad_ai/squad_ai_config.gd`.

Replace block:
```gdscript
## Cap on voiced lines per minute (protects free-tier quotas); extra lines stay subtitle-only.
static var tts_per_minute: int = 5
## Canned event lines (skill callouts, acks) are voiced only at/above this priority; Director replies always are.
## 2 = panic acks, combo calls, downed. Keeps free-tier TTS quotas for the lines that matter.
static var voice_min_event_priority: int = 2
```
with:
```gdscript
## Legacy (unused since 2026-11-18): the TTS player no longer drops lines per minute; a cloud failure switches
## the session to system voices instead (see voice_engine).
static var tts_per_minute: int = 5
## Ally lines at/above this priority are voiced. 1 = every real line (acks, callouts, replies); 0 = chatter.
static var voice_min_event_priority: int = 1
## auto (cloud while it works, then OS voices for the rest of the session) | cloud | system | off
static var voice_engine: String = "auto"
const VOICE_ENGINES: Array[String] = ["auto", "cloud", "system", "off"]
## Idle lines, banter and kill/engage barks (priority 0). Off: allies only speak when it matters.
static var ambient_chatter: bool = false
```
Replace block:
```gdscript
		show_subtitles = bool(cf.get_value("comms", "show_subtitles", show_subtitles))
```
with:
```gdscript
		show_subtitles = bool(cf.get_value("comms", "show_subtitles", show_subtitles))
		voice_engine = String(cf.get_value("comms", "voice_engine", voice_engine))
		ambient_chatter = bool(cf.get_value("comms", "ambient_chatter", ambient_chatter))
	if not VOICE_ENGINES.has(voice_engine):
		voice_engine = "auto"
```
Notes on that block:
- The first three lines stay inside the `if cf.load(PATH) == OK:` block, at two tabs.
- The `if not VOICE_ENGINES...` line is at one tab, same level as the existing `if not MODES.has(mode):` that follows.
- Confirm the original line is indented with two tabs before replacing.

Replace block:
```gdscript
	cf.set_value("comms", "show_subtitles", show_subtitles)
```
with:
```gdscript
	cf.set_value("comms", "show_subtitles", show_subtitles)
	cf.set_value("comms", "voice_engine", voice_engine)
	cf.set_value("comms", "ambient_chatter", ambient_chatter)
```
Replace block:
```gdscript
static func force_offline() -> void:
	ensure_loaded()
	provider_pref = "openai"
```
with:
```gdscript
static func force_offline() -> void:
	ensure_loaded()
	voice_engine = "off"   # automated tests stay silent (no OS speech during windowed runs)
	provider_pref = "openai"
```
**Postcondition:**
- The file contains `static var voice_engine: String = "auto"`, `const VOICE_ENGINES`, `static var ambient_chatter: bool = false` and `voice_engine = "off"` (inside `force_offline`).
- The cfg keys `"voice_engine"` and `"ambient_chatter"` each appear in both `ensure_loaded` (get_value) and `save` (set_value).

### G3-2 — Enable OS text-to-speech
File `project.godot`. Replace block:
```
[audio]

driver/enable_input=true
```
with:
```
[audio]

driver/enable_input=true
general/text_to_speech=true
```

### G3-3 — TTS player with cloud → system fallback, synced start, stale drop
File `addons/parallax_squad_ai/tts_player.gd`. **Replace the entire file** with:
```gdscript
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
```
**Postcondition:** the file contains `signal line_dropped` and `func engine() -> String:`.

### G3-4 — Brisker cloud delivery
File `addons/parallax_squad_ai/openai_client.gd`. Replace block:
```gdscript
		var prompt: String = text if style.is_empty() else "%s Say: %s" % [style, text]
```
with:
```gdscript
		var pace: String = "Speak at a brisk, natural conversational pace — never slow or drawn out."
		var prompt: String = ("%s Say: %s" % [pace, text]) if style.is_empty() else ("%s %s Say: %s" % [style, pace, text])
```
In the same file, replace block:
```gdscript
	if not style.is_empty() and SquadAIConfig.tts_model().contains("gpt-4o"):
		b2["instructions"] = style
```
with:
```gdscript
	if SquadAIConfig.tts_model().contains("gpt-4o"):
		b2["instructions"] = (style + " " if not style.is_empty() else "") + "Speak at a brisk, natural conversational pace."
```

### G3-5 — Comms: subtitles follow speech, chatter gated, no streaming subtitles, no double acks
File `addons/parallax_squad_ai/squad_comms.gd`.

(a) Replace block:
```gdscript
	tts.bind_client(client)
```
with:
```gdscript
	tts.bind_client(client)
	# Subtitles follow the voice: shown when a line is actually heard, or right away if it won't be voiced.
	tts.line_started.connect(_on_voice_line)
	tts.line_dropped.connect(_on_voice_line)
```
(b) Replace block (streaming text no longer shown as a growing subtitle):
```gdscript
	rec["text"] = String(rec["text"]) + delta
	var ally: SquadAlly = rec["ally"] as SquadAlly
	if ally == null or not is_instance_valid(ally):
		return
	subtitle.emit(ally.get_display_name(), String(rec["text"]), ally.profile.color, false)
```
with:
```gdscript
	rec["text"] = String(rec["text"]) + delta
```
(c) Replace block (Director `say` lines):
```gdscript
				if who.is_downed:
					line = "(weakly) " + line
				subtitle.emit(who.get_display_name(), line, who.profile.color, true)
				_voice(who, line, 1)
```
with:
```gdscript
				if who.is_downed:
					line = "(weakly) " + line
				_voice(who, line, 1)   # subtitle is emitted by _on_voice_line when the line plays (or is dropped)
```
(d) Replace block (fallback speaker):
```gdscript
			spoken = speaker.profile.line("ack", "On it.") if not calls.is_empty() else speaker.profile.line("confused", "Say again?")
		subtitle.emit(speaker.get_display_name(), spoken, speaker.profile.color, true)
		_voice(speaker, spoken, 1)
```
with:
```gdscript
			spoken = speaker.profile.line("ack", "On it.") if not calls.is_empty() else speaker.profile.line("confused", "Say again?")
		_voice(speaker, spoken, 1)
```
(e) Replace block (`_voice` and `_on_ally_spoke`):
```gdscript
func _voice(ally: SquadAlly, text: String, prio: int) -> void:
	if text.is_empty() or ally == null:
		return
	var voice: String = ally.profile.gemini_voice if SquadAIConfig.provider() == "gemini" else ally.profile.tts_voice
	tts.speak(ally.get_display_name(), text, voice, ally.profile.tts_instructions, prio)


func _on_ally_spoke(ally_name: String, text: String, _event: String, priority: int, _voice_id: String) -> void:
	var a: SquadAlly = _manager.find_ally(ally_name) if _manager != null else null
	var col: Color = a.profile.color if a != null else UITheme.GOLD
	subtitle.emit(ally_name, text, col, true)
	# Chatter stays subtitle-only; real lines are voiced (higher priority interrupts lower).
	if priority >= 1 and a != null:
		# Routine callouts stay subtitle-only to spare free-tier TTS quota; important ones are voiced.
		if priority >= SquadAIConfig.voice_min_event_priority:
			_voice(a, text, priority)
		_remember(ally_name, "said: " + text)
```
with:
```gdscript
const SYS_PITCH: Dictionary = {"vanguard": 0.8, "skirmisher": 1.25, "artillery": 1.0}
const SYS_RATE: Dictionary = {"vanguard": 1.0, "skirmisher": 1.12, "artillery": 1.02}


func _voice(ally: SquadAlly, text: String, prio: int) -> void:
	if text.is_empty() or ally == null:
		return
	var voice: String = ally.profile.gemini_voice if SquadAIConfig.provider() == "gemini" else ally.profile.tts_voice
	var role: String = ally.get_role()
	var slot: int = maxi(0, _manager.allies.find(ally)) if _manager != null else 0
	tts.speak(ally.get_display_name(), text, voice, ally.profile.tts_instructions, prio,
		float(SYS_PITCH.get(role, 1.0)), float(SYS_RATE.get(role, 1.0)), slot)


## A line became audible (or will not be voiced): show it now, so text always matches what is heard.
func _on_voice_line(speaker: String, text: String) -> void:
	var a: SquadAlly = _manager.find_ally(speaker) if _manager != null else null
	subtitle.emit(speaker, text, a.profile.color if a != null else UITheme.GOLD, true)


func _on_ally_spoke(ally_name: String, text: String, _event: String, priority: int, _voice_id: String) -> void:
	var a: SquadAlly = _manager.find_ally(ally_name) if _manager != null else null
	if priority <= 0:
		# Chatter (idle lines, banter, kill/engage barks): only when ambient chatter is switched on.
		if SquadAIConfig.ambient_chatter:
			subtitle.emit(ally_name, text, a.profile.color if a != null else UITheme.GOLD, true)
		return
	if a == null:
		subtitle.emit(ally_name, text, UITheme.GOLD, true)
		return
	if priority >= SquadAIConfig.voice_min_event_priority:
		_voice(a, text, priority)
	else:
		subtitle.emit(ally_name, text, a.profile.color, true)
	_remember(ally_name, "said: " + text)
```
(f) Replace block (TTS failure notice reflects the fallback):
```gdscript
		if Time.get_ticks_msec() - _last_tts_warn > 30000:
			_last_tts_warn = Time.get_ticks_msec()
			if not SquadAIConfig.tts_available():
				notify.emit("Ally voices hit today's free TTS quota — subtitles only (orders still work).", "warn")
			else:
				notify.emit("Ally voice unavailable: %s" % message.left(120), "warn")
		return
```
with:
```gdscript
		if Time.get_ticks_msec() - _last_tts_warn > 30000:
			_last_tts_warn = Time.get_ticks_msec()
			if tts.engine() == "system":
				notify.emit("Cloud voices unavailable — switched to system voices for this session.", "info")
			elif not SquadAIConfig.tts_available():
				notify.emit("Ally voices hit today's free TTS quota — subtitles only (orders still work).", "warn")
			else:
				notify.emit("Ally voice unavailable: %s" % message.left(120), "warn")
		return
```
(g) File `scripts/allies/ally_squad_manager.gd`. Replace block:
```gdscript
		if chained:
			continue   # later steps of a chain don't re-acknowledge
```
with:
```gdscript
		if chained:
			continue   # later steps of a chain don't re-acknowledge
		if source.ends_with("+llm"):
			continue   # the Director already voices its own `say` line for this order (no second, canned ack)
```

### G3-6 — Director prompt: say only what was ordered
File `addons/parallax_squad_ai/squad_comms.gd`. Replace block:
```
(10) The squad auto-rallies to protect anyone at low HP; don't fight that unless told.\n" \
```
with:
```
(10) The squad auto-rallies to protect anyone at low HP; don't fight that unless told. (11) Every `say` line must describe ONLY what that ally was ordered to do in THIS response (or answer the player's question) — never announce a plan, target or skill you did not issue as a tool call, never narrate other allies, no lore or filler. Default to ONE speaker; use two only when the player addressed several allies.\n" \
```
**Note:** the original anchor is the end of the long `RULES:` string line. Match the exact text `(10) The squad auto-rallies to protect anyone at low HP; don't fight that unless told.\n" \`; it appears exactly once.

### G3-7 — MEMORY
Append to `MEMORY/07_DEV_STATUS_AND_CHANGELOG.md`:
```markdown
- **2026-11-18 (Squad voice coherence)**: Priority-0 chatter off by default (`ambient_chatter`); subtitles emitted when a line is heard (`SquadTTSPlayer.line_started` / `line_dropped`), stale queued lines (> 4 s) skipped, no streaming LLM subtitles, no canned ack on Director orders, prompt rule 11 (say = only the issued orders); voice engine `auto` = cloud then OS voices (`DisplayServer.tts_*`, `audio/general/text_to_speech=true`) for the rest of the session after a cloud failure; per-role pitch/rate; brisk-pace TTS prompt; tests force `voice_engine = "off"`.
```
In `MEMORY/05_UI_SCORING_AND_AUDIO.md`, insert after the line that starts with `- **Director tools (2026-11-17)**` (unique), as a new line:
```markdown
- **Voice pipeline (2026-11-18)**: one line at a time; subtitle shown on `line_started` (cloud: first audio chunk) or `line_dropped`; chatter (priority 0) hidden unless `ambient_chatter`; engine `auto` → cloud, then OS voices for the session after any cloud failure (`voice_engine` in `user://squad_ai.cfg`: auto/cloud/system/off).
```

## E. Verification and failure handling

**G3-V1 — import + parse.**
```powershell
& $g --headless --path . --import --quit
foreach ($f in @("addons/parallax_squad_ai/squad_ai_config.gd","addons/parallax_squad_ai/tts_player.gd","addons/parallax_squad_ai/openai_client.gd","addons/parallax_squad_ai/squad_comms.gd","scripts/allies/ally_squad_manager.gd")) { $o = & $g --headless --path . --check-only -s "res://$f" 2>&1 | Out-String; if ($o -match "SCRIPT ERROR|Parse Error") { "FAIL $f"; $o } else { "ok $f" } }
```
**Pass:** every line says `ok`.

**G3-V2 — inspections.**
- `Select-String project.godot "general/text_to_speech=true"`: 1 line.
- `Select-String addons/parallax_squad_ai/openai_client.gd "brisk"`: 2 lines.
- `Select-String addons/parallax_squad_ai/squad_comms.gd "subtitle.emit"`: exactly 5 lines (`YOU` echo, `_on_voice_line`, chatter, unknown speaker, sub-threshold).

**G3-V3 — boot + unit.**
```powershell
& $g --headless --path . -s res://tests/boot_smoke.gd 2>&1 | Select-String "boot_smoke|SCRIPT ERROR"
& $g --headless --path . -s res://tests/squad_ai_unit_test.gd 2>&1 | Select-String "FAIL|SUMMARY"
```
**Pass:** `[boot_smoke] OK`; `SUMMARY 74 checks, 0 failed`.

**G3-V4 — voice pipeline test (new, headless, no network).** Create `tests/voice_pipeline_test.gd`:
```gdscript
extends SceneTree
## Headless checks for the voice pipeline (guide 03): engine selection, drop/start signals, stale skipping,
## chatter gating, no canned ack on Director orders. Run: godot --headless --path . -s res://tests/voice_pipeline_test.gd
var _results: Array[String] = []

func _initialize() -> void:
	_run()

func _check(n: String, ok: bool, d: String = "") -> void:
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", n, d]
	_results.append(line)
	print("[voice] ", line)

func _run() -> void:
	await process_frame
	SquadAIConfig.force_offline()   # sets voice_engine = "off"
	_check("tests_force_off", SquadAIConfig.voice_engine == "off")
	var tts := SquadTTSPlayer.new()
	root.add_child(tts)
	await process_frame
	var dropped: Array = []
	var started: Array = []
	tts.line_dropped.connect(func(s: String, t: String) -> void: dropped.append([s, t]))
	tts.line_started.connect(func(s: String, t: String) -> void: started.append([s, t]))
	tts.speak("Sera", "Behind you.", "Puck", "", 1)
	_check("off_engine_drops_with_text", dropped.size() == 1 and String(dropped[0][1]) == "Behind you." and started.is_empty(), str(dropped))
	SquadAIConfig.voice_engine = "auto"
	# Headless + offline: no cloud key, no OS voices -> engine "" -> still a drop (never silent without a subtitle).
	_check("auto_headless_engine_empty", tts.engine() == "", tts.engine())
	tts.speak("Ivo", "Warded!", "Iapetus", "", 2)
	_check("auto_headless_drops", dropped.size() == 2)
	# Chatter gating in SquadComms: a priority-0 line emits no subtitle when ambient_chatter is false.
	var comms := SquadComms.new()
	root.add_child(comms)
	await process_frame
	var subs: Array = []
	comms.subtitle.connect(func(sp: String, t: String, _c: Color, _f: bool) -> void: subs.append([sp, t]))
	SquadAIConfig.ambient_chatter = false
	comms._on_ally_spoke("Brannoc", "Bored now.", "idle", 0, "")
	_check("chatter_hidden_by_default", subs.is_empty(), str(subs))
	SquadAIConfig.ambient_chatter = true
	comms._on_ally_spoke("Brannoc", "Bored now.", "idle", 0, "")
	_check("chatter_shown_when_enabled", subs.size() == 1, str(subs))
	SquadAIConfig.ambient_chatter = false
	var fails: int = _results.filter(func(r: String) -> bool: return r.begins_with("FAIL")).size()
	print("[voice] SUMMARY %d checks, %d failed" % [_results.size(), fails])
	quit(1 if fails > 0 else 0)
```
Run:
```powershell
& $g --headless --path . -s res://tests/voice_pipeline_test.gd 2>&1 | Select-String "\[voice\]|SCRIPT ERROR"
```
**Pass:** `[voice] SUMMARY 6 checks, 0 failed`.

**G3-V5 — windowed squad regression (≈5 min).**
```powershell
& $g --path . -s res://tests/squad_ai_windowed_test.gd -- --shots="$env:TEMP\pshots" 2>&1 | Select-String "FAIL|SUMMARY|SCRIPT ERROR"
```
**Pass:** `SUMMARY 53 checks, 0 failed`, and no speech is heard (tests force `off`).
- If `small_talk_replies` or a log-based check fails, report the detail. The command log still receives entries, so these checks should be unaffected.

**G3-V6 — manual listening check (needs a person; optional but recommended).**
- **Setup:** run the game (F5), start a run, press Enter and type `Brannoc guard me, Sera bait the skeleton and run in circles`.
- **Expected:** each spoken line appears as a subtitle at the moment you hear it, and no subtitle shows a different line than the one being spoken. No idle chatter for 2 minutes of standing still.
- **Cloud quota:** with a Gemini key whose quota is exhausted, a notification "switched to system voices" appears once, and from then on every line is spoken in an OS voice: Brannoc deeper, Sera higher.
- **Report:** what was observed.

**Restore the save:** `Copy-Item "$env:TEMP\parallax_save_bk_g3\savegame.cfg" "$env:APPDATA\Godot\app_userdata\PARALLAX\savegame.cfg" -Force`.

**Failure handling:**
- **`tts_get_voices_for_language` / `tts_speak` parse error:** the API is missing in this Godot build. Report it; don't remove the system engine. Set `voice_engine = "cloud"` as a temporary default and mark R4 blocked.
- **Rollback:** `git checkout -- <files in section C>`, then delete `tests/voice_pipeline_test.gd`.

## F. Completion report contract
Report:
- applied step IDs;
- changed files;
- each check with PASS/FAIL and its output;
- the manual listening result (or "not performed").

**Done means:** G3-1 … G3-7 are applied and V1–V5 pass.

**Author's validation:** the anchors were checked against the baseline source. The code has not been compiled or run by the author.
