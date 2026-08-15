## 科大讯飞语音听写（流式版）WebAPI 集成
## 接口文档: https://www.xfyun.cn/doc/asr/voicedictation/API.html
extends Node

# ===== 信号 =====
signal recording_started
signal recording_stopped
signal recognition_completed(text: String)
signal recognition_failed(error: String)
signal status_message(msg: String)

# ===== 配置 =====
var app_id: String = ""
var api_key: String = ""
var api_secret: String = ""

# ===== 录音 =====
var _record_effect: AudioEffectRecord
var _mic_player: AudioStreamPlayer
var _is_recording: bool = false

# ===== WebSocket =====
var _ws: WebSocketPeer
var _ws_state: int = 0  # 0=空闲, 1=连接中, 2=已连接, 3=发送中, 4=等待结果, 5=完成
var _pcm_data: PackedByteArray
var _send_offset: int = 0
var _frame_timer: float = 0.0
var _recognized_text: String = ""
var _timeout_timer: float = 0.0

# ===== 常量 =====
const HOST_URL = "wss://iat-api.xfyun.cn/v2/iat"
const HOST_NAME = "iat-api.xfyun.cn"
const HOST_PATH = "/v2/iat"
const FRAME_SIZE = 1280  # 每帧1280字节 = 40ms的16kHz 16bit单声道音频
const FRAME_INTERVAL = 0.04  # 40ms
const TARGET_RATE = 16000
const TIMEOUT_SECONDS = 15.0


func _ready() -> void:
	_load_config()
	_setup_recording()


# ========== 配置管理 ==========

func _load_config() -> void:
	var path := "user://iflytek_config.json"
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var json = JSON.parse_string(f.get_as_text())
			if json is Dictionary:
				app_id = json.get("app_id", "")
				api_key = json.get("api_key", "")
				api_secret = json.get("api_secret", "")


func save_config(p_app_id: String, p_api_key: String, p_api_secret: String) -> void:
	app_id = p_app_id
	api_key = p_api_key
	api_secret = p_api_secret
	var path := "user://iflytek_config.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		var config := {
			"app_id": app_id,
			"api_key": api_key,
			"api_secret": api_secret,
		}
		f.store_string(JSON.stringify(config))


func is_configured() -> bool:
	return app_id != "" and api_key != "" and api_secret != ""


# ========== 录音设置 ==========

func _setup_recording() -> void:
	# 创建专用录音总线
	var bus_idx := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus_idx, "MicRecord")
	AudioServer.set_bus_volume_db(bus_idx, -80.0)  # 静音避免反馈

	# 添加录音效果
	_record_effect = AudioEffectRecord.new()
	AudioServer.add_bus_effect(bus_idx, _record_effect)

	# 创建麦克风播放器
	_mic_player = AudioStreamPlayer.new()
	_mic_player.bus = "MicRecord"
	var mic_stream := AudioStreamMicrophone.new()
	_mic_player.stream = mic_stream
	add_child(_mic_player)
	_mic_player.play()
	print("[IFlytekSR] 录音系统初始化完成")


# ========== 录音控制 ==========

func start_recording() -> void:
	if not is_configured():
		recognition_failed.emit("讯飞API未配置，请在设置页面填写APP_ID、API_KEY和API_SECRET")
		return
	if _is_recording:
		return
	# 强制重置可能卡住的WebSocket状态
	if _ws_state != 0:
		_ws_state = 0
		if _ws:
			_ws.close()
			_ws = null

	_is_recording = true
	_record_effect.set_recording_active(true)
	recording_started.emit()
	status_message.emit("正在录音...")
	print("[IFlytekSR] 开始录音")


func stop_and_recognize() -> void:
	if not _is_recording:
		return

	_is_recording = false
	_record_effect.set_recording_active(false)
	recording_stopped.emit()
	status_message.emit("正在识别...")

	var recording := _record_effect.get_recording()
	if recording == null:
		recognition_failed.emit("录音失败，未捕获到音频数据")
		return

	var raw_data := recording.data
	if raw_data.size() < 3200:  # 少于0.1秒
		recognition_failed.emit("录音太短，请长按按钮说话")
		return

	_pcm_data = _process_audio(recording.data, recording.format, recording.mix_rate, recording.stereo)
	print("[IFlytekSR] 音频处理完成: %d 字节 PCM 数据" % _pcm_data.size())

	if _pcm_data.size() < 3200:
		recognition_failed.emit("音频处理后数据太短")
		return

	_start_recognition()


# ========== 音频处理 ==========

func _process_audio(raw: PackedByteArray, format: int, mix_rate: int, stereo: bool) -> PackedByteArray:
	# 1. 提取单声道浮点样本
	var input_samples := []
	var i := 0
	var stride := 2
	if stereo:
		stride = 4

	if format == AudioStreamWAV.FORMAT_16_BITS:
		i = 0
		while i + (stride - 1) < raw.size():
			var left := raw.decode_s16(i)
			if stereo:
				var right := raw.decode_s16(i + 2)
				input_samples.append(float(left + right) * 0.5)
			else:
				input_samples.append(float(left))
			i += stride
	else:
		# 其他格式按 32-bit float 解码（兼容性后备）
		i = 0
		stride = 4 if stereo else 4
		while i + (stride - 1) < raw.size():
			var left := raw.decode_float(i)
			if stereo:
				var right := raw.decode_float(i + 4)
				input_samples.append((left + right) * 0.5)
			else:
				input_samples.append(left)
			i += stride

	if input_samples.is_empty():
		return PackedByteArray()

	# 2. 重采样到16kHz
	var ratio := float(mix_rate) / float(TARGET_RATE)
	var output_count := int(input_samples.size() / ratio)
	var output := PackedByteArray()

	for j in range(output_count):
		var src_idx := j * ratio
		var idx0 := int(src_idx)
		if idx0 >= input_samples.size() - 1:
			_append_s16(output, int(clamp(input_samples[-1], -32768.0, 32767.0)))
			continue
		var idx1 := idx0 + 1
		var frac := src_idx - idx0
		var sample: float = float(input_samples[idx0]) * (1.0 - frac) + float(input_samples[idx1]) * frac
		_append_s16(output, int(clamp(sample, -32768.0, 32767.0)))

	return output


func _append_s16(buf: PackedByteArray, value: int) -> void:
	buf.append(value & 0xFF)
	buf.append((value >> 8) & 0xFF)


# ========== WebSocket 识别流程 ==========

func _start_recognition() -> void:
	_recognized_text = ""
	_send_offset = 0
	_frame_timer = 0.0
	_timeout_timer = 0.0
	_ws_state = 1

	var url := _build_auth_url()
	_ws = WebSocketPeer.new()
	var err := _ws.connect_to_url(url)
	if err != OK:
		recognition_failed.emit("WebSocket连接失败: 错误码 %d" % err)
		_ws_state = 0
		return
	print("[IFlytekSR] 正在连接讯飞WebSocket...")


func _build_auth_url() -> String:
	# 生成RFC1123格式的UTC日期
	var dt := Time.get_datetime_dict_from_system(false)
	var days := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var date_str := "%s, %02d %s %d %02d:%02d:%02d GMT" % [
		days[dt.weekday], dt.day, months[dt.month - 1], dt.year,
		dt.hour, dt.minute, dt.second
	]

	# 构建签名原始字符串
	var signature_origin := "host: %s\ndate: %s\nGET %s HTTP/1.1" % [HOST_NAME, date_str, HOST_PATH]

	# HMAC-SHA256签名
	var hmac := HMACContext.new()
	hmac.start(HashingContext.HASH_SHA256, api_secret.to_utf8_buffer())
	hmac.update(signature_origin.to_utf8_buffer())
	var signature_bytes := hmac.finish()
	var signature := Marshalls.raw_to_base64(signature_bytes)

	# 构建authorization
	var authorization_origin := 'api_key="%s", algorithm="hmac-sha256", headers="host date request-line", signature="%s"' % [api_key, signature]
	var authorization := Marshalls.raw_to_base64(authorization_origin.to_utf8_buffer())

	# 构建最终URL
	var url := "%s?authorization=%s&date=%s&host=%s" % [
		HOST_URL,
		authorization.uri_encode(),
		date_str.uri_encode(),
		HOST_NAME.uri_encode()
	]
	return url


func _process(delta: float) -> void:
	if _ws_state == 0:
		return

	# 超时检查
	_timeout_timer += delta
	if _timeout_timer > TIMEOUT_SECONDS:
		_handle_error("识别超时，请重试")
		return

	if _ws_state == 1:
		# 连接中
		_ws.poll()
		var state := _ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			_ws_state = 2
			print("[IFlytekSR] WebSocket已连接，开始发送音频")
			_send_first_frame()
		elif state == WebSocketPeer.STATE_CLOSED:
			_handle_error("WebSocket连接被拒绝，请检查API密钥")

	elif _ws_state == 2 or _ws_state == 3:
		# 发送音频数据
		_ws.poll()
		_frame_timer += delta
		if _frame_timer >= FRAME_INTERVAL:
			_frame_timer = 0.0
			_send_audio_frame()

		# 接收结果
		_receive_messages()

		if _send_offset >= _pcm_data.size() and _ws_state == 3:
			# 所有数据已发送，发送结束帧
			_send_end_frame()
			_ws_state = 4

	elif _ws_state == 4:
		# 等待最终结果
		_ws.poll()
		_receive_messages()

		if _ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			if _recognized_text.is_empty():
				_handle_error("未识别到语音内容")
			else:
				_ws_state = 0
				status_message.emit("")
				recognition_completed.emit(_recognized_text)
				print("[IFlytekSR] 识别完成: %s" % _recognized_text)


func _send_first_frame() -> void:
	# 首帧包含common、business和data
	var first_frame := {
		"common": {"app_id": app_id},
		"business": {
			"language": "zh_cn",
			"domain": "iat",
			"accent": "mandarin",
			"vad_eos": 5000,
			"dwa": "wpgs",
		},
		"data": {
			"status": 0,
			"format": "audio/L16;rate=16000",
			"audio": _get_base64_chunk(),
			"encoding": "raw",
		}
	}
	_ws.send_text(JSON.stringify(first_frame))
	_ws_state = 3
	print("[IFlytekSR] 首帧已发送")


func _send_audio_frame() -> void:
	if _send_offset >= _pcm_data.size():
		return

	var frame := {
		"data": {
			"status": 1,
			"format": "audio/L16;rate=16000",
			"audio": _get_base64_chunk(),
			"encoding": "raw",
		}
	}
	_ws.send_text(JSON.stringify(frame))


func _send_end_frame() -> void:
	var end_frame := {
		"data": {
			"status": 2,
			"format": "audio/L16;rate=16000",
			"audio": "",
			"encoding": "raw",
		}
	}
	_ws.send_text(JSON.stringify(end_frame))
	print("[IFlytekSR] 结束帧已发送")


func _get_base64_chunk() -> String:
	var end: int = mini(_send_offset + FRAME_SIZE, _pcm_data.size())
	var chunk := _pcm_data.slice(_send_offset, end)
	_send_offset = end
	return Marshalls.raw_to_base64(chunk)


func _receive_messages() -> void:
	while _ws.get_available_packet_count() > 0:
		var packet := _ws.get_packet()
		var text := packet.get_string_from_utf8()
		if text.is_empty():
			continue
		var json = JSON.parse_string(text)
		if json == null:
			continue
		if json.get("code", -1) != 0:
			_handle_error("讯飞API错误: %s" % json.get("message", "未知错误"))
			return
		var data = json.get("data", {})
		if data is Dictionary:
			var result = data.get("result", {})
			if result is Dictionary:
				var ws_arr = result.get("ws", [])
				if ws_arr is Array:
					for ws_item in ws_arr:
						var cw_arr = ws_item.get("cw", [])
						if cw_arr is Array:
							for cw_item in cw_arr:
								_recognized_text += cw_item.get("w", "")
			var status = data.get("status", 0)
			if status == 2:
				# 最终结果
				_ws.close()
				if not _recognized_text.is_empty():
					_ws_state = 0
					status_message.emit("")
					recognition_completed.emit(_recognized_text)
					print("[IFlytekSR] 识别完成: %s" % _recognized_text)


func _handle_error(msg: String) -> void:
	_ws_state = 0
	status_message.emit("")
	if _ws:
		_ws.close()
	recognition_failed.emit(msg)
	print("[IFlytekSR] 错误: %s" % msg)


func is_recording() -> bool:
	return _is_recording


func is_recognizing() -> bool:
	return _ws_state != 0


func cancel() -> void:
	if _is_recording:
		_is_recording = false
		_record_effect.set_recording_active(false)
		recording_stopped.emit()
	_ws_state = 0
	if _ws:
		_ws.close()
	status_message.emit("")
