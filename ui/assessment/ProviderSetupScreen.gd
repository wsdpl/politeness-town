extends Control
## API 提供商设置场景
## 配置 endpoint / api_key / model，支持连接测试与保存。
## 连接测试通过临时实例化 AssessmentAIManager 发送一次最简对话请求，
## 依据信号回填测试结果。

const DEFAULT_ENDPOINT := "https://api.deepseek.com/chat/completions"
const DEFAULT_MODEL := "deepseek-chat"

const TEST_SYSTEM_PROMPT := "你是一个连接测试助手。"
const TEST_USER_PROMPT := "请回复：连接成功"

# 测试连接使用的临时 AI 管理器实例（class_name AssessmentAIManager）
var _test_ai_manager: AssessmentAIManager = null
var _is_testing: bool = false

# 讯飞语音识别 API 配置控件
var _iflytek_app_id_edit: LineEdit
var _iflytek_api_key_edit: LineEdit
var _iflytek_api_secret_edit: LineEdit
var _iflytek_save_button: Button

# 豆包 TTS 配置控件
var _doubao_provider_option: OptionButton
var _doubao_endpoint_edit: LineEdit
var _doubao_app_id_edit: LineEdit
var _doubao_token_edit: LineEdit
var _doubao_voice_edit: LineEdit

@onready var _form_container: VBoxContainer = $CanvasLayer/FormCenter/FormContainer
@onready var _endpoint_edit: LineEdit = $CanvasLayer/FormCenter/FormContainer/EndpointRow/EndpointEdit
@onready var _api_key_edit: LineEdit = $CanvasLayer/FormCenter/FormContainer/ApiKeyRow/ApiKeyEdit
@onready var _model_edit: LineEdit = $CanvasLayer/FormCenter/FormContainer/ModelRow/ModelEdit
@onready var _test_result_label: Label = $CanvasLayer/TestResultLabel
@onready var _back_button: Button = $CanvasLayer/ButtonContainer/BackButton
@onready var _test_button: Button = $CanvasLayer/ButtonContainer/TestButton
@onready var _save_button: Button = $CanvasLayer/ButtonContainer/SaveButton


# ============================================================
#  生命周期
# ============================================================

func _ready() -> void:
	# 应用统一主题
	theme = AssessmentUiTheme.theme

	# 给标题添加底框
	AssessmentUiTheme.wrap_in_panel($CanvasLayer/TitleLabel, AssessmentUiTheme.title_panel_style())

	# 给表单区域添加主面板底框
	AssessmentUiTheme.wrap_in_panel($CanvasLayer/FormCenter, AssessmentUiTheme.board_panel_style())

	# 给按钮区域添加分区面板底框
	AssessmentUiTheme.wrap_in_panel($CanvasLayer/ButtonContainer, AssessmentUiTheme.section_panel_style())

	# 规范化所有字体大小（不低于28）并包裹剩余浮动标签
	AssessmentUiTheme.normalize_font_sizes($CanvasLayer)
	AssessmentUiTheme.wrap_all_floating_labels($CanvasLayer)

	_back_button.pressed.connect(_on_back_button_pressed)
	_test_button.pressed.connect(_on_test_button_pressed)
	_save_button.pressed.connect(_on_save_button_pressed)

	# 应用按钮样式
	AssessmentUiTheme.apply_primary_button(_save_button)

	_load_existing_config()
	_setup_iflytek_config()
	_setup_doubao_config()


# ============================================================
#  讯飞 API 配置
# ============================================================

func _setup_iflytek_config() -> void:
	var form: VBoxContainer = _form_container

	# 分隔标题
	var sep := Label.new()
	sep.text = "─── 科大讯飞语音识别 API ───"
	sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sep.add_theme_font_size_override("font_size", 28)
	sep.add_theme_color_override("font_color", Color(0.2, 0.5, 0.8))
	form.add_child(sep)

	# APP_ID
	_iflytek_app_id_edit = _create_iflytek_row(form, "APP ID:", "讯飞开放平台 APP_ID")
	# API_KEY
	_iflytek_api_key_edit = _create_iflytek_row(form, "API Key:", "讯飞开放平台 APIKey")
	# API_SECRET
	_iflytek_api_secret_edit = _create_iflytek_row(form, "API Secret:", "讯飞开放平台 APISecret")

	# 保存按钮
	_iflytek_save_button = Button.new()
	_iflytek_save_button.text = "保存讯飞配置"
	_iflytek_save_button.custom_minimum_size = Vector2(200, 50)
	_iflytek_save_button.add_theme_font_size_override("font_size", 28)
	form.add_child(_iflytek_save_button)
	_iflytek_save_button.pressed.connect(_on_iflytek_save_pressed)
	AssessmentUiTheme.apply_primary_button(_iflytek_save_button)

	# 回填已保存的配置
	_iflytek_app_id_edit.text = IFlytekSR.app_id
	_iflytek_api_key_edit.text = IFlytekSR.api_key
	_iflytek_api_secret_edit.text = IFlytekSR.api_secret


func _create_iflytek_row(parent: Node, label_text: String, placeholder: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(120, 40)
	lbl.add_theme_font_size_override("font_size", 28)
	row.add_child(lbl)
	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(400, 40)
	edit.placeholder_text = placeholder
	edit.add_theme_font_size_override("font_size", 28)
	row.add_child(edit)
	parent.add_child(row)
	return edit


func _on_iflytek_save_pressed() -> void:
	var app_id := _iflytek_app_id_edit.text.strip_edges()
	var api_key := _iflytek_api_key_edit.text.strip_edges()
	var api_secret := _iflytek_api_secret_edit.text.strip_edges()
	if app_id.is_empty() or api_key.is_empty() or api_secret.is_empty():
		_update_test_result("讯飞配置保存失败：APP ID、API Key、API Secret 均不能为空。", Color(0.8, 0.2, 0.2, 1))
		return
	IFlytekSR.save_config(app_id, api_key, api_secret)
	_update_test_result("讯飞API配置已保存，语音识别功能可用。", Color(0.2, 0.6, 0.2, 1))


func _setup_doubao_config() -> void:
	var form: VBoxContainer = _form_container
	var sep := Label.new()
	sep.text = "─── 豆包 TTS 语音播报 ───"
	sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sep.add_theme_font_size_override("font_size", 28)
	sep.add_theme_color_override("font_color", Color(0.75, 0.3, 0.15))
	form.add_child(sep)

	var service: Node = get_node_or_null("/root/TTSService")
	var config: Dictionary = service.get_config() if service else {}
	_doubao_provider_option = OptionButton.new()
	_doubao_provider_option.add_item("本机 TTS（不使用豆包）", 0)
	_doubao_provider_option.add_item("豆包 TTS", 1)
	_doubao_provider_option.select(1 if String(config.get("provider", "system")) == "doubao" else 0)
	form.add_child(_create_doubao_option_row("播报提供商：", _doubao_provider_option))
	_doubao_endpoint_edit = _create_doubao_row(form, "接口地址：", "https://openspeech.bytedance.com/api/v1/tts")
	_doubao_app_id_edit = _create_doubao_row(form, "APP ID：", "火山引擎语音 APP ID")
	_doubao_token_edit = _create_doubao_row(form, "Access Token：", "火山引擎 Access Token")
	_doubao_token_edit.secret = true
	_doubao_token_edit.secret_character = "•"
	_doubao_voice_edit = _create_doubao_row(form, "默认音色：", "如 BV700_V2_streaming")
	_doubao_endpoint_edit.text = String(config.get("endpoint", DoubaoTTS.DEFAULT_ENDPOINT))
	_doubao_app_id_edit.text = String(config.get("app_id", ""))
	_doubao_token_edit.text = String(config.get("access_token", ""))
	_doubao_voice_edit.text = String(config.get("voice_type", DoubaoTTS.DEFAULT_VOICE))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var save := Button.new()
	save.text = "保存豆包配置"
	save.custom_minimum_size = Vector2(220, 50)
	save.add_theme_font_size_override("font_size", 28)
	save.pressed.connect(_on_doubao_save_pressed)
	buttons.add_child(save)
	var test := Button.new()
	test.text = "试听豆包语音"
	test.custom_minimum_size = Vector2(220, 50)
	test.add_theme_font_size_override("font_size", 28)
	test.pressed.connect(_on_doubao_test_pressed)
	buttons.add_child(test)
	form.add_child(buttons)
	AssessmentUiTheme.apply_primary_button(save)
	AssessmentUiTheme.apply_primary_button(test)


func _create_doubao_option_row(label_text: String, option: OptionButton) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(180, 40)
	label.add_theme_font_size_override("font_size", 28)
	row.add_child(label)
	option.custom_minimum_size = Vector2(400, 40)
	option.add_theme_font_size_override("font_size", 28)
	row.add_child(option)
	return row


func _create_doubao_row(parent: Node, label_text: String, placeholder: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(180, 40)
	label.add_theme_font_size_override("font_size", 28)
	row.add_child(label)
	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(480, 40)
	edit.placeholder_text = placeholder
	edit.add_theme_font_size_override("font_size", 28)
	row.add_child(edit)
	parent.add_child(row)
	return edit


func _collect_doubao_config() -> Dictionary:
	var service: Node = get_node_or_null("/root/TTSService")
	var config: Dictionary = service.get_config() if service else {}
	config["provider"] = "doubao" if _doubao_provider_option.selected == 1 else "system"
	config["endpoint"] = _doubao_endpoint_edit.text.strip_edges()
	config["app_id"] = _doubao_app_id_edit.text.strip_edges()
	config["access_token"] = _doubao_token_edit.text.strip_edges()
	config["voice_type"] = _doubao_voice_edit.text.strip_edges()
	config["voice_narrator"] = config["voice_type"]
	config["voice_child"] = config["voice_type"]
	config["voice_female"] = config["voice_type"]
	config["voice_male"] = config["voice_type"]
	return config


func _on_doubao_save_pressed() -> void:
	var service: Node = get_node_or_null("/root/TTSService")
	if service == null:
		_update_test_result("豆包服务未初始化。", Color(0.8, 0.2, 0.2, 1))
		return
	var config := _collect_doubao_config()
	if String(config.get("provider", "")) == "doubao" and (String(config.get("app_id", "")).is_empty() or String(config.get("access_token", "")).is_empty()):
		_update_test_result("请填写豆包 APP ID 和 Access Token，或选择本机 TTS。", Color(0.8, 0.2, 0.2, 1))
		return
	service.set_config(config)
	_update_test_result("豆包语音配置已保存。", Color(0.2, 0.6, 0.2, 1))


func _on_doubao_test_pressed() -> void:
	var service: Node = get_node_or_null("/root/TTSService")
	if service == null:
		_update_test_result("豆包服务未初始化。", Color(0.8, 0.2, 0.2, 1))
		return
	var config := _collect_doubao_config()
	service.set_config(config)
	if not service.is_configured():
		_update_test_result("请先选择豆包并填写 APP ID、Access Token。", Color(0.8, 0.2, 0.2, 1))
		return
	_update_test_result("正在请求豆包语音……", Color(0.3, 0.4, 0.7, 1))
	TTSHelper.speak("你好，这里是礼貌小镇的豆包语音测试。", TTSHelper.VoiceProfile.NARRATOR)


## 进入时从 AssessmentGameManager 加载已保存的 API 配置并回填表单。
func _load_existing_config() -> void:
	var config := AssessmentGameManager.get_api_config()
	_endpoint_edit.text = String(config.get("endpoint", DEFAULT_ENDPOINT))
	_api_key_edit.text = String(config.get("api_key", ""))
	_model_edit.text = String(config.get("model", DEFAULT_MODEL))
	if _endpoint_edit.text.is_empty():
		_endpoint_edit.text = DEFAULT_ENDPOINT
	if _model_edit.text.is_empty():
		_model_edit.text = DEFAULT_MODEL
	_update_test_result("尚未测试连接。", Color(0.4, 0.4, 0.4, 1))


# ============================================================
#  按钮事件
# ============================================================

## 返回注册页。
func _on_back_button_pressed() -> void:
	await AssessmentFlowHost.go_to_registration()


## 保存配置到 AssessmentGameManager（持久化到 user://api_config.json）。
func _on_save_button_pressed() -> void:
	var config := _collect_config()
	if config["endpoint"].is_empty() or config["model"].is_empty():
		_update_test_result("保存失败：API Endpoint 与 Model 不能为空。", Color(0.8, 0.2, 0.2, 1))
		return
	AssessmentGameManager.set_api_config(config)
	_update_test_result("配置已保存。", Color(0.2, 0.6, 0.2, 1))


## 测试连接：实例化 AssessmentAIManager 发送一次最简对话请求。
func _on_test_button_pressed() -> void:
	if _is_testing:
		return
	var config := _collect_config()
	if config["endpoint"].is_empty():
		_update_test_result("请先填写 API Endpoint。", Color(0.8, 0.2, 0.2, 1))
		return
	if config["api_key"].is_empty():
		_update_test_result("请先填写 API Key。", Color(0.8, 0.2, 0.2, 1))
		return
	if config["model"].is_empty():
		_update_test_result("请先填写 Model。", Color(0.8, 0.2, 0.2, 1))
		return
	_start_connection_test(config)


# ============================================================
#  连接测试
# ============================================================

func _start_connection_test(config: Dictionary) -> void:
	_is_testing = true
	_test_button.disabled = true
	_update_test_result("正在测试连接，请稍候……", Color(0.3, 0.4, 0.7, 1))

	# 清理上一次测试实例
	if _test_ai_manager != null and is_instance_valid(_test_ai_manager):
		_test_ai_manager.queue_free()
	_test_ai_manager = AssessmentAIManager.new()
	add_child(_test_ai_manager)
	# 用表单配置覆盖（覆盖后不再从 AssessmentGameManager 刷新）
	_test_ai_manager.set_api_config(config)

	_test_ai_manager.ai_response_received.connect(_on_test_response_received, CONNECT_ONE_SHOT)
	_test_ai_manager.ai_response_error.connect(_on_test_response_error, CONNECT_ONE_SHOT)

	var messages: Array = [{"role": "user", "content": TEST_USER_PROMPT}]
	_test_ai_manager.send_dialogue(TEST_SYSTEM_PROMPT, messages, 0.2)


func _on_test_response_received(text: String) -> void:
	_finish_test("连接成功！模型回复：%s" % text, Color(0.2, 0.6, 0.2, 1))


func _on_test_response_error(error: String) -> void:
	_finish_test("连接失败：%s" % error, Color(0.8, 0.2, 0.2, 1))


func _finish_test(message: String, color: Color) -> void:
	_is_testing = false
	_test_button.disabled = false
	_update_test_result(message, color)
	# 测试结束释放临时实例
	if _test_ai_manager != null and is_instance_valid(_test_ai_manager):
		_test_ai_manager.queue_free()
		_test_ai_manager = null


# ============================================================
#  辅助
# ============================================================

func _collect_config() -> Dictionary:
	return {
		"endpoint": _endpoint_edit.text.strip_edges(),
		"api_key": _api_key_edit.text.strip_edges(),
		"model": _model_edit.text.strip_edges(),
	}


func _update_test_result(message: String, color: Color) -> void:
	_test_result_label.text = message
	_test_result_label.add_theme_color_override("font_color", color)


func _exit_tree() -> void:
	if _test_ai_manager != null and is_instance_valid(_test_ai_manager):
		_test_ai_manager.queue_free()
		_test_ai_manager = null
