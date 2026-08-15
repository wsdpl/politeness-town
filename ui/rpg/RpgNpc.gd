## RPG NPC 控制器
## 站桩 NPC + 交互区域 + 对话触发
## 使用 AI Town 项目的 resident_2d_rig_v1 素材（look_XX 方向 rest pose）
class_name RpgNpc
extends CharacterBody2D

# ===== 信号 =====
signal npc_interacted(npc: Node)
signal walk_finished

# ===== 导出参数 =====
@export var npc_name: String = "NPC"
@export var npc_id: String = ""  # 对应 AssessmentData 中的角色
@export var portrait_path: String = ""  # 立绘路径
@export var look_index: int = 0  # 对应 look_00 ~ look_15
@export var face_direction: String = "down"  # 默认朝向 down/right/up
@export var interact_hint: String = "按 E 对话"

# ===== 节点引用 =====
var _sprite: Sprite2D
var _interact_area: Area2D
var _interact_shape: CollisionShape2D
var _collision: CollisionShape2D
var _name_label: Label
var _hint_label: Label

# ===== 状态 =====
var _is_active: bool = true  # 是否可交互
var _is_interacting: bool = false

# ===== 纹理路径前缀 =====
const NPC_TEX_BASE := "res://assets/characters/npc/"


func _ready() -> void:
	_build_nodes()
	_load_sprite()
	_update_display()


func _build_nodes() -> void:
	# 碰撞形状
	_collision = CollisionShape2D.new()
	var col_shape := CapsuleShape2D.new()
	col_shape.radius = 20.0
	col_shape.height = 56.0
	_collision.shape = col_shape
	_collision.rotation = PI / 2.0
	add_child(_collision)

	# 精灵
	_sprite = Sprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2(0.35, 0.35)  # 原图约525px高，缩放到约184px
	_sprite.position = Vector2(0, -20)
	add_child(_sprite)

	# 交互检测区域（玩家进入此区域可交互）
	_interact_area = Area2D.new()
	_interact_area.name = "NpcInteractArea"
	_interact_shape = CollisionShape2D.new()
	var area_shape := CircleShape2D.new()
	area_shape.radius = 90.0
	_interact_shape.shape = area_shape
	_interact_area.add_child(_interact_shape)
	add_child(_interact_area)

	# NPC 名牌
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	_name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_name_label.add_theme_constant_override("outline_size", 4)
	_name_label.position = Vector2(-60, -100)
	_name_label.size = Vector2(120, 30)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.z_index = 10
	add_child(_name_label)

	# 交互提示
	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 18)
	_hint_label.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
	_hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint_label.add_theme_constant_override("outline_size", 3)
	_hint_label.position = Vector2(-60, 80)
	_hint_label.size = Vector2(120, 24)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.z_index = 10
	_hint_label.visible = false
	add_child(_hint_label)


func _load_sprite() -> void:
	var look_str := "look_%02d" % look_index
	var tex_path := NPC_TEX_BASE + look_str + "_" + face_direction + ".png"
	var tex := load(tex_path) as Texture2D
	if tex == null:
		# 后备：尝试 down 方向
		tex = load(NPC_TEX_BASE + look_str + "_down.png") as Texture2D
	if tex == null:
		push_warning("[RpgNpc] 无法加载NPC精灵: %s" % tex_path)
		return
	_sprite.texture = tex


func _update_display() -> void:
	_name_label.text = npc_name
	_hint_label.text = interact_hint


## 标记为 RPG NPC（供 RpgPlayer 识别）
func is_rpg_npc() -> bool:
	return true


## 设置是否可交互
func set_active(active: bool) -> void:
	_is_active = active
	_interact_area.monitoring = active
	_interact_area.monitorable = active
	modulate.a = 1.0 if active else 0.4
	_hint_label.visible = false


## 设置交互中状态
func set_interacting(interacting: bool) -> void:
	_is_interacting = interacting


## 获取立绘纹理
func get_portrait() -> Texture2D:
	if portrait_path != "":
		return load(portrait_path) as Texture2D
	var look_str := "look_%02d" % look_index
	var p_path := "res://assets/characters/portraits/" + look_str + ".png"
	return load(p_path) as Texture2D


## 显示/隐藏交互提示（由玩家进入/离开交互范围时调用）
func show_hint(show: bool) -> void:
	if _is_active:
		_hint_label.visible = show


## 获取 NPC 数据字典
func get_npc_data() -> Dictionary:
	return {
		"npc_name": npc_name,
		"npc_id": npc_id,
		"look_index": look_index,
		"face_direction": face_direction,
		"portrait": get_portrait(),
	}


## NPC 走路到目标位置（带上下弹跳模拟步行）
func walk_to(target_pos: Vector2, duration: float = 1.5) -> void:
	var orig_sprite_y := _sprite.position.y
	var dir := target_pos - position

	# 根据移动方向设置朝向
	if abs(dir.x) > abs(dir.y):
		face_direction = "right"
		_sprite.flip_h = dir.x < 0
	elif dir.y > 0:
		face_direction = "down"
		_sprite.flip_h = false
	else:
		face_direction = "up"
		_sprite.flip_h = false
	_load_sprite()

	# 位置移动 tween
	var pos_tween := create_tween()
	pos_tween.tween_property(self, "position", target_pos, duration)

	# 上下弹跳 tween（模拟走路步伐）
	var bob_tween := create_tween()
	bob_tween.set_loops()
	bob_tween.tween_property(_sprite, "position:y", orig_sprite_y - 6, 0.12)
	bob_tween.tween_property(_sprite, "position:y", orig_sprite_y, 0.12)

	# 等待移动完成
	await pos_tween.finished

	# 停止弹跳，恢复朝向
	bob_tween.kill()
	_sprite.position.y = orig_sprite_y
	face_direction = "down"
	_sprite.flip_h = false
	_load_sprite()

	walk_finished.emit()
