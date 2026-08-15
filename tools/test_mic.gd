extends SceneTree
## 诊断 v4：AudioEffectCapture 是否能捕获麦克风（ToDesk 虚拟设备已知有音频）

func _measure(device: String) -> Dictionary:
	AudioServer.input_device = device
	await process_frame
	await create_timer(0.4).timeout
	var bus_idx := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus_idx, "CapTest%d" % bus_idx)
	AudioServer.set_bus_volume_db(bus_idx, -80.0)
	var cap := AudioEffectCapture.new()
	AudioServer.add_bus_effect(bus_idx, cap)
	var player := AudioStreamPlayer.new()
	player.bus = AudioServer.get_bus_name(bus_idx)
	player.stream = AudioStreamMicrophone.new()
	root.add_child(player)
	await process_frame
	await create_timer(0.3).timeout
	player.play()
	await create_timer(1.2).timeout
	var sum := 0.0
	var n := 0
	var peak := 0.0
	while cap.get_buffer_length() > 0:
		var frames := cap.get_buffer(cap.get_buffer_length())
		for f in frames:
			var s: float = (abs(f.x) + abs(f.y)) * 0.5
			sum += s * s
			if s > peak:
				peak = s
			n += 1
	var rms := sqrt(sum / max(n, 1))
	player.stop()
	player.queue_free()
	AudioServer.remove_bus_effect(bus_idx, 0)
	return {"device": device, "frames": n, "rms": rms, "peak": peak}

func _initialize() -> void:
	print("[TEST_CAP] 开始...")
	for d in AudioServer.get_input_device_list():
		var r := await _measure(String(d))
		print("[TEST_CAP] %s" % str(r))
	quit()
