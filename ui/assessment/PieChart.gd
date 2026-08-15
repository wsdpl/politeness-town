class_name PieChart
extends Control
## 饼图组件：绘制饼图，用于展示五级礼貌策略等级分布。

var _labels: Array[String] = []
var _values: Array[float] = []
var _title: String = ""
var _has_data: bool = false

const LEVEL_COLORS: Array[Color] = [
	Color(0.8, 0.3, 0.3, 0.85),  # 等级1 - 红
	Color(0.9, 0.5, 0.2, 0.85),  # 等级2 - 橙
	Color(0.9, 0.8, 0.2, 0.85),  # 等级3 - 黄
	Color(0.3, 0.7, 0.4, 0.85),  # 等级4 - 绿
	Color(0.2, 0.5, 0.9, 0.85),  # 等级5 - 蓝
]
const LABEL_COLOR: Color = Color(0.85, 0.85, 0.85, 1.0)
const TITLE_COLOR: Color = Color(1.0, 0.85, 0.4, 1.0)
const FONT_SIZE: int = 13
const TITLE_FONT_SIZE: int = 18


func set_data(labels: Array[String], values: Array[float], title: String = "") -> void:
	_labels = labels.duplicate()
	_values = values.duplicate()
	_title = title
	_has_data = _values.size() > 0
	queue_redraw()


func _draw() -> void:
	var font: Font = get_theme_default_font()
	if not font:
		return

	var title_y: float = 8.0
	if not _title.is_empty():
		draw_string(font, Vector2(10, title_y + TITLE_FONT_SIZE), _title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT_SIZE, TITLE_COLOR)
		title_y += TITLE_FONT_SIZE + 8.0

	if not _has_data or _values.is_empty():
		draw_string(font, Vector2(10, title_y + FONT_SIZE), "暂无数据",
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, LABEL_COLOR)
		return

	var total: float = 0.0
	for v in _values:
		total += v

	if total <= 0.0:
		draw_string(font, Vector2(10, title_y + FONT_SIZE), "暂无数据",
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, LABEL_COLOR)
		return

	# 饼图圆心和半径
	var pie_cx: float = size.x * 0.3
	var pie_cy: float = title_y + (size.y - title_y) * 0.5
	var pie_r: float = min(size.x * 0.25, (size.y - title_y) * 0.4)

	var start_angle: float = -PI * 0.5  # 从顶部开始

	for i in range(_values.size()):
		var fraction: float = _values[i] / total
		var sweep: float = fraction * TAU
		var end_angle: float = start_angle + sweep

		var color: Color = LEVEL_COLORS[i % LEVEL_COLORS.size()]
		_draw_pie_slice(pie_cx, pie_cy, pie_r, start_angle, end_angle, color)

		# 百分比标签（在扇区中点外侧）
		if fraction > 0.05:
			var mid_angle: float = (start_angle + end_angle) * 0.5
			var label_r: float = pie_r * 0.65
			var lx: float = pie_cx + cos(mid_angle) * label_r
			var ly: float = pie_cy + sin(mid_angle) * label_r
			var pct_text: String = "%d%%" % int(fraction * 100)
			draw_string(font, Vector2(lx - 12, ly + 5), pct_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(1, 1, 1, 0.95))

		start_angle = end_angle

	# 图例
	var legend_x: float = pie_cx + pie_r + 30.0
	var legend_y: float = title_y + 10.0
	for i in range(_values.size()):
		var ly: float = legend_y + i * 24.0
		var color: Color = LEVEL_COLORS[i % LEVEL_COLORS.size()]
		draw_rect(Rect2(legend_x, ly, 16, 16), color, true)
		var label_text: String = _labels[i] if i < _labels.size() else "等级%d" % (i + 1)
		label_text += " (%d)" % int(_values[i])
		draw_string(font, Vector2(legend_x + 22, ly + 13), label_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, LABEL_COLOR)


func _draw_pie_slice(cx: float, cy: float, r: float, start: float, end: float, color: Color) -> void:
	var steps: int = max(2, int(abs(end - start) / 0.1))
	var pts: PackedVector2Array = [Vector2(cx, cy)]
	for i in range(steps + 1):
		var a: float = start + (end - start) * float(i) / float(steps)
		pts.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
	var cols: PackedColorArray = []
	cols.resize(pts.size())
	cols.fill(color)
	draw_polygon(pts, cols)
