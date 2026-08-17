extends SceneTree
## 窗口模式 TTS 冒烟测试：确认系统语音存在且播报真正开始。

const DoubaoTTSScript = preload("res://ui/DoubaoTTS.gd")

var _started := false
var _ended := false


func _initialize() -> void:
	if not _test_doubao_response_parser():
		quit(1)
		return
	if DisplayServer.get_name() == "headless":
		print("[TEST_TTS] PASS: 豆包响应解析（headless 跳过系统音色播放）")
		quit(0)
		return
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_STARTED, _on_utterance_started)
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, _on_utterance_ended)

	var voices := DisplayServer.tts_get_voices()
	if voices.is_empty():
		push_error("[TEST_TTS] FAIL: 窗口模式未发现系统语音")
		quit(1)
		return

	TTSHelper.speak_with_name("礼貌小镇语音播报测试成功。", "小礼")
	var deadline := Time.get_ticks_msec() + 8000
	while not _ended and Time.get_ticks_msec() < deadline:
		await process_frame

	TTSHelper.stop()
	if not _started:
		push_error("[TEST_TTS] FAIL: TTS 未触发开始事件")
		quit(1)
		return

	print("[TEST_TTS] PASS: TTS started=%s ended=%s voices=%d" % [_started, _ended, voices.size()])
	quit(0)


func _test_doubao_response_parser() -> bool:
	var service: Node = DoubaoTTSScript.new()
	var sample := PackedByteArray([0x49, 0x44, 0x33, 0x04, 0x00, 0x00])
	var encoded := Marshalls.raw_to_base64(sample)
	var json_body := JSON.stringify({"code": 3000, "data": encoded}).to_utf8_buffer()
	var decoded: PackedByteArray = service._extract_audio(json_body, PackedStringArray(["Content-Type: application/json"]))
	if decoded != sample:
		push_error("[TEST_TTS] FAIL: 豆包 Base64 音频解析")
		return false
	var binary: PackedByteArray = service._extract_audio(sample, PackedStringArray(["Content-Type: audio/mpeg"]))
	if binary != sample:
		push_error("[TEST_TTS] FAIL: 豆包 MP3 二进制解析")
		return false
	var invalid: PackedByteArray = service._extract_audio('{"code":3001,"message":"bad token"}'.to_utf8_buffer(), PackedStringArray(["Content-Type: application/json"]))
	if not invalid.is_empty():
		push_error("[TEST_TTS] FAIL: 错误响应被误当成音频")
		return false
	print("[TEST_TTS] PASS: 豆包响应解析")
	return true


func _on_utterance_started(_utterance_id: int) -> void:
	_started = true


func _on_utterance_ended(_utterance_id: int) -> void:
	_ended = true
