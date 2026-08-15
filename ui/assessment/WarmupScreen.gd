extends Control
## 预热场景 (WarmupScreen)
## 儿童与 AI 进行 3 分钟自由聊天，采集礼貌基线。
## 通过 AssessmentAIManager 调用 LLM 进行自由对话，
## 倒计时结束后用 PolitenessScoring 计算基线并交给 AssessmentGameManager。

# ============================================================
#  常量
# ============================================================

const WARMUP_DURATION_SECONDS := 180

const WELCOME_MESSAGE := "欢迎来到礼貌小镇！在开始闯关之前，我们先和AI向导聊聊天吧～（3分钟自由对话）"

const FRIEND_OPENING_LINE := "你好呀！我是小礼，很高兴认识你！你想聊什么呢？"
const TOOL_OPENING_LINE := "对话模式已启动。请输入消息。"

const FRIEND_AI_NAME := "小礼"
const TOOL_AI_NAME := "系统"

const WARMUP_SCENARIO_CONTEXT := "自由聊天预热阶段（3分钟自由对话，采集礼貌基线）"

# 后备对话回复（API 不可时使用）
const FRIEND_FALLBACK_REPLIES := [
	"嗯嗯，你说得真好！",
	"哇，好有趣呀！然后呢？",
	"我也觉得呢！",
	"哈哈，你真可爱～",
	"然后发生了什么呢？",
]

const TOOL_FALLBACK_REPLIES := [
	"已接收。请继续。",
	"理解。请输入下一条消息。",
	"信息已记录。",
	"继续对话。",
]

# 名标 / 系统文本颜色（hex 仅供注释参考，实际使用归一化 RGB）
# 儿童发言名标 #1565C0
const CHILD_NAME_COLOR := Color(0.082, 0.396, 0.753)
# 朋友型 AI 名标 #E65100
const FRIEND_AI_COLOR := Color(0.902, 0.318, 0.0)
# 工具型 AI 名标 #6A1B9A
const TOOL_AI_COLOR := Color(0.416, 0.106, 0.604)
# 系统提示文本 #5D4037
const SYSTEM_TEXT_COLOR := Color(0.365, 0.251, 0.216)


# ============================================================
#  节点引用
# ============================================================

@onready var TitleLabel: Label = %TitleLabel
@onready var DialogueArea: RichTextLabel = %DialogueArea
@onready var InputContainer: HBoxContainer = %InputContainer
@onready var InputField: LineEdit = %InputField
@onready var SendButton: Button = %SendButton
@onready var TimerLabel: Label = %TimerLabel
@onready var Progress_Bar: ProgressBar = %ProgressBar
@onready var StartButton: Button = %StartButton
@onready var StatusLabel: Label = %StatusLabel
@onready var ContinueButton: Button = %ContinueButton
@onready var AIManager: AssessmentAIManager = $AssessmentAIManager


# ============================================================
#  内部状态
# ============================================================

var _warmup_timer: Timer = null
var _remaining_seconds: int = WARMUP_DURATION_SECONDS
var _start_time_msec: int = 0
var _warmup_finished: bool = false

# 发往 LLM 的多轮对话历史：[{"role": "user"/"assistant", "content": "..."}]
var _dialogue_messages: Array = []

# 本地缓存的儿童预热轮次，用于基线计算（仅 speaker == "child"）
var _warmup_child_turns: Array = []


# ============================================================
#  生命周期
# ============================================================

func _ready() -> void:
	# 应用统一主题
	theme = AssessmentUiTheme.theme

	# 给标题和状态标签添加底框
	AssessmentUiTheme.wrap_in_panel(TitleLabel, AssessmentUiTheme.title_panel_style())
	AssessmentUiTheme.wrap_in_panel(TimerLabel, AssessmentUiTheme.label_panel_style())
	AssessmentUiTheme.wrap_in_panel(StatusLabel, AssessmentUiTheme.label_panel_style())

	# 给对话区域添加面板底框
	AssessmentUiTheme.wrap_in_panel(DialogueArea, AssessmentUiTheme.section_panel_style())

	# 给输入区域添加面板底框
	AssessmentUiTheme.wrap_in_panel(InputContainer, AssessmentUiTheme.section_panel_style())

	# 规范化所有字体大小（不低于28）并包裹剩余浮动标签
	AssessmentUiTheme.normalize_font_sizes($CanvasLayer)
	AssessmentUiTheme.wrap_all_floating_labels($CanvasLayer)

	# 应用按钮样式
	AssessmentUiTheme.apply_primary_button(StartButton)
	AssessmentUiTheme.apply_primary_button(ContinueButton)
	AssessmentUiTheme.apply_primary_button(SendButton)

	# 创建每秒触发的倒计时定时器
	_warmup_timer = Timer.new()
	_warmup_timer.wait_time = 1.0
	_warmup_timer.one_shot = false
	_warmup_timer.timeout.connect(_on_timer_timeout)
	add_child(_warmup_timer)

	# 连接 AI 管理器信号（子节点 _ready 已先执行，配置已刷新）
	AIManager.ai_response_received.connect(_on_ai_response_received)
	AIManager.ai_response_error.connect(_on_ai_response_error)

	# 连接按钮 / 输入框信号
	StartButton.pressed.connect(_on_start_button_pressed)
	SendButton.pressed.connect(_on_send_button_pressed)
	ContinueButton.pressed.connect(_on_continue_button_pressed)
	InputField.text_submitted.connect(_on_input_field_text_submitted)

	# 进度条初始化
	Progress_Bar.min_value = 0.0
	Progress_Bar.max_value = float(WARMUP_DURATION_SECONDS)
	Progress_Bar.value = float(WARMUP_DURATION_SECONDS)

	# 显示欢迎语
	DialogueArea.clear()
	_display_system_message(WELCOME_MESSAGE)

	# 初始控件状态：StartButton 可见，输入控件禁用
	StartButton.visible = true
	ContinueButton.visible = false
	_set_input_enabled(false)
	_update_timer_display()

	# 状态提示
	if AIManager.is_ready():
		StatusLabel.text = "点击「开始预热」开始 3 分钟自由对话"
	else:
		StatusLabel.text = "（AI 接口未配置，将使用预设回复）点击「开始预热」开始"


# ============================================================
#  按钮事件
# ============================================================

func _on_start_button_pressed() -> void:
	StartButton.visible = false
	_set_input_enabled(true)

	# 进入预热阶段，确保后续 record_turn 标记为 WARMUP
	AssessmentGameManager.start_warmup()
	_start_time_msec = Time.get_ticks_msec()
	_remaining_seconds = WARMUP_DURATION_SECONDS
	_update_timer_display()
	_warmup_timer.start()

	# AI 发送开场白（根据 AI 类型）
	var opening := _get_ai_opening_line()
	_display_ai_message(opening)
	AssessmentGameManager.record_turn({
		"speaker": "ai",
		"text": opening,
		"section": "warmup",
	})
	_dialogue_messages.append({"role": "assistant", "content": opening})


func _on_send_button_pressed() -> void:
	_send_current_input()


func _on_input_field_text_submitted(_text: String) -> void:
	_send_current_input()


func _on_continue_button_pressed() -> void:
	AssessmentGameManager.start_politeness_house()
	AssessmentFlowHost.go_to_politeness_house()


# ============================================================
#  发送 / 接收对话
# ============================================================

func _send_current_input() -> void:
	if _warmup_finished:
		return
	var text := InputField.text.strip_edges()
	if text.is_empty():
		return

	# 在对话区显示儿童消息
	_display_child_message(text)
	# 记录到全局会话数据
	AssessmentGameManager.record_turn({
		"speaker": "child",
		"text": text,
		"section": "warmup",
	})
	# 本地缓存用于基线计算
	_warmup_child_turns.append({"text": text})

	InputField.clear()
	_set_input_enabled(false)
	StatusLabel.text = "AI 正在回复…"

	# 追加到多轮对话历史并请求 LLM
	_dialogue_messages.append({"role": "user", "content": text})
	var system_prompt := AIManager.build_dialogue_system_prompt(WARMUP_SCENARIO_CONTEXT)
	AIManager.send_dialogue(system_prompt, _dialogue_messages)


func _on_ai_response_received(text: String) -> void:
	_dialogue_messages.append({"role": "assistant", "content": text})
	_display_ai_message(text)
	AssessmentGameManager.record_turn({
		"speaker": "ai",
		"text": text,
		"section": "warmup",
	})
	if _warmup_finished:
		return
	StatusLabel.text = ""
	_set_input_enabled(true)


func _on_ai_response_error(error: String) -> void:
	# 使用预设回复作为后备
	var fallback := _get_fallback_reply()
	_dialogue_messages.append({"role": "assistant", "content": fallback})
	_display_ai_message(fallback)
	AssessmentGameManager.record_turn({
		"speaker": "ai",
		"text": fallback,
		"section": "warmup",
	})
	if _warmup_finished:
		return
	StatusLabel.text = "网络异常，已使用预设回复。（%s）" % error
	_set_input_enabled(true)


# ============================================================
#  倒计时
# ============================================================

func _on_timer_timeout() -> void:
	_remaining_seconds = max(0, _remaining_seconds - 1)
	_update_timer_display()
	if _remaining_seconds <= 0:
		_finish_warmup()


func _update_timer_display() -> void:
	var minutes := _remaining_seconds / 60
	var seconds := _remaining_seconds % 60
	TimerLabel.text = "%02d:%02d" % [minutes, seconds]
	Progress_Bar.value = float(_remaining_seconds)


func _finish_warmup() -> void:
	if _warmup_finished:
		return
	_warmup_finished = true
	_warmup_timer.stop()
	_set_input_enabled(false)

	# 计算基线数据：使用 PolitenessScoring 分析所有预热儿童轮次
	var baseline := _compute_baseline()
	AssessmentGameManager.set_warmup_baseline(baseline)

	_display_system_message("预热结束！接下来我们要去礼貌小屋闯关啦！")
	StatusLabel.text = "预热结束！点击「继续」进入礼貌小屋"
	ContinueButton.visible = true
	ContinueButton.grab_focus()


# ============================================================
#  基线计算
# ============================================================

## 使用 PolitenessScoring 对预热阶段儿童的发言进行多维度分析，
## 生成基线字典并交给 AssessmentGameManager。
func _compute_baseline() -> Dictionary:
	var child_turns: Array = _warmup_child_turns

	var baseline := {
		"turn_count": child_turns.size(),
		"average_level": PolitenessScoring.calculate_average_level(child_turns, "greeting"),
		"stability": PolitenessScoring.calculate_stability(child_turns),
		"frequency": {},
		"level": {},
	}
	for dim in PolitenessScoring.CORE_DIMENSIONS:
		baseline["frequency"][dim] = PolitenessScoring.calculate_frequency(child_turns, dim)
		baseline["level"][dim] = PolitenessScoring.calculate_average_level(child_turns, dim)
	return baseline


# ============================================================
#  对话显示辅助
# ============================================================

## 使用 push_* / add_text 接口写入文本，避免 BBCode 注入风险。
func _display_system_message(text: String) -> void:
	DialogueArea.push_color(SYSTEM_TEXT_COLOR)
	DialogueArea.push_italics()
	DialogueArea.add_text(text)
	DialogueArea.pop()
	DialogueArea.pop()
	DialogueArea.add_text("\n\n")


func _display_child_message(text: String) -> void:
	DialogueArea.push_color(CHILD_NAME_COLOR)
	DialogueArea.push_bold()
	DialogueArea.add_text("我：")
	DialogueArea.pop()
	DialogueArea.pop()
	DialogueArea.add_text(" " + text + "\n\n")


func _display_ai_message(text: String) -> void:
	DialogueArea.push_color(_get_ai_display_color())
	DialogueArea.push_bold()
	DialogueArea.add_text(_get_ai_display_name() + "：")
	DialogueArea.pop()
	DialogueArea.pop()
	DialogueArea.add_text(" " + text + "\n\n")


# ============================================================
#  AI 类型辅助
# ============================================================

func _is_tool_ai() -> bool:
	return AssessmentGameManager.get_ai_type_name() == "工具型"


func _get_ai_opening_line() -> String:
	return TOOL_OPENING_LINE if _is_tool_ai() else FRIEND_OPENING_LINE


func _get_ai_display_name() -> String:
	return TOOL_AI_NAME if _is_tool_ai() else FRIEND_AI_NAME


func _get_ai_display_color() -> Color:
	return TOOL_AI_COLOR if _is_tool_ai() else FRIEND_AI_COLOR


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
	if enabled:
		InputField.grab_focus()
