extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_manager := root.get_node("AssessmentGameManager")
	game_manager.register_child({"nickname": "流程测试", "age": 5})
	game_manager.set_ai_type(0)
	game_manager.start_sunshine_market()

	var scene := load("res://ui/rpg/SunshineMarketRpg.tscn") as PackedScene
	var market = scene.instantiate()
	root.add_child(market)
	await process_frame
	market._ai_manager.set_api_config({"endpoint": "", "api_key": "", "model": ""})
	market._start_sl1_event(0)

	var polite_answers := [
		"你好", "请让我帮帮你好吗", "我们一起想办法", "不用谢",
		"老师您好", "老师请往左边走", "可以，我来帮您", "老师再见",
		"阿姨您好", "不好意思，我没看见", "我可以帮您叫工作人员", "阿姨再见",
	]
	for answer in polite_answers:
		market._submit_response(answer)

	_expect_eq(market._story_phase, 1, "story line one advances to story line two")
	_expect_eq(game_manager.get_scenario_results().size(), 3, "three social-distance events complete")
	_expect_eq(game_manager.get_all_turns().size(), 12, "story line one records exactly 12 child turns")

	var pressure_answers := [
		"阿姨，请问购物车在哪里", "请问是停车场左边吗", "谢谢阿姨",
		"叔叔，请帮我拿下贴纸好吗", "我们可以轮流用梯子", "我愿意和小妹妹一起分享",
		"对不起阿姨", "对不起，请给我钥匙好吗", "请，谢谢",
	]
	for answer in pressure_answers:
		market._submit_response(answer)

	_expect_eq(market._sl2_phase_index, 2, "high-pressure phase reached")
	_expect_eq(market._current_step_index, 3, "first three high-pressure rounds advance without looping")
	_expect_eq(game_manager.get_scenario_results().size(), 5, "five complete market events recorded before final round")
	_expect_eq(game_manager.get_all_turns().size(), 21, "no duplicate child_score turns")

	market.queue_free()
	await process_frame
	if _failures.is_empty():
		print("[TEST] PASS: sunshine market progression")
		quit(0)
		return
	for failure in _failures:
		push_error("[TEST] %s" % failure)
	quit(1)


func _expect_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures.append("%s (actual=%s expected=%s)" % [label, actual, expected])
