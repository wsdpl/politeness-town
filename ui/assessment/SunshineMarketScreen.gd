extends Control
## 阳光超市场景 (SunshineMarketScreen)
## 板块二「阳光超市」进阶挑战场景。
## 包含两条故事线：
##   故事线一：阳光超市同行者（3 个事件，分别与小朋友、老师、陌生人互动）
##   故事线二：超市大冒险（3 个阶段递进难度：低压力找购物车、中压力资源竞争、高压道歉+请求复合）
## 通过 AssessmentAIManager 调用 LLM 进行场景对话与礼貌评分，
## 所有事件结束后汇总结果交由 AssessmentGameManager，再跳转结果页。

# ============================================================
#  常量
# ============================================================

# 后备对话回复（API 不可用时使用）
const FRIEND_FALLBACK_REPLIES := [
	"嗯嗯，你说得对！",
	"哇，好棒呀！",
	"好主意！我们继续吧～",
]

const TOOL_FALLBACK_REPLIES := [
	"已接收。",
	"理解。",
	"继续。",
]

# 旁白与 AI 同伴名标
const NARRATOR_NAME := "旁白"
const FRIEND_COMPANION_NAME := "小熊布布"
const TOOL_COMPANION_NAME := "引导系统"

# 名标颜色（归一化 RGB，仅供备注参考）
const CHILD_NAME_COLOR := Color(0.082, 0.396, 0.753)
const FRIEND_AI_COLOR := Color(0.902, 0.318, 0.0)
const TOOL_AI_COLOR := Color(0.416, 0.106, 0.604)

# 故事线显示文案
const STORY_LINE_1_TITLE := "故事线一：阳光超市同行者"
const STORY_LINE_2_TITLE := "故事线二：超市大冒险"


# ============================================================
#  节点引用
# ============================================================

# DialogueBox.gd 未声明 class_name，故保持无类型引用以便调用其脚本方法/信号
@onready var DialogueBox = $CanvasLayer/DialogueBox
@onready var InputContainer: HBoxContainer = $CanvasLayer/InputContainer
@onready var InputField: LineEdit = $CanvasLayer/InputContainer/InputField
@onready var SendButton: Button = $CanvasLayer/InputContainer/SendButton
@onready var StoryLineLabel: Label = $CanvasLayer/StoryLineLabel
@onready var EventLabel: Label = $CanvasLayer/EventLabel
@onready var NpcInfoLabel: Label = $CanvasLayer/NpcInfoLabel
@onready var Progress_Bar: ProgressBar = $CanvasLayer/ProgressBar
@onready var AIManager: AssessmentAIManager = $AssessmentAIManager
@onready var LoadingLabel: Label = $CanvasLayer/LoadingLabel
@onready var ContinueButton: Button = $CanvasLayer/ContinueButton

# ---- 语音输入相关 ----
var _mic_button: Button
var _voice_status_label: Label


# ============================================================
#  核心数据结构
# ============================================================

var _current_story_line: int = 0   # 0=故事线一, 1=故事线二
var _current_event_index: int = 0  # 当前事件/阶段索引
var _current_step_index: int = 0   # 当前步骤索引
var _is_waiting_for_child: bool = false
var _dialogue_messages: Array = []
var _event_turns: Array = []
var _event_scores: Array = []
var _all_scores: Array = []        # 所有事件的评分


# ============================================================
#  当前事件/阶段缓存与流程状态
# ============================================================

# 当前事件/阶段原始数据
var _current_event_data: Dictionary = {}
# 当前事件/阶段的步骤列表（故事线一=dialogue_steps，故事线二=rounds）
var _current_steps: Array = []
# 当前 NPC 信息（故事线一为事件级 NPC，故事线二按轮次取）
var _current_npc: Dictionary = {}
# 当前预期礼貌等级（故事线一为事件级，故事线二按压力推导）
var _current_expected_level: String = ""

# DialogueBox 当前播放阶段："intro" / "step_line" / "ai_reply"
var _dialogue_phase: String = ""


# ============================================================
#  进度统计（预计算）
# ============================================================

var _sl1_step_counts: Array = []
var _sl1_total_steps: int = 0
var _sl2_step_counts: Array = []
var _sl2_total_steps: int = 0
var _total_steps: int = 0


# ============================================================
#  生命周期
# ============================================================

func _ready() -> void:
	# AssessmentGameManager / AssessmentFlowHost 为 autoload 单例，可直接访问。
	# 进入板块二前已由 PolitenessHouseScreen._complete_section() 调用
	# start_sunshine_market()，此处无需重复调用。
	theme = AssessmentUiTheme.theme

	# 给故事线标签添加底框
	AssessmentUiTheme.wrap_in_panel(StoryLineLabel, AssessmentUiTheme.title_panel_style())

	# 给事件标签添加底框
	AssessmentUiTheme.wrap_in_panel(EventLabel, AssessmentUiTheme.label_panel_style())

	# 给NPC信息标签添加底框
	AssessmentUiTheme.wrap_in_panel(NpcInfoLabel, AssessmentUiTheme.label_panel_style())

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

	# 预计算各事件/阶段步数，用于进度条
	_precompute_step_counts()
	Progress_Bar.min_value = 0.0
	Progress_Bar.max_value = float(maxi(_total_steps, 1))
	Progress_Bar.value = 0.0
	Progress_Bar.show_percentage = false

	# 连接 AI 管理器信号
	AIManager.scoring_received.connect(_on_scoring_received)
	AIManager.scoring_error.connect(_on_scoring_error)
	AIManager.ai_response_received.connect(_on_ai_response_received)
	AIManager.ai_response_error.connect(_on_ai_response_error)

	# 连接对话框信号
	DialogueBox.dialogue_finished.connect(_on_dialogue_finished)

	# 连接按钮 / 输入框信号
	SendButton.pressed.connect(_on_send_button_pressed)
	InputField.text_submitted.connect(_on_input_field_text_submitted)
	ContinueButton.pressed.connect(_on_continue_button_pressed)

	# 初始控件状态
	_set_input_enabled(false)
	LoadingLabel.visible = false
	ContinueButton.visible = false
	DialogueBox.visible = false

	# 进入故事线一
	_start_story_line_1()
	
	# 初始化语音输入
	_setup_voice_input()


# ============================================================
#  语音输入
# ============================================================

func _setup_voice_input() -> void:
	_mic_button = Button.new()
	_mic_button.text = "🎤 说话"
	_mic_button.custom_minimum_size = Vector2(140, 50)
	_mic_button.add_theme_font_size_override("font_size", 28)
	InputContainer.add_child(_mic_button)
	AssessmentUiTheme.apply_primary_button(_mic_button)
	
	_voice_status_label = Label.new()
	_voice_status_label.text = ""
	_voice_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_voice_status_label.add_theme_font_size_override("font_size", 28)
	_voice_status_label.add_theme_color_override("font_color", AssessmentUiTheme.INK)
	InputContainer.add_child(_voice_status_label)
	# 给语音状态标签添加底框
	AssessmentUiTheme.wrap_label_in_panel(_voice_status_label)
	
	_mic_button.pressed.connect(_on_mic_button_pressed)
	IFlytekSR.recording_started.connect(_on_voice_recording_started)
	IFlytekSR.recording_stopped.connect(_on_voice_recording_stopped)
	IFlytekSR.recognition_completed.connect(_on_voice_recognition_completed)
	IFlytekSR.recognition_failed.connect(_on_voice_recognition_failed)
	IFlytekSR.status_message.connect(_on_voice_status_message)
	
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
	print("[SunshineMarketScreen] 语音识别完成: %s" % text)
	
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
#  故事线一：阳光超市同行者
# ============================================================

func _start_story_line_1() -> void:
	_current_story_line = 0
	_current_event_index = 0
	StoryLineLabel.text = STORY_LINE_1_TITLE
	_load_event(0)


## 加载故事线一指定事件，更新 UI 并播放事件引导语。
func _load_event(index: int) -> void:
	_current_event_data = AssessmentData.get_story_line_1_event_by_index(index)
	if _current_event_data.is_empty():
		push_error("[SunshineMarketScreen] 故事线一事件数据为空: %d" % index)
		return

	_current_event_index = index
	_current_step_index = 0
	_event_turns.clear()
	_event_scores.clear()
	_dialogue_messages.clear()

	_current_steps = _current_event_data.get("dialogue_steps", [])
	_current_npc = _current_event_data.get("npc", {})
	var social_distance: Dictionary = _current_event_data.get("social_distance", {})
	_current_expected_level = String(_current_event_data.get("expected_politeness_level", ""))

	EventLabel.text = "事件%d: %s" % [index + 1, String(_current_event_data.get("name", ""))]
	NpcInfoLabel.text = "NPC: %s (%s), 社会距离: %s, 预期等级: %s" % [
		String(_current_npc.get("name", "")),
		String(_current_npc.get("role", "")),
		String(social_distance.get("label", social_distance.get("type", ""))),
		_current_expected_level,
	]
	_update_progress_bar()

	_play_event_intro()


## 播放事件引导语（旁白描述场景与互动目标）。
func _play_event_intro() -> void:
	var intro := "场景：%s\n\n互动目标：%s" % [
		String(_current_event_data.get("scene_context", "")),
		String(_current_event_data.get("interaction_goal", "")),
	]
	_dialogue_phase = "intro"
	DialogueBox.show_dialogue(NARRATOR_NAME, intro)


# ============================================================
#  故事线二：超市大冒险
# ============================================================

func _start_story_line_2() -> void:
	_current_story_line = 1
	_current_event_index = 0
	StoryLineLabel.text = STORY_LINE_2_TITLE
	_load_phase(0)


## 加载故事线二指定阶段，更新 UI 并播放阶段引导语。
func _load_phase(index: int) -> void:
	_current_event_data = AssessmentData.get_story_line_2_phase_by_index(index)
	if _current_event_data.is_empty():
		push_error("[SunshineMarketScreen] 故事线二阶段数据为空: %d" % index)
		return

	_current_event_index = index
	_current_step_index = 0
	_event_turns.clear()
	_event_scores.clear()
	_dialogue_messages.clear()

	_current_steps = _current_event_data.get("rounds", [])
	_current_npc = {}
	var pressure := String(_current_event_data.get("pressure_level", ""))
	_current_expected_level = _pressure_to_expected_level(pressure)

	EventLabel.text = "阶段%d: %s (难度: %s)" % [
		index + 1,
		String(_current_event_data.get("name", "")),
		pressure,
	]
	NpcInfoLabel.text = "难度: %s | %s" % [
		pressure,
		String(_current_event_data.get("pressure_description", "")),
	]
	_update_progress_bar()

	_play_phase_intro()


## 播放阶段引导语（旁白描述场景与压力说明）。
func _play_phase_intro() -> void:
	var intro := "场景：%s\n\n难度说明：%s" % [
		String(_current_event_data.get("scene_context", "")),
		String(_current_event_data.get("pressure_description", "")),
	]
	_dialogue_phase = "intro"
	DialogueBox.show_dialogue(NARRATOR_NAME, intro)


# ============================================================
#  步骤播放与推进
# ============================================================

## 播放当前步骤台词：根据 AI 类型选择朋友型/工具型台词，用 DialogueBox 显示。
## 若该步骤为测量点，dialogue_finished 后等待儿童输入；否则直接推进。
func _play_current_step() -> void:
	var step := _get_current_step()
	if step.is_empty():
		_complete_event()
		return

	_update_progress_bar()

	# 故事线二：按轮次更新 NPC 信息
	if _current_story_line == 1:
		var round_npc: Dictionary = step.get("npc", {})
		NpcInfoLabel.text = "NPC: %s (%s) | 测量点: %s" % [
			String(round_npc.get("name", "")),
			String(round_npc.get("role", "")),
			String(step.get("measure_point", "")),
		]

	var display := _get_step_display(step)
	var speaker := String(display.get("speaker", _get_companion_name()))
	var line_text := String(display.get("text", ""))
	# 将脚本台词追加到对话历史，为后续 LLM 调用提供上下文
	_dialogue_messages.append({"role": "assistant", "content": line_text})
	_dialogue_phase = "step_line"
	DialogueBox.show_dialogue(speaker, line_text)


## DialogueBox 台词播放完毕回调，根据当前阶段决定后续动作。
func _on_dialogue_finished() -> void:
	match _dialogue_phase:
		"intro":
			_dialogue_phase = ""
			_play_current_step()
		"step_line":
			_dialogue_phase = ""
			var step := _get_current_step()
			if _step_needs_input(step):
				_is_waiting_for_child = true
				_set_input_enabled(true)
			else:
				_advance_step()
		"ai_reply":
			_dialogue_phase = ""
			_advance_step()
		_:
			_dialogue_phase = ""


## 推进到下一个步骤；若步骤完毕则完成当前事件/阶段。
func _advance_step() -> void:
	_current_step_index += 1
	if _current_step_index >= _current_steps.size():
		_complete_event()
	else:
		_play_current_step()


# ============================================================
#  儿童输入与 AI 交互
# ============================================================

func _on_send_button_pressed() -> void:
	_submit_child_input()


func _on_input_field_text_submitted(_text: String) -> void:
	_submit_child_input()


## 提交儿童当前输入：记录轮次、请求礼貌分析与 AI 回复。
func _submit_child_input() -> void:
	if not _is_waiting_for_child:
		return
	var text := InputField.text.strip_edges()
	if text.is_empty():
		return

	_is_waiting_for_child = false
	_set_input_enabled(false)
	InputField.clear()

	var step := _get_current_step()
	var measure_point := _get_step_measure_point(step)
	var dimension := _derive_dimension(measure_point)
	var scenario_context := _build_scenario_context(step)

	# 记录儿童轮次到本事件缓存与全局会话
	var turn := {
		"speaker": "child",
		"child_input": text,
		"text": text,
		"story_line": _current_story_line,
		"event_index": _current_event_index,
		"step_index": _current_step_index,
		"measure_point": measure_point,
		"dimension": dimension,
		"expected_level": _current_expected_level,
		"pressure_level": String(_current_event_data.get("pressure_level", "")),
	}
	_event_turns.append(turn)
	AssessmentGameManager.record_turn(turn)

	# 追加到多轮对话历史
	_dialogue_messages.append({"role": "user", "content": text})

	LoadingLabel.visible = true

	# 礼貌分析 + AI 回复（异步并行，各自通过信号回调）
	AIManager.analyze_politeness(text, dimension, scenario_context)
	var system_prompt := AIManager.build_dialogue_system_prompt(scenario_context)
	AIManager.send_dialogue(system_prompt, _dialogue_messages)


## 收到礼貌评分结果：记录到本事件评分，并记录情境适配信息。
func _on_scoring_received(result: Dictionary) -> void:
	_event_scores.append(result)
	_record_contextual_fit(result)


## 收到 AI 回复：显示 AI 回复，随后推进步骤。
func _on_ai_response_received(text: String) -> void:
	LoadingLabel.visible = false
	_dialogue_messages.append({"role": "assistant", "content": text})
	AssessmentGameManager.record_turn({
		"speaker": "ai",
		"text": text,
		"story_line": _current_story_line,
		"event_index": _current_event_index,
		"step_index": _current_step_index,
	})
	_dialogue_phase = "ai_reply"
	DialogueBox.show_dialogue(_get_companion_name(), text)


## 评分出错：使用本地 PolitenessScoring 作为后备，并记录情境适配。
func _on_scoring_error(error: String) -> void:
	var last_text := ""
	var dimension := "基础礼貌"
	if not _event_turns.is_empty():
		var last: Dictionary = _event_turns[-1]
		last_text = String(last.get("child_input", last.get("text", "")))
		dimension = String(last.get("dimension", "基础礼貌"))
	var fallback_result := PolitenessScoring.score_response(last_text, dimension)
	fallback_result["source"] = "local_fallback"
	fallback_result["error"] = error
	_event_scores.append(fallback_result)
	_record_contextual_fit(fallback_result)
	print("[SunshineMarketScreen] 评分回退到本地计算: %s" % error)


## AI 回复出错：使用预设回复作为后备，显示后推进步骤。
func _on_ai_response_error(error: String) -> void:
	LoadingLabel.visible = false
	var fallback := _get_fallback_reply()
	_dialogue_messages.append({"role": "assistant", "content": fallback})
	AssessmentGameManager.record_turn({
		"speaker": "ai",
		"text": fallback,
		"story_line": _current_story_line,
		"event_index": _current_event_index,
		"step_index": _current_step_index,
		"is_fallback": true,
	})
	_dialogue_phase = "ai_reply"
	DialogueBox.show_dialogue(_get_companion_name(), fallback)
	print("[SunshineMarketScreen] AI 回复回退到预设: %s" % error)


# ============================================================
#  事件/阶段完成与流程切换
# ============================================================

## 完成当前事件/阶段：计算得分、记录结果，按故事线决定下一步。
func _complete_event() -> void:
	var score_summary := _compute_event_score()
	var scenario_id := _get_current_scenario_id()

	_all_scores.append({
		"story_line": _current_story_line,
		"event": _current_event_index,
		"scores": _event_scores.duplicate(true),
		"summary": score_summary,
	})

	AssessmentGameManager.record_scenario_result(scenario_id, {
		"scenario_id": scenario_id,
		"story_line": _current_story_line,
		"event_index": _current_event_index,
		"scores": _event_scores.duplicate(true),
		"turns": _event_turns.duplicate(true),
		"stars": int(score_summary.get("stars", 0)),
		"average_level": float(score_summary.get("average_level", 0.0)),
	})
	AssessmentGameManager.advance_scenario()

	_current_event_index += 1
	var unit_count := _get_current_unit_count()
	if _current_event_index >= unit_count:
		if _current_story_line == 0:
			_start_story_line_2()
		else:
			_complete_section()
	else:
		_show_continue_button()


## 显示「继续」按钮，等待进入下一个事件/阶段。
func _show_continue_button() -> void:
	ContinueButton.text = "继续"
	ContinueButton.visible = true
	ContinueButton.grab_focus()
	var unit_label := "事件" if _current_story_line == 0 else "阶段"
	var unit_count := _get_current_unit_count()
	EventLabel.text = "%s %d/%d 已完成，点击「继续」进入下一个%s" % [
		unit_label, _current_event_index, unit_count, unit_label
	]


func _on_continue_button_pressed() -> void:
	ContinueButton.visible = false
	if _current_story_line == 0:
		_load_event(_current_event_index)
	else:
		_load_phase(_current_event_index)


## 完成整个板块二：汇总最终结果并跳转结果页。
func _complete_section() -> void:
	var final_results := _build_final_results()
	AssessmentGameManager.complete_assessment(final_results)
	AssessmentFlowHost.go_to_results()


# ============================================================
#  得分计算与结果汇总
# ============================================================

## 计算当前事件/阶段得分汇总。
func _compute_event_score() -> Dictionary:
	var turn_count := _event_turns.size()
	if _event_scores.is_empty():
		return {
			"average_level": 0.0,
			"turn_count": turn_count,
			"stars": 0,
			"score_count": 0,
		}
	var total := 0.0
	for s in _event_scores:
		total += float(s.get("level", 0))
	var avg := total / float(_event_scores.size())
	return {
		"average_level": avg,
		"turn_count": turn_count,
		"stars": _level_to_stars(avg),
		"score_count": _event_scores.size(),
	}


## 将平均礼貌等级映射为星章（0-3）。
func _level_to_stars(avg: float) -> int:
	if avg >= 4.0:
		return 3
	elif avg >= 3.0:
		return 2
	elif avg >= 2.0:
		return 1
	return 0


## 构建板块二最终结果，包含雷达图数据与汇总得分。
func _build_final_results() -> Dictionary:
	var all_turns: Array = []
	# 仅收集本场景记录的轮次（带 story_line 字段）
	for t in AssessmentGameManager.get_all_turns():
		if t is Dictionary and t.has("story_line"):
			all_turns.append(t)

	var radar := PolitenessScoring.generate_radar_data({"turns": all_turns})

	var total_stars := 0
	var total_level := 0.0
	var score_count := 0
	for entry in _all_scores:
		var summary: Dictionary = entry.get("summary", {})
		total_stars += int(summary.get("stars", 0))
		var scores: Array = entry.get("scores", [])
		for s in scores:
			total_level += float(s.get("level", 0))
			score_count += 1
	var overall_level := total_level / float(score_count) if score_count > 0 else 0.0

	return {
		"section": "sunshine_market",
		"all_scores": _all_scores.duplicate(true),
		"total_stars": total_stars,
		"overall_average_level": overall_level,
		"radar_data": radar,
		"turn_count": all_turns.size(),
		"completed": true,
	}


## 记录情境适配信息：比较预期等级与实际礼貌等级，写回最近一条轮次。
func _record_contextual_fit(result: Dictionary) -> void:
	var actual_level := int(result.get("level", 0))
	var fit := _evaluate_level_fit(_current_expected_level, actual_level)
	if not _event_turns.is_empty():
		_event_turns[-1]["actual_level"] = actual_level
		_event_turns[-1]["level_fit"] = fit
		_event_turns[-1]["scoring_markers"] = result.get("markers", [])
		_event_turns[-1]["scoring_strategy"] = String(result.get("strategy", ""))


# ============================================================
#  步骤数据解析辅助
# ============================================================

## 获取当前步骤数据。
func _get_current_step() -> Dictionary:
	if _current_step_index < 0 or _current_step_index >= _current_steps.size():
		return {}
	return _current_steps[_current_step_index]


## 获取当前步骤的说话者与台词（故事线二按 AI 类型选择朋友型/工具型）。
func _get_step_display(step: Dictionary) -> Dictionary:
	if _current_story_line == 0:
		return {
			"speaker": String(step.get("speaker", _get_companion_name())),
			"text": String(step.get("text", "")),
		}
	# 故事线二：根据 AI 类型选择 ai_prompt_friend / ai_prompt_tool
	var raw := ""
	if _is_tool_ai():
		raw = String(step.get("ai_prompt_tool", ""))
	else:
		raw = String(step.get("ai_prompt_friend", ""))
	return _extract_speaker_and_text(raw, _get_companion_name())


## 获取当前步骤的测量点描述（故事线一用 intent，故事线二用 measure_point）。
func _get_step_measure_point(step: Dictionary) -> String:
	if _current_story_line == 0:
		return String(step.get("intent", ""))
	return String(step.get("measure_point", ""))


## 判断当前步骤是否需要等待儿童输入。
func _step_needs_input(step: Dictionary) -> bool:
	if _current_story_line == 0:
		# 故事线一：每个对话步骤均为互动测量点
		return not String(step.get("text", "")).is_empty()
	# 故事线二：有 measure_point 视为测量点
	return not String(step.get("measure_point", "")).is_empty()


## 从 "名字：台词" 格式中拆分说话者与台词。
func _extract_speaker_and_text(raw: String, default_speaker: String) -> Dictionary:
	var text := raw.strip_edges()
	var speaker := default_speaker
	var colon_idx := text.find("：")
	if colon_idx > 0:
		var possible := text.substr(0, colon_idx)
		if possible.length() <= 8 and possible.find(" ") == -1:
			speaker = possible
			text = text.substr(colon_idx + 1).strip_edges()
	return {"speaker": speaker, "text": text}


# ============================================================
#  场景上下文与维度推导
# ============================================================

## 构建发送给 LLM 的场景上下文描述。
func _build_scenario_context(step: Dictionary) -> String:
	var parts: Array = []
	parts.append("故事线%s" % ("一" if _current_story_line == 0 else "二"))

	if _current_story_line == 0:
		parts.append("事件：%s" % String(_current_event_data.get("name", "")))
		parts.append("NPC：%s（%s）" % [
			String(_current_npc.get("name", "")),
			String(_current_npc.get("role", "")),
		])
		parts.append("场景：%s" % String(_current_event_data.get("scene_context", "")))
		parts.append("互动目标：%s" % String(_current_event_data.get("interaction_goal", "")))
		parts.append("测量点：%s" % _get_step_measure_point(step))
		if not _current_expected_level.is_empty():
			parts.append("预期礼貌等级：%s" % _current_expected_level)
	else:
		parts.append("阶段：%s（难度：%s）" % [
			String(_current_event_data.get("name", "")),
			String(_current_event_data.get("pressure_level", "")),
		])
		var round_npc: Dictionary = step.get("npc", {})
		parts.append("NPC：%s（%s）" % [
			String(round_npc.get("name", "")),
			String(round_npc.get("role", "")),
		])
		parts.append("场景：%s" % String(_current_event_data.get("scene_context", "")))
		parts.append("测量点：%s" % _get_step_measure_point(step))
		var expected_behavior := String(step.get("expected_behavior", ""))
		if not expected_behavior.is_empty():
			parts.append("期望行为：%s" % expected_behavior)
		if not _current_expected_level.is_empty():
			parts.append("预期礼貌等级：%s" % _current_expected_level)
	return _join_strings(parts, "；")


## 由测量点描述推导礼貌维度（用于评分上下文）。
func _derive_dimension(measure_point: String) -> String:
	var mp := measure_point
	if mp.find("道歉") != -1 or mp.find("致歉") != -1 or mp.find("歉意") != -1:
		return "致歉"
	if mp.find("感谢") != -1 or mp.find("道谢") != -1 or mp.find("谢谢") != -1:
		return "道谢"
	if mp.find("告别") != -1 or mp.find("再见") != -1:
		return "告别"
	if mp.find("分享") != -1 or mp.find("谦让") != -1 or mp.find("轮流") != -1:
		return "分享"
	if mp.find("问候") != -1 or mp.find("打招呼") != -1:
		return "问候"
	if mp.find("请求") != -1 or mp.find("求助") != -1 or mp.find("协商") != -1:
		return "请求"
	return "基础礼貌"


## 将压力等级映射为预期礼貌等级区间。
func _pressure_to_expected_level(pressure: String) -> String:
	match pressure:
		"低":
			return "2-3"
		"中":
			return "3-4"
		"高":
			return "4-5"
		_:
			return ""


## 评估实际等级是否符合预期等级区间。
func _evaluate_level_fit(expected: String, actual: int) -> String:
	var levels := _parse_expected_levels(expected)
	if levels.is_empty():
		return "未知"
	var min_l := int(levels[0])
	var max_l := int(levels[0])
	for l in levels:
		var li := int(l)
		if li < min_l:
			min_l = li
		if li > max_l:
			max_l = li
	if actual >= min_l and actual <= max_l:
		return "符合预期"
	elif actual > max_l:
		return "高于预期"
	return "低于预期"


## 解析期望等级字符串中的所有整数（支持 "3-4" / "4或3" / "3" 等格式）。
func _parse_expected_levels(expected: String) -> Array:
	var levels: Array = []
	var num := ""
	for ch in expected:
		if ch.is_valid_int():
			num += ch
		else:
			if num != "":
				levels.append(int(num))
				num = ""
	if num != "":
		levels.append(int(num))
	return levels


# ============================================================
#  进度条与步数预计算
# ============================================================

func _update_progress_bar() -> void:
	Progress_Bar.value = float(_compute_global_step_index())


## 计算当前步骤在板块二全局中的序号（用于进度条）。
func _compute_global_step_index() -> int:
	var idx := 0
	if _current_story_line == 0:
		for i in range(_current_event_index):
			idx += int(_sl1_step_counts[i]) if i < _sl1_step_counts.size() else 0
		idx += _current_step_index
	else:
		idx += _sl1_total_steps
		for i in range(_current_event_index):
			idx += int(_sl2_step_counts[i]) if i < _sl2_step_counts.size() else 0
		idx += _current_step_index
	return idx


func _precompute_step_counts() -> void:
	_sl1_step_counts.clear()
	_sl1_total_steps = 0
	var sl1_count := AssessmentData.get_story_line_1_event_count()
	for i in range(sl1_count):
		var ev := AssessmentData.get_story_line_1_event_by_index(i)
		var c := int(ev.get("dialogue_steps", []).size())
		_sl1_step_counts.append(c)
		_sl1_total_steps += c

	_sl2_step_counts.clear()
	_sl2_total_steps = 0
	var sl2_count := AssessmentData.get_story_line_2_phase_count()
	for i in range(sl2_count):
		var ph := AssessmentData.get_story_line_2_phase_by_index(i)
		var c := int(ph.get("rounds", []).size())
		_sl2_step_counts.append(c)
		_sl2_total_steps += c

	_total_steps = _sl1_total_steps + _sl2_total_steps


## 获取当前故事线的事件/阶段总数。
func _get_current_unit_count() -> int:
	if _current_story_line == 0:
		return AssessmentData.get_story_line_1_event_count()
	return AssessmentData.get_story_line_2_phase_count()


## 获取当前事件/阶段的场景标识（优先使用数据中的 event_id / phase_id）。
func _get_current_scenario_id() -> String:
	if _current_story_line == 0:
		return String(_current_event_data.get("event_id", "S1-E%d" % (_current_event_index + 1)))
	return String(_current_event_data.get("phase_id", "S2-P%d" % (_current_event_index + 1)))


# ============================================================
#  AI 类型与后备回复辅助
# ============================================================

func _is_tool_ai() -> bool:
	return AssessmentGameManager.get_ai_type_name() == "工具型"


func _get_companion_name() -> String:
	return TOOL_COMPANION_NAME if _is_tool_ai() else FRIEND_COMPANION_NAME


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
	if _voice_status_label and not enabled:
		_voice_status_label.text = ""


# ============================================================
#  通用辅助
# ============================================================

## 用分隔符拼接字符串数组。
func _join_strings(parts: Array, sep: String) -> String:
	var result := ""
	for i in range(parts.size()):
		if i > 0:
			result += sep
		result += String(parts[i])
	return result
