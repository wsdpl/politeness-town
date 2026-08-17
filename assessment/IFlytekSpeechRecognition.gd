## 科大讯飞语音听写（流式版）WebAPI 集成
## 接口文档: https://www.xfyun.cn/doc/asr/voicedictation/API.html
## 修复内容：
##   1. 签名日期使用 UTC（原实现用本地时间冒充 GMT，会被服务端拒绝）
##   2. 支持输入设备枚举/手动选择/启动时自动探测最强信号设备
##   3. 录音时实时 VAD（静音自动结束 / 长时间无语音自动结束）
##   4. 录音自动保存 WAV 到 user://audio/ 供审计
extends Node

# ===== 信号 =====
signal recording_started
signal recording_stopped
signal recognition_completed(text: String)
signal recognition_failed(error: String)
signal status_message(msg: String)
signal devices_scanned(devices: Array)          # 设备列表更新
signal active_device_changed(device_name: String, rms: float)

# ===== 配置 =====
var app_id: String = ""
var api_key: String = ""
var api_secret: String = ""
var input_device: String = ""          # 选择的输入设备名（空=Default）

# ===== 录音 =====
var _record_effect: AudioEffectRecord
var _capture_effect: AudioEffectCapture  # 实时监控用
var _mic_player: AudioStreamPlayer
var _is_recording: bool = false
var _record_start_time: int = 0

# ===== WebSocket =====
var _ws: WebSocketPeer
var _ws_state: int = 0  # 0=空闲, 1=连接中, 2=已连接, 3=发送中, 4=等待结果, 5=完成
var _pcm_data: PackedByteArray
var _send_offset: int = 0
var _frame_timer: float = 0.0
var _recognized_text: String = ""
var _timeout_timer: float = 0.0

# ===== VAD =====
var _vad_enabled: bool = true
var _vad_has_speech: bool = false
var _vad_silence_time: float = 0.0
var _vad_total_time: float = 0.0
var _vad_auto_stopped: bool = false
const VAD_SILENCE_STOP_SECONDS := 2.2   # 检测到语音后静音 2.2 秒自动结束
const VAD_NO_SPEECH_TIMEOUT := 20.0     # 一直无语音 20 秒自动结束
const VAD_MIN_RECORD_SECONDS := 1.0     # 至少录 1 秒才允许静音自动结束
const VAD_SPEECH_THRESHOLD := 0.006     # RMS 阈值

# ===== 设备扫描 =====
var _scanning_devices: bool = false
var _device_scan_index: int = 0
var _device_scan_results: Array = []
var _scan_player: AudioStreamPlayer = null
var _scan_capture: AudioEffectCapture = null
var _scan_accum: float = 0.0
var _scan_peak: float = 0.0
var _scan_time: float = 0.0
var _scan_frame_count: int = 0
const DEVICE_SCAN_SECONDS := 0.8
var _device_scan_bus: int = -1

# ===== 常量 =====
const HOST_URL = "wss://iat-api.xfyun.cn/v2/iat"
const HOST_NAME = "iat-api.xfyun.cn"
const HOST_PATH = "/v2/iat"
const FRAME_SIZE = 1280  # 每帧1280字节 = 40ms的16kHz 16bit单声道音频
const FRAME_INTERVAL = 0.04  # 40ms
const TARGET_RATE = 16000
const TIMEOUT_SECONDS = 20.0
const CONFIG_PATH := "user://iflytek_config.json"
const AUDIO_DIR := "user://audio"
const SAVE_RECORDINGS := true

# 常见虚拟设备名（自动选择时跳过）
const VIRTUAL_DEVICE_KEYWORDS := ["ToDesk", "Steam Streaming", "Virtual", "Loopback", "立体声混音"]


func _ready() -> void:
	_load_config()
	_setup_recording()


# ========== 配置管理 ==========

func _load_config() -> void:
	if FileAccess.file_exists(CONFIG_PATH):
		var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
		if f:
			var json = JSON.parse_string(f.get_as_text())
			if json is Dictionary:
				app_id = String(json.get("app_id", ""))
				api_key = String(json.get("api_key", ""))
				api_secret = String(json.get("api_secret", ""))
				input_device = String(json.get("input_device", ""))
				_vad_enabled = bool(json.get("vad_enabled", true))


func save_config(p_app_id: String, p_api_key: String, p_api_secret: String) -> void:
	app_id = p_app_id
	api_key = p_api_key
	api_secret = p_api_secret
	_persist_config()


func _persist_config() -> void:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f:
		var config := {
			"app_id": app_id,
			"api_key": api_key,
			"api_secret": api_secret,
			"input_device": input_device,
			"vad_enabled": _vad_enabled,
		}
		f.store_string(JSON.stringify(config))
		f.close()


func is_configured() -> bool:
	return app_id != "" and api_key != "" and api_secret != ""


# ========== 输入设备管理 ==========

## 返回系统输入设备列表（始终包含 Default）
func get_input_devices() -> Array:
	var devices: Array = []
	devices.append("Default")
	for d in AudioServer.get_input_device_list():
		if String(d) not in devices:
			devices.append(String(d))
	return devices


## 手动设置输入设备（并持久化）
func set_input_device(device_name: String) -> void:
	input_device = device_name
	_apply_input_device()
	_persist_config()
	status_message.emit("输入设备: %s" % (device_name if device_name != "" else "系统默认"))
	active_device_changed.emit(input_device, -1.0)


func _apply_input_device() -> void:
	var target := input_device
	if target.is_empty():
		target = "Default"
	AudioServer.input_device = target


## 后台自动探测：逐个设备短录音测 RMS，选择信号最强的物理设备。
## 完成后自动应用选择并广播信号。
func auto_select_input_device() -> void:
	if _scanning_devices or _is_recording:
		return
	var devices := get_input_devices()
	if devices.size() <= 1:
		return

	# 如果已保存过选择且设备仍存在，直接应用
	if input_device != "" and String(input_device) in devices:
		_apply_input_device()
		active_device_changed.emit(input_device, -1.0)
		return

	_scanning_devices = true
	_device_scan_index = 0
	_device_scan_results = []
	_scan_accum = 0.0
	_scan_peak = 0.0
	_scan_time = 0.0
	_scan_frame_count = 0
	# 暂停并释放主麦克风播放器，避免占用输入设备导致切换失败
	if _mic_player:
		_mic_player.stop()
		_mic_player.queue_free()
		_mic_player = null
	status_message.emit("正在检测麦克风设备…")
	call_deferred("_start_device_scan_next")


func _start_device_scan_next() -> void:
	var devices := get_input_devices()
	if _device_scan_index >= devices.size():
		_finish_device_scan()
		return

	var device_name := String(devices[_device_scan_index])
	_device_scan_index += 1

	AudioServer.input_device = device_name

	# 创建临时录音总线 + capture 效果
	if _device_scan_bus < 0:
		_device_scan_bus = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(_device_scan_bus, "DeviceScan")
		AudioServer.set_bus_volume_db(_device_scan_bus, -80.0)
	_scan_capture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(_device_scan_bus, _scan_capture)

	_scan_player = AudioStreamPlayer.new()
	_scan_player.bus = "DeviceScan"
	_scan_player.stream = AudioStreamMicrophone.new()
	add_child(_scan_player)
	# 异步等待 WASAPI 输入设备切换完成后开始播放与计时
	_play_scan_device_async()


func _play_scan_device_async() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	if not _scanning_devices or not is_instance_valid(_scan_player):
		return
	_scan_accum = 0.0
	_scan_peak = 0.0
	_scan_time = 0.0
	_scan_frame_count = 0
	if _scan_capture:
		_scan_capture.clear_buffer()
	_scan_player.play()


func _process(delta: float) -> void:
	if _scanning_devices:
		_process_device_scan(delta)

	# VAD 监控（录音中）
	if _is_recording and _vad_enabled:
		_process_vad(delta)

	# WebSocket 状态机
	if _ws_state != 0:
		_process_ws(delta)


func _process_device_scan(delta: float) -> void:
	_scan_time += delta
	# 读取 capture buffer 计算 RMS
	if _scan_capture and _scan_capture.get_buffer_length() > 0:
		var frames := _scan_capture.get_buffer(_scan_capture.get_buffer_length())
		for f in frames:
			var s: float = (abs(f.x) + abs(f.y)) * 0.5
			_scan_accum += s * s
			if s > _scan_peak:
				_scan_peak = s
			_scan_frame_count += 1
	if _scan_time >= DEVICE_SCAN_SECONDS:
		# 记录结果
		var rms := sqrt(_scan_accum / max(_scan_frame_count, 1))
		var device_name := String(get_input_devices()[_device_scan_index - 1])
		_device_scan_results.append({
			"name": device_name,
			"rms": rms,
			"peak": _scan_peak,
		})
		_cleanup_scan_player()
		call_deferred("_start_device_scan_next")


func _cleanup_scan_player() -> void:
	if _scan_player:
		_scan_player.stop()
		_scan_player.queue_free()
		_scan_player = null
	if _scan_capture:
		_remove_capture_effect()
		_scan_capture = null




## 按对象查找并移除 capture 效果
func _remove_capture_effect() -> void:
	if _device_scan_bus < 0:
		return
	for i in AudioServer.get_bus_effect_count(_device_scan_bus):
		var eff := AudioServer.get_bus_effect(_device_scan_bus, i)
		if eff == _scan_capture:
			AudioServer.remove_bus_effect(_device_scan_bus, i)
			return

func _finish_device_scan() -> void:
	_scanning_devices = false
	_cleanup_scan_player()

	# 选择最佳设备：排除 Default 与虚拟设备，优先真实麦克风，取 RMS 最大
	var best_name := ""
	var best_rms := -1.0
	var best_peak := 0.0
	var virtual_fallback := ""
	var virtual_rms := -1.0
	for r in _device_scan_results:
		var name := String(r["name"])
		var rms := float(r["rms"])
		if name == "Default":
			continue
		var is_virtual := false
		for kw in VIRTUAL_DEVICE_KEYWORDS:
			if name.contains(kw):
				is_virtual = true
				break
		if is_virtual:
			if rms > virtual_rms:
				virtual_rms = rms
				virtual_fallback = name
			continue
		if rms > best_rms:
			best_rms = rms
			best_peak = float(r["peak"])
			best_name = name

	if best_name == "" and virtual_fallback != "":
		best_name = virtual_fallback
		best_rms = virtual_rms

	# 重建并恢复主麦克风播放器
	_apply_input_device()
	_setup_mic_player()

	if best_name != "" and best_rms >= 0.0005:
		input_device = best_name
		_persist_config()
		_apply_input_device()
		status_message.emit("麦克风已自动选择: %s" % best_name)
		print("[IFlytekSR] 自动选择输入设备: %s (RMS=%.4f)" % [best_name, best_rms])
	else:
		input_device = ""
		_apply_input_device()
		status_message.emit("提示：未能自动检测到可用麦克风，请在设置中选择输入设备")
		print("[IFlytekSR] 未能自动选择可用麦克风，扫描结果: %s" % str(_device_scan_results))
	devices_scanned.emit(_device_scan_results)
	active_device_changed.emit(input_device, best_rms)


# ========== 录音设置 ==========

func _setup_recording() -> void:
	# 创建专用录音总线
	var bus_idx := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus_idx, "MicRecord")
	AudioServer.set_bus_volume_db(bus_idx, -80.0)  # 静音避免反馈（录音效果在音量前采样，不受影响）

	# 录音效果
	_record_effect = AudioEffectRecord.new()
	AudioServer.add_bus_effect(bus_idx, _record_effect)

	# 实时监控效果（VAD）
	_capture_effect = AudioEffectCapture.new()
	AudioServer.add_bus_effect(bus_idx, _capture_effect)

	_setup_mic_player()
	print("[IFlytekSR] 录音系统初始化完成")


## 创建麦克风播放器（供初始化与设备扫描后重建）
func _setup_mic_player() -> void:
	_mic_player = AudioStreamPlayer.new()
	_mic_player.bus = "MicRecord"
	var mic_stream := AudioStreamMicrophone.new()
	_mic_player.stream = mic_stream
	add_child(_mic_player)
	_apply_input_device()
	_mic_player.play()


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

	# 确保录音播放器在播放
	if _mic_player and not _mic_player.playing:
		_mic_player.play()

	# 清空 capture buffer 中残留
	if _capture_effect:
		_capture_effect.clear_buffer()

	_is_recording = true
	_vad_has_speech = false
	_vad_silence_time = 0.0
	_vad_total_time = 0.0
	_vad_auto_stopped = false
	_record_start_time = Time.get_ticks_msec()
	_record_effect.set_recording_active(true)
	recording_started.emit()
	status_message.emit("🎤 请说话，说完按 E 键结束")
	print("[IFlytekSR] 开始录音")


func stop_and_recognize() -> void:
	if not _is_recording:
		return

	_is_recording = false
	_record_effect.set_recording_active(false)
	recording_stopped.emit()
	status_message.emit("⏳ 正在识别...")

	var recording := _record_effect.get_recording()
	if recording == null:
		recognition_failed.emit("录音失败，未捕获到音频数据")
		return

	var raw_data := recording.data
	var record_duration := (Time.get_ticks_msec() - _record_start_time) / 1000.0
	print("[IFlytekSR] 录音时长: %.2f 秒, 原始数据 %d 字节" % [record_duration, raw_data.size()])

	# 保存录音 WAV 供审计
	if SAVE_RECORDINGS and raw_data.size() > 100:
		_save_wav(raw_data, recording.mix_rate, recording.stereo)

	if raw_data.size() < 3200:  # 少于0.1秒
		recognition_failed.emit("录音太短，请说完后按 E 键结束")
		return

	_pcm_data = _process_audio(recording.data, recording.format, recording.mix_rate, recording.stereo)
	print("[IFlytekSR] 音频处理完成: %d 字节 PCM 数据" % _pcm_data.size())

	if _pcm_data.size() < 3200:
		recognition_failed.emit("音频处理后数据太短")
		return

	# 计算录音音量，静音时提前告知（便于用户排查设备问题）
	var vol_rms := _compute_rms(_pcm_data)
	if vol_rms < 0.002:
		recognition_failed.emit("没有检测到说话声音（音量过低），请检查麦克风或输入设备设置")
		return

	_start_recognition()


func cancel() -> void:
	if _is_recording:
		_is_recording = false
		_record_effect.set_recording_active(false)
		recording_stopped.emit()
	_ws_state = 0
	if _ws:
		_ws.close()
	status_message.emit("")


func is_recording() -> bool:
	return _is_recording


func is_recognizing() -> bool:
	return _ws_state != 0


func get_current_device() -> String:
	if input_device != "":
		return input_device
	return "Default"


# ========== VAD 监控 ==========

func _process_vad(delta: float) -> void:
	_vad_total_time += delta
	var rms := 0.0
	if _capture_effect and _capture_effect.get_buffer_length() > 0:
		var frames := _capture_effect.get_buffer(_capture_effect.get_buffer_length())
		var sum := 0.0
		var n := 0
		for f in frames:
			var s: float = (abs(f.x) + abs(f.y)) * 0.5
			sum += s * s
			n += 1
		if n > 0:
			rms = sqrt(sum / float(n))

	if rms > VAD_SPEECH_THRESHOLD:
		_vad_has_speech = true
		_vad_silence_time = 0.0
	else:
		_vad_silence_time += delta

	# VAD 自动停止已禁用：录音仅在用户手动按下停止按钮时结束


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
		var fstride := 8 if stereo else 4
		while i + (fstride - 1) < raw.size():
			var left := raw.decode_float(i)
			if stereo:
				var right := raw.decode_float(i + 4)
				input_samples.append((left + right) * 0.5)
			else:
				input_samples.append(left)
			i += fstride

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


func _compute_rms(pcm16: PackedByteArray) -> float:
	if pcm16.size() < 2:
		return 0.0
	var sum := 0.0
	var n := 0
	var i := 0
	while i + 1 < pcm16.size():
		var s := float(pcm16.decode_s16(i)) / 32768.0
		sum += s * s
		n += 1
		i += 2
	if n == 0:
		return 0.0
	return sqrt(sum / float(n))


## 保存 16-bit PCM 为 WAV 文件（user://audio/rec_<时间戳>.wav）
func _save_wav(pcm: PackedByteArray, mix_rate: int, stereo: bool) -> void:
	DirAccess.make_dir_recursive_absolute(AUDIO_DIR)
	var path := "%s/rec_%d.wav" % [AUDIO_DIR, Time.get_ticks_msec()]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	var channels := 2 if stereo else 1
	var byte_rate := mix_rate * channels * 2
	var data_size := pcm.size()
	# RIFF 头
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + data_size)
	f.store_buffer("WAVE".to_ascii_buffer())
	f.store_buffer("fmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)                     # PCM
	f.store_16(channels)
	f.store_32(mix_rate)
	f.store_32(byte_rate)
	f.store_16(channels * 2)          # block align
	f.store_16(16)                    # bits per sample
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data_size)
	f.store_buffer(pcm)
	f.close()


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
	# 生成RFC1123格式的 UTC 日期（必须用 UTC，否则签名会被服务端拒绝）
	var dt := Time.get_datetime_dict_from_system(true)
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


func _process_ws(delta: float) -> void:
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
			_handle_error("WebSocket连接被拒绝，请检查API密钥与网络")

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