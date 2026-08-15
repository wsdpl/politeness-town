extends Control
## 星章板组件：显示6个关卡对应的星章槽位，支持已获得/未获得/当前高亮三种状态。

signal star_earned(star_index: int)

const STAR_COUNT: int = 6

@onready var _hbox: HBoxContainer = $Panel/HBoxContainer
@onready var _title_label: Label = $Panel/TitleLabel

var _star_slots: Array[TextureRect] = []
var _earned: Array[bool] = []
var _current_index: int = -1
var _blink_visible: bool = true
var _blink_timer: Timer = null


func _ready() -> void:
	theme = AssessmentUiTheme.theme
	AssessmentUiTheme.normalize_font_sizes(self)
	_star_slots.clear()
	for child in _hbox.get_children():
		var slot: TextureRect = child as TextureRect
		if slot:
			_star_slots.append(slot)
	_earned.resize(STAR_COUNT)
	_earned.fill(false)
	_blink_timer = Timer.new()
	_blink_timer.wait_time = 0.5
	_blink_timer.timeout.connect(_on_blink_tick)
	add_child(_blink_timer)
	_update_slots()


## 设置已获得的星章数量，新获得的星章会触发 star_earned 信号。
func set_star_count(count: int) -> void:
	count = clampi(count, 0, STAR_COUNT)
	for i in range(STAR_COUNT):
		var was_earned: bool = _earned[i]
		_earned[i] = i < count
		if _earned[i] and not was_earned:
			star_earned.emit(i)
	_update_slots()


## 高亮当前关卡对应的星章槽位（闪烁）。传入 -1 取消高亮。
func highlight_current(index: int) -> void:
	_current_index = clampi(index, -1, STAR_COUNT - 1)
	if _current_index >= 0:
		if _blink_timer.is_stopped():
			_blink_timer.start()
	else:
		if not _blink_timer.is_stopped():
			_blink_timer.stop()
	_blink_visible = true
	_update_slots()


## 重置所有星章为未获得状态并取消高亮。
func reset() -> void:
	_earned.fill(false)
	_current_index = -1
	_blink_visible = true
	if _blink_timer and not _blink_timer.is_stopped():
		_blink_timer.stop()
	_update_slots()


func _update_slots() -> void:
	for i in range(_star_slots.size()):
		var slot: TextureRect = _star_slots[i]
		if i == _current_index:
			slot.modulate = Color(1.0, 0.85, 0.3) if _blink_visible else Color(0.9, 0.66, 0.29, 0.5)
		elif _earned[i]:
			slot.modulate = Color(0.9, 0.66, 0.29)
		else:
			slot.modulate = Color(0.4, 0.3, 0.2, 0.5)


func _on_blink_tick() -> void:
	_blink_visible = not _blink_visible
	_update_slots()
