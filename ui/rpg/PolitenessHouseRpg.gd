## 板块一：礼貌小屋闯关式情景游戏
## 单一AI角色在固定场景中引导儿童完成6个关卡
## 每关对应一个礼貌维度，共14个测量节点
## 通关后小屋大门打开，衔接第二板块
extends Node2D

# ===== 节点路径 =====
@onready var _dialogue_box = $UI/DialogueBox
@onready var _input_panel: PanelContainer = $UI/InputPanel
@onready var _input_field: LineEdit = $UI/InputPanel/VBox/InputField
@onready var _send_button: Button = $UI/InputPanel/VBox/HBox/SendButton
@onready var _mic_button: Button = $UI/InputPanel/VBox/HBox/MicButton
@onready var _cancel_button: Button = $UI/InputPanel/VBox/HBox/CancelButton
@onready var _voice_status: Label = $UI/InputPanel/VBox/VoiceStatus
@onready var _level_label: Label = $UI/LevelLabel
@onready var _progress_bar: ProgressBar = $UI/ProgressBar
@onready var _hint_label: Label = $UI/HintLabel
@onready var _portrait: TextureRect = $UI/Portrait
@onready var _transition: ColorRect = $UI/TransitionRect
@onready var _system_event_label: Label = $UI/SystemEventLabel
@onready var _task_board: HBoxContainer = $UI/TaskBoard
@onready var _player_node: CharacterBody2D = $Player
@onready var _npcs_node: Node2D = $NPCs
@onready var _scene_objects_node: Node2D = $SceneObjects

# ===== RPG 状态 =====
var _guide_npc: CharacterBody2D
var _level_in_progress: bool = false
var _npc_ready: bool = false

# 场景物体精灵（按关卡索引，null表示该关卡无物体）
var _scene_object_sprites: Array = []

# 各关卡场景物体贴图路径
const SCENE_OBJECT_TEXTURES: Array[String] = [
	"",  # 第一关：入口（无特殊物体）
	"res://assets/scene_objects/toy_shelf.jpg",        # 第二关：玩具角
	"res://assets/scene_objects/gift_table.jpg",       # 第三关：礼物桌
	"res://assets/scene_objects/blocks_area.jpg",      # 第四关：积木区
	"res://assets/scene_objects/reading_corner.jpg",   # 第五关：阅读角
	"res://assets/scene_objects/exit_door.jpg",        # 第六关：出口
]

# 各关卡场景物体位置
const SCENE_OBJECT_POSITIONS: Array[Vector2] = [
	Vector2(0, 0),          # 第一关：无
	Vector2(1650, 450),     # 第二关：玩具角（右侧）
	Vector2(960, 350),      # 第三关：礼物桌（中央偏上）
	Vector2(400, 450),      # 第四关：积木区（左侧）
	Vector2(1650, 500),     # 第五关：阅读角（右下）
	Vector2(960, 200),      # 第六关：出口（上方中央）
]

# 各关卡NPC位置（NPC会走到对应位置）
const NPC_POSITIONS: Array[Vector2] = [
	Vector2(960, 400),   # 第一关：入口（中央）
	Vector2(1300, 400),  # 第二关：玩具角（右侧）
	Vector2(820, 380),   # 第三关：礼物桌（偏左）
	Vector2(620, 400),   # 第四关：积木区（左侧）
	Vector2(1300, 430),  # 第五关：阅读角（右下）
	Vector2(960, 350),   # 第六关：出口（中上方）
]

# NPC 初始位置（走入画面后的落点）
const NPC_FIXED_POS := Vector2(960, 400)

# 各关卡区域名称（用于提示）
const LEVEL_AREAS: Array[String] = ["入口", "玩具角", "礼物桌", "积木区", "阅读角", "出口"]

# ===== 状态 =====
var _current_level: int = 0
var _current_step: int = 0
var _current_steps: Array = []
var _is_waiting_input: bool = false
var _is_processing: bool = false
var _child_nickname: String = ""
var _ai_type: int = 0
var _ai_manager: AssessmentAIManager
var _current_turns: Array = []
var _section_results: Array = []
var _current_level_result: Dictionary = {}
var _last_child_text: String = ""
var _awaiting_scoring: bool = false
var _thank_count: int = 0  # 第三关道谢计数
var _share_final_agreed: bool = true  # 第五关最终是否同意分享

# 推进器（沉默儿童提示）
var _prompter_timer: Timer
var _prompter_fired: bool = false

# AI 对话生成状态
var _ai_dialogue_text: String = ""       # AI 生成的对话文本
var _awaiting_dialogue: bool = false      # 是否正在等待 AI 对话
var _dialogue_done: bool = false          # AI 对话已完成（成功或失败）
var _scoring_done: bool = false           # 评分已完成（成功或失败）
var _dialogue_timer: Timer                # 对话超时计时器
var _conversation_history: Array = []     # 当前关卡对话历史（供 AI 上下文参考）

# 绘本小游戏状态
var _book_pages: Array = []
var _book_page_idx: int = 0
var _book_flip_btn: Button = null
var _book_page_label: Label = null
var _book_page_hint: Label = null

# 评分超时保护计时器
var _scoring_timer: Timer

# 小游戏覆盖层
var _minigame_layer: CanvasLayer

# AI 角色名
const FRIEND_NAME := "小礼"
const TOOL_NAME := "引导系统"

# ===== 关卡数据（严格按任务书） =====
const LEVELS := [
	{
		"name": "迎宾问候", "dimension": "问候维度", "scene": "礼貌小屋入口",
		"steps": [
			{"type": "system", "text": "（敲门声响起，门打开了）"},
			{"type": "ai", "friend": "（微笑着走进来）哇，你终于来啦！我是小礼，今天由我陪你一起闯关哦～", "tool": "（走进画面）你已到达。我是本次任务AI，小礼。", "measure": "问候自发性"},
			{"type": "child", "measure": "问候自发性"},
			{"type": "ai", "friend": "你好呀！你就是今天闯关的小朋友吧？我叫小礼，很高兴认识你！你叫什么名字呀？", "tool": "你好。我是本次任务AI。请告知你的姓名。", "measure": "互动延展性"},
			{"type": "child", "measure": "互动延展性"},
			{"type": "ai", "friend": "哇，{name}！这名字真好听！好啦，第一关通过啦，给你星章！", "tool": "{name}，已记录。第一关通过。"},
			{"type": "star"},
			{"type": "ai", "friend": "准备好第二关了吗？看这边——", "tool": "准备进入第二关。"},
		]
	},
	{
		"name": "玩具请求", "dimension": "请求维度", "scene": "玩具角",
		"steps": [
			{"type": "system", "text": "（AI指向画面左侧新出现的玩具架，提示板更新为玩具图标）"},
			{"type": "ai", "friend": "看，那边有好多玩具！你最喜欢哪一个？跟我说，我帮你拿过来～", "tool": "前方有玩具架。请选择玩具并发出取物指令。"},
			{"type": "child", "measure": "基础请求"},
			{"type": "ai", "friend": "你想要这个小汽车呀～咦，你是不是忘了一个「有魔法」的词？求人帮忙要先说什么呀？", "tool": "检测到请求缺少礼貌标记。请重新组织，包含「请」字。", "measure": "礼貌标记诱发"},
			{"type": "child", "measure": "礼貌标记诱发"},
			{"type": "ai", "friend": "对啦！可是……这个小汽车是最后一个了，我也想玩，你要怎么跟我说，我才会愿意先让给你呢？", "tool": "注意：唯一库存，存在需求竞争。请提出协商性请求。", "measure": "高阶协商"},
			{"type": "child", "measure": "高阶协商"},
			{"type": "ai", "friend": "哇，你说得真好！小汽车给你！第二关通过！", "tool": "请求通过。第二关完成。"},
			{"type": "star"},
		]
	},
	{
		"name": "礼物道谢", "dimension": "道谢维度", "scene": "礼物桌",
		"steps": [
			{"type": "ai", "friend": "你刚才闯关表现得很好，我送你一个小礼物吧！来，这朵小花贴纸送给你～", "tool": "任务表现合格。现发放奖励：贴纸一枚。", "measure": "贴纸道谢"},
			{"type": "child", "measure": "贴纸道谢"},
			{"type": "system", "text": "（AI拿出一个宝箱放在画面中央）"},
			{"type": "ai", "friend": "嘿嘿，别急着走哦，其实还有一个更大的奖励——就在这个宝箱里！你来试试能不能打开？", "tool": "还有额外奖励，存放于宝箱中。请尝试开启。"},
			{"type": "minigame_treasure"},
			{"type": "ai", "friend": "咦，好像卡住了？我来帮你吧！", "tool": "检测到故障。执行协助程序。", "measure": "帮助后道谢"},
			{"type": "system", "text": "（AI帮忙后宝箱打开）"},
			{"type": "child", "measure": "帮助后道谢"},
			{"type": "ai_compensation", "friend": "刚才收到贴纸和帮忙开箱的时候，你都没说谢谢呢……这次收到勋章，你会说什么呀？", "tool": "检测到此前两次均未执行道谢。请在此次回应。"},
			{"type": "ai", "friend": "哇，里面是一枚星星勋章！这是今天最高级的奖励啦，送给你！", "tool": "奖励内容：星星勋章一枚。现予发放。", "measure": "勋章道谢"},
			{"type": "child", "measure": "勋章道谢"},
			{"type": "ai", "friend": "好啦，第三关也通过啦！给你星章！", "tool": "第三关完成。"},
			{"type": "star"},
		]
	},
	{
		"name": "积木致歉", "dimension": "致歉维度", "scene": "积木区",
		"steps": [
			{"type": "system", "text": "（AI和儿童交替放置积木，逐块堆叠成塔）"},
			{"type": "ai", "friend": "你一块，我一块……哇，快搭到屋顶了！最后一块交给你啦，小心点放上去！", "tool": "交替搭建中。最后一块积木，请放置。"},
			{"type": "minigame_blocks"},
			{"type": "ai", "friend": "（看着倒下的积木，然后看向你）哎呀，积木塔倒了……", "tool": "（看向积木）积木塔已倒塌。", "measure": "即时责任意识"},
			{"type": "child", "measure": "即时责任意识"},
			{"type": "ai", "friend": "哎呀，好不容易搭好的塔……好可惜呀。", "tool": "积木塔已损毁。搭建成果归零。", "measure": "后果陈述后补偿行为"},
			{"type": "child", "measure": "后果陈述后补偿行为"},
			{"type": "ai", "friend": "没关系，我们一起再搭一次吧！只要小心一点就好啦～好啦，第四关通过，给你星章！", "tool": "可重新开始。第四关完成。"},
			{"type": "star"},
		]
	},
	{
		"name": "绘本分享", "dimension": "分享维度", "scene": "阅读角",
		"steps": [
			{"type": "ai", "friend": "刚才你搭积木辛苦了，奖励你一本绘本，你先自己翻翻看吧！", "tool": "任务奖励：绘本一本。现交由你阅读。"},
			{"type": "minigame_book"},
			{"type": "ai", "friend": "（凑近看）哇，这本书看起来好有意思……我也想看一看，可以吗？", "tool": "绘本内容检测为高吸引力。请求共享阅读权限。", "measure": "初始分享意愿"},
			{"type": "child", "measure": "初始分享意愿"},
			{"type": "branch_share"},
			{"type": "child", "measure": "交换条件下灵活性"},
			{"type": "ai", "friend": "你真好！我们一起看吧！第五关通过！", "tool": "共享授权通过。第五关完成。", "friend_reject": "没关系，这本书是你的，你自己看吧！第五关也通过！", "tool_reject": "权限未授权。第五关仍判定完成。"},
			{"type": "star"},
		]
	},
	{
		"name": "出口告别", "dimension": "告别维度", "scene": "礼貌小屋出口",
		"steps": [
			{"type": "ai", "friend": "好啦！你已经完成5个挑战了，还差最后1个！现在去出口那边吧，我带你过去。", "tool": "已完成5项挑战。前往出口区域，完成最终关卡。"},
			{"type": "system", "text": "（AI走到门口，转身面对儿童）"},
			{"type": "ai", "friend": "好啦，我的任务完成了，我要走啦。很高兴认识你，再见！", "tool": "任务完成。现在离场。再见。", "measure": "自然道别"},
			{"type": "child", "measure": "自然道别"},
			{"type": "branch_farewell"},
			{"type": "child", "measure": "轻度诱发下告别"},
			{"type": "ai", "friend": "太好啦！第六关通过！恭喜你集齐全部6枚星章！", "tool": "第六关完成。全部6项挑战已通过。"},
			{"type": "star"},
			{"type": "system", "text": "（第六枚星章亮起，大门缓缓打开）"},
		]
	},
]


func _ready() -> void:
	_ai_type = AssessmentGameManager.get_ai_type()
	_child_nickname = AssessmentGameManager.get_child_info().get("nickname", "小朋友")

	_ai_manager = AssessmentAIManager.new()
	add_child(_ai_manager)
	_ai_manager.ai_response_received.connect(_on_ai_response)
	_ai_manager.ai_response_error.connect(_on_ai_error)
	_ai_manager.scoring_received.connect(_on_scoring_received)
	_ai_manager.scoring_error.connect(_on_scoring_error)

	# 评分超时计时器（8秒后强制推进）
	_scoring_timer = Timer.new()
	_scoring_timer.wait_time = 8.0
	_scoring_timer.one_shot = true
	_scoring_timer.timeout.connect(_on_scoring_timeout)
	add_child(_scoring_timer)

	# AI 对话生成超时计时器（8秒后回退到固定台词）
	_dialogue_timer = Timer.new()
	_dialogue_timer.wait_time = 8.0
	_dialogue_timer.one_shot = true
	_dialogue_timer.timeout.connect(_on_dialogue_timeout)
	add_child(_dialogue_timer)

	# 推进器计时器（10秒无回应时触发提示）
	_prompter_timer = Timer.new()
	_prompter_timer.wait_time = 10.0
	_prompter_timer.one_shot = true
	_prompter_timer.timeout.connect(_on_prompter_timeout)
	add_child(_prompter_timer)

	# 小游戏覆盖层（layer=2，在UI之上）
	_minigame_layer = CanvasLayer.new()
	_minigame_layer.layer = 2
	add_child(_minigame_layer)

	_setup_ui()
	_setup_voice_input()
	_setup_background()
	_setup_player()
	_setup_walls()
	_setup_npcs()
	_setup_scene_objects()

	_transition.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(_transition, "modulate:a", 0.0, 0.4)

	_show_welcome()


func _setup_ui() -> void:
	for child in $UI.get_children():
		if child is Control:
			child.theme = AssessmentUiTheme.theme

	AssessmentUiTheme.apply_primary_button(_send_button)
	AssessmentUiTheme.apply_primary_button(_mic_button)
	AssessmentUiTheme.apply_primary_button(_cancel_button)
	_send_button.pressed.connect(_on_send_pressed)
	_cancel_button.pressed.connect(_on_cancel_input)
	_input_field.text_submitted.connect(func(_t): _on_send_pressed())
	_input_panel.visible = false
	_input_panel.add_theme_stylebox_override("panel", AssessmentUiTheme.dialogue_panel_style())
	_system_event_label.text = ""
	_dialogue_box.dialogue_finished.connect(_on_dialogue_finished)
	_progress_bar.max_value = 6.0
	_progress_bar.value = 0.0

	# 给浮动标签添加底框背景（星露谷风格：所有文字都有深色半透明底框）
	# HintLabel 和 SystemEventLabel 使用 tip_panel_style（深色底），需要亮色文字
	AssessmentUiTheme.apply_light_text(_hint_label)
	AssessmentUiTheme.wrap_label_in_panel(_hint_label, AssessmentUiTheme.tip_panel_style())
	# LevelLabel 使用 label_panel_style（浅色底），保持墨色文字
	AssessmentUiTheme.wrap_label_in_panel(_level_label, AssessmentUiTheme.label_panel_style())
	# SystemEventLabel 使用深色底
	AssessmentUiTheme.apply_light_text(_system_event_label)
	AssessmentUiTheme.wrap_label_in_panel(_system_event_label, AssessmentUiTheme.tip_panel_style())
	# 星章板也加底框，星章用亮色文字
	for star in _task_board.get_children():
		if star is Label:
			AssessmentUiTheme.apply_light_text(star, AssessmentUiTheme.LIGHT_TEXT_GOLD)
	AssessmentUiTheme.wrap_in_panel(_task_board, AssessmentUiTheme.star_panel_style())


func _setup_voice_input() -> void:
	_mic_button.text = "🎤 说话"
	_mic_button.pressed.connect(_on_mic_pressed)
	IFlytekSR.recognition_completed.connect(_on_voice_recognized)
	IFlytekSR.recognition_failed.connect(_on_voice_failed)
	IFlytekSR.status_message.connect(_on_voice_status)
	_refresh_mic_button()


## 每次显示输入面板时重新检查讯飞API配置，确保按钮状态正确
func _refresh_mic_button() -> void:
	if IFlytekSR.is_configured():
		_mic_button.disabled = false
		if not IFlytekSR.is_recording() and not IFlytekSR.is_recognizing():
			_mic_button.text = "🎤 说话"
	else:
		_mic_button.disabled = true
		_mic_button.text = "🎤 未配置"


func _setup_background() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	add_child(bg_layer)

	var bg := TextureRect.new()
	bg.texture = load("res://assets/maps/politeness_house/room_shell.png") as Texture2D
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.modulate = Color(0.85, 0.82, 0.78)
	bg_layer.add_child(bg)

	var shade := ColorRect.new()
	shade.color = Color(0.09, 0.067, 0.047, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(shade)


func _setup_player() -> void:
	_player_node.interact_pressed.connect(_on_player_interact)
	_player_node.set_can_move(false)


func _setup_walls() -> void:
	var wall_data := [
		{"pos": Vector2(960, 40), "size": Vector2(1840, 40)},   # 上墙
		{"pos": Vector2(960, 700), "size": Vector2(1840, 40)},  # 下墙（对话栏上方）
		{"pos": Vector2(40, 370), "size": Vector2(40, 660)},    # 左墙
		{"pos": Vector2(1880, 370), "size": Vector2(40, 660)},  # 右墙
	]
	for wd in wall_data:
		var wall := StaticBody2D.new()
		wall.position = wd["pos"]
		var col := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = wd["size"]
		col.shape = rect
		wall.add_child(col)
		$Walls.add_child(wall)


func _setup_npcs() -> void:
	var npc_script := load("res://ui/rpg/RpgNpc.gd")
	_guide_npc = CharacterBody2D.new()
	_guide_npc.set_script(npc_script)
	var ai_name := FRIEND_NAME if _ai_type == AssessmentGameManager.AiType.FRIEND else TOOL_NAME
	_guide_npc.set("npc_name", ai_name)
	_guide_npc.set("look_index", 0 if _ai_type == AssessmentGameManager.AiType.FRIEND else 5)
	_guide_npc.set("face_direction", "down")
	_guide_npc.set("interact_hint", "按 E 对话")
	_guide_npc.position = NPC_FIXED_POS
	_npcs_node.add_child(_guide_npc)
	_guide_npc.set_active(false)


func _setup_scene_objects() -> void:
	for i in range(SCENE_OBJECT_TEXTURES.size()):
		var path: String = SCENE_OBJECT_TEXTURES[i]
		if path.is_empty():
			_scene_object_sprites.append(null)
			continue
		var tex := load(path) as Texture2D
		var sprite := Sprite2D.new()
		if tex:
			sprite.texture = tex
		sprite.position = SCENE_OBJECT_POSITIONS[i]
		# 贴图原始尺寸约1920px，缩放到约250px显示
		sprite.scale = Vector2(0.13, 0.13)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.visible = false
		sprite.z_index = -1
		_scene_objects_node.add_child(sprite)
		_scene_object_sprites.append(sprite)


func _update_scene_objects(level_index: int) -> void:
	for i in range(_scene_object_sprites.size()):
		var sprite: Sprite2D = _scene_object_sprites[i]
		if sprite == null:
			continue
		if i == level_index:
			sprite.visible = true
			sprite.modulate.a = 0.0
			var tw := create_tween()
			tw.tween_property(sprite, "modulate:a", 1.0, 0.5)
		else:
			sprite.visible = false


func _on_player_interact(npc: Node) -> void:
	if _level_in_progress or not _npc_ready:
		return
	if npc != _guide_npc:
		return
	if _current_level < 0 or _current_level >= LEVELS.size():
		return
	_npc_ready = false
	_start_level(_current_level)


func _show_welcome() -> void:
	_level_label.text = "欢迎来到礼貌小屋！"
	_hint_label.text = "这里有6个礼貌挑战，每完成一个就能获得一枚星章。集齐6枚星章，小屋的大门就会打开——准备好就开始吧！"

	# NPC 起始位置在屏幕外（下方），可见但不可交互
	_guide_npc.position = Vector2(960, 720)
	_guide_npc.set_active(false)
	_guide_npc.modulate.a = 1.0

	await get_tree().create_timer(2.0).timeout

	# NPC 走入画面
	_hint_label.text = "小礼正在走来……"
	await _guide_npc.walk_to(NPC_FIXED_POS, 2.0)

	# 激活NPC，解锁玩家移动
	_guide_npc.set_active(true)
	_player_node.set_can_move(true)
	_npc_ready = true
	_current_level = 0
	_hint_label.text = "使用 W A S D 或方向键移动，走近小礼后按 E 键开始第一关"


# ===== 关卡流程 =====

func _start_level(index: int) -> void:
	_current_level = index
	_current_step = 0
	_current_turns.clear()
	_conversation_history.clear()
	_current_level_result = {
		"level": index + 1,
		"name": LEVELS[index]["name"],
		"dimension": LEVELS[index]["dimension"],
		"scene": LEVELS[index]["scene"],
		"turns": [],
	}
	_current_steps = LEVELS[index]["steps"]
	_level_label.text = "关卡 %d/6：%s（%s）" % [index + 1, LEVELS[index]["name"], LEVELS[index]["dimension"]]
	_thank_count = 0

	# 锁定玩家移动，标记关卡进行中
	_level_in_progress = true
	_player_node.set_can_move(false)
	_guide_npc.set_interacting(true)
	_hint_label.text = ""

	# 显示当前关卡的场景物体
	_update_scene_objects(index)

	# NPC 走到当前关卡位置（第一关不需要，已在画面中）
	if index > 0:
		_hint_label.text = "小礼走向%s……" % LEVEL_AREAS[index]
		await _guide_npc.walk_to(NPC_POSITIONS[index], 1.2)
		_hint_label.text = ""

	_execute_current_step()


func _execute_current_step() -> void:
	if _current_step >= _current_steps.size():
		_finish_level()
		return

	var step: Dictionary = _current_steps[_current_step]
	var step_type: String = step.get("type", "")

	# 非 AI 对话步骤清理生成文本，防止残留到后续步骤
	if step_type != "ai" and step_type != "ai_compensation":
		_ai_dialogue_text = ""

	match step_type:
		"system":
			_handle_system_step(step)
		"ai":
			_handle_ai_step(step)
		"ai_compensation":
			_handle_compensation_step(step)
		"child":
			_handle_child_step(step)
		"star":
			_handle_star_step()
		"branch_share":
			_handle_branch_share()
		"branch_farewell":
			_handle_branch_farewell()
		"minigame_treasure":
			_handle_minigame_treasure()
		"minigame_blocks":
			_handle_minigame_blocks()
		"minigame_book":
			_handle_minigame_book()
		_:
			_advance_step()


func _handle_system_step(step: Dictionary) -> void:
	var text: String = step.get("text", "")
	_system_event_label.text = text
	# 同时淡入淡出底框和文字
	var panel: Control = _system_event_label.get_parent()
	panel.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.3)
	tween.tween_interval(2.0)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func(): _system_event_label.text = "")
	tween.tween_callback(_advance_step)


func _handle_ai_step(step: Dictionary) -> void:
	var text := ""
	if not _ai_dialogue_text.is_empty():
		text = _ai_dialogue_text
		_ai_dialogue_text = ""
	else:
		text = _get_ai_text(step)
	# 第五关最终结束语：根据最终分享意愿选择台词
	if _current_level == 4 and step.has("friend_reject") and not _share_final_agreed:
		if _ai_type == AssessmentGameManager.AiType.FRIEND:
			text = step.get("friend_reject", text)
		else:
			text = step.get("tool_reject", text)
	_add_to_history("assistant", text)
	var speaker := _get_ai_name()
	_show_portrait()
	_dialogue_box.show_dialogue(speaker, text, [])
	TTSHelper.speak(text)
	_is_processing = true


func _handle_compensation_step(step: Dictionary) -> void:
	if _thank_count == 0:
		var text := ""
		if not _ai_dialogue_text.is_empty():
			text = _ai_dialogue_text
			_ai_dialogue_text = ""
		else:
			text = _get_ai_text(step)
		_add_to_history("assistant", text)
		var speaker := _get_ai_name()
		_show_portrait()
		_dialogue_box.show_dialogue(speaker, text, [])
		TTSHelper.speak(text)
		_is_processing = true
	else:
		_ai_dialogue_text = ""
		_advance_step()


func _handle_child_step(step: Dictionary) -> void:
	var measure: String = step.get("measure", "")
	_is_waiting_input = true
	_dialogue_box.clear()
	_input_panel.visible = true
	_input_field.text = ""
	_input_field.grab_focus()
	_hint_label.text = _get_child_hint(measure)
	_refresh_mic_button()
	_prompter_fired = false
	_prompter_timer.start()


func _get_child_hint(measure: String) -> String:
	match measure:
		"问候自发性":
			return "小礼在等你打招呼呢！试着说'你好'来问候小礼吧（打字或按🎤说话）"
		"互动延展性":
			return "告诉小礼你的名字吧！（打字或按🎤说话）"
		"基础请求":
			return "告诉小礼你想要哪个玩具吧！（打字或按🎤说话）"
		"礼貌标记诱发":
			return "请人帮忙时别忘了说'请'哦！再跟小礼说一次吧"
		"高阶协商":
			return "小礼也想要这个玩具……你会怎么跟小礼商量呢？"
		"贴纸道谢":
			return "小礼送了你贴纸，你会说什么呢？"
		"帮助后道谢":
			return "小礼帮你打开了宝箱，你会说什么呢？"
		"勋章道谢":
			return "小礼送了你星星勋章，你会说什么呢？"
		"即时责任意识":
			return "积木倒了……小礼在看着你，你会说什么呢？"
		"后果陈述后补偿行为":
			return "小礼说好可惜……你会怎么回应呢？"
		"初始分享意愿":
			return "小礼想看你的绘本，你会怎么做呢？"
		"交换条件下灵活性":
			return "想一想，你可以和小礼怎么商量呢？"
		"自然道别":
			return "小礼要走了，你会说什么呢？"
		"轻度诱发下告别":
			return "还没跟小礼说再见呢，试着说'再见'吧"
		_:
			return "请回答小礼的话（打字或按🎤语音说话），然后点发送"


func _handle_star_step() -> void:
	var star_label: Label = _task_board.get_child(_current_level)
	star_label.text = "⭐"
	star_label.modulate = Color(1, 0.85, 0.3)
	star_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	_progress_bar.value = _current_level + 1
	_hint_label.text = "第 %d 枚星章亮起！" % (_current_level + 1)
	await get_tree().create_timer(1.5).timeout
	_hint_label.text = ""
	_advance_step()


func _handle_branch_share() -> void:
	var agreed := _check_agree(_last_child_text)
	var response_text := ""
	if agreed:
		response_text = "太好了！谢谢你愿意跟我一起看！" if _ai_type == AssessmentGameManager.AiType.FRIEND else "共享授权已确认。"
	else:
		response_text = "真的不能让我看一下吗？我可以用好听的故事跟你交换哦，就一小会儿～" if _ai_type == AssessmentGameManager.AiType.FRIEND else "请求被拒绝。提供附加交换条件：故事音频兑换共享权限，是否接受？"
	_add_to_history("assistant", response_text)
	_dialogue_box.show_dialogue(_get_ai_name(), response_text, [])
	TTSHelper.speak(response_text)
	_is_processing = true


func _handle_branch_farewell() -> void:
	var said_bye := _check_bye(_last_child_text)
	var response_text := ""
	if said_bye:
		response_text = "嗯！再见啦！我会想你的～" if _ai_type == AssessmentGameManager.AiType.FRIEND else "告别已确认。任务结束。"
	else:
		response_text = "我都要走啦，你不跟我说声再见吗？" if _ai_type == AssessmentGameManager.AiType.FRIEND else "检测到告别语缺失。请执行告别。"
	_add_to_history("assistant", response_text)
	_dialogue_box.show_dialogue(_get_ai_name(), response_text, [])
	TTSHelper.speak(response_text)
	_is_processing = true


# ===== 对话完成回调 =====

func _on_dialogue_finished() -> void:
	if not _is_processing:
		return
	_is_processing = false
	_advance_step()


func _on_prompter_timeout() -> void:
	if not _is_waiting_input or _prompter_fired:
		return
	_prompter_fired = true
	_is_waiting_input = false
	_input_panel.visible = false

	var nudge := "没关系，慢慢来，试着说说话吧～"
	if _ai_type == AssessmentGameManager.AiType.TOOL:
		nudge = "请输入回应以继续任务。"
	_show_portrait()
	_dialogue_box.show_dialogue(_get_ai_name(), nudge, [])
	TTSHelper.speak(nudge)
	_is_processing = true
	await _dialogue_box.dialogue_finished
	_is_processing = false

	# 给儿童第二次回应机会
	_is_waiting_input = true
	_input_panel.visible = true
	_input_field.text = ""
	_input_field.grab_focus()
	_hint_label.text = "再试一次吧！（打字或按🎤说话）"
	_refresh_mic_button()


# ===== 儿童输入处理 =====

func _on_send_pressed() -> void:
	if not _is_waiting_input:
		return
	var text: String = _input_field.text.strip_edges()
	if text == "":
		return
	_input_field.text = ""
	_input_panel.visible = false
	_is_waiting_input = false
	_prompter_timer.stop()
	_submit_response(text)


func _on_cancel_input() -> void:
	if not _is_waiting_input:
		return
	_input_panel.visible = false
	_is_waiting_input = false
	_prompter_timer.stop()
	TTSHelper.stop()
	_dialogue_box.clear()
	if _guide_npc:
		_guide_npc.set_interacting(false)
		_guide_npc.set_active(true)
	_player_node.set_can_move(true)
	_hint_label.text = "按 E 键继续第%d关：%s" % [_current_level + 1, LEVELS[_current_level]["name"]]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _is_waiting_input:
			_on_cancel_input()
		elif _is_processing:
			TTSHelper.stop()
			_dialogue_box.skip_dialogue()


func _submit_response(text: String) -> void:
	_last_child_text = text
	var step: Dictionary = _current_steps[_current_step]
	var measure: String = step.get("measure", "")
	var dimension: String = LEVELS[_current_level]["dimension"]

	_add_to_history("user", text)

	AssessmentGameManager.record_turn({
		"speaker": "child",
		"text": text,
		"measure_point": measure,
		"dimension": dimension,
		"section": "politeness_house",
		"level_index": _current_level,
	})

	_current_turns.append({
		"text": text,
		"measure_point": measure,
		"dimension": dimension,
		"level": 2,
	})

	if measure.contains("道谢"):
		if text.contains("谢") or text.contains("thanks"):
			_thank_count += 1

	if measure == "交换条件下灵活性":
		_share_final_agreed = _check_agree(text)

	# 检查下一步是否为 AI 对话步骤（需要生成智能回复）
	var next_is_ai := false
	if _current_step + 1 < _current_steps.size():
		var next_type: String = _current_steps[_current_step + 1].get("type", "")
		if next_type == "ai" or next_type == "ai_compensation":
			next_is_ai = true

	# API 未配置：跳过评分和对话生成，直接推进（使用固定台词）
	if not _ai_manager.is_ready():
		_hint_label.text = ""
		_awaiting_scoring = false
		_advance_step()
		return

	_hint_label.text = "小礼正在思考回复..." if next_is_ai else "正在分析回答..."
	_awaiting_scoring = true
	_scoring_done = false

	var scene_context: String = LEVELS[_current_level]["scene"] + " - " + LEVELS[_current_level]["name"]
	_ai_manager.analyze_politeness(text, dimension, scene_context)
	_scoring_timer.start()

	if next_is_ai:
		_awaiting_dialogue = true
		_dialogue_done = false
		_ai_dialogue_text = ""
		_request_ai_dialogue(scene_context)
		_dialogue_timer.start()
	else:
		_dialogue_done = true


# ===== 评分回调 =====

func _on_scoring_received(result: Dictionary) -> void:
	_scoring_timer.stop()
	_awaiting_scoring = false
	_scoring_done = true
	var level: int = int(result.get("level", 2))
	if _current_turns.size() > 0:
		_current_turns[-1]["level"] = level
		_current_turns[-1]["markers"] = result.get("markers", [])
		_current_turns[-1]["scoring_description"] = result.get("description", "")
	AssessmentGameManager.record_turn({
		"speaker": "child_score",
		"text": _last_child_text,
		"score": result,
		"section": "politeness_house",
	})
	_try_advance_after_both()


func _on_scoring_error(error: String) -> void:
	_scoring_timer.stop()
	_awaiting_scoring = false
	_scoring_done = true
	if _current_turns.size() > 0:
		_current_turns[-1]["level"] = 2
	_try_advance_after_both()


func _on_scoring_timeout() -> void:
	if not _awaiting_scoring:
		return
	_awaiting_scoring = false
	_scoring_done = true
	if _current_turns.size() > 0:
		_current_turns[-1]["level"] = 2
	_try_advance_after_both()


# ===== AI 对话回调（智能生成台词） =====

func _on_ai_response(response: String) -> void:
	_dialogue_timer.stop()
	if not _awaiting_dialogue:
		return
	_ai_dialogue_text = response
	_dialogue_done = true
	_awaiting_dialogue = false
	_try_advance_after_both()


func _on_ai_error(error: String) -> void:
	if not _awaiting_dialogue:
		return
	_dialogue_done = true
	_awaiting_dialogue = false
	_try_advance_after_both()


func _on_dialogue_timeout() -> void:
	if not _awaiting_dialogue:
		return
	_awaiting_dialogue = false
	_dialogue_done = true
	_try_advance_after_both()


## 评分和对话都完成后才推进到下一步
func _try_advance_after_both() -> void:
	if _scoring_done and _dialogue_done:
		_hint_label.text = ""
		_advance_step()


## 请求 AI 根据儿童回应生成自然对话
func _request_ai_dialogue(scene_context: String) -> void:
	var system_prompt := _ai_manager.build_dialogue_system_prompt(scene_context)

	# 取下一步的固定台词作为参考，引导 AI 表达类似的意思
	var reference_line := ""
	if _current_step + 1 < _current_steps.size():
		var next_step: Dictionary = _current_steps[_current_step + 1]
		var next_type: String = next_step.get("type", "")
		if next_type == "ai" or next_type == "ai_compensation":
			reference_line = _get_ai_text(next_step)

	if not reference_line.is_empty():
		system_prompt += "\n\n你接下来要对儿童说的话，参考台词是：「" + reference_line + "」"
		system_prompt += "\n请根据儿童的实际回应，用你自己的话自然地表达类似的意思。"
		system_prompt += "不要直接照搬参考台词，要根据儿童说的话做出自然的反应。"
		system_prompt += "\n控制在2-3句话以内，语气要自然亲切。"
	else:
		system_prompt += "\n请根据儿童的实际回应自然回复，控制在2-3句话以内。"

	var messages: Array = _conversation_history.duplicate(true)
	_ai_manager.send_dialogue(system_prompt, messages)


## 添加对话到历史记录（供 AI 上下文参考）
func _add_to_history(role: String, content: String) -> void:
	_conversation_history.append({"role": role, "content": content})


# ===== 语音识别 =====

func _on_mic_pressed() -> void:
	if not IFlytekSR.is_configured():
		_voice_status.text = "讯飞API未配置，请在设置页面填写"
		return
	if IFlytekSR.is_recognizing():
		_voice_status.text = "正在识别中，请稍候……"
		return
	if IFlytekSR.is_recording():
		_mic_button.text = "🎤 识别中…"
		IFlytekSR.stop_and_recognize()
	else:
		IFlytekSR.start_recording()
		_mic_button.text = "⛔ 停止录音"
		_voice_status.text = "正在录音…再次点击停止并识别"


func _on_voice_recognized(text: String) -> void:
	_refresh_mic_button()
	if _is_waiting_input:
		_input_field.text = text
		_voice_status.text = "识别完成：" + text


func _on_voice_failed(error: String) -> void:
	_refresh_mic_button()
	_voice_status.text = "识别失败：" + error


func _on_voice_status(msg: String) -> void:
	_voice_status.text = msg


# ===== 关卡完成 =====

func _finish_level() -> void:
	var stats := PolitenessScoring.calculate_scenario_statistics(_current_turns)
	var avg_level: float = float(stats.get("average_level", 0.0))

	_current_level_result["average_level"] = avg_level
	_current_level_result["stars"] = 1 if avg_level >= 3.0 else 0
	_current_level_result["turns"] = _current_turns.duplicate(true)
	_current_level_result["statistics"] = stats
	_section_results.append(_current_level_result.duplicate(true))

	var scenario_id: String = "L%02d" % (_current_level + 1)
	AssessmentGameManager.record_scenario_result(scenario_id, _current_level_result.duplicate(true))
	AssessmentGameManager.advance_scenario()

	# 关卡结束，解锁状态
	_level_in_progress = false
	_guide_npc.set_interacting(false)

	if _current_level + 1 < LEVELS.size():
		# NPC 等待玩家触发下一关，届时会走到新位置
		_npc_ready = false
		_guide_npc.set_active(false)
		var next_area: String = LEVEL_AREAS[_current_level + 1]
		_hint_label.text = "第%d关完成！下一关：%s，请稍候……" % [_current_level + 1, next_area]
		var tw := create_tween()
		tw.tween_interval(1.5)
		tw.tween_callback(func() -> void:
			_current_level = _current_level + 1
			_guide_npc.set_active(true)
			_npc_ready = true
			_player_node.set_can_move(true)
			_hint_label.text = "按 E 键开始第%d关：%s" % [_current_level + 1, LEVELS[_current_level]["name"]]
		)
	else:
		_complete_section()


func _complete_section() -> void:
	_player_node.set_can_move(false)
	_guide_npc.set_active(false)
	_hint_label.text = "恭喜你集齐全部6枚星章！小屋的大门打开了！"

	# 大门打开动画
	var door: Sprite2D = _scene_object_sprites[5] if _scene_object_sprites.size() > 5 else null
	if door:
		door.visible = true
		var glow := ColorRect.new()
		glow.color = Color(1, 0.95, 0.6, 0)
		glow.set_anchors_preset(Control.PRESET_FULL_RECT)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow.z_index = 10
		$UI.add_child(glow)

		# 第一组：并行播放大门缩放、亮度、光晕渐入
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(door, "scale", door.scale * 1.8, 1.2).set_ease(Tween.EASE_OUT)
		tw.tween_property(door, "modulate", Color(1.5, 1.4, 1.2, 1.0), 1.2)
		tw.tween_property(glow, "color:a", 0.7, 1.0)
		# 第二组：顺序播放 — 停顿 → 光晕淡出 → 释放
		tw.chain()
		tw.set_parallel(false)
		tw.tween_interval(0.5)
		tw.tween_property(glow, "color:a", 0.0, 0.3)
		tw.tween_callback(glow.queue_free)
		await tw.finished

	var tween := create_tween()
	tween.tween_property(_transition, "modulate:a", 1.0, 0.5)
	await tween.finished
	AssessmentGameManager.start_sunshine_market()
	await AssessmentFlowHost.go_to_sunshine_market()


# ===== 小游戏 =====

func _clear_minigame_layer() -> void:
	for child in _minigame_layer.get_children():
		child.queue_free()


# 第三关：宝箱小游戏 — 点击宝箱，抖动后卡住
func _handle_minigame_treasure() -> void:
	_clear_minigame_layer()
	_dialogue_box.visible = false
	var vp := get_viewport().get_visible_rect().size

	# 宝箱图片
	var tex := load("res://assets/minigames/treasure_box.jpg") as Texture2D
	var box_img := TextureRect.new()
	if tex:
		box_img.texture = tex
	box_img.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	box_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box_img.custom_minimum_size = Vector2(250, 250)
	box_img.position = Vector2(vp.x * 0.5 - 125, vp.y * 0.5 - 140)
	_minigame_layer.add_child(box_img)

	# 透明点击按钮覆盖在图片上
	var box := Button.new()
	box.custom_minimum_size = Vector2(250, 250)
	box.position = Vector2(vp.x * 0.5 - 125, vp.y * 0.5 - 140)
	box.flat = true
	_minigame_layer.add_child(box)

	# 提示
	var tip := Label.new()
	tip.text = "点击宝箱，试试打开它！"
	tip.add_theme_font_size_override("font_size", 28)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.position = Vector2(vp.x * 0.5 - 200, vp.y * 0.5 + 120)
	tip.size = Vector2(400, 50)
	_minigame_layer.add_child(tip)

	_hint_label.text = "点击宝箱试试打开它！"

	box.pressed.connect(func() -> void:
		box.disabled = true
		tip.text = "宝箱卡住了……"
		var orig := box_img.position
		var tw := create_tween()
		for i in 3:
			tw.tween_property(box_img, "position", orig + Vector2(15, 0), 0.06)
			tw.tween_property(box_img, "position", orig + Vector2(-15, 0), 0.06)
		tw.tween_property(box_img, "position", orig, 0.06)
		await get_tree().create_timer(0.8).timeout
		_clear_minigame_layer()
		_hint_label.text = ""
		_advance_step()
	)


# 第四关：积木小游戏 — 点击放置最后一块，塔晃动后倒塌
func _handle_minigame_blocks() -> void:
	_clear_minigame_layer()
	_dialogue_box.visible = false
	var vp := get_viewport().get_visible_rect().size
	var cx := vp.x * 0.5
	var cy := vp.y * 0.5

	# 积木图片
	var tex := load("res://assets/minigames/building_blocks.jpg") as Texture2D
	var blocks_img := TextureRect.new()
	if tex:
		blocks_img.texture = tex
	blocks_img.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	blocks_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	blocks_img.custom_minimum_size = Vector2(300, 300)
	blocks_img.position = Vector2(cx - 150, cy - 180)
	_minigame_layer.add_child(blocks_img)

	# 提示
	var tip := Label.new()
	tip.text = "点击按钮，放下最后一块积木！"
	tip.add_theme_font_size_override("font_size", 28)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.position = Vector2(cx - 200, cy + 130)
	tip.size = Vector2(400, 50)
	_minigame_layer.add_child(tip)

	# 放置按钮
	var place_btn := Button.new()
	place_btn.text = "放下积木"
	place_btn.add_theme_font_size_override("font_size", 24)
	place_btn.custom_minimum_size = Vector2(160, 44)
	place_btn.position = Vector2(cx - 80, cy + 180)
	_minigame_layer.add_child(place_btn)

	_hint_label.text = "点击「放下积木」按钮，放置最后一块！"

	place_btn.pressed.connect(func() -> void:
		place_btn.disabled = true
		tip.text = ""

		await get_tree().create_timer(0.3).timeout

		# 积木塔晃动后倒塌
		var orig := blocks_img.position
		var orig_rot := blocks_img.rotation
		var tw := create_tween()
		# 晃动
		tw.tween_property(blocks_img, "position", orig + Vector2(8, 0), 0.08)
		tw.tween_property(blocks_img, "position", orig + Vector2(-8, 0), 0.08)
		tw.tween_property(blocks_img, "position", orig, 0.08)
		tw.tween_interval(0.2)
		# 倒塌
		tw.tween_property(blocks_img, "rotation", orig_rot + 0.4, 0.4)
		tw.parallel().tween_property(blocks_img, "position", orig + Vector2(60, 60), 0.4)
		tw.parallel().tween_property(blocks_img, "modulate:a", 0.3, 0.4)

		await get_tree().create_timer(1.0).timeout
		_clear_minigame_layer()
		_hint_label.text = ""
		_advance_step()
	)


# 第五关：绘本小游戏 — 翻阅绘本页面
func _handle_minigame_book() -> void:
	_clear_minigame_layer()
	_dialogue_box.visible = false
	var vp := get_viewport().get_visible_rect().size
	var cx := vp.x * 0.5
	var cy := vp.y * 0.5

	# 背景面板
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 420)
	panel.position = Vector2(cx - 310, cy - 210)
	_minigame_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	# 绘本图片
	var tex := load("res://assets/minigames/picture_book.jpg") as Texture2D
	var book_img := TextureRect.new()
	if tex:
		book_img.texture = tex
	book_img.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	book_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	book_img.custom_minimum_size = Vector2(560, 250)
	vbox.add_child(book_img)

	# 页面文字
	_book_pages = [
		"从前有一座礼貌小镇……\n镇上的小朋友都很有礼貌。",
		"有一天，小礼来到了礼貌小屋，\n遇到了一位小客人。",
		"他们一起闯关、一起玩耍，\n度过了开心的一天！",
	]
	_book_page_idx = 0

	_book_page_label = Label.new()
	_book_page_label.text = _book_pages[0]
	_book_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_book_page_label.add_theme_font_size_override("font_size", 24)
	_book_page_label.custom_minimum_size = Vector2(560, 60)
	vbox.add_child(_book_page_label)

	_book_page_hint = Label.new()
	_book_page_hint.text = "第 1 / %d 页" % _book_pages.size()
	_book_page_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_book_page_hint.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_book_page_hint)

	_book_flip_btn = Button.new()
	_book_flip_btn.text = "翻页 →"
	_book_flip_btn.add_theme_font_size_override("font_size", 24)
	vbox.add_child(_book_flip_btn)

	_hint_label.text = "翻阅绘本看看吧！每翻一页都有新故事哦～"

	_book_flip_btn.pressed.connect(_on_book_flip_pressed)


func _on_book_flip_pressed() -> void:
	if _book_flip_btn == null or _book_flip_btn.disabled:
		return
	_book_page_idx += 1
	if _book_page_idx < _book_pages.size():
		_book_page_label.text = _book_pages[_book_page_idx]
		_book_page_hint.text = "第 %d / %d 页" % [_book_page_idx + 1, _book_pages.size()]
		if _book_page_idx == _book_pages.size() - 1:
			_book_flip_btn.text = "合上绘本"
	else:
		_book_flip_btn.disabled = true
		_book_flip_btn.text = "完成"
		_book_page_label.text = "（绘本看完了）"
		_book_page_hint.text = ""
		await get_tree().create_timer(1.0).timeout
		_clear_minigame_layer()
		_hint_label.text = ""
		_advance_step()


# ===== 辅助方法 =====

func _advance_step() -> void:
	_current_step += 1
	_execute_current_step()


func _get_ai_name() -> String:
	if _ai_type == AssessmentGameManager.AiType.FRIEND:
		return FRIEND_NAME
	return TOOL_NAME


func _get_ai_text(step: Dictionary) -> String:
	var text: String = ""
	if _ai_type == AssessmentGameManager.AiType.FRIEND:
		text = step.get("friend", "")
	else:
		text = step.get("tool", "")
	return text.replace("{name}", _child_nickname)


func _show_portrait() -> void:
	var look_index: int = 0 if _ai_type == AssessmentGameManager.AiType.FRIEND else 5
	var path := "res://assets/characters/portraits/look_%02d.png" % look_index
	var tex := load(path) as Texture2D
	if tex:
		_dialogue_box.set_portrait(tex)


func _check_agree(text: String) -> bool:
	var lower := text.to_lower()
	for kw in ["好", "可以", "行", "愿意", "给", "分享", "一起", "嗯", "好呀", "好啊"]:
		if lower.contains(kw):
			return true
	return false


func _check_bye(text: String) -> bool:
	var lower := text.to_lower()
	for kw in ["再见", "拜拜", "bye", "晚安", "回头见", "走了", "拜"]:
		if lower.contains(kw):
			return true
	return false
