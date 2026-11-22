class_name SquadAIConfig
extends RefCounted
## Settings for the Squad AI plugin. Stored in `user://squad_ai.cfg` (per user, never in the repo).
##
## Providers (any OpenAI-compatible chat endpoint works; set `base_url` / `model` to override):
##   gemini (preferred, free tier): chat via Gemini's OpenAI-compatible endpoint, speech-to-text and
##           streamed TTS via the native Gemini API (generateContent / streamGenerateContent?alt=sse).
##   openai : chat/completions, Whisper /audio/transcriptions, /audio/speech PCM.
##   auto   : gemini when a Gemini key exists, else openai, else offline.
## Keys are looked up (never written to project files), in order: environment variables
## (GEMINI_API_KEY | GEMINI_KEY | GOOGLE_API_KEY, OPENAI_API_KEY | OPENAI_KEY) -> a `.env` file in the project
## folder (dev; gitignored) or in user:// -> keys pasted in Options (user://squad_ai.cfg).
## With no key the game stays fully playable: chat uses the offline keyword parser.

const PATH: String = "user://squad_ai.cfg"
const MODES: Array[String] = ["both", "chat", "voice"]
const PROVIDERS: Array[String] = ["auto", "gemini", "openai"]

const DEFAULTS: Dictionary = {
	"gemini": {
		"base_url": "https://generativelanguage.googleapis.com/v1beta/openai",
		"native_url": "https://generativelanguage.googleapis.com/v1beta",
		# Flash-Lite: ~1.5 s streamed replies with tool calls on the free tier (full Flash models stalled for
		# 30 s+ on this key, 2026-11-17). Override in Options / PARALLAX_AI_MODEL if a faster model appears.
		"model": "gemini-3.1-flash-lite",
		"stt_model": "gemini-3.1-flash-lite",
		"tts_model": "gemini-2.5-flash-preview-tts",
	},
	"openai": {
		"base_url": "https://api.openai.com/v1",
		"native_url": "",
		"model": "gpt-4o",
		"stt_model": "whisper-1",
		"tts_model": "gpt-4o-mini-tts",
	},
}

static var _loaded: bool = false
static var provider_pref: String = "openai"
## Optional overrides (empty = provider default).
static var base_url_override: String = ""
static var model_override: String = ""
static var _file_keys: Dictionary = {"gemini": "", "openai": ""}
static var _env_keys: Dictionary = {"gemini": "", "openai": ""}
static var _env_source: Dictionary = {"gemini": "", "openai": ""}
## both | chat | voice
static var mode: String = "both"
static var tts_enabled: bool = true
## Hidden by default (toggle with L). Persisted under the v2 key so an old "visible" setting is not inherited.
static var show_command_log: bool = false
static var show_subtitles: bool = true
static var request_timeout_sec: float = 25.0
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


static func config_path() -> String:
	if OS.has_feature("template") or not OS.has_feature("editor"):
		return OS.get_executable_path().get_base_dir().path_join("saved").path_join("squad_ai.cfg")
	return PATH


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(config_path()) == OK:
		provider_pref = String(cf.get_value("api", "provider", provider_pref))
		base_url_override = String(cf.get_value("api", "base_url_override", ""))
		model_override = String(cf.get_value("api", "model_override", ""))
		_file_keys["gemini"] = String(cf.get_value("api", "gemini_key", ""))
		_file_keys["openai"] = String(cf.get_value("api", "openai_key", ""))
		mode = String(cf.get_value("comms", "mode", mode))
		tts_enabled = bool(cf.get_value("comms", "tts_enabled", tts_enabled))
		show_command_log = bool(cf.get_value("comms", "show_command_log_v2", show_command_log))
		show_subtitles = bool(cf.get_value("comms", "show_subtitles", show_subtitles))
		voice_engine = String(cf.get_value("comms", "voice_engine", voice_engine))
		ambient_chatter = bool(cf.get_value("comms", "ambient_chatter", ambient_chatter))
	if not VOICE_ENGINES.has(voice_engine):
		voice_engine = "auto"
	if OS.get_name() == "Windows" and voice_engine == "system":
		voice_engine = "auto"
	if not MODES.has(mode):
		mode = "both"
	if not PROVIDERS.has(provider_pref):
		provider_pref = "auto"
	_load_env_keys()


static func _load_env_keys() -> void:
	var names: Dictionary = {
		"gemini": ["GEMINI_API_KEY", "GEMINI_KEY", "GOOGLE_API_KEY"],
		"openai": ["OPENAI_API_KEY", "OPENAI_KEY"],
	}
	var dotenv: Dictionary = {}
	for path in [ProjectSettings.globalize_path("res://.env"), ProjectSettings.globalize_path("user://.env"), OS.get_executable_path().get_base_dir().path_join(".env")]:
		var parsed: Dictionary = _parse_dotenv(String(path))
		for k in parsed.keys():
			if not dotenv.has(k):
				dotenv[k] = parsed[k]
				dotenv["__src_" + String(k)] = ".env"
	for prov in names.keys():
		for n in (names[prov] as Array):
			var v: String = OS.get_environment(String(n)).strip_edges()
			if not v.is_empty():
				_env_keys[prov] = v
				_env_source[prov] = "env " + String(n)
				break
			if dotenv.has(n) and not String(dotenv[n]).is_empty():
				_env_keys[prov] = String(dotenv[n])
				_env_source[prov] = ".env " + String(n)
				break


static func _parse_dotenv(path: String) -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(path):
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.begins_with("export "):
			line = line.substr(7)
		var eq: int = line.find("=")
		if eq <= 0:
			continue
		var k: String = line.substr(0, eq).strip_edges()
		var v: String = line.substr(eq + 1).strip_edges()
		if v.length() >= 2 and ((v.begins_with("\"") and v.ends_with("\"")) or (v.begins_with("'") and v.ends_with("'"))):
			v = v.substr(1, v.length() - 2)
		out[k] = v.strip_edges()
	return out


static func save() -> void:
	ensure_loaded()
	var p: String = config_path()
	if not p.begins_with("user://") and not p.begins_with("res://"):
		var dir_path: String = p.get_base_dir()
		if not dir_path.is_empty() and not DirAccess.dir_exists_absolute(dir_path):
			DirAccess.make_dir_recursive_absolute(dir_path)
	var cf := ConfigFile.new()
	cf.load(p)
	cf.set_value("api", "provider", provider_pref)
	cf.set_value("api", "base_url_override", base_url_override)
	cf.set_value("api", "model_override", model_override)
	cf.set_value("api", "gemini_key", _file_keys["gemini"])
	cf.set_value("api", "openai_key", _file_keys["openai"])
	cf.set_value("comms", "mode", mode)
	cf.set_value("comms", "tts_enabled", tts_enabled)
	cf.set_value("comms", "show_command_log_v2", show_command_log)
	cf.set_value("comms", "show_subtitles", show_subtitles)
	cf.set_value("comms", "voice_engine", voice_engine)
	cf.set_value("comms", "ambient_chatter", ambient_chatter)
	cf.save(p)


static func key_for(prov: String) -> String:
	ensure_loaded()
	var k: String = String(_env_keys.get(prov, ""))
	if k.is_empty():
		k = String(_file_keys.get(prov, "")).strip_edges()
	return k


## Resolved provider actually in use ("" = offline).
static func provider() -> String:
	ensure_loaded()
	match provider_pref:
		"gemini", "openai":
			return provider_pref if not key_for(provider_pref).is_empty() else ""
	if not key_for("gemini").is_empty():
		return "gemini"
	if not key_for("openai").is_empty():
		return "openai"
	return ""


static func api_key() -> String:
	var p: String = provider()
	return key_for(p) if not p.is_empty() else ""


static func _def(field: String) -> String:
	var p: String = provider()
	if p.is_empty():
		p = "gemini"
	return String((DEFAULTS[p] as Dictionary).get(field, ""))


static func base_url() -> String:
	ensure_loaded()
	return base_url_override if not base_url_override.strip_edges().is_empty() else _def("base_url")


static func native_url() -> String:
	return _def("native_url")


static func model() -> String:
	ensure_loaded()
	if not model_override.strip_edges().is_empty():
		return model_override
	var env_model: String = OS.get_environment("PARALLAX_AI_MODEL").strip_edges()
	return env_model if not env_model.is_empty() else _def("model")


static func stt_model() -> String:
	return _def("stt_model")


## Gemini TTS models tried in order; one that returns 429 (free-tier quota spent) is skipped for the session.
const GEMINI_TTS_FALLBACKS: Array[String] = ["gemini-2.5-flash-preview-tts", "gemini-3.1-flash-tts-preview", "gemini-3.8-flash-lite-tts", "gemini-3.8-flash-tts", "gemini-2.5-pro-preview-tts"]
static var _tts_exhausted: Dictionary = {}


static func tts_model() -> String:
	if provider() == "gemini":
		for m in GEMINI_TTS_FALLBACKS:
			if not _tts_exhausted.has(m):
				return m
		return ""
	return _def("tts_model")


static func mark_tts_exhausted(model_id: String) -> void:
	_tts_exhausted[model_id] = true


## False once every TTS model's quota is spent this session (voices fall back to subtitles only).
static func tts_available() -> bool:
	return is_online() and not tts_model().is_empty()


static func key_source() -> String:
	var p: String = provider()
	if p.is_empty():
		return "none"
	var s: String = String(_env_source.get(p, ""))
	return s if not s.is_empty() else "user://squad_ai.cfg"


static func set_file_key(prov: String, k: String) -> void:
	ensure_loaded()
	_file_keys[prov] = k.strip_edges()
	save()


static func is_online() -> bool:
	return not provider().is_empty()


static func describe() -> String:
	if not is_online():
		return "offline — keyword orders"
	return "%s %s (key: %s)" % [provider(), model(), key_source()]


static func voice_allowed() -> bool:
	ensure_loaded()
	return mode == "both" or mode == "voice"


static func chat_allowed() -> bool:
	ensure_loaded()
	return mode == "both" or mode == "chat"


## Test hook: force offline (ignores every key source for this session).
static func force_offline() -> void:
	ensure_loaded()
	voice_engine = "off"   # automated tests stay silent (no OS speech during windowed runs)
	provider_pref = "openai"
	_env_keys["openai"] = ""
	_file_keys["openai"] = ""
