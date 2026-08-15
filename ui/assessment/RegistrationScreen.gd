extends Control
## 注册场景（项目主场景）
## 收集儿童基础信息与 AI 类型选择，完成必填校验后进入预热阶段。
## 调用 AssessmentGameManager 注册儿童 / 设置 AI 类型，
## 并通过 AssessmentFlowHost 切换到预热场景或 API 设置场景。

# ============================================================
#  UI 节点引用（路径与 .tscn 节点树一一对应）
# ============================================================

@onready var _nickname_edit: LineEdit = $CanvasLayer/FormContainer/VBox/NicknameRow/NicknameEdit
@onready var _age_spin_box: SpinBox = $CanvasLayer/FormContainer/VBox/AgeRow/AgeSpinBox
@onready var _gender_option: OptionButton = $CanvasLayer/FormContainer/VBox/GenderRow/GenderOption
@onready var _school_edit: LineEdit = $CanvasLayer/FormContainer/VBox/SchoolRow/SchoolEdit
@onready var _class_edit: LineEdit = $CanvasLayer/FormContainer/VBox/ClassRow/ClassEdit
@onready var _disorder_check_box: CheckBox = $CanvasLayer/FormContainer/VBox/DisorderRow/DisorderCheckBox
@onready var _device_option: OptionButton = $CanvasLayer/FormContainer/VBox/DeviceRow/DeviceOption
@onready var _ai_type_option: OptionButton = $CanvasLayer/FormContainer/VBox/AiTypeRow/AiTypeOption
@onready var _api_button: Button = $CanvasLayer/ButtonContainer/APIButton
@onready var _start_button: Button = $CanvasLayer/ButtonContainer/StartButton


# ============================================================
#  生命周期
# ============================================================

func _ready() -> void:
	# 应用统一主题
	theme = AssessmentUiTheme.theme

	# 给标题和副标题添加底框
	AssessmentUiTheme.wrap_in_panel($CanvasLayer/TitleLabel, AssessmentUiTheme.title_panel_style())
	AssessmentUiTheme.wrap_in_panel($CanvasLayer/SubtitleLabel, AssessmentUiTheme.title_panel_style())

	# 给表单区域添加主面板底框
	AssessmentUiTheme.wrap_in_panel($CanvasLayer/FormContainer, AssessmentUiTheme.board_panel_style())

	# 给按钮区域添加分区面板底框
	AssessmentUiTheme.wrap_in_panel($CanvasLayer/ButtonContainer, AssessmentUiTheme.section_panel_style())

	# 规范化所有字体大小（不低于28）并包裹剩余浮动标签
	AssessmentUiTheme.normalize_font_sizes($CanvasLayer)
	AssessmentUiTheme.wrap_all_floating_labels($CanvasLayer)

	_api_button.pressed.connect(_on_api_button_pressed)
	_start_button.pressed.connect(_on_start_button_pressed)

	# 应用按钮样式
	AssessmentUiTheme.apply_primary_button(_start_button)

	_populate_option_buttons()


## 初始化各下拉选项，保证单一数据源。
func _populate_option_buttons() -> void:
	# 性别：男 / 女
	_gender_option.clear()
	_gender_option.add_item("男")
	_gender_option.add_item("女")
	_gender_option.select(0)

	# 智能设备使用程度：低 / 正常 / 高（默认正常）
	_device_option.clear()
	_device_option.add_item("低")
	_device_option.add_item("正常")
	_device_option.add_item("高")
	_device_option.select(1)

	# AI 类型：朋友型 / 工具型（被试间设计，默认朋友型）
	_ai_type_option.clear()
	_ai_type_option.add_item("朋友型")
	_ai_type_option.add_item("工具型")
	_ai_type_option.select(0)


# ============================================================
#  按钮事件
# ============================================================

## 点击"开始测评"：校验 → 收集数据 → 注册儿童 → 设置 AI 类型 → 直接进入板块一。
func _on_start_button_pressed() -> void:
	if not _validate_form():
		return

	var info := _collect_form_data()
	AssessmentGameManager.register_child(info)
	AssessmentGameManager.set_ai_type(_selected_ai_type())
	AssessmentGameManager.start_politeness_house()

	await AssessmentFlowHost.go_to_politeness_house()


## 点击“API设置”：跳转到 API 提供商设置场景。
func _on_api_button_pressed() -> void:
	await AssessmentFlowHost.go_to_provider_setup()


# ============================================================
#  表单校验与数据收集
# ============================================================

## 必填校验：昵称、年龄（SpinBox 限定 4-6 岁）。
func _validate_form() -> bool:
	var nickname := _nickname_edit.text.strip_edges()
	if nickname.is_empty():
		push_warning("[RegistrationScreen] 昵称为必填项，请填写昵称。")
		_nickname_edit.grab_focus()
		return false

	var age := int(_age_spin_box.value)
	if age < 4 or age > 6:
		push_warning("[RegistrationScreen] 年龄必须在 4-6 岁之间。")
		return false
	return true


## 收集表单数据，字段名与 AssessmentGameManager.register_child 约定一致。
func _collect_form_data() -> Dictionary:
	return {
		"nickname": _nickname_edit.text.strip_edges(),
		"age": int(_age_spin_box.value),
		"gender": _selected_gender(),
		"school": _school_edit.text.strip_edges(),
		"class_name": _class_edit.text.strip_edges(),
		"has_language_disorder": _disorder_check_box.button_pressed,
		"device_usage_level": _selected_device_level(),
	}


func _selected_gender() -> String:
	match _gender_option.selected:
		1:
			return "female"
		_:
			return "male"


func _selected_device_level() -> String:
	match _device_option.selected:
		0:
			return "low"
		2:
			return "high"
		_:
			return "normal"


## 返回 AssessmentGameManager.AiType 枚举值（int）。
func _selected_ai_type() -> int:
	match _ai_type_option.selected:
		1:
			return AssessmentGameManager.AiType.TOOL
		_:
			return AssessmentGameManager.AiType.FRIEND
