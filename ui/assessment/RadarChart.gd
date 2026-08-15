class_name RadarChart
extends Control
## 雷达图组件：在 _draw() 中绘制六维雷达图，支持0-5的数值范围（对应五级策略等级）。

@onready var title_label: Label = $TitleLabel

var _labels: Array[String] = []
var _values: Array[float] = []
var _max_value: float = 5.0
var _title: String = ""
var _has_data: bool = false

const GRID_LAYERS: int = 5
const NUM_AXES: int = 6
const GRID_COLOR: Color = Color(0.5, 0.5, 0.5, 0.5)
const AXIS_COLOR: Color = Color(0.5, 0.5, 0.5, 0.7)
const FILL_COLOR: Color = Color(0.2, 0.4, 0.9, 0.35)
const EDGE_COLOR: Color = Color(0.2, 0.4, 0.9, 0.9)
const POINT_COLOR: Color = Color(0.1, 0.2, 0.6, 1.0)
const LABEL_COLOR: Color = Color(0.85, 0.85, 0.85, 1.0)
const LABEL_FONT_SIZE: int = 14


func _ready() -> void:
	title_label.text = _title


## 设置雷达图数据。labels 为维度名称数组，values 为对应数值数组，max_value 为最大刻度。
func set_data(labels: Array[String], values: Array[float], max_value: float = 5.0, title: String = "") -> void:
	_labels = labels.duplicate()
	_values = values.duplicate()
	_max_value = max_value
	_title = title
	_has_data = _values.size() > 0
	if title_label:
		title_label.text = title
	queue_redraw()


## 清空雷达图数据。
func clear() -> void:
	_labels = []
	_values = []
	_max_value = 5.0
	_title = ""
	_has_data = false
	if title_label:
		title_label.text = ""
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = min(size.x, size.y) * 0.36

	# 绘制六边形网格（5层）
	for layer in range(1, GRID_LAYERS + 1):
		var r: float = radius * (float(layer) / float(GRID_LAYERS))
		var pts: PackedVector2Array = _polygon_points(r, center)
		for i in range(pts.size()):
			draw_line(pts[i], pts[(i + 1) % pts.size()], GRID_COLOR, 1.0)

	# 绘制坐标轴
	var outer: PackedVector2Array = _polygon_points(radius, center)
	for i in range(outer.size()):
		draw_line(center, outer[i], AXIS_COLOR, 1.0)

	# 绘制数据多边形
	if _has_data and _values.size() > 0:
		var data_pts: PackedVector2Array = []
		var n: int = min(_values.size(), NUM_AXES)
		for i in range(n):
			var angle: float = _axis_angle(i)
			var v: float = clampf(_values[i], 0.0, _max_value)
			var r: float = radius * (v / _max_value) if _max_value > 0.0 else 0.0
			data_pts.append(center + Vector2(cos(angle), sin(angle)) * r)

		# 半透明填充
		if data_pts.size() >= 3:
			var cols: PackedColorArray = []
			cols.resize(data_pts.size())
			cols.fill(FILL_COLOR)
			draw_polygon(data_pts, cols)

		# 边线
		for i in range(data_pts.size()):
			draw_line(data_pts[i], data_pts[(i + 1) % data_pts.size()], EDGE_COLOR, 2.0)

		# 数据点
		for i in range(data_pts.size()):
			draw_circle(data_pts[i], 4.0, POINT_COLOR)

	# 绘制轴标签
	var font: Font = get_theme_default_font()
	if font:
		for i in range(min(_labels.size(), NUM_AXES)):
			var angle: float = _axis_angle(i)
			var lpos: Vector2 = center + Vector2(cos(angle), sin(angle)) * (radius + 26.0)
			var text: String = _labels[i]
			var ts: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
			var draw_pos: Vector2 = Vector2(lpos.x - ts.x * 0.5, lpos.y + ts.y * 0.5)
			draw_string(font, draw_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, LABEL_COLOR)


func _axis_angle(index: int) -> float:
	# 从顶部（-PI/2）开始顺时针排列
	return -PI * 0.5 + (float(index) / float(NUM_AXES)) * TAU


func _polygon_points(radius: float, center: Vector2) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	for i in range(NUM_AXES):
		var angle: float = _axis_angle(i)
		pts.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return pts
