extends Control
## 提示板组件：显示当前关卡的任务提示、测量维度与提示内容。

@onready var title_label: Label = $Panel/TitleLabel
@onready var dimension_label: Label = $Panel/DimensionLabel
@onready var content_label: RichTextLabel = $Panel/ContentLabel


func _ready() -> void:
	theme = AssessmentUiTheme.theme
	AssessmentUiTheme.normalize_font_sizes(self)
	clear()


## 设置任务标题与提示内容。
func set_tip(title: String, content: String) -> void:
	title_label.text = title
	content_label.text = content


## 设置当前测量维度名称（如"问候"、"致谢"等）。
func set_dimension(dimension: String) -> void:
	dimension_label.text = "当前维度: " + dimension


## 清空所有提示信息并恢复默认占位文本。
func clear() -> void:
	title_label.text = "任务提示"
	dimension_label.text = "当前维度: "
	content_label.text = ""
