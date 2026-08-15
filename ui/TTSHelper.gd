class_name TTSHelper
extends RefCounted
## NPC 语音朗读工具：使用 Godot 内置 DisplayServer TTS 朗读中文台词。

static var _voice_id: String = ""
static var _initialized: bool = false


static func _ensure_init() -> void:
	if _initialized:
		return
	_initialized = true

	var all_voices: Array[Dictionary] = DisplayServer.tts_get_voices()
	if all_voices.is_empty():
		print("[TTSHelper] 系统无可用TTS语音")
		return

	for voice: Dictionary in all_voices:
		var lang: String = voice.get("language", "")
		if lang.begins_with("zh"):
			_voice_id = voice.get("id", "")
			print("[TTSHelper] 使用中文语音: %s (id=%s)" % [voice.get("name", ""), _voice_id])
			return

	var first: Dictionary = all_voices[0]
	_voice_id = first.get("id", "")
	print("[TTSHelper] 未找到中文语音，使用默认语音: %s" % first.get("name", ""))


## 朗读文本。interrupt=true 时打断当前朗读。
static func speak(text: String, interrupt: bool = true) -> void:
	if text.strip_edges().is_empty():
		return
	_ensure_init()
	DisplayServer.tts_speak(text, _voice_id, 1.0, 1.0, 0, interrupt)


## 停止当前朗读。
static func stop() -> void:
	DisplayServer.tts_stop()
