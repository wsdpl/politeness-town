## RPG 玩家控制器
## 四方向移动 + 行走动画 + 碰撞 + 交互检测
## 使用 AI Town 项目的 player_avatar_white_walk_64.png 精灵图（4x4 Atlas: 4方向×4帧）
extends CharacterBody2D

# ===== 信号 =====
signal interact_pressed(nearby_npc: Node)
signal facing_changed(direction: String)

# ===== 常量 =====
const MOVE_SPEED := 220.0
const FRAME_SIZE := 64  # 每帧 64x64 像素
const INTERACT_RANGE := 120.0

# ===== 方向枚举 =====
enum Dir { DOWN, RIGHT, UP, LEFT }
const DIR_NAMES := ["down", "right", "up", "left"]
const DIR_VECTORS := [
	Vector2.DOWN,   # DOWN
	Vector2.RIGHT,  # RIGHT
	Vector2.UP,     # UP
	Vector2.LEFT,   # LEFT
]

# ===== 节点引用 =====
var _sprite: Sprite2D
var _collision: CollisionShape2D
var _interact_area: Area2D
var _interact_shape: CollisionShape2D
var _interact_prompt: Label

# ===== 状态 =====
var _facing: int = Dir.DOWN
var _is_moving: bool = false
var _walk_phase: float = 0.0
var _walk_cycle_distance := 48.0  # 每48像素切换一帧
var _distance_accumulator: float = 0.0
var _nearby_npcs: Array[Node] = []
var _can_move: bool = true

# ===== 纹理 =====
var _walk_texture: Texture2D


func _ready() -> void:
	_walk_texture = load("res://assets/characters/player/player_walk.png") as Texture2D
	_build_nodes()
	_update_sprite_frame()


func _build_nodes() -> void:
	# 碰撞形状（脚部圆形）
	_collision = CollisionShape2D.new()
	var col_shape := CapsuleShape2D.new()
	col_shape.radius = 18.0
	col_shape.height = 52.0
	_collision.shape = col_shape
	_collision.rotation = PI / 2.0  # 横向胶囊
	add_child(_collision)

	# 精灵
	_sprite = Sprite2D.new()
	_sprite.texture = _walk_texture
	_sprite.hframes = 4
	_sprite.vframes = 4
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2(1.8, 1.8)  # 放大显示
	_sprite.position = Vector2(0, -10)  # 略微上移，脚部对齐碰撞体
	add_child(_sprite)

	# 交互检测区域
	_interact_area = Area2D.new()
	_interact_area.name = "InteractArea"
	_interact_shape = CollisionShape2D.new()
	var area_shape := CircleShape2D.new()
	area_shape.radius = INTERACT_RANGE
	_interact_shape.shape = area_shape
	_interact_area.add_child(_interact_shape)
	add_child(_interact_area)

	# 交互提示标签
	_interact_prompt = Label.new()
	_interact_prompt.text = "按 E 对话"
	_interact_prompt.add_theme_font_size_override("font_size", 20)
	_interact_prompt.add_theme_color_override("font_color", Color.WHITE)
	_interact_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_interact_prompt.add_theme_constant_override("outline_size", 4)
	_interact_prompt.position = Vector2(-50, -80)
	_interact_prompt.visible = false
	_interact_prompt.z_index = 10
	add_child(_interact_prompt)

	# 连接交互区域信号（仅使用 area_entered，避免与 body_entered 重复）
	_interact_area.area_entered.connect(_on_area_entered)
	_interact_area.area_exited.connect(_on_area_exited)


func _physics_process(delta: float) -> void:
	if not _can_move:
		velocity = Vector2.ZERO
		_is_moving = false
		_update_sprite_frame()
		move_and_slide()
		return

	# 读取输入
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1.0
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("move_down"):
		input_dir.y += 1.0
	if Input.is_action_pressed("move_up"):
		input_dir.y -= 1.0

	# 归一化对角线移动
	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()
		_is_moving = true
		# 更新朝向（优先水平方向）
		if abs(input_dir.x) >= abs(input_dir.y):
			_facing = Dir.RIGHT if input_dir.x > 0 else Dir.LEFT
		else:
			_facing = Dir.DOWN if input_dir.y > 0 else Dir.UP
		# 累积行走距离用于帧切换
		_distance_accumulator += input_dir.length() * MOVE_SPEED * delta
	else:
		_is_moving = false

	velocity = input_dir * MOVE_SPEED
	move_and_slide()

	# 更新精灵帧
	_update_sprite_frame()

	# 更新交互提示
	_update_interact_prompt()


func _update_sprite_frame() -> void:
	if _sprite == null:
		return
	var row := _facing  # 0=down, 1=right, 2=up, 3=left
	var col := 0
	if _is_moving:
		var phase := int(_distance_accumulator / _walk_cycle_distance) % 4
		col = phase
	else:
		col = 0  # 静止时显示第0帧
	_sprite.frame_coords = Vector2i(col, row)

	# 左方向使用右方向镜像
	_sprite.flip_h = (_facing == Dir.LEFT)
	if _facing == Dir.LEFT:
		_sprite.frame_coords = Vector2i(col, Dir.RIGHT)  # 使用 right 行然后翻转


func _update_interact_prompt() -> void:
	var has_npc := false
	for npc in _nearby_npcs:
		if npc == null or not is_instance_valid(npc):
			continue
		if npc.has_method("is_interactable") and not npc.is_interactable():
			continue
		has_npc = true
		break
	_interact_prompt.visible = has_npc


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _nearby_npcs.size() > 0:
		var nearest := _get_nearest_npc()
		if nearest != null:
			interact_pressed.emit(nearest)


func _get_nearest_npc() -> Node:
	if _nearby_npcs.is_empty():
		return null
	var nearest: Node = null
	var min_dist := INF
	for npc in _nearby_npcs:
		if npc == null or not is_instance_valid(npc):
			continue
		if npc.has_method("is_interactable") and not npc.is_interactable():
			continue
		var dist := global_position.distance_to(npc.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = npc
	return nearest


func _on_area_entered(area: Area2D) -> void:
	var owner_node := area.get_parent()
	if owner_node != null and owner_node.has_method("is_rpg_npc") and owner_node.is_rpg_npc():
		if not _nearby_npcs.has(owner_node):
			_nearby_npcs.append(owner_node)


func _on_area_exited(area: Area2D) -> void:
	var owner_node := area.get_parent()
	_nearby_npcs.erase(owner_node)


## 设置是否可以移动（对话时锁定移动）
func set_can_move(enabled: bool) -> void:
	_can_move = enabled
	if not enabled:
		velocity = Vector2.ZERO
		_is_moving = false
		_update_sprite_frame()


## 获取当前朝向名称
func get_facing_name() -> String:
	return DIR_NAMES[_facing]
