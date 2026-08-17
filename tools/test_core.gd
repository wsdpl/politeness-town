extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_story_contract()
	_test_scoring_contract()
	_test_statistics_contract()
	_test_input_wait_contract()
	_test_html_report()
	await _test_scene_loading()
	if _failures.is_empty():
		print("[TEST] PASS: core assessment contract")
		quit(0)
		return
	for failure in _failures:
		push_error("[TEST] %s" % failure)
	quit(1)


func _test_story_contract() -> void:
	_expect_eq(AssessmentData.get_section_one_level_count(), 6, "section one level count")
	var measure_points := 0
	for level in AssessmentData.get_all_section_one_levels():
		measure_points += int(level.get("measure_point_count", 0))
	_expect_eq(measure_points, 14, "section one measure point count")

	var story_one_turns := 0
	for event in AssessmentData.get_story_line_1_events():
		story_one_turns += (event.get("dialogue_steps", []) as Array).size()
	_expect_eq(story_one_turns, 12, "section two story line one turn count")
	_expect_eq(AssessmentData.get_story_line_2_total_rounds(), 10, "section two story line two turn count")
	_expect_eq(story_one_turns + AssessmentData.get_story_line_2_total_rounds(), 22, "section two total turn count")


func _test_scoring_contract() -> void:
	_expect_eq(PolitenessScoring.score_response("", "request").level, 1, "silent score")
	_expect_eq(PolitenessScoring.score_response("给我那个", "request").level, 2, "direct score")
	_expect_eq(PolitenessScoring.score_response("请给我那个", "request").level, 3, "marker score")
	_expect_eq(PolitenessScoring.score_response("阿姨，请帮帮我", "request").level, 4, "address score")
	_expect_eq(PolitenessScoring.score_response("对不起阿姨，请帮我换一个好吗", "apology").level, 5, "composite score")
	_expect_eq(PolitenessScoring._count_markers_in_dimension("请请请帮我", "request"), 1, "same marker deduplicated per turn")
	_expect_eq(PolitenessScoring._count_markers_in_dimension("再见", "greeting"), 0, "farewell excluded from greeting")


func _test_statistics_contract() -> void:
	var turns := [
		{"speaker": "child", "text": "请帮我", "level": 3, "level_fit": true, "social_distance": "低"},
		{"speaker": "child", "text": "老师您好", "level": 4, "level_fit": true, "social_distance": "高"},
		{"speaker": "child", "text": "", "level": 1, "level_fit": false, "social_distance": "中等"},
		{"speaker": "ai", "text": "请谢谢再见", "level": 5},
	]
	_expect_near(PolitenessScoring.calculate_average_level(turns, "request"), 8.0 / 3.0, 0.001, "stored child levels used")
	var adaptation := PolitenessScoring.calculate_contextual_adaptation(turns)
	_expect_eq(adaptation.total, 3, "adaptation denominator")
	_expect_eq(adaptation.correct, 2, "adaptation numerator")
	var stats := PolitenessScoring.calculate_scenario_statistics(turns)
	_expect_eq(stats.turn_count, 3, "AI turns excluded from scenario stats")


func _test_input_wait_contract() -> void:
	for path in [
		"res://ui/rpg/PolitenessHouseRpg.gd",
		"res://ui/rpg/SunshineMarketRpg.gd",
	]:
		var source := FileAccess.get_file_as_string(path)
		_expect(not source.contains("_prompter_timer"), "child input has no timeout timer: %s" % path)
		_expect(not source.contains("_on_prompter_timeout"), "child input has no timeout advance: %s" % path)


func _test_html_report() -> void:
	var path := "user://codex_report_test_tmp.html"
	var report := {
		"session_id": "test",
		"child_info": {"nickname": "测试", "age": 5, "ai_type": "朋友型"},
		"turns": [{"speaker": "child", "text": "谢谢"}],
		"final_results": {
			"overall_score": 3.5, "total_stars": 4, "max_stars": 6, "turn_count": 1,
			"recommendation": "继续练习", "per_dimension": [{"name": "道谢", "frequency": 2.0, "level": 3.0, "star": 1}],
		},
	}
	_expect(AssessmentStorage._write_html_report(report, path), "HTML report writes")
	_expect(FileAccess.file_exists(path), "HTML report exists")
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		_expect(file != null and file.get_as_text().contains("礼貌小镇"), "HTML report contains Chinese content")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_scene_loading() -> void:
	for path in [
		"res://ui/assessment/RegistrationScreen.tscn",
		"res://ui/assessment/WarmupScreen.tscn",
		"res://ui/rpg/PolitenessHouseRpg.tscn",
		"res://ui/rpg/SunshineMarketRpg.tscn",
		"res://ui/assessment/ResultsScreen.tscn",
	]:
		var packed := load(path) as PackedScene
		_expect(packed != null, "scene loads: %s" % path)
		if packed == null:
			continue
		var instance := packed.instantiate()
		_expect(instance != null, "scene instantiates: %s" % path)
		if instance != null:
			instance.free()
	await process_frame


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _expect_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures.append("%s (actual=%s expected=%s)" % [label, actual, expected])


func _expect_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) > tolerance:
		_failures.append("%s (actual=%f expected=%f)" % [label, actual, expected])
