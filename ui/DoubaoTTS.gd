class_name DoubaoTTS
extends Node
## 豆包/火山引擎 TTS 客户端。
## 使用 HTTP API 获取 MP3 后由 Godot AudioStreamPlayer 播放；请求失败时回退到 TTSHelper 的本机语音。

signal speech_started
signal speech_finished
signal speech_failed(message: String)

const DEFAULT_ENDPOINT := "https://openspeech.bytedance.com/api/v1/tts"
const DEFAULT_CLUSTER := "volcano_tts"
const DEFAULT_VOICE := "BV700_V2_streaming"
const CONFIG_PATH := "user://tts_config.json"

var _config: Dictionary = {
	"provider": "system",
	"endpoint": DEFAULT_ENDPOINT,
	"app_id": "",
	"access_token": "",
	"cluster": DEFAULT_CLUSTER,
	"voice_type": DEFAULT_VOICE,
	"voice_narrator": DEFAULT_VOICE,
	"voice_child": DEFAULT_VOICE,
	"voice_female": DEFAULT_VOICE,
	"voice_male": DEFAULT_VOICE,
	"encoding": "mp3",
	"sample_rate": 24000,
	"speed_ratio": 1.0,
	"pitch_ratio": 1.0,
}

var _http: HTTPRequest
var _player: AudioStreamPlayer
var _request_id := 0
var _active_text := ""
var _active_profile := 0


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)
	_player = AudioStreamPlayer.new()
	_player.finished.connect(_on_player_finished)
	add_child(_player)
	_load_config()


func get_config() -> Dictionary:
	return _config.duplicate(true)


func set_config(config: Dictionary) -> void:
	for key in config.keys():
		_config[key] = config[key]
	if String(_config.get("endpoint", "")).is_empty():
		_config["endpoint"] = DEFAULT_ENDPOINT
	if String(_config.get("cluster", "")).is_empty():
		_config["cluster"] = DEFAULT_CLUSTER
	if String(_config.get("voice_type", "")).is_empty():
		_config["voice_type"] = DEFAULT_VOICE
	_save_config()


func is_configured() -> bool:
	return String(_config.get("provider", "system")) == "doubao" \
		and not String(_config.get("endpoint", "")).strip_edges().is_empty() \
		and not String(_config.get("app_id", "")).strip_edges().is_empty() \
		and not String(_config.get("access_token", "")).strip_edges().is_empty() \
		and not String(_config.get("voice_type", "")).strip_edges().is_empty()


func speak(text: String, profile: int = 0) -> bool:
	if text.strip_edges().is_empty() or not is_configured():
		return false
	stop()
	_request_id += 1
	_active_text = text
	_active_profile = profile
	var voice_type := _voice_for_profile(profile)
	var body := {
		"app": {
			"appid": String(_config.get("app_id", "")),
			"token": String(_config.get("access_token", "")),
			"cluster": String(_config.get("cluster", DEFAULT_CLUSTER)),
		},
		"user": {"uid": "politeness-town"},
		"audio": {
			"voice_type": voice_type,
			"encoding": String(_config.get("encoding", "mp3")),
			"sample_rate": int(_config.get("sample_rate", 24000)),
			"speed_ratio": float(_config.get("speed_ratio", 1.0)),
			"pitch_ratio": float(_config.get("pitch_ratio", 1.0)),
			"volume_ratio": 1.0,
		},
		"request": {
			"reqid": _make_request_id(),
			"text": text,
			"text_type": "plain",
			"operation": "query",
		},
	}
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer;%s" % String(_config.get("access_token", "")),
	])
	var err := _http.request(String(_config.get("endpoint", DEFAULT_ENDPOINT)), headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_fail("豆包 TTS 请求启动失败（错误码 %d）" % err)
		return false
	return true


func stop() -> void:
	if is_instance_valid(_http):
		_http.cancel_request()
	if _player and _player.playing:
		_player.stop()
	_active_text = ""


func _voice_for_profile(profile: int) -> String:
	var key := "voice_narrator"
	match profile:
		1:
			key = "voice_child"
		2, 4:
			key = "voice_female"
		3, 5:
			key = "voice_male"
	var voice := String(_config.get(key, ""))
	return voice if not voice.is_empty() else String(_config.get("voice_type", DEFAULT_VOICE))


func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_fail("豆包 TTS HTTP %d" % response_code)
		return
	var audio_data := _extract_audio(body, headers)
	if audio_data.is_empty():
		_fail("豆包 TTS 返回中没有音频数据")
		return
	var stream := AudioStreamMP3.new()
	stream.data = audio_data
	_player.stream = stream
	_player.play()
	speech_started.emit()


func _extract_audio(body: PackedByteArray, headers: PackedStringArray = PackedStringArray()) -> PackedByteArray:
	var content_type := ""
	for header in headers:
		if header.to_lower().begins_with("content-type:"):
			content_type = header.split(":", false, 1)[1].strip_edges().to_lower()
			break
	# 二进制 MP3 响应不需要经过 JSON 解析，避免把音频头当作错误 JSON。
	if content_type.find("audio/mpeg") >= 0 or _looks_like_mp3(body):
		return body
	var raw_text := body.get_string_from_utf8()
	var parsed = JSON.parse_string(raw_text)
	if parsed is Dictionary:
		# 经典接口成功码为 3000；部分网关会省略 code，因此仅在存在且非成功时拒绝。
		var code_value = parsed.get("code", 3000)
		var code := int(code_value)
		if code != 0 and code != 3000:
			_fail("豆包 TTS 返回错误：%s" % String(parsed.get("message", code)))
			return PackedByteArray()
		var audio_value = parsed.get("data", parsed.get("audio", ""))
		if audio_value is Dictionary:
			audio_value = audio_value.get("audio", audio_value.get("data", ""))
		var encoded := String(audio_value)
		if not encoded.is_empty():
			var decoded := Marshalls.base64_to_raw(encoded)
			if not decoded.is_empty():
				return decoded
			_fail("豆包 TTS 音频 Base64 解码失败")
			return PackedByteArray()
	return PackedByteArray()


func _looks_like_mp3(body: PackedByteArray) -> bool:
	if body.size() >= 3 and body[0] == 0x49 and body[1] == 0x44 and body[2] == 0x33:
		return true # ID3
	return body.size() >= 2 and body[0] == 0xff and (body[1] & 0xe0) == 0xe0


func _make_request_id() -> String:
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(16).hex_encode()


func _on_player_finished() -> void:
	speech_finished.emit()


func _fail(message: String) -> void:
	print("[DoubaoTTS] %s" % message)
	speech_failed.emit(message)
	# 远程不可用时恢复本机声音，避免 NPC 完全静音。
	if not _active_text.is_empty():
		TTSHelper.speak_system(_active_text, _active_profile)
	_active_text = ""


func _load_config() -> void:
	if FileAccess.file_exists(CONFIG_PATH):
		var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				set_config(parsed)
			file.close()
	if String(_config.get("app_id", "")).is_empty():
		_config["app_id"] = OS.get_environment("DOUBAO_APP_ID")
	if String(_config.get("access_token", "")).is_empty():
		_config["access_token"] = OS.get_environment("DOUBAO_ACCESS_TOKEN")
	if String(_config.get("provider", "system")) == "system" \
		and not String(_config.get("app_id", "")).is_empty() \
		and not String(_config.get("access_token", "")).is_empty():
		_config["provider"] = "doubao"


func _save_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_config))
		file.close()
