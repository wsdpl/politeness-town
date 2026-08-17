extends Control
## 测评结果展示场景 (ResultsScreen)
## 展示频次雷达图与策略等级雷达图、柱状图、饼图、得分明细表、
## 扩展维度评估、总星章数、总分与评估建议。
## 数据来源于 AssessmentGameManager 单例，评分由 PolitenessScoring 静态方法计算，
## 导出报告通过 AssessmentStorage 持久化，场景跳转由 AssessmentFlowHost 控制。

# ============================================================
#  常量
# ============================================================

const RADAR_LABELS: Array[String] = ["问候", "请求", "道谢", "致歉", "分享", "告别"]
const FREQUENCY_RADAR_MAX: float = 10.0
const LEVEL_RADAR_MAX: float = 5.0
const STAR_LEVEL_THRESHOLD: float = 3.0
const MAX_STARS: int = 6

const GENDER_DISPLAY := {
	"male": "男",
	"female": "女",
}

# 五级策略等级标签（用于饼图）
const LEVEL_LABELS: Array[String] = [
	"沉默/无回应",
	"直白无修饰",
	"消极礼貌",
	"积极礼貌+称呼",
	"复合策略",
]


# ============================================================
#  节点引用
# ============================================================

@onready var ChildInfoLabel: Label = %ChildInfoLabel
@onready var FrequencyRadar: RadarChart = %FrequencyRadar
@onready var LevelRadar: RadarChart = %LevelRadar
@onready var BarChartNode: BarChart = %BarChart
@onready var PieChartNode: PieChart = %PieChart
@onready var ScoreTable: VBoxContainer = %ScoreTable
@onready var ExtendedDimsContainer: VBoxContainer = %ExtendedDimsContainer
@onready var TotalStarsLabel: Label = %TotalStarsLabel
@onready var OverallScoreLabel: Label = %OverallScoreLabel
@onready var TurnCountLabel: Label = %TurnCountLabel
@onready var RecommendationLabel: RichTextLabel = %RecommendationLabel
@onready var ExportButton: Button = %ExportButton
@onready var ExportCsvButton: Button = %ExportCsvButton
@onready var RestartButton: Button = %RestartButton
@onready var QuitButton: Button = %QuitButton


# ============================================================
#  内部状态
# ============================================================

var _child_info: Dictionary = {}
var _scenario_results: Dictionary = {}
var _all_turns: Array = []
var _warmup_baseline: Dictionary = {}
var _results: Dictionary = {}


# ============================================================
#  生命周期
# ============================================================

func _ready() -> void:
	theme = AssessmentUiTheme.theme

	AssessmentUiTheme.wrap_in_panel($CanvasLayer/TitleLabel, AssessmentUiTheme.title_panel_style())
	AssessmentUiTheme.wrap_in_panel($CanvasLayer/ChildInfoLabel, AssessmentUiTheme.label_panel_style())
	AssessmentUiTheme.wrap_in_panel($CanvasLayer/ScoreContainer, AssessmentUiTheme.board_panel_style())
	AssessmentUiTheme.wrap_in_panel($CanvasLayer/ChartsContainer, AssessmentUiTheme.board_panel_style())
	AssessmentUiTheme.wrap_in_panel($CanvasLayer/ScoreTable, AssessmentUiTheme.section_panel_style())
	AssessmentUiTheme.wrap_in_panel($CanvasLayer/ExtendedDimsContainer, AssessmentUiTheme.section_panel_style())
	AssessmentUiTheme.wrap_in_panel($CanvasLayer/InfoContainer, AssessmentUiTheme.section_panel_style())
	AssessmentUiTheme.wrap_in_panel($CanvasLayer/ButtonContainer, AssessmentUiTheme.section_panel_style())

	AssessmentUiTheme.normalize_font_sizes($CanvasLayer)
	AssessmentUiTheme.wrap_all_floating_labels($CanvasLayer)

	ExportButton.pressed.connect(_on_export_button_pressed)
	ExportCsvButton.pressed.connect(_on_export_csv_button_pressed)
	RestartButton.pressed.connect(_on_restart_button_pressed)
	QuitButton.pressed.connect(_on_quit_button_pressed)

	AssessmentUiTheme.apply_primary_button(ExportCsvButton)
	AssessmentUiTheme.apply_primary_button(RestartButton)
	AssessmentUiTheme.apply_danger_button(QuitButton)

	_child_info = AssessmentGameManager.get_child_info()
	_scenario_results = AssessmentGameManager.get_scenario_results()
	_all_turns = AssessmentGameManager.get_all_turns()
	_warmup_baseline = AssessmentGameManager.get_warmup_baseline()

	_results = _calculate_results()
	AssessmentGameManager.complete_assessment(_results)
	_display_results()


# ============================================================
#  结果计算
# ============================================================

func _calculate_results() -> Dictionary:
	var radar_data := PolitenessScoring.generate_radar_data(_scenario_results)
	var frequency_radar: Dictionary = radar_data.get("frequency_radar", {})
	var level_radar: Dictionary = radar_data.get("level_radar", {})
	var extended_frequency: Dictionary = radar_data.get("extended_frequency_radar", {})
	var extended_level: Dictionary = radar_data.get("extended_level_radar", {})
	var dimension_names: Dictionary = radar_data.get("dimension_names", {})

	var dimensions: Array = PolitenessScoring.CORE_DIMENSIONS
	var freq_values: Array[float] = []
	var level_values: Array[float] = []
	var per_dimension: Array[Dictionary] = []
	var total_stars := 0
	var sum_core_level := 0.0
	for dim in dimensions:
		var freq := float(frequency_radar.get(dim, 0.0))
		var lvl := float(level_radar.get(dim, 0.0))
		freq_values.append(freq)
		level_values.append(lvl)
		var has_star: bool = lvl >= STAR_LEVEL_THRESHOLD
		if has_star:
			total_stars += 1
		sum_core_level += lvl
		per_dimension.append({
			"key": String(dim),
			"name": String(dimension_names.get(dim, dim)),
			"frequency": freq,
			"level": lvl,
			"star": 1 if has_star else 0,
		})

	var extended_dimensions: Array = PolitenessScoring.EXTENDED_DIMENSIONS.keys()
	var extended_summary: Array[Dictionary] = []
	var sum_ext_level := 0.0
	for dim in extended_dimensions:
		var freq := float(extended_frequency.get(dim, 0.0))
		var lvl := float(extended_level.get(dim, 0.0))
		sum_ext_level += lvl
		extended_summary.append({
			"key": String(dim),
			"name": String(dimension_names.get(dim, dim)),
			"frequency": freq,
			"level": lvl,
		})

	var core_weight := 1.0
	var ext_weight := 0.5
	var total_weight := float(dimensions.size()) * core_weight + float(extended_summary.size()) * ext_weight
	var overall_score := 0.0
	if total_weight > 0.0:
		overall_score = (sum_core_level * core_weight + sum_ext_level * ext_weight) / total_weight
	overall_score = clampf(overall_score, 0.0, 5.0)

	var recommendation := _build_recommendation(overall_score, per_dimension)

	# 五级策略等级分布（用于饼图）
	var level_distribution := _calculate_level_distribution(_all_turns)

	# 各维度标记词类型频次（用于柱状图）
	var marker_type_counts := _calculate_marker_type_counts(_all_turns)

	return {
		"frequency_values": freq_values,
		"level_values": level_values,
		"per_dimension": per_dimension,
		"extended_summary": extended_summary,
		"total_stars": total_stars,
		"max_stars": MAX_STARS,
		"overall_score": overall_score,
		"recommendation": recommendation,
		"radar_data": radar_data,
		"turn_count": int(radar_data.get("turn_count", 0)),
		"warmup_baseline": _warmup_baseline,
		"child_info": _child_info,
		"all_turns": _all_turns,
		"level_distribution": level_distribution,
		"marker_type_counts": marker_type_counts,
	}


func _build_recommendation(overall_level: float, per_dimension: Array) -> String:
	if overall_level >= 4.0:
		return "优秀！该儿童在大多数礼貌维度表现良好，建议继续保持。"
	elif overall_level >= 3.0:
		var weak := _find_weakest_dimension(per_dimension)
		return "良好。儿童具备基本礼貌能力，建议在%s方面加强练习。" % weak
	elif overall_level >= 2.0:
		return "需要提升。建议通过日常情境中的礼貌示范和练习，帮助儿童发展礼貌语言能力。"
	else:
		return "需要重点关注。建议结合专业语言训练，系统性地培养儿童的礼貌表达能力。"


func _find_weakest_dimension(per_dimension: Array) -> String:
	var weakest_name := "弱项维度"
	var weakest_level := INF
	for entry in per_dimension:
		if entry is Dictionary:
			var lvl := float(entry.get("level", 0.0))
			if lvl < weakest_level:
				weakest_level = lvl
				weakest_name = String(entry.get("name", weakest_name))
	return weakest_name


## 统计五级策略等级分布（返回 Array[float]，索引0=等级1，索引4=等级5）
func _calculate_level_distribution(turns: Array) -> Array[float]:
	var counts: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	for turn in turns:
		if not (turn is Dictionary) or not PolitenessScoring._is_child_turn(turn):
			continue
		var level: int = int(turn.get("level", 0))
		if level <= 0:
			var result := PolitenessScoring.score_response(
				PolitenessScoring._extract_text(turn),
				String(turn.get("dimension", ""))
			)
			level = int(result["level"])
		if level >= 1 and level <= 5:
			counts[level - 1] += 1.0
	return counts


## 统计各维度标记词频次（返回 Dictionary，键为维度英文名，值为计数）
func _calculate_marker_type_counts(turns: Array) -> Dictionary:
	var counts: Dictionary = {}
	for dim in PolitenessScoring.CORE_DIMENSIONS:
		counts[dim] = 0
	for turn in turns:
		if not (turn is Dictionary) or not PolitenessScoring._is_child_turn(turn):
			continue
		var text := PolitenessScoring._extract_text(turn)
		for dim in PolitenessScoring.CORE_DIMENSIONS:
			counts[dim] = int(counts.get(dim, 0)) + PolitenessScoring._count_markers_in_dimension(text, dim)
	return counts


# ============================================================
#  结果展示
# ============================================================

func _display_results() -> void:
	var freq_values: Array[float] = _results.get("frequency_values", [])
	FrequencyRadar.set_data(RADAR_LABELS, freq_values, FREQUENCY_RADAR_MAX, "礼貌标记词频次")

	var level_values: Array[float] = _results.get("level_values", [])
	LevelRadar.set_data(RADAR_LABELS, level_values, LEVEL_RADAR_MAX, "礼貌策略等级")

	# 柱状图：各维度标记词频次
	var marker_counts: Dictionary = _results.get("marker_type_counts", {})
	var bar_labels: Array[String] = []
	var bar_values: Array[float] = []
	var bar_max := 1.0
	for dim in PolitenessScoring.CORE_DIMENSIONS:
		var dim_name: String = String(PolitenessScoring.DIMENSION_NAMES.get(dim, dim))
		var count := float(marker_counts.get(dim, 0))
		bar_labels.append(dim_name)
		bar_values.append(count)
		if count > bar_max:
			bar_max = count
	BarChartNode.set_data(bar_labels, bar_values, bar_max * 1.2, "各维度标记词频次")

	# 饼图：五级策略等级分布
	var level_dist: Array[float] = _results.get("level_distribution", [0.0, 0.0, 0.0, 0.0, 0.0])
	PieChartNode.set_data(LEVEL_LABELS, level_dist, "五级策略等级分布")

	ChildInfoLabel.text = _format_child_info(_child_info)

	var total_stars := int(_results.get("total_stars", 0))
	var max_stars := int(_results.get("max_stars", MAX_STARS))
	TotalStarsLabel.text = "总星章: %d/%d" % [total_stars, max_stars]

	var overall := float(_results.get("overall_score", 0.0))
	OverallScoreLabel.text = "总分: %.1f/5.0" % overall

	var turn_count := int(_results.get("turn_count", 0))
	TurnCountLabel.text = "话轮数: %d" % turn_count

	_populate_score_table(_results.get("per_dimension", []))
	_populate_extended_dims(_results.get("extended_summary", []))

	RecommendationLabel.text = String(_results.get("recommendation", ""))


func _format_child_info(child_info: Dictionary) -> String:
	var nickname := String(child_info.get("nickname", "未填写"))
	var age := int(child_info.get("age", 0))
	var gender_key := String(child_info.get("gender", ""))
	var gender := String(GENDER_DISPLAY.get(gender_key, gender_key))
	if gender.is_empty():
		gender = "未知"
	var ai_type := AssessmentGameManager.get_ai_type_name()
	return "昵称：%s    年龄：%d岁    性别：%s    AI类型：%s" % [nickname, age, gender, ai_type]


func _populate_score_table(per_dimension: Array) -> void:
	var header := _get_or_create_label("Header", 0, 24)
	header.text = "维度 | 频次 | 等级 | 星章"
	for i in range(per_dimension.size()):
		var row := _get_or_create_label("Row%d" % (i + 1), i + 1, 24)
		var entry: Dictionary = per_dimension[i]
		var dim_name := String(entry.get("name", ""))
		var freq := float(entry.get("frequency", 0.0))
		var lvl := float(entry.get("level", 0.0))
		var star := int(entry.get("star", 0))
		row.text = "%s | %.2f | %.1f | %s" % [dim_name, freq, lvl, "★" if star > 0 else "—"]


func _populate_extended_dims(extended_summary: Array) -> void:
	var header_label := ExtendedDimsContainer.get_node_or_null("ExtHeader")
	if header_label is Label:
		header_label.text = "扩展维度评估"

	for i in range(extended_summary.size()):
		var row_name := "ExtRow%d" % (i + 1)
		var row := ExtendedDimsContainer.get_node_or_null(row_name)
		if row is Label:
			var entry: Dictionary = extended_summary[i]
			var dim_name := String(entry.get("name", ""))
			var freq := float(entry.get("frequency", 0.0))
			var lvl := float(entry.get("level", 0.0))
			row.text = "%s：频次 %.2f / 等级 %.1f" % [dim_name, freq, lvl]

	# 增加一行汇总
	var summary_row := ExtendedDimsContainer.get_node_or_null("ExtRow4")
	if summary_row is Label:
		var scenario_stats := PolitenessScoring.calculate_scenario_statistics(_all_turns)
		var duration := float(scenario_stats.get("duration_minutes", 0.0))
		var marker_total := int(scenario_stats.get("marker_total_count", 0))
		summary_row.text = "互动时长: %.1f分钟 | 标记词总数: %d" % [duration, marker_total]


func _get_or_create_label(node_name: String, index: int, font_size: int) -> Label:
	var node := ScoreTable.get_node_or_null(node_name)
	if node is Label:
		return node
	var label := Label.new()
	label.name = node_name
	label.add_theme_font_size_override("font_size", font_size)
	ScoreTable.add_child(label)
	ScoreTable.move_child(label, index)
	return label


# ============================================================
#  按钮事件
# ============================================================

func _on_export_button_pressed() -> void:
	var session_id := AssessmentGameManager.get_session_id()
	var report := AssessmentStorage.export_report(session_id)
	if report.is_empty():
		_show_dialog("导出报告", "导出失败：未找到会话数据（会话ID：%s）。" % session_id)
		return
	var turn_count := 0
	if report.has("turns") and report["turns"] is Array:
		turn_count = (report["turns"] as Array).size()
	_show_dialog("导出报告", "JSON数据和可打印HTML报告已导出！\n会话ID：%s\n轮次数：%d" % [session_id, turn_count])


func _on_export_csv_button_pressed() -> void:
	var session_id := AssessmentGameManager.get_session_id()
	var csv_path := AssessmentStorage.export_csv(session_id)
	if csv_path.is_empty():
		_show_dialog("导出CSV", "导出失败：未找到会话数据（会话ID：%s）。" % session_id)
		return
	_show_dialog("导出CSV", "Excel兼容CSV已导出成功！\n文件路径：%s" % csv_path)


func _on_restart_button_pressed() -> void:
	await AssessmentFlowHost.go_to_registration()


func _on_quit_button_pressed() -> void:
	AssessmentFlowHost.quit_game()


# ============================================================
#  对话框辅助
# ============================================================

func _show_dialog(title: String, message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
