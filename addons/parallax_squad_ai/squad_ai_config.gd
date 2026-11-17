class_name SquadAIConfig
extends RefCounted
## Settings for the Squad AI plugin. Stored in `user://squad_ai.cfg` (per user, never in the repo).
## The API key is read, in order, from: env `OPENAI_API_KEY` -> `user://squad_ai.cfg [api] key`.
## Base URL / model can also come from env `OPENAI_BASE_URL` / `PARALLAX_AI_MODEL` (any OpenAI-compatible
## endpoint works). With no key the game stays fully playable: chat uses the offline keyword parser.

const PATH: String = "user://squad_ai.cfg"
const MODES: Array[String] = ["both", "chat", "voice"]

static var _loaded: bool = false
static var base_url: String = "https://api.openai.com/v1"
static var model: String = "gpt-4o"
static var stt_model: String = "whisper-1"
static var tts_model: String = "gpt-4o-mini-tts"
static var _file_key: String = ""
## both | chat | voice
static var mode: String = "both"
static var tts_enabled: bool = true
static var show_command_log: bool = true
static var show_subtitles: bool = true
static var request_timeout_sec: float = 25.0


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		base_url = String(cf.get_value("api", "base_url", base_url))
		model = String(cf.get_value("api", "model", model))
		stt_model = String(cf.get_value("api", "stt_model", stt_model))
		tts_model = String(cf.get_value("api", "tts_model", tts_model))
		_file_key = String(cf.get_value("api", "key", ""))
		mode = String(cf.get_value("comms", "mode", mode))
		tts_enabled = bool(cf.get_value("comms", "tts_enabled", tts_enabled))
		show_command_log = bool(cf.get_value("comms", "show_command_log", show_command_log))
		show_subtitles = bool(cf.get_value("comms", "show_subtitles", show_subtitles))
	var env_url: String = OS.get_environment("OPENAI_BASE_URL")
	if not env_url.is_empty():
		base_url = env_url
	var env_model: String = OS.get_environment("PARALLAX_AI_MODEL")
	if not env_model.is_empty():
		model = env_model
	if not MODES.has(mode):
		mode = "both"


static func save() -> void:
	ensure_loaded()
	var cf := ConfigFile.new()
	cf.load(PATH)
	cf.set_value("api", "base_url", base_url)
	cf.set_value("api", "model", model)
	cf.set_value("api", "stt_model", stt_model)
	cf.set_value("api", "tts_model", tts_model)
	cf.set_value("api", "key", _file_key)
	cf.set_value("comms", "mode", mode)
	cf.set_value("comms", "tts_enabled", tts_enabled)
	cf.set_value("comms", "show_command_log", show_command_log)
	cf.set_value("comms", "show_subtitles", show_subtitles)
	cf.save(PATH)


static func api_key() -> String:
	ensure_loaded()
	var env_key: String = OS.get_environment("OPENAI_API_KEY")
	if not env_key.strip_edges().is_empty():
		return env_key.strip_edges()
	return _file_key.strip_edges()


static func key_source() -> String:
	if not OS.get_environment("OPENAI_API_KEY").strip_edges().is_empty():
		return "env OPENAI_API_KEY"
	ensure_loaded()
	return "user://squad_ai.cfg" if not _file_key.strip_edges().is_empty() else "none"


static func set_file_key(k: String) -> void:
	ensure_loaded()
	_file_key = k.strip_edges()
	save()


static func is_online() -> bool:
	return not api_key().is_empty()


static func voice_allowed() -> bool:
	ensure_loaded()
	return mode == "both" or mode == "voice"


static func chat_allowed() -> bool:
	ensure_loaded()
	return mode == "both" or mode == "chat"
