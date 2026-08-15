extends Control
## 测评结果展示场景 (ResultsScreen)
## 展示频次雷达图与策略等级雷达图、得分明细表、总星章数、总分与评估建议。
## 数据来源于 AssessmentGameManager 单例，评分由 PolitenessScoring 静态方法计算，
## 导出报告通过 AssessmentStorage 持久化，场景跳转由 AssessmentFlowHost 控制。

# ============================================================
#  常量
# ============================================================

# 雷达图维度顺序与中文名（与 PolitenessScoring.CORE_DIMENSIONS 一一对应）
const RADAR_LABELS: Array[String] = ["问候", "请求", "道谢", "致歉", "分享", "告别"]

# 频次雷达图最大刻度（每分钟礼貌标记词频次上限）
const FREQUENCY_RADAR_MAX: float = 10.0

# 等级雷达图最大刻度（五级礼貌策略等级上限）
const LEVEL_RADAR_MAX: float = 5.0

# 单维度星章阈值：平均等级达到消极礼貌（等级3）及以上即获得星章
const STAR_LEVEL_THRESHOLD: float = 3.0

# 总星章上限（六大核心维度各 1 枚）
const MAX_STARS: int = 6

# 性别显示名映射
const GENDER_DISPLAY := {
	"male": "男",
	"female": "女",
}


# ============================================================
#  节点引用（路径与 .tscn 节点树一一对应，均通过唯一名称访问）
# ============================================================

@onready var ChildInfoLabel: Label = %ChildInfoLabel
@onready var FrequencyRadar: RadarChart = %FrequencyRadar
@onready var LevelRadar: RadarChart = %LevelRadar
@onready var ScoreTable: VBoxContainer = %ScoreTable
@onready var TotalStarsLabel: Label = %TotalStarsLabel
@onready var OverallScoreLabel: Label = %OverallScoreLabel
@onready var RecommendationLabel: RichTextLabel = %RecommendationLabel
@onready var ExportButton: Button = %ExportButton
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
	# 应用统一主题
	theme = AssessmentUiTheme.theme

	# 给标题添加底框
	AssessmentUiTheme.wrap_in_panel($CanvasLayer/TitleLabel, AssessmentUiTheme.title_panel_style())

	# 给儿童信息标签添加底框
	AssessmentUiTheme.wrap_in_panel($CanvasLayer/ChildInfoLabel, AssessmentUiTheme.label_panel_style())

	# 给分数容器添加主面板底框
	AssessmentUiTheme.wrap_in_panel($CanvasLayer/ScoreContainer, AssessmentUiTheme.board_panel_style())

	# 给得分表添加面板底框
	AssessmentUiTheme.wrap_in_panel($CanvasLayer/ScoreTable, AssessmentUiTheme.section_panel_style())

	# 给信息容器添加面板底框
	AssessmentUiTheme.wrap_in_panel($CanvasLayer/InfoContainer, AssessmentUiTheme.section_panel_style())

	# 给按钮区域添加面板底框
	AssessmentUiTheme.wrap_in_panel($CanvasLayer/ButtonContainer, AssessmentUiTheme.section_panel_style())

	# 规范化所有字体大小（不低于28）并包裹剩余浮动标签
	AssessmentUiTheme.normalize_font_sizes($CanvasLayer)
	AssessmentUiTheme.wrap_all_floating_labels($CanvasLayer)

	ExportButton.pressed.connect(_on_export_button_pressed)
	RestartButton.pressed.connect(_on_restart_button_pressed)
	QuitButton.pressed.connect(_on_quit_button_pressed)

	# 应用按钮样式
	AssessmentUiTheme.apply_primary_button(RestartButton)
	AssessmentUiTheme.apply_danger_button(QuitButton)

	# 从 AssessmentGameManager 单例获取全部测评数据
	_child_info = AssessmentGameManager.get_child_info()
	_scenario_results = AssessmentGameManager.get_scenario_results()
	_all_turns = AssessmentGameManager.get_all_turns()
	_warmup_baseline = AssessmentGameManager.get_warmup_baseline()

	# 计算结果
	_results = _calculate_results()

	# 完成测评并持久化会话数据，供导出报告使用
	AssessmentGameManager.complete_assessment(_results)

	# 显示结果
	_display_results()


# ============================================================
#  结果计算
# ============================================================

## 汇总雷达图数据、六大维度频次/平均等级、补充维度、总分、星章与评估建议，返回完整结果字典。
func _calculate_results() -> Dictionary:
	# 使用 PolitenessScoring 生成雷达图数据（含核心六维与板块二补充维度）
	var radar_data := PolitenessScoring.generate_radar_data(_scenario_results)
	var frequency_radar: Dictionary = radar_data.get("frequency_radar", {})
	var level_radar: Dictionary = radar_data.get("level_radar", {})
	var extended_frequency: Dictionary = radar_data.get("extended_frequency_radar", {})
	var extended_level: Dictionary = radar_data.get("extended_level_radar", {})
	var dimension_names: Dictionary = radar_data.get("dimension_names", {})

	# 六大核心维度：频次与平均等级
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

	# 板块二补充维度（基础礼貌、策略灵活性、压力应对）
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

	# 总分：核心维度（权重 1.0）与补充维度（权重 0.5）的加权平均，归一到 0~5
	var core_weight := 1.0
	var ext_weight := 0.5
	var total_weight := float(dimensions.size()) * core_weight + float(extended_summary.size()) * ext_weight
	var overall_score := 0.0
	if total_weight > 0.0:
		overall_score = (sum_core_level * core_weight + sum_ext_level * ext_weight) / total_weight
	overall_score = clampf(overall_score, 0.0, 5.0)

	# 评估建议
	var recommendation := _build_recommendation(overall_score, per_dimension)

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
	}


## 根据平均等级生成评估建议文本，并在“良好”档位指出弱项维度。
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


## 找出平均等级最低的核心维度中文名（并列时取第一个）。
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


# ============================================================
#  结果展示
# ============================================================

func _display_results() -> void:
	# 频次雷达图
	var freq_values: Array[float] = _results.get("frequency_values", [])
	FrequencyRadar.set_data(RADAR_LABELS, freq_values, FREQUENCY_RADAR_MAX, "礼貌标记词频次")

	# 策略等级雷达图
	var level_values: Array[float] = _results.get("level_values", [])
	LevelRadar.set_data(RADAR_LABELS, level_values, LEVEL_RADAR_MAX, "礼貌策略等级")

	# 儿童信息摘要
	ChildInfoLabel.text = _format_child_info(_child_info)

	# 总星章数
	var total_stars := int(_results.get("total_stars", 0))
	var max_stars := int(_results.get("max_stars", MAX_STARS))
	TotalStarsLabel.text = "总星章: %d/%d" % [total_stars, max_stars]

	# 总分
	var overall := float(_results.get("overall_score", 0.0))
	OverallScoreLabel.text = "总分: %.1f/5.0" % overall

	# 各维度得分明细表
	_populate_score_table(_results.get("per_dimension", []))

	# 评估建议
	RecommendationLabel.text = String(_results.get("recommendation", ""))


## 格式化儿童信息摘要：昵称、年龄、性别、AI 类型。
func _format_child_info(child_info: Dictionary) -> String:
	var nickname := String(child_info.get("nickname", "未填写"))
	var age := int(child_info.get("age", 0))
	var gender_key := String(child_info.get("gender", ""))
	var gender := String(GENDER_DISPLAY.get(gender_key, gender_key))
	if gender.is_empty():
		gender = "未知"
	var ai_type := AssessmentGameManager.get_ai_type_name()
	return "昵称：%s    年龄：%d岁    性别：%s    AI类型：%s" % [nickname, age, gender, ai_type]


## 填充得分明细表：表头 + 各维度（维度 | 频次 | 等级 | 星章）。
func _populate_score_table(per_dimension: Array) -> void:
	var header := _get_or_create_label("Header", 0, 28)
	header.text = "维度 | 频次 | 等级 | 星章"
	for i in range(per_dimension.size()):
		var row := _get_or_create_label("Row%d" % (i + 1), i + 1, 28)
		var entry: Dictionary = per_dimension[i]
		var dim_name := String(entry.get("name", ""))
		var freq := float(entry.get("frequency", 0.0))
		var lvl := float(entry.get("level", 0.0))
		var star := int(entry.get("star", 0))
		row.text = "%s | %.2f | %.1f | %s" % [dim_name, freq, lvl, "★" if star > 0 else "—"]


## 按名称获取明细表中的 Label，若缺失则创建并放置到指定位置。
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

## 导出报告：调用 AssessmentStorage 导出会话报告，弹窗提示成功/失败。
func _on_export_button_pressed() -> void:
	var session_id := AssessmentGameManager.get_session_id()
	var report := AssessmentStorage.export_report(session_id)
	if report.is_empty():
		_show_dialog("导出报告", "导出失败：未找到会话数据（会话ID：%s）。" % session_id)
		return
	var turn_count := 0
	if report.has("turns") and report["turns"] is Array:
		turn_count = (report["turns"] as Array).size()
	_show_dialog("导出报告", "报告已导出成功！\n会话ID：%s\n轮次数：%d" % [session_id, turn_count])


## 重新测评：返回注册页。
func _on_restart_button_pressed() -> void:
	await AssessmentFlowHost.go_to_registration()


## 退出游戏。
func _on_quit_button_pressed() -> void:
	AssessmentFlowHost.quit_game()


# ============================================================
#  对话框辅助
# ============================================================

## 弹出确认对话框显示提示信息，关闭后自动释放。
func _show_dialog(title: String, message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
