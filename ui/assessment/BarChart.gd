class_name BarChart
extends Control
## 柱状图组件：绘制水平柱状图，用于展示各维度礼貌标记词频次。

var _labels: Array[String] = []
var _values: Array[float] = []
var _max_value: float = 10.0
var _title: String = ""
var _has_data: bool = false

const BAR_HEIGHT: float = 28.0
const BAR_GAP: float = 8.0
const LABEL_WIDTH: float = 80.0
const VALUE_WIDTH: float = 60.0
const BAR_COLOR: Color = Color(0.2, 0.6, 0.9, 0.85)
const BAR_BG_COLOR: Color = Color(0.3, 0.3, 0.3, 0.3)
const LABEL_COLOR: Color = Color(0.85, 0.85, 0.85, 1.0)
const VALUE_COLOR: Color = Color(1.0, 0.85, 0.4, 1.0)
const TITLE_COLOR: Color = Color(1.0, 0.85, 0.4, 1.0)
const FONT_SIZE: int = 14
const TITLE_FONT_SIZE: int = 18


func set_data(labels: Array[String], values: Array[float], max_value: float = 10.0, title: String = "") -> void:
	_labels = labels.duplicate()
	_values = values.duplicate()
	_max_value = max_value
	_title = title
	_has_data = _values.size() > 0
	queue_redraw()


func _draw() -> void:
	var font: Font = get_theme_default_font()
	if not font:
		return

	# 绘制标题
	var title_y: float = 8.0
	if not _title.is_empty():
		draw_string(font, Vector2(10, title_y + TITLE_FONT_SIZE), _title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT_SIZE, TITLE_COLOR)
		title_y += TITLE_FONT_SIZE + 8.0

	if not _has_data or _values.is_empty():
		draw_string(font, Vector2(10, title_y + FONT_SIZE), "暂无数据",
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, LABEL_COLOR)
		return

	var bar_start_x: float = LABEL_WIDTH + 10.0
	var bar_max_width: float = size.x - bar_start_x - VALUE_WIDTH - 10.0

	for i in range(_values.size()):
		var y: float = title_y + i * (BAR_HEIGHT + BAR_GAP)

		# 标签
		var label_text: String = _labels[i] if i < _labels.size() else ""
		draw_string(font, Vector2(10, y + BAR_HEIGHT * 0.7), label_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, LABEL_COLOR)

		# 背景条
		var bg_rect := Rect2(bar_start_x, y, bar_max_width, BAR_HEIGHT)
		draw_rect(bg_rect, BAR_BG_COLOR, true)

		# 数据条
		var v: float = clampf(_values[i], 0.0, _max_value)
		var bar_w: float = bar_max_width * (v / _max_value) if _max_value > 0.0 else 0.0
		if bar_w > 0.0:
			var bar_rect := Rect2(bar_start_x, y, bar_w, BAR_HEIGHT)
			draw_rect(bar_rect, BAR_COLOR, true)

		# 数值
		var val_text: String = "%.2f" % v
		draw_string(font, Vector2(bar_start_x + bar_max_width + 8.0, y + BAR_HEIGHT * 0.7), val_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, VALUE_COLOR)
