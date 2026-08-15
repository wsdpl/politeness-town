extends Node
## 统一 UI 主题控制器 (Autoload)
## 严格基于 AI Town 项目 BulletinBoardTheme.gd 的中式古镇风格
## 所有颜色值、StyleBoxFlat 属性与 AI Town 源码完全一致

# ===== 颜色常量（严格复制自 BulletinBoardTheme.gd，逐字节一致）=====
const INK := Color("3b271b")            # 墨色 - 主文字
const INK_MUTED := Color("68432c")      # 淡墨 - 次要文字
const PAPER := Color("f4d29a")          # 宣纸 - 面板背景
const PAPER_LIGHT := Color("fff0cc")    # 浅宣纸 - 输入框/浅色面板
const PAPER_SOFT := Color("f7dfae")     # 柔宣纸 - 卡片背景
const PAPER_DISABLED := Color("cbbd9f") # 禁用态背景
const WOOD := Color("6c3d20")           # 木质 - 边框
const WOOD_DARK := Color("321d12")      # 深木 - 深色边框
const WOOD_LIGHT := Color("a96a35")     # 浅木 - 强调边框
const TERRACOTTA := Color("b94d2d")     # 赤陶 - 主要按钮
const TERRACOTTA_DARK := Color("742b1b")# 赤陶深 - 按钮边框
const MOSS := Color("557b2a")           # 苔藓绿 - 成功
const MOSS_DARK := Color("36511e")      # 苔藓深 - 成功边框
const HONEY := Color("e5a84b")          # 蜂蜜金 - 悬停/聚焦
const ERROR_COL := Color("a7352b")      # 错误
const ERROR_DARK := Color("69251f")     # 错误深
const BUTTON_INK := Color("fff2d2")     # 亮色文字（深色按钮上）
const DISABLED_INK := Color("5b4b39")   # 禁用态文字（严格复制自 BulletinBoardTheme）
const SHADOW := Color("1e120b78")       # 阴影色
const OVERLAY := Color("17110c8c")      # 背景遮罩色（严格复制自 ProviderSettingsTheme.OVERLAY）

# 背景图路径（从 AI Town 复制的城镇背景）
const BACKGROUND_PATH := "res://assets/ui/backgrounds/startup_town_background.png"

# 字体路径（严格复制自 BulletinBoardTheme.FONT_PATH 的对应路径）
const FONT_PATH := "res://assets/fonts/noto_sans_cjk_sc_medium/NotoSansCJKsc-Medium.otf"

# 单例主题
var theme: Theme
# 背景纹理缓存
var _bg_texture: Texture2D


func _ready() -> void:
	theme = _build_theme()
	_bg_texture = load(BACKGROUND_PATH) as Texture2D
	print("[AssessmentUiTheme] 主题构建完成，字体大小=32，颜色严格匹配 BulletinBoardTheme")


## 构建完整主题资源（严格按照 BulletinBoardTheme.create() 实现）
func _build_theme() -> Theme:
	var t := Theme.new()

	# --- 字体（与 AI Town 完全一致）---
	var font_file := load(FONT_PATH) as FontFile
	if font_file:
		var font := FontVariation.new()
		font.base_font = font_file
		font.spacing_glyph = 2
		font.spacing_space = 0
		font.variation_embolden = 0.0
		t.default_font = font
	# 严格匹配参考源码：default_font_size = 32
	t.default_font_size = 32

	# --- Label（严格复制自 BulletinBoardTheme.create()）---
	t.set_color("font_color", "Label", INK)
	t.set_color("font_outline_color", "Label", PAPER_LIGHT)
	t.set_color("font_shadow_color", "Label", Color.TRANSPARENT)
	t.set_constant("outline_size", "Label", 0)
	t.set_constant("line_spacing", "Label", 8)

	# --- Button（严格复制自 BulletinBoardTheme，font_size=32）---
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_focus_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", DISABLED_INK)
	t.set_font_size("font_size", "Button", 32)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		t.set_stylebox(state, "Button", _button_style("quiet", state))

	# --- LineEdit（与 BulletinBoardTheme.input_style 一致，font_size=32）---
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", INK_MUTED)
	t.set_color("caret_color", "LineEdit", TERRACOTTA_DARK)
	t.set_color("selection_color", "LineEdit", Color(MOSS, 0.45))
	t.set_font_size("font_size", "LineEdit", 32)
	t.set_stylebox("normal", "LineEdit", _input_style("normal"))
	t.set_stylebox("focus", "LineEdit", _input_style("focus"))
	t.set_stylebox("read_only", "LineEdit", _input_style("disabled"))

	# --- TextEdit（严格复制自 BulletinBoardTheme，font_size=32）---
	t.set_color("font_color", "TextEdit", INK)
	t.set_color("font_placeholder_color", "TextEdit", INK_MUTED)
	t.set_color("font_readonly_color", "TextEdit", INK_MUTED)
	t.set_color("caret_color", "TextEdit", INK)
	t.set_color("selection_color", "TextEdit", Color(HONEY, 0.42))
	t.set_constant("line_spacing", "TextEdit", 8)
	t.set_font_size("font_size", "TextEdit", 32)
	t.set_stylebox("normal", "TextEdit", _input_style("normal"))
	t.set_stylebox("focus", "TextEdit", _input_style("focus"))
	t.set_stylebox("read_only", "TextEdit", _input_style("disabled"))

	# --- Panel / PanelContainer ---
	t.set_stylebox("panel", "Panel", board_panel_style())
	t.set_stylebox("panel", "PanelContainer", section_panel_style())

	# --- ProgressBar ---
	t.set_stylebox("background", "ProgressBar", _progress_bg())
	t.set_stylebox("fill", "ProgressBar", _progress_fill())
	t.set_color("font_color", "ProgressBar", INK)
	t.set_font_size("font_size", "ProgressBar", 28)

	# --- SpinBox ---
	t.set_color("font_color", "SpinBox", INK)
	t.set_color("font_placeholder_color", "SpinBox", INK_MUTED)
	t.set_font_size("font_size", "SpinBox", 32)
	t.set_stylebox("up", "SpinBox", _input_style("normal"))
	t.set_stylebox("down", "SpinBox", _input_style("normal"))
	t.set_stylebox("up_hover", "SpinBox", _input_style("focus"))
	t.set_stylebox("down_hover", "SpinBox", _input_style("focus"))
	t.set_stylebox("up_pressed", "SpinBox", _input_style("normal"))
	t.set_stylebox("down_pressed", "SpinBox", _input_style("normal"))

	# --- OptionButton ---
	t.set_color("font_color", "OptionButton", INK)
	t.set_color("font_hover_color", "OptionButton", INK)
	t.set_color("font_pressed_color", "OptionButton", INK)
	t.set_color("font_focus_color", "OptionButton", INK)
	t.set_color("font_disabled_color", "OptionButton", DISABLED_INK)
	t.set_font_size("font_size", "OptionButton", 32)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		t.set_stylebox(state, "OptionButton", _input_style(state))
	t.set_stylebox("hover", "OptionButton", _input_style("focus"))
	t.set_stylebox("pressed", "OptionButton", _input_style("focus"))

	# --- CheckBox ---
	t.set_color("font_color", "CheckBox", INK)
	t.set_color("font_hover_color", "CheckBox", INK)
	t.set_color("font_pressed_color", "CheckBox", INK)
	t.set_color("font_focus_color", "CheckBox", INK)
	t.set_font_size("font_size", "CheckBox", 32)

	# --- ScrollContainer / ScrollBar ---
	t.set_stylebox("panel", "ScrollContainer", _empty_style())
	t.set_stylebox("scroll", "VScrollBar", _scroll_track())
	t.set_stylebox("grabber", "VScrollBar", _scroll_thumb())
	t.set_stylebox("grabber_highlight", "VScrollBar", _scroll_thumb_hover())
	t.set_stylebox("scroll", "HScrollBar", _scroll_track())
	t.set_stylebox("grabber", "HScrollBar", _scroll_thumb())
	t.set_stylebox("grabber_highlight", "HScrollBar", _scroll_thumb_hover())

	# --- RichTextLabel ---
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_constant("line_separation", "RichTextLabel", 8)

	# --- PopupMenu ---
	t.set_stylebox("panel", "PopupMenu", _popup_panel())
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", INK)
	t.set_color("font_selected_color", "PopupMenu", INK)
	t.set_font_size("font_size", "PopupMenu", 32)
	t.set_stylebox("hover", "PopupMenu", _popup_item_hover())
	t.set_stylebox("selected", "PopupMenu", _popup_item_hover())

	return t


# ============================================================
#  StyleBox 工厂方法（严格复制自 BulletinBoardTheme.gd）
# ============================================================

## 主面板 - 宣纸背景 + 木质粗边框 + 阴影
## 严格复制自 BulletinBoardTheme.board_panel()
func board_panel_style() -> StyleBoxFlat:
	var s := _flat(Color(PAPER, 0.985), WOOD_DARK, 10, 24)
	s.border_color = WOOD
	s.shadow_color = SHADOW
	s.shadow_size = 12
	s.shadow_offset = Vector2(8, 10)
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 2
	s.corner_radius_bottom_left = 2
	s.corner_radius_bottom_right = 4
	return s


## 分区面板 - 浅宣纸 + 浅木边框
## 严格复制自 BulletinBoardTheme.section_panel()
func section_panel_style() -> StyleBoxFlat:
	var s := _flat(PAPER_LIGHT, WOOD_LIGHT, 6, 20)
	s.shadow_color = Color(SHADOW, 0.42)
	s.shadow_size = 5
	s.shadow_offset = Vector2(4, 5)
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 2
	s.corner_radius_bottom_left = 2
	s.corner_radius_bottom_right = 4
	return s


## 卡片面板
## 严格复制自 BulletinBoardTheme.card_panel()
func card_panel_style() -> StyleBoxFlat:
	return _flat(PAPER_SOFT, WOOD_LIGHT, 4, 16)


## 标题底框 - 宣纸背景 + 木质边框 + 阴影（用于标题文字底框）
func title_panel_style() -> StyleBoxFlat:
	var s := _flat(Color(PAPER, 0.95), WOOD, 6, 16)
	s.shadow_color = Color(SHADOW, 0.35)
	s.shadow_size = 6
	s.shadow_offset = Vector2(4, 5)
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_left = 4
	s.corner_radius_bottom_right = 4
	return s


## 小标签底框 - 浅宣纸背景 + 浅木边框（用于行内标签底框）
## 增强可读性：提高不透明度、加粗边框、增加内边距
func label_panel_style() -> StyleBoxFlat:
	var s := _flat(Color(PAPER, 0.96), WOOD, 4, 12)
	s.shadow_color = Color(SHADOW, 0.3)
	s.shadow_size = 4
	s.shadow_offset = Vector2(2, 3)
	s.set_corner_radius_all(4)
	return s


## 对话框面板 - 深木色半透明
func dialogue_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(WOOD_DARK, 0.92)
	s.border_color = WOOD_LIGHT
	s.set_border_width_all(3)
	s.set_corner_radius_all(8)
	s.shadow_color = Color(SHADOW, 0.5)
	s.shadow_size = 8
	s.shadow_offset = Vector2(4, 6)
	s.content_margin_left = 24
	s.content_margin_top = 20
	s.content_margin_right = 24
	s.content_margin_bottom = 20
	return s


## 提示面板 - 深木色半透明 + 蜂蜜金边框
func tip_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(WOOD_DARK, 0.90)
	s.border_color = HONEY
	s.set_border_width_all(3)
	s.set_corner_radius_all(6)
	s.shadow_color = Color(SHADOW, 0.45)
	s.shadow_size = 6
	s.shadow_offset = Vector2(4, 5)
	s.content_margin_left = 20
	s.content_margin_top = 16
	s.content_margin_right = 20
	s.content_margin_bottom = 16
	return s


## 星章板面板
func star_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(WOOD_DARK, 0.90)
	s.border_color = HONEY
	s.set_border_width_all(3)
	s.set_corner_radius_all(6)
	s.shadow_color = Color(SHADOW, 0.45)
	s.shadow_size = 6
	s.shadow_offset = Vector2(4, 5)
	s.content_margin_left = 20
	s.content_margin_top = 16
	s.content_margin_right = 20
	s.content_margin_bottom = 16
	return s


## 按钮样式工厂（严格复制自 BulletinBoardTheme.button_style）
## variant: "primary" | "quiet" | "danger" | "success" | "wood"
## state: "normal" | "hover" | "pressed" | "focus" | "disabled"
func _button_style(variant: String, state: String) -> StyleBoxFlat:
	var background := PAPER_LIGHT
	var border := WOOD
	match variant:
		"primary":
			background = TERRACOTTA
			border = TERRACOTTA_DARK
		"wood":
			background = Color("5c351f")
			border = Color("c78a4d")
		"danger":
			background = Color("c45a3e")
			border = ERROR_DARK
		"success":
			background = MOSS
			border = MOSS_DARK
		_:
			background = PAPER_LIGHT
			border = WOOD
	match state:
		"hover":
			background = background.lightened(0.08)
			border = HONEY
		"pressed":
			background = background.darkened(0.10)
		"focus":
			border = HONEY
		"disabled":
			background = PAPER_DISABLED
			border = Color("756956")
	var border_width := 7 if state == "focus" else 4
	var s := _flat(background, border, border_width, 10)
	s.shadow_color = Color(SHADOW, 0.38)
	s.shadow_size = 4
	s.shadow_offset = Vector2(3, 4)
	if state == "pressed":
		s.content_margin_top += 3
		s.content_margin_bottom = maxf(4.0, s.content_margin_bottom - 3.0)
	return s


## 输入框样式（严格复制自 BulletinBoardTheme.input_style）
func _input_style(state: String) -> StyleBoxFlat:
	var background := Color(PAPER_LIGHT, 0.92)
	var border := WOOD_LIGHT
	if state == "focus":
		border = HONEY
	elif state == "disabled":
		background = Color(PAPER_DISABLED, 0.94)
		border = Color("756956")
	var bw := 7 if state == "focus" else 4
	var s := _flat(background, border, bw, 12)
	return s


## 进度条背景
func _progress_bg() -> StyleBoxFlat:
	var s := _flat(Color(WOOD_DARK, 0.3), WOOD, 2, 2)
	s.set_corner_radius_all(4)
	return s


## 进度条填充
func _progress_fill() -> StyleBoxFlat:
	var s := _flat(TERRACOTTA, TERRACOTTA_DARK, 2, 2)
	s.set_corner_radius_all(4)
	return s


## 滚动条轨道
func _scroll_track() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(WOOD_DARK, 0.15)
	s.set_corner_radius_all(4)
	return s


## 滚动条滑块
func _scroll_thumb() -> StyleBoxFlat:
	var s := _flat(WOOD, WOOD_DARK, 2, 0)
	s.set_corner_radius_all(4)
	return s


func _scroll_thumb_hover() -> StyleBoxFlat:
	var s := _flat(WOOD_LIGHT, WOOD, 2, 0)
	s.set_corner_radius_all(4)
	return s


## 弹出菜单面板
func _popup_panel() -> StyleBoxFlat:
	var s := _flat(PAPER_LIGHT, WOOD, 4, 8)
	s.shadow_color = SHADOW
	s.shadow_size = 8
	s.shadow_offset = Vector2(4, 6)
	s.set_corner_radius_all(4)
	return s


## 弹出菜单悬停项
func _popup_item_hover() -> StyleBoxFlat:
	var s := _flat(Color(HONEY, 0.25), HONEY, 2, 8)
	s.set_corner_radius_all(2)
	return s


## 空样式
func _empty_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


## 基础扁平样式工厂（严格复制自 ProviderSettingsTheme.shared_flat）
func _flat(background: Color, border: Color, border_width: int, content_margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = background
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(2)
	s.anti_aliasing = false
	s.content_margin_left = content_margin
	s.content_margin_top = content_margin
	s.content_margin_right = content_margin
	s.content_margin_bottom = content_margin
	return s


# ============================================================
#  公共 API：供场景脚本调用
# ============================================================

## 获取背景纹理
func get_background_texture() -> Texture2D:
	if _bg_texture:
		return _bg_texture
	_bg_texture = load(BACKGROUND_PATH) as Texture2D
	return _bg_texture


## 在指定父节点下创建游戏背景 TextureRect
## 严格复制自 ProviderSettingsScreen._build_background()
## expand_mode = EXPAND_IGNORE_SIZE, stretch_mode = STRETCH_KEEP_ASPECT_COVERED
## 返回创建的 TextureRect 节点
func create_background(parent: Node, z_index: int = -1) -> TextureRect:
	var tex_rect := TextureRect.new()
	tex_rect.name = "TownVisualAnchor"
	tex_rect.texture = get_background_texture()
	tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if z_index != -1:
		tex_rect.z_index = z_index
	parent.add_child(tex_rect)
	parent.move_child(tex_rect, 0)
	return tex_rect


## 在指定父节点下创建背景遮罩 ColorRect
## 严格复制自 ProviderSettingsScreen._build_background() 的 BackdropShade
## 应在 create_background() 之后调用，确保遮罩渲染在背景之上、UI 之下
func create_shade_overlay(parent: Node) -> ColorRect:
	var shade := ColorRect.new()
	shade.name = "BackdropShade"
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = OVERLAY
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(shade)
	# 确保遮罩在背景之后、其他 UI 之前（索引 1）
	if parent.get_child_count() > 1:
		parent.move_child(shade, 1)
	return shade


## 将一个 Control 包裹进 PanelContainer 并应用指定面板样式
## control 会被从原父节点移除，放入新的 PanelContainer
## PanelContainer 会被添加到原父节点的同一位置
## 严格复制参考源码 ProviderSettingsScreen._build_background() 的锚点处理方式
func wrap_in_panel(control: Control, panel_style: StyleBoxFlat) -> PanelContainer:
	var original_parent := control.get_parent()
	var original_index := control.get_index()

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style)

	# 判断父节点是否为 Container（Container 管理子节点布局，锚点不生效）
	var parent_is_container := original_parent is Container

	if parent_is_container:
		# 容器环境：复制 size_flags，让 PanelContainer 在容器中正确布局
		panel.size_flags_horizontal = control.size_flags_horizontal
		panel.size_flags_vertical = control.size_flags_vertical
		panel.custom_minimum_size = control.custom_minimum_size
	else:
		# 自由布局环境：直接复制锚点值（Godot 4 无 get_anchors_preset()）
		panel.anchor_left = control.anchor_left
		panel.anchor_top = control.anchor_top
		panel.anchor_right = control.anchor_right
		panel.anchor_bottom = control.anchor_bottom
		panel.offset_left = control.offset_left
		panel.offset_top = control.offset_top
		panel.offset_right = control.offset_right
		panel.offset_bottom = control.offset_bottom
		panel.grow_horizontal = control.grow_horizontal
		panel.grow_vertical = control.grow_vertical
		panel.size_flags_horizontal = control.size_flags_horizontal
		panel.size_flags_vertical = control.size_flags_vertical
		panel.custom_minimum_size = control.custom_minimum_size

	original_parent.remove_child(control)
	panel.add_child(control)
	original_parent.add_child(panel)
	original_parent.move_child(panel, original_index)

	# 让内部 control 填满 panel（PanelContainer 是 Container，自动管理子节点布局）
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_EXPAND_FILL

	return panel


## 给 Label 创建底框：将 Label 包裹进 PanelContainer
func wrap_label_in_panel(label: Label, panel_style: StyleBoxFlat = null) -> PanelContainer:
	if panel_style == null:
		panel_style = label_panel_style()
	return wrap_in_panel(label, panel_style)


## 递归查找并包裹所有不在 Panel/PanelContainer 内的浮动 Label / RichTextLabel
## 在场景 _ready() 中手动包裹特定容器后调用此函数，确保无遗漏
func wrap_all_floating_labels(root: Node, panel_style: StyleBoxFlat = null) -> void:
	if panel_style == null:
		panel_style = label_panel_style()
	for child in root.get_children():
		# 如果子节点本身是 Panel/PanelContainer，跳过其内部（已有背景）
		if child is Panel or child is PanelContainer:
			continue
		if child is Label or child is RichTextLabel:
			wrap_in_panel(child, panel_style)
		else:
			wrap_all_floating_labels(child, panel_style)


## 递归规范化所有控件的字体大小：低于 min_size 的自动提升到 min_size
## 确保 .tscn 中遗留的小字号覆盖不会导致文字看不清
func normalize_font_sizes(root: Node, min_size: int = 28) -> void:
	for child in root.get_children():
		if child is Label or child is Button or child is LineEdit \
		or child is TextEdit or child is OptionButton or child is SpinBox \
		or child is CheckBox:
			var ctrl: Control = child as Control
			var current_size: int = ctrl.get_theme_font_size("font_size")
			if current_size > 0 and current_size < min_size:
				ctrl.add_theme_font_size_override("font_size", min_size)
		elif child is RichTextLabel:
			# RichTextLabel 使用 normal_font_size 而非 font_size
			var rt: RichTextLabel = child as RichTextLabel
			var rt_current: int = rt.get_theme_font_size("normal_font_size")
			if rt_current > 0 and rt_current < min_size:
				rt.add_theme_font_size_override("normal_font_size", min_size)
			# 也检查 font_size（部分 RichTextLabel 使用 font_size）
			var rt_default: int = rt.get_theme_font_size("font_size")
			if rt_default > 0 and rt_default < min_size:
				rt.add_theme_font_size_override("font_size", min_size)
		# 递归处理所有子节点
		normalize_font_sizes(child, min_size)


## 递归为所有 Label / RichTextLabel 设置墨色文字和宣纸描边色
## 确保即使在深色背景上文字也有清晰轮廓
func apply_text_colors(root: Node) -> void:
	for child in root.get_children():
		if child is Label:
			child.add_theme_color_override("font_color", INK)
			child.add_theme_color_override("font_outline_color", PAPER_LIGHT)
		elif child is RichTextLabel:
			child.add_theme_color_override("default_color", INK)
		apply_text_colors(child)


## 设置按钮为主按钮样式（赤陶色背景 + 亮色文字）
func apply_primary_button(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal", _button_style("primary", "normal"))
	btn.add_theme_stylebox_override("hover", _button_style("primary", "hover"))
	btn.add_theme_stylebox_override("pressed", _button_style("primary", "pressed"))
	btn.add_theme_stylebox_override("focus", _button_style("primary", "focus"))
	btn.add_theme_stylebox_override("disabled", _button_style("primary", "disabled"))
	btn.add_theme_color_override("font_color", BUTTON_INK)
	btn.add_theme_color_override("font_hover_color", BUTTON_INK)
	btn.add_theme_color_override("font_pressed_color", BUTTON_INK)
	btn.add_theme_color_override("font_focus_color", BUTTON_INK)
	btn.add_theme_color_override("font_disabled_color", Color(BUTTON_INK, 0.5))


## 设置按钮为危险按钮样式
func apply_danger_button(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal", _button_style("danger", "normal"))
	btn.add_theme_stylebox_override("hover", _button_style("danger", "hover"))
	btn.add_theme_stylebox_override("pressed", _button_style("danger", "pressed"))
	btn.add_theme_stylebox_override("focus", _button_style("danger", "focus"))
	btn.add_theme_stylebox_override("disabled", _button_style("danger", "disabled"))
	btn.add_theme_color_override("font_color", BUTTON_INK)
	btn.add_theme_color_override("font_hover_color", BUTTON_INK)
	btn.add_theme_color_override("font_pressed_color", BUTTON_INK)


## 设置按钮为成功按钮样式
func apply_success_button(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal", _button_style("success", "normal"))
	btn.add_theme_stylebox_override("hover", _button_style("success", "hover"))
	btn.add_theme_stylebox_override("pressed", _button_style("success", "pressed"))
	btn.add_theme_stylebox_override("focus", _button_style("success", "focus"))
	btn.add_theme_stylebox_override("disabled", _button_style("success", "disabled"))
	btn.add_theme_color_override("font_color", BUTTON_INK)
	btn.add_theme_color_override("font_hover_color", BUTTON_INK)
	btn.add_theme_color_override("font_pressed_color", BUTTON_INK)


## 设置按钮为木质按钮样式
func apply_wood_button(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal", _button_style("wood", "normal"))
	btn.add_theme_stylebox_override("hover", _button_style("wood", "hover"))
	btn.add_theme_stylebox_override("pressed", _button_style("wood", "pressed"))
	btn.add_theme_stylebox_override("focus", _button_style("wood", "focus"))
	btn.add_theme_stylebox_override("disabled", _button_style("wood", "disabled"))
	btn.add_theme_color_override("font_color", BUTTON_INK)
	btn.add_theme_color_override("font_hover_color", BUTTON_INK)
	btn.add_theme_color_override("font_pressed_color", BUTTON_INK)


## 亮色文字常量（用于深色底框上的文字）
const LIGHT_TEXT := Color(1, 0.97, 0.88, 1)
const LIGHT_TEXT_GOLD := Color(1, 0.85, 0.4, 1)
const TEXT_OUTLINE := Color(0, 0, 0, 0.85)


## 给 Label 设置亮色文字+黑色描边，用于深色底框
func apply_light_text(label: Label, color: Color = LIGHT_TEXT, outline_size: int = 5) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", TEXT_OUTLINE)
	label.add_theme_constant_override("outline_size", outline_size)


## 给 RichTextLabel 设置亮色文字+黑色描边，用于深色底框
func apply_light_rich_text(rt: RichTextLabel, color: Color = LIGHT_TEXT, outline_size: int = 4) -> void:
	rt.add_theme_color_override("default_color", color)
	rt.add_theme_color_override("font_outline_color", TEXT_OUTLINE)
	rt.add_theme_constant_override("outline_size", outline_size)
