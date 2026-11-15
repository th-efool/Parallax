class_name LeaderboardManager
extends Node
## Autoloaded as `LeaderboardStore`.
## Manages offline Top-5 leaderboard persistence (`user://leaderboard.cfg`) and user settings (`user://settings.cfg`).

signal leaderboard_updated(entries: Array[Dictionary])
signal settings_changed(settings: Dictionary)

const LEADERBOARD_PATH: String = "user://leaderboard.cfg"
const SETTINGS_PATH: String = "user://settings.cfg"
const MAX_ENTRIES: int = 5

var _entries: Array[Dictionary] = []
var _settings: Dictionary = {}


func _ready() -> void:
	_ensure_audio_buses()
	_load_leaderboard_from_disk()
	_load_settings_from_disk()
	apply_settings()


func sanitize_initials(raw: String) -> String:
	var cleaned: String = ""
	var upper: String = raw.strip_edges().to_upper()
	for i in range(upper.length()):
		var ch: String = upper.substr(i, 1)
		var code: int = ch.unicode_at(0)
		var is_alpha: bool = (code >= 65 and code <= 90)
		var is_digit: bool = (code >= 48 and code <= 57)
		if is_alpha or is_digit:
			cleaned += ch
			if cleaned.length() == 3:
				break
	if cleaned.is_empty():
		return "WAR"
	return cleaned


func qualifies_for_top_five(score: int, time_sec: float) -> bool:
	if _entries.size() < MAX_ENTRIES:
		return true
	var fifth: Dictionary = _entries[MAX_ENTRIES - 1]
	var fifth_score: int = int(fifth.get("score", 0))
	var fifth_time: float = float(fifth.get("time_sec", 999999.0))
	if score > fifth_score:
		return true
	if score == fifth_score and time_sec < fifth_time:
		return true
	return false


func save_run(initials: String, score: int, time_sec: float, rank: String) -> int:
	var entry: Dictionary = {
		"initials": sanitize_initials(initials),
		"score": maxi(0, score),
		"time_sec": maxf(0.0, time_sec),
		"rank": rank if not rank.is_empty() else "C",
		"timestamp": Time.get_datetime_string_from_system(false, true),
		"_order": _entries.size(),
	}
	_entries.append(entry)
	_sort_entries()
	if _entries.size() > MAX_ENTRIES:
		_entries.resize(MAX_ENTRIES)

	var placed_index: int = -1
	for i in range(_entries.size()):
		if _entries[i] == entry:
			placed_index = i + 1
		# Re-index _order so future tie-breaks preserve chronological insertion order
		_entries[i]["_order"] = i

	_save_leaderboard_to_disk()
	leaderboard_updated.emit(get_top_five())
	return placed_index


func get_top_five() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for e in _entries:
		result.append({
			"initials": String(e.get("initials", "WAR")),
			"score": int(e.get("score", 0)),
			"time_sec": float(e.get("time_sec", 0.0)),
			"rank": String(e.get("rank", "C")),
			"timestamp": String(e.get("timestamp", "")),
		})
	return result


func reset_leaderboard() -> void:
	_entries.clear()
	_save_leaderboard_to_disk()
	leaderboard_updated.emit(get_top_five())


static func format_time(time_sec: float) -> String:
	var total_sec: int = maxi(0, int(floor(time_sec)))
	var mins: int = total_sec / 60
	var secs: int = total_sec % 60
	return "%02d:%02d" % [mins, secs]


func get_default_settings() -> Dictionary:
	return {
		"master_volume": 1.0,
		"music_volume": 0.85,
		"sfx_volume": 0.90,
		"mouse_sensitivity": 0.0025,
		"invert_y": false,
		"fullscreen": false,
		"resolution": Vector2i(1920, 1080),
	}


func get_settings() -> Dictionary:
	return _settings.duplicate()


func save_settings(new_settings: Dictionary) -> void:
	var defaults: Dictionary = get_default_settings()
	for k in defaults.keys():
		if new_settings.has(k):
			_settings[k] = new_settings[k]
		elif not _settings.has(k):
			_settings[k] = defaults[k]
	_save_settings_to_disk()
	apply_settings()
	settings_changed.emit(get_settings())


func restore_default_settings() -> Dictionary:
	_settings = get_default_settings()
	_save_settings_to_disk()
	apply_settings()
	settings_changed.emit(get_settings())
	return get_settings()


func apply_settings() -> void:
	_ensure_audio_buses()
	_apply_bus_volume("Master", float(_settings.get("master_volume", 1.0)))
	_apply_bus_volume("Music", float(_settings.get("music_volume", 0.85)))
	_apply_bus_volume("SFX", float(_settings.get("sfx_volume", 0.90)))

	if DisplayServer.get_name() != "headless":
		var is_fs: bool = bool(_settings.get("fullscreen", false))
		var target_mode: int = DisplayServer.WINDOW_MODE_FULLSCREEN if is_fs else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != target_mode:
			DisplayServer.window_set_mode(target_mode)
		if not is_fs:
			var res_val: Variant = _settings.get("resolution", Vector2i(1920, 1080))
			if res_val is Vector2i:
				var res: Vector2i = res_val as Vector2i
				if res.x >= 640 and res.y >= 360:
					DisplayServer.window_set_size(res)


func _ensure_audio_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			var idx: int = AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func _apply_bus_volume(bus_name: String, linear_vol: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		var vol: float = clampf(linear_vol, 0.0, 1.0)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(vol, 0.0001)))
		AudioServer.set_bus_mute(idx, vol <= 0.001)


func _sort_entries() -> void:
	_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: int = int(a.get("score", 0))
		var sb: int = int(b.get("score", 0))
		if sa != sb:
			return sa > sb
		var ta: float = float(a.get("time_sec", 999999.0))
		var tb: float = float(b.get("time_sec", 999999.0))
		if not is_equal_approx(ta, tb):
			return ta < tb
		return int(a.get("_order", 0)) < int(b.get("_order", 0))
	)


func _load_leaderboard_from_disk() -> void:
	_entries.clear()
	var cfg := ConfigFile.new()
	if cfg.load(LEADERBOARD_PATH) != OK:
		return
	var count: int = mini(MAX_ENTRIES, int(cfg.get_value("meta", "count", 0)))
	for i in range(count):
		var sec: String = "entry_%d" % i
		if cfg.has_section(sec):
			_entries.append({
				"initials": sanitize_initials(String(cfg.get_value(sec, "initials", "WAR"))),
				"score": int(cfg.get_value(sec, "score", 0)),
				"time_sec": float(cfg.get_value(sec, "time_sec", 0.0)),
				"rank": String(cfg.get_value(sec, "rank", "C")),
				"timestamp": String(cfg.get_value(sec, "timestamp", "")),
				"_order": i,
			})
	_sort_entries()


func _save_leaderboard_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "count", _entries.size())
	for i in range(_entries.size()):
		var sec: String = "entry_%d" % i
		var e: Dictionary = _entries[i]
		cfg.set_value(sec, "initials", String(e.get("initials", "WAR")))
		cfg.set_value(sec, "score", int(e.get("score", 0)))
		cfg.set_value(sec, "time_sec", float(e.get("time_sec", 0.0)))
		cfg.set_value(sec, "rank", String(e.get("rank", "C")))
		cfg.set_value(sec, "timestamp", String(e.get("timestamp", "")))
	cfg.save(LEADERBOARD_PATH)


func _load_settings_from_disk() -> void:
	_settings = get_default_settings()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for k in _settings.keys():
		if cfg.has_section_key("settings", k):
			_settings[k] = cfg.get_value("settings", k, _settings[k])


func _save_settings_to_disk() -> void:
	var cfg := ConfigFile.new()
	for k in _settings.keys():
		cfg.set_value("settings", k, _settings[k])
	cfg.save(SETTINGS_PATH)
