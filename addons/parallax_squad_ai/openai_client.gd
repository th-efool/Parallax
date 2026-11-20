class_name OpenAIClient
extends Node
## Minimal non-blocking AI client built on HTTPClient (no threads, polled in _process). Provider-aware
## (see SquadAIConfig): Gemini is preferred, OpenAI optional, any OpenAI-compatible endpoint works for chat.
##  - chat_stream(): OpenAI-style /chat/completions with "stream": true — SSE parsing, incremental text deltas
##    and *parallel* tool calls accumulated per index (Gemini's OpenAI-compatible endpoint uses the same wire format).
##  - transcribe(): Gemini generateContent with inline WAV (or OpenAI Whisper multipart upload).
##  - speak_stream(): Gemini streamGenerateContent?alt=sse with AUDIO modality (base64 PCM per event) or
##    OpenAI /audio/speech response_format "pcm" — both deliver 24 kHz s16le mono chunks as they arrive.
## Every failure is reported through `request_failed` — never an exception, never a crash.

signal text_delta(request_id: int, delta: String)
signal tool_call_received(request_id: int, tool_name: String, args: Dictionary, call_id: String)
signal chat_completed(request_id: int, text: String, tool_calls: Array)
signal transcribed(request_id: int, text: String)
signal tts_chunk(request_id: int, pcm: PackedByteArray)
signal tts_finished(request_id: int)
signal request_failed(request_id: int, kind: String, message: String)

const CONNECT_TIMEOUT_SEC: float = 8.0

var _jobs: Array[Job] = []
var _seq: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func has_key() -> bool:
	return SquadAIConfig.is_online()


func busy_count() -> int:
	return _jobs.size()


func cancel(request_id: int) -> void:
	for j in _jobs:
		if j.id == request_id:
			j.cancelled = true


func cancel_kind(kind: String) -> void:
	for j in _jobs:
		if j.kind == kind:
			j.cancelled = true


# ------------------------------------------------------------------ public API

func chat_stream(messages: Array, tools: Array = [], temperature: float = 0.8) -> int:
	var body: Dictionary = {
		"model": SquadAIConfig.model(),
		"messages": messages,
		"stream": true,
		"temperature": temperature,
	}
	if not tools.is_empty():
		body["tools"] = tools
		body["tool_choice"] = "auto"
		# Gemini emits parallel calls natively and rejects unknown params; OpenAI needs the flag.
		if SquadAIConfig.provider() != "gemini":
			body["parallel_tool_calls"] = true
	return _start("chat", SquadAIConfig.base_url() + "/chat/completions", JSON.stringify(body).to_utf8_buffer(), "application/json", _bearer())


func transcribe(wav_bytes: PackedByteArray, prompt_hint: String = "") -> int:
	if SquadAIConfig.provider() == "gemini":
		var body: Dictionary = {
			"contents": [{"role": "user", "parts": [
				{"text": "Listen to the audio and transcribe only what the player actually spoke verbatim. If the audio is silence, background noise, or inaudible, reply with empty text. Do not invent words or repeat instructions. " + prompt_hint},
				{"inline_data": {"mime_type": "audio/wav", "data": Marshalls.raw_to_base64(wav_bytes)}},
			]}],
			"generationConfig": {"temperature": 0.0},
		}
		var url: String = "%s/models/%s:generateContent" % [SquadAIConfig.native_url(), SquadAIConfig.stt_model()]
		return _start("stt_gemini", url, JSON.stringify(body).to_utf8_buffer(), "application/json", _goog())
	var boundary: String = "----parallax%d" % Time.get_ticks_usec()
	var mb := PackedByteArray()
	mb.append_array(_form_field(boundary, "model", SquadAIConfig.stt_model()))
	if not prompt_hint.is_empty():
		mb.append_array(_form_field(boundary, "prompt", prompt_hint))
	mb.append_array(("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\n" % boundary).to_utf8_buffer())
	mb.append_array(wav_bytes)
	mb.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	return _start("stt", SquadAIConfig.base_url() + "/audio/transcriptions", mb, "multipart/form-data; boundary=" + boundary, _bearer())


## `voice` = provider voice id; `style` = delivery hint (OpenAI `instructions` field only — never prepended into Gemini text).
func speak_stream(text: String, voice: String, style: String = "") -> int:
	var clean_text: String = text.strip_edges()
	# Ensure no prompt-leak: "Say: ..." or instructions
	var patterns: PackedStringArray = ["Say: ", "Speaks: ", "Voice: "]
	for p in patterns:
		if clean_text.begins_with(p):
			clean_text = clean_text.substr(p.length()).strip_edges()

	if SquadAIConfig.provider() == "gemini":
		var body: Dictionary = {
			"contents": [{"role": "user", "parts": [{"text": clean_text}]}],
			"generationConfig": {
				"responseModalities": ["AUDIO"],
				"speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": voice}}},
			},
		}
		var tm: String = SquadAIConfig.tts_model()
		if tm.is_empty():
			_seq += 1
			call_deferred("_fail_deferred", _seq, "tts_gemini", "QUOTA: all Gemini TTS models are out of quota for today.")
			return _seq
		var url: String = "%s/models/%s:streamGenerateContent?alt=sse" % [SquadAIConfig.native_url(), tm]
		var jid: int = _start("tts_gemini", url, JSON.stringify(body).to_utf8_buffer(), "application/json", _goog())
		for jb in _jobs:
			if jb.id == jid:
				jb.model = tm
		return jid
	var b2: Dictionary = {
		"model": SquadAIConfig.tts_model(),
		"input": clean_text,
		"voice": voice,
		"response_format": "pcm",
	}
	return _start("tts", SquadAIConfig.base_url() + "/audio/speech", JSON.stringify(b2).to_utf8_buffer(), "application/json", _bearer())


static func _bearer() -> PackedStringArray:
	return PackedStringArray(["Authorization: Bearer " + SquadAIConfig.api_key()])


static func _goog() -> PackedStringArray:
	return PackedStringArray(["x-goog-api-key: " + SquadAIConfig.api_key()])


static func _form_field(boundary: String, field: String, value: String) -> PackedByteArray:
	return ("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % [boundary, field, value]).to_utf8_buffer()


static func is_tts_kind(k: String) -> bool:
	return k == "tts" or k == "tts_gemini"


static func is_stt_kind(k: String) -> bool:
	return k == "stt" or k == "stt_gemini"


# ------------------------------------------------------------------ jobs

class Job:
	extends RefCounted
	var id: int = 0
	var kind: String = ""
	var path: String = ""
	var body: PackedByteArray = PackedByteArray()
	var content_type: String = ""
	var auth: PackedStringArray = PackedStringArray()
	var http: HTTPClient = null
	var stage: String = "connect"   # connect | response | body
	var started_ms: int = 0
	var code: int = 0
	var raw: PackedByteArray = PackedByteArray()      # unparsed SSE bytes / error body / stt body
	var text: String = ""
	var calls: Dictionary = {}       # index -> {id, name, args}
	var carry: PackedByteArray = PackedByteArray()    # odd PCM byte
	var cancelled: bool = false
	var model: String = ""


func _start(kind: String, url_s: String, body: PackedByteArray, content_type: String, auth: PackedStringArray) -> int:
	_seq += 1
	var j := Job.new()
	j.id = _seq
	j.kind = kind
	j.body = body
	j.content_type = content_type
	j.auth = auth
	j.started_ms = Time.get_ticks_msec()
	if SquadAIConfig.api_key().is_empty():
		call_deferred("_fail_deferred", j.id, kind, "No API key set (offline mode).")
		return j.id
	var url: Dictionary = _parse_url(url_s)
	if url.is_empty():
		call_deferred("_fail_deferred", j.id, kind, "Bad URL: %s" % url_s.left(60))
		return j.id
	j.path = String(url["path"])
	j.http = HTTPClient.new()
	var tls: TLSOptions = TLSOptions.client() if bool(url["tls"]) else null
	var err: int = j.http.connect_to_host(String(url["host"]), int(url["port"]), tls)
	if err != OK:
		call_deferred("_fail_deferred", j.id, kind, "Could not connect to %s (error %d)." % [url["host"], err])
		return j.id
	_jobs.append(j)
	return j.id


func _fail_deferred(id: int, kind: String, msg: String) -> void:
	request_failed.emit(id, kind, msg)


## "https://host[:port]/a/b?q" -> {host, port, tls, path:"/a/b?q"}
static func _parse_url(u: String) -> Dictionary:
	var s: String = u.strip_edges()
	var tls: bool = true
	if s.begins_with("https://"):
		s = s.substr(8)
	elif s.begins_with("http://"):
		s = s.substr(7)
		tls = false
	else:
		return {}
	var slash: int = s.find("/")
	var hostport: String = s if slash < 0 else s.substr(0, slash)
	var path: String = "/" if slash < 0 else s.substr(slash)
	var host: String = hostport
	var port: int = 443 if tls else 80
	var colon: int = hostport.rfind(":")
	if colon > 0:
		host = hostport.substr(0, colon)
		port = int(hostport.substr(colon + 1))
	if host.is_empty():
		return {}
	return {"host": host, "port": port, "tls": tls, "path": path}


func _process(_delta: float) -> void:
	if _jobs.is_empty():
		return
	for i in range(_jobs.size() - 1, -1, -1):
		var j: Job = _jobs[i]
		var finished: bool = _step(j)
		if finished:
			if j.http != null:
				j.http.close()
			_jobs.remove_at(i)


## Returns true when the job is over (success, failure or cancel).
func _step(j: Job) -> bool:
	if j.cancelled:
		return true
	# Refused / unroutable hosts can sit in CONNECTING for a long time on Windows: give up fast.
	if j.stage == "connect" and Time.get_ticks_msec() - j.started_ms > int(CONNECT_TIMEOUT_SEC * 1000.0):
		request_failed.emit(j.id, j.kind, "Cannot reach the AI endpoint (connect timeout).")
		return true
	if Time.get_ticks_msec() - j.started_ms > int(SquadAIConfig.request_timeout_sec * 1000.0) and j.stage != "body":
		request_failed.emit(j.id, j.kind, "Request timed out.")
		return true
	var err: int = j.http.poll()
	if err != OK:
		request_failed.emit(j.id, j.kind, "Connection error (%d)." % err)
		return true
	var st: int = j.http.get_status()
	match j.stage:
		"connect":
			if st == HTTPClient.STATUS_CONNECTED:
				var headers: PackedStringArray = j.auth.duplicate()
				headers.append("Content-Type: " + j.content_type)
				headers.append("Accept: " + ("text/event-stream" if j.kind == "chat" or j.kind == "tts_gemini" else "*/*"))
				headers.append("User-Agent: Parallax-SquadAI/1.1")
				var rerr: int = j.http.request_raw(HTTPClient.METHOD_POST, j.path, headers, j.body)
				if rerr != OK:
					request_failed.emit(j.id, j.kind, "Request failed to send (%d)." % rerr)
					return true
				j.stage = "response"
			elif st == HTTPClient.STATUS_CANT_CONNECT or st == HTTPClient.STATUS_CANT_RESOLVE or st == HTTPClient.STATUS_TLS_HANDSHAKE_ERROR or st == HTTPClient.STATUS_CONNECTION_ERROR:
				request_failed.emit(j.id, j.kind, "Cannot reach the AI endpoint (%s)." % _status_name(st))
				return true
		"response":
			if st == HTTPClient.STATUS_BODY or st == HTTPClient.STATUS_CONNECTED:
				j.code = j.http.get_response_code()
				j.stage = "body"
				if st == HTTPClient.STATUS_CONNECTED:
					return _finish(j)
			elif st == HTTPClient.STATUS_CONNECTION_ERROR or st == HTTPClient.STATUS_DISCONNECTED:
				request_failed.emit(j.id, j.kind, "Connection dropped.")
				return true
		"body":
			if st == HTTPClient.STATUS_BODY:
				var chunk: PackedByteArray = j.http.read_response_body_chunk()
				if not chunk.is_empty():
					_consume(j, chunk)
				if Time.get_ticks_msec() - j.started_ms > 90000:
					request_failed.emit(j.id, j.kind, "Stream took too long.")
					return true
			else:
				return _finish(j)
	return false


func _consume(j: Job, chunk: PackedByteArray) -> void:
	if j.code >= 400 or is_stt_kind(j.kind):
		j.raw.append_array(chunk)
		return
	if j.kind == "tts":
		_emit_pcm(j, chunk)
		return
	# SSE (chat, tts_gemini)
	j.raw.append_array(chunk)
	while true:
		var nl: int = j.raw.find(10)
		if nl < 0:
			break
		var line: String = j.raw.slice(0, nl).get_string_from_utf8().strip_edges()
		j.raw = j.raw.slice(nl + 1)
		if line.begins_with("data:"):
			if j.kind == "chat":
				_sse_data(j, line.substr(5).strip_edges())
			else:
				_gemini_audio_event(j, line.substr(5).strip_edges())


func _emit_pcm(j: Job, chunk: PackedByteArray) -> void:
	var data: PackedByteArray = j.carry + chunk
	if data.size() % 2 == 1:
		j.carry = data.slice(data.size() - 1)
		data = data.slice(0, data.size() - 1)
	else:
		j.carry = PackedByteArray()
	if not data.is_empty():
		tts_chunk.emit(j.id, data)


func _gemini_audio_event(j: Job, payload: String) -> void:
	var parsed: Variant = JSON.parse_string(payload)
	if not (parsed is Dictionary):
		return
	var d: Dictionary = parsed as Dictionary
	if d.has("error"):
		j.code = 500
		j.raw = payload.to_utf8_buffer()
		return
	for part in _gemini_parts(d):
		var inline: Variant = (part as Dictionary).get("inlineData", (part as Dictionary).get("inline_data", null))
		if inline is Dictionary:
			var b64: String = String((inline as Dictionary).get("data", ""))
			if not b64.is_empty():
				_emit_pcm(j, Marshalls.base64_to_raw(b64))


static func _gemini_parts(d: Dictionary) -> Array:
	var cands: Array = d.get("candidates", []) as Array
	if cands.is_empty() or not (cands[0] is Dictionary):
		return []
	var content: Dictionary = (cands[0] as Dictionary).get("content", {}) as Dictionary
	return content.get("parts", []) as Array


func _sse_data(j: Job, payload: String) -> void:
	if payload == "[DONE]" or payload.is_empty():
		return
	var parsed: Variant = JSON.parse_string(payload)
	if parsed is Array and not (parsed as Array).is_empty():
		parsed = (parsed as Array)[0]
	if not (parsed is Dictionary):
		return
	var d: Dictionary = parsed as Dictionary
	if d.has("error"):
		j.code = 500
		j.raw = payload.to_utf8_buffer()
		return
	var choices: Array = d.get("choices", []) as Array
	if choices.is_empty() or not (choices[0] is Dictionary):
		return
	var delta: Dictionary = (choices[0] as Dictionary).get("delta", {}) as Dictionary
	var content: Variant = delta.get("content", null)
	if content is String and not String(content).is_empty():
		j.text += String(content)
		text_delta.emit(j.id, String(content))
	var tcs: Variant = delta.get("tool_calls", null)
	if tcs is Array:
		for tc_v in (tcs as Array):
			if not (tc_v is Dictionary):
				continue
			var tc: Dictionary = tc_v as Dictionary
			# Some compatible servers omit `index` and send each call whole: give it the next free slot.
			var idx: int = int(tc.get("index", -1))
			if idx < 0:
				idx = j.calls.size()
			var entry: Dictionary = j.calls.get(idx, {"id": "", "name": "", "args": ""}) as Dictionary
			if tc.get("id", null) is String and not String(tc["id"]).is_empty():
				entry["id"] = String(tc["id"])
			# Gemini attaches a thought signature that must be echoed back in the history.
			if tc.get("extra_content", null) is Dictionary:
				entry["extra"] = tc["extra_content"]
			var fn: Dictionary = tc.get("function", {}) as Dictionary
			if fn.get("name", null) is String:
				entry["name"] = String(entry["name"]) + String(fn["name"])
			if fn.get("arguments", null) is String:
				entry["args"] = String(entry["args"]) + String(fn["arguments"])
			j.calls[idx] = entry


func _finish(j: Job) -> bool:
	if j.code >= 400 or j.code == 0:
		var msg: String = _error_message(j)
		# Free-tier quota spent on this TTS model: skip it for the session; the TTS player retries the next one.
		if j.code == 429 and j.kind == "tts_gemini" and not j.model.is_empty():
			SquadAIConfig.mark_tts_exhausted(j.model)
			msg = "QUOTA %s: %s" % [j.model, msg]
		request_failed.emit(j.id, j.kind, msg)
		return true
	match j.kind:
		"chat":
			if not j.raw.is_empty():
				_sse_data(j, j.raw.get_string_from_utf8().strip_edges().trim_prefix("data:").strip_edges())
			if j.code >= 400:
				request_failed.emit(j.id, j.kind, _error_message(j))
				return true
			var out_calls: Array = []
			var keys: Array = j.calls.keys()
			keys.sort()
			var n: int = 0
			for k in keys:
				var e: Dictionary = j.calls[k]
				n += 1
				var call_id: String = String(e["id"]) if not String(e["id"]).is_empty() else "call_%d_%d" % [j.id, n]
				var args: Variant = JSON.parse_string(String(e["args"])) if not String(e["args"]).is_empty() else {}
				var ad: Dictionary = args as Dictionary if args is Dictionary else {}
				var oc: Dictionary = {"id": call_id, "name": String(e["name"]), "args": ad, "raw_args": String(e["args"]) if not String(e["args"]).is_empty() else "{}"}
				if e.has("extra"):
					oc["extra_content"] = e["extra"]
				out_calls.append(oc)
				tool_call_received.emit(j.id, String(e["name"]), ad, call_id)
			chat_completed.emit(j.id, j.text, out_calls)
		"stt":
			var parsed: Variant = JSON.parse_string(j.raw.get_string_from_utf8())
			var t: String = String((parsed as Dictionary).get("text", "")) if parsed is Dictionary else j.raw.get_string_from_utf8()
			transcribed.emit(j.id, t.strip_edges())
		"stt_gemini":
			var pg: Variant = JSON.parse_string(j.raw.get_string_from_utf8())
			var txt: String = ""
			if pg is Dictionary:
				for part in _gemini_parts(pg as Dictionary):
					txt += String((part as Dictionary).get("text", ""))
			transcribed.emit(j.id, txt.strip_edges().trim_prefix("\"").trim_suffix("\""))
		"tts_gemini":
			if j.code >= 400:
				request_failed.emit(j.id, j.kind, _error_message(j))
				return true
			tts_finished.emit(j.id)
		"tts":
			tts_finished.emit(j.id)
	return true


func _error_message(j: Job) -> String:
	var body: String = j.raw.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(body)
	if parsed is Array and not (parsed as Array).is_empty():
		parsed = (parsed as Array)[0]
	if parsed is Dictionary and (parsed as Dictionary).get("error", null) is Dictionary:
		var em: String = String(((parsed as Dictionary)["error"] as Dictionary).get("message", ""))
		if not em.is_empty():
			return "API %d: %s" % [j.code, em.left(160)]
	if j.code == 0:
		return "No response from the AI endpoint."
	return "API error %d." % j.code


static func _status_name(st: int) -> String:
	match st:
		HTTPClient.STATUS_CANT_RESOLVE:
			return "can't resolve host"
		HTTPClient.STATUS_CANT_CONNECT:
			return "can't connect"
		HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			return "TLS handshake failed"
	return "connection error"
