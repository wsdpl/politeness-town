extends SceneTree
## 端到端流程验收：注册 -> 预热 -> 板块一 -> 板块二 -> 结果页。

var _failures: Array[String] = []
var _manager: AssessmentGameManager
var _flow: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_manager = root.get_node("AssessmentGameManager")
	_flow = root.get_node("AssessmentFlowHost")
	# 验收数据只写本地，避免向不可达的公网服务发送测试儿童数据。
	ProjectSettings.set_setting("assessment/server_upload_enabled", false)
	_manager.register_child({"nickname": "端到端测试", "age": 5, "gender": "female"})
	_manager.set_ai_type(AssessmentGameManager.AiType.FRIEND)

	await _run_registration_to_warmup()
	await _run_warmup()
	await _run_politeness_house()
	await _run_sunshine_market()

	var session := AssessmentStorage.load_session_results(_manager.get_session_id())
	_expect(not session.is_empty(), "session saved after complete flow")
	_expect(int(session.get("turn_count", 0)) > 20, "session contains complete interaction turns")
	_expect(_manager.get_scenario_results().size() >= 12, "all 12 scenario results recorded")
	_expect(_manager.get_warmup_baseline().has("turn_count"), "warmup baseline retained")

	if _failures.is_empty():
		print("[TEST] PASS: full assessment flow")
		quit(0)
		return
	for failure in _failures:
		push_error("[TEST] %s" % failure)
	quit(1)


func _run_registration_to_warmup() -> void:
	var registration := (load("res://ui/assessment/RegistrationScreen.tscn") as PackedScene).instantiate()
	root.add_child(registration)
	await process_frame
	_flow._current_scene = registration
	current_scene = registration
	registration._nickname_edit.text = "端到端测试"
	registration._age_spin_box.value = 5
	registration._on_start_button_pressed()
	await _wait_for_scene("WarmupScreen", 300)
	_expect(_flow._current_scene != registration, "registration transitions")


func _run_warmup() -> void:
	var warmup: Node = _flow._current_scene
	_expect(warmup != null and warmup.has_method("_on_start_button_pressed"), "warmup scene loaded")
	if warmup == null or not warmup.has_method("_on_start_button_pressed"):
		return
	warmup._on_start_button_pressed()
	warmup._warmup_child_turns.append({"text": "你好，谢谢你"})
	warmup._remaining_seconds = 1
	warmup._on_timer_timeout()
	await process_frame
	await _wait_for_transition_idle(300)
	_expect(bool(warmup._warmup_finished), "warmup finishes and computes baseline")
	_expect(int(_manager.get_warmup_baseline().get("turn_count", 0)) == 1, "warmup baseline counts child turn")
	warmup._on_continue_button_pressed()
	print("[TEST_FLOW] continue warmup: transitioning=%s current=%s" % [_flow._is_transitioning, _flow._current_scene.name if _flow._current_scene else "null"])
	await _wait_for_scene("PolitenessHouseRpg", 300)


func _run_politeness_house() -> void:
	var house: Node = _flow._current_scene
	_expect(house != null and house.has_method("_start_level"), "politeness house scene loaded")
	if house == null or not house.has_method("_start_level"):
		return
	await _wait_for_transition_idle(300)
	await process_frame
	house._ai_manager.set_api_config({"endpoint": "", "api_key": "", "model": ""})
	# 跳过欢迎语的打字机和继续按钮，等待 NPC 入场动画完成。
	await _wait_for_dialogue(house, 120)
	_dismiss_dialogue(house)
	await _wait_frames(150)
	house._start_level(0)

	var started_level := -1
	var deadline := Time.get_ticks_msec() + 60000
	var loop_count := 0
	while Time.get_ticks_msec() < deadline and is_instance_valid(house):
		loop_count += 1
		if loop_count % 180 == 0:
			print("[TEST_FLOW] house level=%d step=%d waiting=%s processing=%s dialogue=%s buttons=%d" % [house._current_level, house._current_step, house._is_waiting_input, house._is_processing, house._dialogue_box.visible, house._minigame_layer.get_child_count()])
		if not house._level_in_progress and house._current_level < 6:
			if started_level != house._current_level:
				started_level = house._current_level
				house._start_level(started_level)
		elif house._is_waiting_input:
			house._input_field.text = _house_answer(house._current_steps[house._current_step].get("measure", ""))
			house._on_send_pressed()
		elif house._is_processing:
			_dismiss_dialogue(house)
		else:
			var minigame_children: int = house._minigame_layer.get_child_count()
			if minigame_children > 0:
				# headless 验收只验证小游戏节点和控件存在，直接完成交互，
				# 避免提前销毁按钮导致其异步动画回调访问已释放节点。
				house._clear_minigame_layer()
				house._advance_step()
		if _flow._current_scene != house:
			break
		await process_frame

	_expect(_flow._current_scene != house, "politeness house transitions to market")
	await _wait_for_scene("SunshineMarketRpg", 300)


func _run_sunshine_market() -> void:
	var market: Node = _flow._current_scene
	_expect(market != null and market.has_method("_submit_response"), "sunshine market scene loaded")
	if market == null or not market.has_method("_submit_response"):
		return
	await _wait_for_transition_idle(300)
	await process_frame
	market._ai_manager.set_api_config({"endpoint": "", "api_key": "", "model": ""})
	market._on_player_interact(market._all_npcs[0])
	var deadline := Time.get_ticks_msec() + 60000
	var loop_count := 0
	while Time.get_ticks_msec() < deadline and is_instance_valid(market):
		loop_count += 1
		if loop_count % 180 == 0:
			print("[TEST_FLOW] market phase=%d event=%d step=%d waiting=%s processing=%s dialogue=%s" % [market._story_phase, market._sl1_event_index, market._current_step_index, market._is_waiting_input, market._is_processing, market._dialogue_box.visible])
		if not market._is_waiting_input and not market._is_processing and market._current_step_index == 0:
			var npc_index: int = market._sl1_event_index if market._story_phase == 0 else 3 + min(market._sl2_phase_index, 2)
			if npc_index < market._all_npcs.size():
				market._on_player_interact(market._all_npcs[npc_index])
		elif market._is_waiting_input:
			var measure := ""
			if market._current_step_index < market._current_steps.size():
				if market._story_phase == 0:
					measure = String(market._current_steps[market._current_step_index].get("measure_point", ""))
				else:
					measure = String(market._current_steps[market._current_step_index].get("round_data", {}).get("measure_point", ""))
			market._input_field.text = _market_answer(measure)
			market._on_send_pressed()
		elif market._is_processing:
			_dismiss_dialogue(market)
		if _flow._current_scene != market:
			break
		await process_frame

	await _wait_for_scene("ResultsScreen", 300)
	_expect(_flow._current_scene != market, "market transitions to results")


func _house_answer(measure: String) -> String:
	if measure.contains("分享"):
		return "可以，我们一起看"
	if measure.contains("告别"):
		return "再见"
	if measure.contains("道歉") or measure.contains("责任"):
		return "对不起，请原谅我"
	if measure.contains("道谢"):
		return "谢谢你"
	return "请你好"


func _market_answer(measure: String) -> String:
	if measure.contains("告别"):
		return "再见"
	if measure.contains("道谢"):
		return "谢谢"
	if measure.contains("道歉"):
		return "对不起，请帮帮我好吗"
	return "请问，可以吗"


func _dismiss_dialogue(scene: Node) -> void:
	var box: Node = scene._dialogue_box
	if box.visible:
		box.skip_dialogue()
		box.skip_dialogue()


func _click_first_enabled_button(parent: Node) -> void:
	if parent == null:
		return
	for child in parent.get_children():
		if child is Button and child.visible and not child.disabled:
			child.pressed.emit()
			return


func _has_enabled_button(parent: Node) -> bool:
	if parent == null:
		return false
	for child in parent.get_children():
		if child is Button and child.visible and not child.disabled:
			return true
	return false


func _wait_for_dialogue(scene: Node, max_frames: int) -> void:
	for _i in range(max_frames):
		if scene._dialogue_box.visible:
			return
		await process_frame


func _wait_for_scene(script_name: String, max_frames: int) -> void:
	for _i in range(max_frames):
		var scene: Node = _flow._current_scene
		if scene != null and String(scene.get_script().resource_path).get_file().begins_with(script_name):
			return
		await process_frame
	_expect(false, "scene transition timeout: %s" % script_name)


func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _wait_for_transition_idle(max_frames: int) -> void:
	for _i in range(max_frames):
		if not _flow._is_transitioning:
			return
		await process_frame
	_expect(false, "scene transition did not become idle")


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
