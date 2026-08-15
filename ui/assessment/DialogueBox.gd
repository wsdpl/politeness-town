extends Control
## 对话框组件：显示AI角色对话文本，支持打字机效果与选项按钮。

signal dialogue_finished()
signal choice_made(choice_index: int)

@onready var panel: Panel = $Panel
@onready var speaker_label: Label = $Panel/SpeakerLabel
@onready var content_label: RichTextLabel = $Panel/ContentLabel
@onready var choices_container: VBoxContainer = $Panel/ChoicesContainer
@onready var skip_hint: Label = $Panel/SkipHint
@onready var portrait_rect: TextureRect = $Panel/PortraitRect

## 每个字符的显示间隔（秒）
const CHAR_DELAY: float = 0.03

var _full_text: String = ""
var _visible_chars: int = 0
var _is_typing: bool = false
var _typing_done: bool = false
var _typewriter_timer: Timer = null
var _pending_choices: Array = []
var _has_choices: bool = false


func _ready() -> void:
	theme = AssessmentUiTheme.theme
	_typewriter_timer = Timer.new()
	_typewriter_timer.wait_time = CHAR_DELAY
	_typewriter_timer.one_shot = false
	_typewriter_timer.timeout.connect(_on_typewriter_tick)
	add_child(_typewriter_timer)
	panel.gui_input.connect(_on_panel_gui_input)
	_reset_state()
	visible = false
	AssessmentUiTheme.normalize_font_sizes(self)
	_start_bounce_anim()


func _start_bounce_anim() -> void:
	var tw := create_tween().set_loops()
	tw.tween_property(skip_hint, "position:y", skip_hint.position.y - 6, 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(skip_hint, "position:y", skip_hint.position.y, 0.4).set_trans(Tween.TRANS_SINE)


## 设置头像贴图
func set_portrait(texture: Texture2D) -> void:
	if texture:
		portrait_rect.texture = texture
		portrait_rect.visible = true
		# 有头像时，文字区域从头像右侧开始
		content_label.offset_left = 210.0
		speaker_label.offset_left = 210.0
	else:
		portrait_rect.visible = false
		# 无头像时，文字区域从左侧开始
		content_label.offset_left = 40.0
		speaker_label.offset_left = 40.0


## 显示一段对话。choices 为可选的选项文本数组，提供时在打字结束后显示按钮。
func show_dialogue(speaker_name: String, text: String, choices: Array = []) -> void:
	visible = true
	speaker_label.text = speaker_name
	_full_text = text
	_pending_choices = choices
	_has_choices = choices.size() > 0
	_clear_choices()
	content_label.text = text
	content_label.visible_characters = 0
	_visible_chars = 0
	_is_typing = true
	_typing_done = false
	skip_hint.text = "▼ 点击跳过"
	skip_hint.visible = true
	_typewriter_timer.start()


## 清空对话框内容并隐藏。
func clear() -> void:
	_reset_state()
	visible = false


func _reset_state() -> void:
	_is_typing = false
	_typing_done = false
	if _typewriter_timer and not _typewriter_timer.is_stopped():
		_typewriter_timer.stop()
	_full_text = ""
	_visible_chars = 0
	_pending_choices = []
	_has_choices = false
	if speaker_label:
		speaker_label.text = ""
	if content_label:
		content_label.text = ""
		content_label.visible_characters = 0
	if skip_hint:
		skip_hint.visible = false
	if choices_container:
		_clear_choices()


func _clear_choices() -> void:
	if not choices_container:
		return
	for child in choices_container.get_children():
		child.queue_free()


func _on_typewriter_tick() -> void:
	if _visible_chars < _full_text.length():
		_visible_chars += 1
		content_label.visible_characters = _visible_chars
	else:
		_finish_typing()


func _finish_typing() -> void:
	if not _is_typing:
		return
	_typewriter_timer.stop()
	_is_typing = false
	_typing_done = true
	content_label.visible_characters = -1
	_visible_chars = _full_text.length()
	# 不自动关闭：显示"点击继续"提示，等待玩家手动点击
	skip_hint.text = "▼ 点击继续"
	skip_hint.visible = true
	_show_choices()


func _show_choices() -> void:
	if not _has_choices:
		return
	for i in range(_pending_choices.size()):
		var choice_text: String = str(_pending_choices[i])
		var button: Button = Button.new()
		button.text = choice_text
		button.custom_minimum_size = Vector2(0, 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_choice_pressed.bind(i))
		choices_container.add_child(button)


func _on_choice_pressed(index: int) -> void:
	choice_made.emit(index)
	_clear_choices()
	_has_choices = false


func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_typing:
			_finish_typing()
		elif _typing_done:
			_advance_dialogue()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE or event.keycode == KEY_E or event.keycode == KEY_ENTER:
			if _is_typing:
				_finish_typing()
				get_viewport().set_input_as_handled()
			elif _typing_done:
				_advance_dialogue()
				get_viewport().set_input_as_handled()


func _advance_dialogue() -> void:
	_typing_done = false
	skip_hint.visible = false
	dialogue_finished.emit()
