extends Control
## 板块一「礼貌小屋」闯关场景 (PolitenessHouseScreen)
## 儿童在 AI 向导陪同下依次完成 6 个关卡（问候、请求、道谢、致歉、分享、告别），
## 每关包含多步交互，每步可能需要儿童回应。
## 通过 AssessmentAIManager 调用 LLM 进行动态对话与礼貌等级评分。

# ============================================================
#  常量
# ============================================================

## 关卡总数
const LEVEL_COUNT := 6

# 后备对话回复（API 不可用时使用）
const FRIEND_FALLBACK_REPLIES := [
	"哇，你说得真好！",
	"嗯嗯，我明白啦～",
	"好呀，我们继续吧！",
]

const TOOL_FALLBACK_REPLIES := [
	"已接收。",
	"理解。继续。",
	"信息已记录。",
]

# 朋友型 / 工具型 AI 默认名标（当关卡台词未提供 speaker 时使用）
const FRIEND_AI_NAME := "小礼"
const TOOL_AI_NAME := "系统"


# ============================================================
#  节点引用
# ============================================================

@onready var DialogueBox = $CanvasLayer/DialogueBox
@onready var StarBadgeBoard = $CanvasLayer/StarBadgeBoard
@onready var TipBoard = $CanvasLayer/TipBoard
@onready var InputContainer: HBoxContainer = $CanvasLayer/InputContainer
@onready var InputField: LineEdit = $CanvasLayer/InputContainer/InputField
@onready var SendButton: Button = $CanvasLayer/InputContainer/SendButton
@onready var LevelLabel: Label = $CanvasLayer/LevelLabel
@onready var Progress_Bar: ProgressBar = $CanvasLayer/ProgressBar
@onready var LoadingLabel: Label = $CanvasLayer/LoadingLabel
@onready var ContinueButton: Button = $CanvasLayer/ContinueButton
@onready var AIManager: AssessmentAIManager = $AssessmentAIManager

# ---- 语音输入相关 ----
var _mic_button: Button
var _voice_status_label: Label


# ============================================================
#  核心数据结构
# ============================================================

var _current_level_index: int = 0     # 当前关卡索引 (0-5)
var _current_step_index: int = 0      # 当前步骤索引
var _current_level_data: Dictionary   # 当前关卡数据
var _is_waiting_for_child: bool = false # 是否等待儿童输入
var _dialogue_messages: Array = []    # 对话历史（发往 LLM）
var _level_turns: Array = []          # 当前关卡的轮次记录
var _level_scores: Array = []         # 当前关卡的评分

# ---- 内部辅助状态 ----
# 当前步骤数据（friend_ai / tool_ai 中的某一项）
var _current_step_data: Dictionary = {}
# 当前显示的是否为 AI 动态回复（用于区分 dialogue_finished 来源）
var _showing_ai_reply: bool = false
# 最近一次儿童输入文本（供 scoring 回调记录使用）
var _last_child_text: String = ""


# ============================================================
#  生命周期
# ============================================================

func _ready() -> void:
	# AssessmentGameManager / AssessmentFlowHost 为 autoload 单例，可直接访问
	theme = AssessmentUiTheme.theme

	# 给关卡标签添加底框
	AssessmentUiTheme.wrap_in_panel(LevelLabel, AssessmentUiTheme.title_panel_style())

	# 给输入区域添加面板底框
	AssessmentUiTheme.wrap_in_panel($CanvasLayer/InputContainer, AssessmentUiTheme.section_panel_style())

	# 给加载标签添加底框
	AssessmentUiTheme.wrap_in_panel(LoadingLabel, AssessmentUiTheme.label_panel_style())

	# 规范化所有字体大小（不低于28）并包裹剩余浮动标签
	AssessmentUiTheme.normalize_font_sizes($CanvasLayer)
	AssessmentUiTheme.wrap_all_floating_labels($CanvasLayer)

	# 应用主按钮样式（中式古镇风格）
	AssessmentUiTheme.apply_primary_button(SendButton)
	AssessmentUiTheme.apply_primary_button(ContinueButton)

	# 连接 DialogueBox 信号
	DialogueBox.dialogue_finished.connect(_on_dialogue_finished)

	# 连接 AIManager 信号
	AIManager.ai_response_received.connect(_on_ai_response_received)
	AIManager.ai_response_error.connect(_on_ai_response_error)
	AIManager.scoring_received.connect(_on_scoring_received)
	AIManager.scoring_error.connect(_on_scoring_error)

	# 连接输入控件 / 继续按钮信号
	SendButton.pressed.connect(_on_send_button_pressed)
	InputField.text_submitted.connect(_on_input_field_text_submitted)
	ContinueButton.pressed.connect(_on_continue_button_pressed)

	# 初始化第一关
	_load_level(0)
	
	# 初始化语音输入
	_setup_voice_input()


# ============================================================
#  语音输入
# ============================================================

func _setup_voice_input() -> void:
	# 创建语音按钮，放在输入容器中
	_mic_button = Button.new()
	_mic_button.text = "🎤 说话"
	_mic_button.custom_minimum_size = Vector2(140, 50)
	_mic_button.add_theme_font_size_override("font_size", 28)
	InputContainer.add_child(_mic_button)
	AssessmentUiTheme.apply_primary_button(_mic_button)
	
	# 创建语音状态标签
	_voice_status_label = Label.new()
	_voice_status_label.text = ""
	_voice_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_voice_status_label.add_theme_font_size_override("font_size", 28)
	_voice_status_label.add_theme_color_override("font_color", AssessmentUiTheme.INK)
	InputContainer.add_child(_voice_status_label)
	# 给语音状态标签添加底框
	AssessmentUiTheme.wrap_label_in_panel(_voice_status_label)
	
	# 连接信号
	_mic_button.pressed.connect(_on_mic_button_pressed)
	IFlytekSR.recording_started.connect(_on_voice_recording_started)
	IFlytekSR.recording_stopped.connect(_on_voice_recording_stopped)
	IFlytekSR.recognition_completed.connect(_on_voice_recognition_completed)
	IFlytekSR.recognition_failed.connect(_on_voice_recognition_failed)
	IFlytekSR.status_message.connect(_on_voice_status_message)
	
	# 检查讯飞API是否已配置
	if not IFlytekSR.is_configured():
		_mic_button.text = "🎤 (未配置讯飞API)"
		_mic_button.disabled = true


func _on_mic_button_pressed() -> void:
	if IFlytekSR.is_recording():
		IFlytekSR.stop_and_recognize()
	else:
		IFlytekSR.start_recording()


func _on_voice_recording_started() -> void:
	_mic_button.text = "⏹ 停止录音"
	_mic_button.modulate = Color(1.0, 0.6, 0.4)
	_voice_status_label.text = "正在录音...再次点击停止"


func _on_voice_recording_stopped() -> void:
	_mic_button.text = "识别中..."
	_mic_button.modulate = Color(0.8, 0.8, 0.8)
	_mic_button.disabled = true


func _on_voice_recognition_completed(text: String) -> void:
	_mic_button.text = "🎤 说话"
	_mic_button.disabled = false
	_mic_button.modulate = Color(1.0, 1.0, 1.0)
	
	if text.is_empty():
		_voice_status_label.text = "未识别到语音内容，请重试"
		return
	
	_voice_status_label.text = "识别结果: " + text
	print("[PolitenessHouseScreen] 语音识别完成: %s" % text)
	
	# 自动提交识别结果
	if _is_waiting_for_child:
		InputField.text = text
		_submit_child_input()


func _on_voice_recognition_failed(error: String) -> void:
	_mic_button.text = "🎤 说话"
	_mic_button.disabled = false
	_mic_button.modulate = Color(1.0, 1.0, 1.0)
	_voice_status_label.text = "语音识别失败: " + error


func _on_voice_status_message(msg: String) -> void:
	if not msg.is_empty():
		_voice_status_label.text = msg


# ============================================================
#  关卡加载
# ============================================================

## 加载指定索引的关卡并播放引导语。
func _load_level(index: int) -> void:
	_current_level_index = index
	_current_level_data = AssessmentData.get_section_one_level_by_index(index)
	if _current_level_data.is_empty():
		push_error("[PolitenessHouseScreen] 关卡数据为空: index=%d" % index)
		return

	# 重置步骤与轮次状态
	_current_step_index = 0
	_current_step_data = {}
	_level_turns.clear()
	_level_scores.clear()
	_dialogue_messages.clear()
	_is_waiting_for_child = false
	_showing_ai_reply = false
	_last_child_text = ""

	# 更新星章板高亮（当前关卡闪烁）
	StarBadgeBoard.highlight_current(index)

	# 更新提示板：标题=关卡名, 维度=礼貌维度, 内容=关卡描述
	var level_name := String(_current_level_data.get("name", ""))
	var dimension := String(_current_level_data.get("dimension", ""))
	var description := String(_current_level_data.get("description", ""))
	TipBoard.set_tip(level_name, description)
	TipBoard.set_dimension(dimension)

	# 更新关卡标签与进度条
	LevelLabel.text = "第%d关: %s" % [index + 1, level_name]
	Progress_Bar.value = float(index) / float(LEVEL_COUNT) * 100.0

	# 重置 UI 状态
	_set_input_enabled(false)
	LoadingLabel.visible = false
	ContinueButton.visible = false
	DialogueBox.clear()

	# 播放关卡引导语（AI 的第一句台词）
	_play_current_step()


# ============================================================
#  步骤播放
# ============================================================

## 播放当前关卡的当前步骤台词（根据 AI 类型选择朋友型 / 工具型）。
func _play_current_step() -> void:
	var lines := _get_current_ai_lines()
	if lines.is_empty():
		push_error("[PolitenessHouseScreen] 当前关卡无 AI 台词数据")
		_complete_level()
		return
	if _current_step_index >= lines.size():
		_complete_level()
		return

	_current_step_data = lines[_current_step_index]
	var speaker := String(_current_step_data.get("speaker", _get_default_ai_name()))
	var text := String(_current_step_data.get("text", ""))

	# 将脚本台词追加到对话历史，为后续 LLM 调用提供上下文
	_dialogue_messages.append({"role": "assistant", "content": text})

	# 标记当前显示的是脚本台词（非动态回复）
	_showing_ai_reply = false
	DialogueBox.show_dialogue(speaker, text)


## 对话框打字结束回调：根据来源决定等待儿童输入或推进步骤。
func _on_dialogue_finished() -> void:
	# 若当前显示的是 AI 动态回复，则回复结束后直接推进步骤
	if _showing_ai_reply:
		_showing_ai_reply = false
		_advance_step()
		return

	# 否则当前显示的是脚本台词：根据是否存在测量点决定下一步
	var measure_point := String(_current_step_data.get("measure_point", ""))
	if measure_point.is_empty():
		# 无测量点：直接进入下一步
		_advance_step()
	else:
		# 有测量点：启用输入框等待儿童回应
		_is_waiting_for_child = true
		_set_input_enabled(true)


# ============================================================
#  儿童输入
# ============================================================

func _on_send_button_pressed() -> void:
	_submit_child_input()


func _on_input_field_text_submitted(_new_text: String) -> void:
	_submit_child_input()


## 提交儿童输入：记录轮次、请求评分与 AI 回复。
func _submit_child_input() -> void:
	if not _is_waiting_for_child:
		return
	var text := InputField.text.strip_edges()
	if text.is_empty():
		return

	_is_waiting_for_child = false
	_last_child_text = text
	InputField.clear()
	_set_input_enabled(false)
	LoadingLabel.visible = true

	var step_index := _current_step_index

	# 记录儿童轮次到全局会话数据
	AssessmentGameManager.record_turn({
		"speaker": "child",
		"text": text,
		"level": _current_level_index,
		"step": step_index,
	})
	_level_turns.append({"text": text, "step": step_index})

	# 追加到多轮对话历史
	_dialogue_messages.append({"role": "user", "content": text})

	# 构建场景上下文
	var dimension := String(_current_level_data.get("dimension", ""))
	var scenario_context := _build_scenario_context()

	# 请求礼貌等级评分（异步，结果通过 scoring_received / scoring_error 返回）
	AIManager.analyze_politeness(text, dimension, scenario_context)

	# 同时请求 AI 动态回复（异步，结果通过 ai_response_received / ai_response_error 返回）
	var system_prompt := AIManager.build_dialogue_system_prompt(scenario_context)
	AIManager.send_dialogue(system_prompt, _dialogue_messages)


## 构建发往 LLM 的场景上下文描述。
func _build_scenario_context() -> String:
	var level_name := String(_current_level_data.get("name", ""))
	var scene := String(_current_level_data.get("scene", ""))
	var dimension := String(_current_level_data.get("dimension", ""))
	var measure_point := String(_current_step_data.get("measure_point", ""))
	var description := String(_current_level_data.get("description", ""))
	return "关卡：%s。场景：%s。测量维度：%s。测量点：%s。任务说明：%s" % [
		level_name, scene, dimension, measure_point, description
	]


# ============================================================
#  评分回调
# ============================================================

## 收到礼貌评分结果。
func _on_scoring_received(result: Dictionary) -> void:
	_level_scores.append(result)
	AssessmentGameManager.record_turn({
		"speaker": "child_score",
		"text": _last_child_text,
		"score": result,
		"level": _current_level_index,
		"step": _current_step_index,
	})


## 评分失败：使用默认等级以保证关卡可正常结算。
func _on_scoring_error(error: String) -> void:
	var fallback_score := {
		"level": 2,
		"markers": [],
		"description": "评分失败，使用默认等级",
		"strategy": "fallback",
	}
	_level_scores.append(fallback_score)
	AssessmentGameManager.record_turn({
		"speaker": "child_score",
		"text": _last_child_text,
		"score": fallback_score,
		"level": _current_level_index,
		"step": _current_step_index,
		"error": error,
	})


# ============================================================
#  AI 回复回调
# ============================================================

## 收到 AI 动态回复。
func _on_ai_response_received(text: String) -> void:
	LoadingLabel.visible = false
	_dialogue_messages.append({"role": "assistant", "content": text})

	var speaker := String(_current_step_data.get("speaker", _get_default_ai_name()))
	AssessmentGameManager.record_turn({
		"speaker": "ai",
		"text": text,
		"level": _current_level_index,
		"step": _current_step_index,
	})

	# 标记当前显示的是动态回复，结束后由 _on_dialogue_finished 推进步骤
	_showing_ai_reply = true
	DialogueBox.show_dialogue(speaker, text)


## AI 回复失败：使用后备回复并推进步骤。
func _on_ai_response_error(error: String) -> void:
	LoadingLabel.visible = false
	var fallback := _get_fallback_reply()
	_dialogue_messages.append({"role": "assistant", "content": fallback})

	var speaker := String(_current_step_data.get("speaker", _get_default_ai_name()))
	AssessmentGameManager.record_turn({
		"speaker": "ai",
		"text": fallback,
		"level": _current_level_index,
		"step": _current_step_index,
		"fallback": true,
		"error": error,
	})

	_showing_ai_reply = true
	DialogueBox.show_dialogue(speaker, fallback)


# ============================================================
#  步骤推进 / 关卡完成
# ============================================================

## 推进到下一步；若已到最后一步则完成关卡。
func _advance_step() -> void:
	_current_step_index += 1
	var lines := _get_current_ai_lines()
	if _current_step_index >= lines.size():
		_complete_level()
	else:
		_play_current_step()


## 完成当前关卡：计算得分、记录结果、更新星章板。
func _complete_level() -> void:
	_set_input_enabled(false)
	LoadingLabel.visible = false

	# 基于本关评分计算平均等级
	var avg_level := _calculate_average_level()
	# 星章规则：平均等级 >=3 得 1 星，>=4 得 2 星，封顶每关 1 星
	var raw_stars := 0
	if avg_level >= 4.0:
		raw_stars = 2
	elif avg_level >= 3.0:
		raw_stars = 1
	var stars := mini(raw_stars, 1) # 封顶 1 星 / 关

	var level_id := int(_current_level_data.get("id", _current_level_index + 1))
	AssessmentGameManager.record_scenario_result(str(level_id), {
		"stars": stars,
		"scores": _level_scores.duplicate(true),
		"avg_level": avg_level,
		"level_index": _current_level_index,
		"level_name": String(_current_level_data.get("name", "")),
	})

	# 更新星章板进度（已完成关卡数）
	StarBadgeBoard.set_star_count(_current_level_index + 1)

	_current_level_index += 1
	if _current_level_index >= LEVEL_COUNT:
		_complete_section()
	else:
		ContinueButton.visible = true
		ContinueButton.grab_focus()


## 计算当前关卡所有评分的平均等级。
func _calculate_average_level() -> float:
	if _level_scores.is_empty():
		return 0.0
	var total := 0.0
	for score in _level_scores:
		if score is Dictionary:
			total += float(score.get("level", 0))
	return total / float(_level_scores.size())


## 继续按钮：进入下一关。
func _on_continue_button_pressed() -> void:
	ContinueButton.visible = false
	_load_level(_current_level_index)


## 完成整个板块一，进入板块二（阳光超市）。
func _complete_section() -> void:
	AssessmentGameManager.start_sunshine_market()
	AssessmentFlowHost.go_to_sunshine_market()


# ============================================================
#  AI 类型辅助
# ============================================================

func _is_tool_ai() -> bool:
	return AssessmentGameManager.get_ai_type_name() == "工具型"


## 获取当前关卡的 AI 台词列表（根据 AI 类型选择朋友型 / 工具型）。
func _get_current_ai_lines() -> Array:
	if _is_tool_ai():
		return _current_level_data.get("tool_ai", [])
	return _current_level_data.get("friend_ai", [])


func _get_default_ai_name() -> String:
	return TOOL_AI_NAME if _is_tool_ai() else FRIEND_AI_NAME


func _get_fallback_reply() -> String:
	var pool: Array = TOOL_FALLBACK_REPLIES if _is_tool_ai() else FRIEND_FALLBACK_REPLIES
	if pool.is_empty():
		return ""
	return String(pool[randi() % pool.size()])


# ============================================================
#  输入控件状态
# ============================================================

func _set_input_enabled(enabled: bool) -> void:
	InputField.editable = enabled
	SendButton.disabled = not enabled
	if _mic_button and IFlytekSR.is_configured():
		_mic_button.disabled = not enabled
	if enabled:
		InputField.grab_focus()
	# 清空语音状态
	if _voice_status_label and not enabled:
		_voice_status_label.text = ""
