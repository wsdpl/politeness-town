## 板块二 RPG 场景：阳光超市
## 玩家在超市地图中行走，走到各 NPC 旁按 E 交互触发剧情
## 包含故事线一（3个社会距离事件）和故事线二（3个压力递进阶段）
extends Node2D

# ===== 节点路径 =====
@onready var _player: CharacterBody2D = $Player
@onready var _dialogue_box = $UI/DialogueBox
@onready var _input_panel: PanelContainer = $UI/InputPanel
@onready var _input_field: LineEdit = $UI/InputPanel/VBox/InputField
@onready var _send_button: Button = $UI/InputPanel/VBox/HBox/SendButton
@onready var _mic_button: Button = $UI/InputPanel/VBox/HBox/MicButton
@onready var _voice_status: Label = $UI/InputPanel/VBox/VoiceStatus
@onready var _level_label: Label = $UI/LevelLabel
@onready var _progress_bar: ProgressBar = $UI/ProgressBar
@onready var _hint_label: Label = $UI/HintLabel
@onready var _portrait: TextureRect = $UI/Portrait
@onready var _transition: ColorRect = $UI/TransitionRect

# ===== 状态 =====
var _current_event_index: int = 0  # 全局事件索引 0-5（SL1: 0-2, SL2: 0-2/3个阶段×多轮）
var _current_step_index: int = 0
var _current_steps: Array = []
var _is_waiting_input: bool = false
var _is_processing: bool = false
var _section_results: Array = []
var _current_event_result: Dictionary = {}
var _current_turns: Array = []
var _all_npcs: Array[Node] = []

# 故事线状态
var _story_phase: int = 0  # 0=SL1, 1=SL2
var _sl1_event_index: int = 0
var _sl2_phase_index: int = 0
var _sl2_round_index: int = 0

# AI 类型
var _ai_type: int = 0  # AssessmentGameManager.AiType.FRIEND
var _ai_manager: AssessmentAIManager
var _dialogue_messages: Array = []
var _last_child_text: String = ""

# NPC 位置布局（阳光超市室内8个点位）
# SL1: 3个事件 NPC
# SL2: 3个阶段 NPC（推车管理员、贴纸姐姐/竞争者、收银员）
const NPC_LAYOUT := [
	# SL1
	{"pos": Vector2(350, 300), "look": 5, "dir": "down"},   # S1-E1 乐乐（同龄玩伴）
	{"pos": Vector2(800, 500), "look": 6, "dir": "down"},   # S1-E2 草莓老师
	{"pos": Vector2(1200, 700), "look": 7, "dir": "down"},  # S1-E3 陌生阿姨
	# SL2
	{"pos": Vector2(350, 700), "look": 0, "dir": "down"},   # S2-P1 推车管理员（小熊布布形象）
	{"pos": Vector2(800, 300), "look": 1, "dir": "down"},   # S2-P2 贴纸姐姐/竞争者
	{"pos": Vector2(1200, 400), "look": 2, "dir": "down"},  # S2-P3 收银员
]

# 地图边界
const MAP_BOUNDS := Rect2(50, 50, 1400, 750)
const WALL_THICKNESS := 40.0


func _ready() -> void:
	_ai_type = AssessmentGameManager.get_ai_type()
	_ai_manager = AssessmentAIManager.new()
	add_child(_ai_manager)
	_ai_manager.ai_response_received.connect(_on_ai_response)
	_ai_manager.ai_response_error.connect(_on_ai_error)
	_ai_manager.scoring_received.connect(_on_scoring_received)
	_ai_manager.scoring_error.connect(_on_scoring_error)

	_setup_map()
	_setup_npcs()
	_setup_ui()
	_setup_voice_input()
	_start_sl1_event(0)

	# 淡入
	_transition.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(_transition, "modulate:a", 0.0, 0.4)


func _setup_map() -> void:
	# 创建背景层（渲染在 Node2D 之下，不遮挡玩家和NPC）
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	add_child(bg_layer)

	var bg := TextureRect.new()
	bg.texture = load("res://assets/maps/sunshine_market/room_shell.png") as Texture2D
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.modulate = Color(0.85, 0.85, 0.88)
	bg_layer.add_child(bg)

	var shade := ColorRect.new()
	shade.color = Color(0.047, 0.067, 0.09, 0.3)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(shade)

	_create_walls()
	_player.position = Vector2(200, 450)


func _create_walls() -> void:
	var walls_parent := $Walls
	_create_wall(walls_parent, Vector2(MAP_BOUNDS.position.x + MAP_BOUNDS.size.x / 2, MAP_BOUNDS.position.y - WALL_THICKNESS / 2),
		Vector2(MAP_BOUNDS.size.x + WALL_THICKNESS * 2, WALL_THICKNESS))
	_create_wall(walls_parent, Vector2(MAP_BOUNDS.position.x + MAP_BOUNDS.size.x / 2, MAP_BOUNDS.position.y + MAP_BOUNDS.size.y + WALL_THICKNESS / 2),
		Vector2(MAP_BOUNDS.size.x + WALL_THICKNESS * 2, WALL_THICKNESS))
	_create_wall(walls_parent, Vector2(MAP_BOUNDS.position.x - WALL_THICKNESS / 2, MAP_BOUNDS.position.y + MAP_BOUNDS.size.y / 2),
		Vector2(WALL_THICKNESS, MAP_BOUNDS.size.y + WALL_THICKNESS * 2))
	_create_wall(walls_parent, Vector2(MAP_BOUNDS.position.x + MAP_BOUNDS.size.x + WALL_THICKNESS / 2, MAP_BOUNDS.position.y + MAP_BOUNDS.size.y / 2),
		Vector2(WALL_THICKNESS, MAP_BOUNDS.size.y + WALL_THICKNESS * 2))


func _create_wall(parent: Node, pos: Vector2, size: Vector2) -> void:
	var wall := StaticBody2D.new()
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	col.shape = shape
	wall.position = pos
	wall.add_child(col)
	parent.add_child(wall)


func _setup_npcs() -> void:
	var npc_scene := load("res://ui/rpg/RpgNpc.gd")
	for i in range(NPC_LAYOUT.size()):
		var layout: Dictionary = NPC_LAYOUT[i]
		var npc_name := _get_default_npc_name(i)
		var npc := CharacterBody2D.new()
		npc.set_script(npc_scene)
		npc.position = layout.pos
		npc.set("npc_name", npc_name)
		npc.set("npc_id", "NPC_%02d" % (i + 1))
		npc.set("look_index", layout.look)
		npc.set("face_direction", layout.dir)
		npc.set("interact_hint", "按 E 对话")
		$NPCs.add_child(npc)
		_all_npcs.append(npc)
		npc.set_active(false)

	_player.interact_pressed.connect(_on_player_interact)


func _get_default_npc_name(index: int) -> String:
	var names := ["乐乐", "草莓老师", "陌生阿姨", "管理员叔叔", "贴纸姐姐", "收银员阿姨"]
	if index < names.size():
		return names[index]
	return "NPC"


func _setup_ui() -> void:
	# 将主题应用到 UI 层的所有 Control 子节点（Node2D 本身无 theme 属性）
	for child in $UI.get_children():
		if child is Control:
			child.theme = AssessmentUiTheme.theme

	AssessmentUiTheme.apply_primary_button(_send_button)
	AssessmentUiTheme.apply_primary_button(_mic_button)
	_input_panel.add_theme_stylebox_override("panel", AssessmentUiTheme.dialogue_panel_style())

	_dialogue_box.dialogue_finished.connect(_on_dialogue_finished)
	_send_button.pressed.connect(_on_send_pressed)
	_mic_button.pressed.connect(_on_mic_button_pressed)
	_input_panel.visible = false
	_portrait.visible = false
	_dialogue_box.set_portrait(null)

	# 给浮动标签添加底框背景（星露谷风格）
	# HintLabel 使用深色底框，需要亮色文字
	AssessmentUiTheme.apply_light_text(_hint_label)
	AssessmentUiTheme.wrap_label_in_panel(_hint_label, AssessmentUiTheme.tip_panel_style())
	# LevelLabel 使用浅色底框，保持墨色文字
	AssessmentUiTheme.wrap_label_in_panel(_level_label, AssessmentUiTheme.label_panel_style())


func _setup_voice_input() -> void:
	_mic_button.text = "🎤 说话"
	IFlytekSR.recognition_completed.connect(_on_voice_recognized)
	IFlytekSR.recognition_failed.connect(_on_voice_failed)
	IFlytekSR.status_message.connect(_on_voice_status)
	_refresh_mic_button()


func _refresh_mic_button() -> void:
	if IFlytekSR.is_configured():
		_mic_button.disabled = false
		if not IFlytekSR.is_recording() and not IFlytekSR.is_recognizing():
			_mic_button.text = "🎤 说话"
	else:
		_mic_button.disabled = true
		_mic_button.text = "🎤 未配置"


# ============================================================
# 故事线一：社会距离事件
# ============================================================

func _start_sl1_event(index: int) -> void:
	_sl1_event_index = index
	_current_step_index = 0
	_current_turns = []

	var event_data := AssessmentData.get_story_line_1_event_by_index(index)
	if event_data.is_empty():
		_start_sl2()
		return

	var event_name: String = event_data.get("name", "")
	var npc_data: Dictionary = event_data.get("npc", {})
	var npc_name: String = npc_data.get("name", "")
	_current_event_result = {
		"event_id": event_data.get("event_id", ""),
		"name": event_name,
		"turns": [],
		"average_level": 0.0,
		"stars": 0,
	}

	_level_label.text = "故事线一 事件 %d/3：%s" % [index + 1, event_name]
	_progress_bar.value = float(index) / 6.0 * 100.0
	_hint_label.text = "走到「%s」旁边按 E 键对话" % npc_name

	# 更新 NPC 显示名
	if index < 3:
		_all_npcs[index].set("npc_name", npc_name)
		_all_npcs[index].set_active(true)

	# 准备对话步骤
	_current_steps = event_data.get("dialogue_steps", [])


func _on_player_interact(npc: Node) -> void:
	if _is_processing or _is_waiting_input:
		return

	var npc_index := _all_npcs.find(npc)
	if npc_index == -1:
		return

	# 检查是否是当前应交互的 NPC
	if _story_phase == 0 and npc_index != _sl1_event_index:
		return
	if _story_phase == 1 and npc_index != 3 + min(_sl2_phase_index, 2):
		return

	npc.set_interacting(true)
	_player.set_can_move(false)
	_hint_label.text = ""
	_start_current_step()


func _start_current_step() -> void:
	if _current_step_index >= _current_steps.size():
		_finish_current_event()
		return

	var step: Dictionary = _current_steps[_current_step_index]
	var speaker: String = step.get("speaker", "")
	var text: String = step.get("text", "")

	# 在对话框中显示NPC立绘
	var npc_index := _get_current_npc_index()
	if npc_index >= 0 and npc_index < _all_npcs.size():
		var portrait_tex: Texture2D = _all_npcs[npc_index].get_portrait()
		_dialogue_box.set_portrait(portrait_tex)
	else:
		_dialogue_box.set_portrait(null)

	_dialogue_box.show_dialogue(speaker, text, [])
	_is_processing = true


func _get_current_npc_index() -> int:
	if _story_phase == 0:
		return _sl1_event_index
	else:
		return 3 + min(_sl2_phase_index, 2)


func _on_dialogue_finished() -> void:
	_is_processing = false

	if _story_phase == 0:
		# SL1：每步都需要儿童回应
		_is_waiting_input = true
		_dialogue_box.clear()
		_input_panel.visible = true
		_input_field.grab_focus()
		_hint_label.text = "请用语音或文字回答，然后点击发送"
		_refresh_mic_button()
	else:
		# SL2：有 measure_point 的步骤需要回应
		var step: Dictionary = _current_steps[_current_step_index]
		var round_data: Dictionary = step.get("round_data", {})
		var measure_point: String = round_data.get("measure_point", "")
		if measure_point != "":
			_is_waiting_input = true
			_dialogue_box.clear()
			_input_panel.visible = true
			_input_field.grab_focus()
			_hint_label.text = "请用语音或文字回答，然后点击发送"
			_refresh_mic_button()
		else:
			_advance_step()


func _on_send_pressed() -> void:
	if not _is_waiting_input:
		return
	var text := _input_field.text.strip_edges()
	if text == "":
		return
	_input_field.text = ""
	_input_panel.visible = false
	_is_waiting_input = false
	_submit_response(text)


func _submit_response(text: String) -> void:
	var dimension := ""
	var measure_point := ""
	if _story_phase == 0:
		var event_data := AssessmentData.get_story_line_1_event_by_index(_sl1_event_index)
		dimension = "综合礼貌"
		measure_point = "S1-E%d 互动" % (_sl1_event_index + 1)
	else:
		var round_data: Dictionary = _current_steps[_current_step_index].get("round_data", {})
		measure_point = round_data.get("measure_point", "")
		dimension = measure_point

	_last_child_text = text
	AssessmentGameManager.record_turn({
		"speaker": "child",
		"text": text,
		"measure_point": measure_point,
		"dimension": dimension,
		"section": "sunshine_market",
	})
	_current_turns.append({
		"text": text,
		"measure_point": measure_point,
		"dimension": dimension,
		"level": 2,
	})

	_dialogue_messages.append({"role": "user", "content": text})
	_is_processing = true
	_hint_label.text = "正在分析回答..."

	var scene_context := ""
	if _story_phase == 0:
		var event_data := AssessmentData.get_story_line_1_event_by_index(_sl1_event_index)
		scene_context = event_data.get("scene_context", "")
	else:
		var phase_data := AssessmentData.get_story_line_2_phase_by_index(_sl2_phase_index)
		scene_context = phase_data.get("scene_context", "")

	_ai_manager.analyze_politeness(text, dimension, scene_context)
	var system_prompt := _ai_manager.build_dialogue_system_prompt(scene_context)
	_ai_manager.send_dialogue(system_prompt, _dialogue_messages, 0.7)


func _on_scoring_received(result: Dictionary) -> void:
	var level: int = int(result.get("level", 2))
	if _current_turns.size() > 0:
		_current_turns[-1]["level"] = level
		_current_turns[-1]["markers"] = result.get("markers", [])
	AssessmentGameManager.record_turn({
		"speaker": "child_score",
		"text": _last_child_text,
		"score": result,
		"section": "sunshine_market",
	})
	_hint_label.text = "评分完成（等级 %d）" % level


func _on_scoring_error(error: String) -> void:
	if _current_turns.size() > 0:
		_current_turns[-1]["level"] = 2
	_hint_label.text = "评分降级处理"


func _on_ai_response(response: String) -> void:
	_is_processing = false
	_dialogue_messages.append({"role": "assistant", "content": response})
	AssessmentGameManager.record_turn({
		"speaker": "ai",
		"text": response,
		"section": "sunshine_market",
	})
	var npc_name := ""
	if _story_phase == 0:
		var event_data := AssessmentData.get_story_line_1_event_by_index(_sl1_event_index)
		npc_name = event_data.get("npc", {}).get("name", "")
	else:
		var round_data: Dictionary = _current_steps[_current_step_index].get("round_data", {})
		npc_name = round_data.get("npc", {}).get("name", "")

	_dialogue_box.show_dialogue(npc_name, response, [])
	_is_processing = true
	await _dialogue_box.dialogue_finished
	_is_processing = false
	_advance_step()


func _on_ai_error(error: String) -> void:
	_is_processing = false
	var fallback := "你做得很好！继续加油！"
	if _ai_type == AssessmentGameManager.AiType.TOOL:
		fallback = "回答已记录。请继续。"
	var npc_name := "NPC"
	_dialogue_box.show_dialogue(npc_name, fallback, [])
	_is_processing = true
	await _dialogue_box.dialogue_finished
	_is_processing = false
	_advance_step()


func _advance_step() -> void:
	_current_step_index += 1
	if _current_step_index >= _current_steps.size():
		_finish_current_event()
	else:
		_start_current_step()


func _finish_current_event() -> void:
	var stats := PolitenessScoring.calculate_scenario_statistics(_current_turns)
	var avg_level: float = float(stats.get("average_level", 0.0))

	_current_event_result["average_level"] = avg_level
	_current_event_result["stars"] = _level_to_stars(avg_level)
	_current_event_result["turns"] = _current_turns.duplicate(true)
	_current_event_result["statistics"] = stats
	_section_results.append(_current_event_result.duplicate(true))

	# 记录场景结果到全局管理器
	var scenario_id: String = _current_event_result.get("event_id", _current_event_result.get("phase_id", ""))
	AssessmentGameManager.record_scenario_result(scenario_id, _current_event_result.duplicate(true))

	# 当前 NPC 交互结束
	var npc_idx := _get_current_npc_index()
	if npc_idx >= 0 and npc_idx < _all_npcs.size():
		_all_npcs[npc_idx].set_interacting(false)
		_all_npcs[npc_idx].set_active(false)

	_portrait.visible = false
	_dialogue_box.set_portrait(null)

	if _story_phase == 0:
		# SL1 下一个事件
		if _sl1_event_index + 1 < 3:
			_player.set_can_move(true)
			_start_sl1_event(_sl1_event_index + 1)
		else:
			# SL1 完成，进入 SL2
			_story_phase = 1
			_player.set_can_move(true)
			_start_sl2_phase(0)
	else:
		# SL2 下一个阶段
		if _sl2_phase_index + 1 < 3:
			_player.set_can_move(true)
			_start_sl2_phase(_sl2_phase_index + 1)
		else:
			_complete_section()


func _level_to_stars(level: float) -> int:
	if level >= 4.0:
		return 3
	elif level >= 3.0:
		return 2
	elif level >= 2.0:
		return 1
	return 0


# ============================================================
# 故事线二：压力递进购物任务
# ============================================================

func _start_sl2_phase(index: int) -> void:
	_sl2_phase_index = index
	_sl2_round_index = 0
	_current_step_index = 0
	_current_turns = []

	var phase_data := AssessmentData.get_story_line_2_phase_by_index(index)
	if phase_data.is_empty():
		_complete_section()
		return

	var phase_name: String = phase_data.get("name", "")
	var pressure: String = phase_data.get("pressure_level", "")
	_current_event_result = {
		"phase_id": phase_data.get("phase_id", ""),
		"name": phase_name,
		"pressure_level": pressure,
		"turns": [],
		"average_level": 0.0,
		"stars": 0,
	}

	_level_label.text = "故事线二 阶段 %d/3：%s（压力：%s）" % [index + 1, phase_name, pressure]
	_progress_bar.value = (3.0 + float(index)) / 6.0 * 100.0

	# 激活对应 NPC
	var npc_idx: int = 3 + min(index, 2)
	if npc_idx < _all_npcs.size():
		var rounds: Array = phase_data.get("rounds", [])
		if rounds.size() > 0:
			var first_npc: Dictionary = rounds[0].get("npc", {})
			var npc_name: String = first_npc.get("name", "NPC")
			_all_npcs[npc_idx].set("npc_name", npc_name)
		_all_npcs[npc_idx].set_active(true)
	_hint_label.text = "走到「%s」旁边按 E 键开始任务" % _all_npcs[npc_idx].get("npc_name")

	# 准备步骤（每轮作为一个步骤）
	_current_steps = []
	for round_data in phase_data.get("rounds", []):
		_current_steps.append({
			"speaker": round_data.get("npc", {}).get("name", ""),
			"text": round_data.get("ai_prompt_friend" if _ai_type == AssessmentGameManager.AiType.FRIEND else "ai_prompt_tool", ""),
			"round_data": round_data,
		})


# ============================================================
# 完成
# ============================================================

func _complete_section() -> void:
	_player.set_can_move(false)
	_hint_label.text = "测评完成！正在生成报告..."

	# 构建最终结果
	var final_results := _build_final_results()
	AssessmentGameManager.complete_assessment(final_results)

	# 淡出后切换场景
	var tween := create_tween()
	tween.tween_property(_transition, "modulate:a", 1.0, 0.5)
	await tween.finished
	await AssessmentFlowHost.go_to_results()


func _build_final_results() -> Dictionary:
	# 从 AssessmentGameManager 获取所有场景结果
	var all_scenarios := AssessmentGameManager.get_scenario_results()
	var all_turns := AssessmentGameManager.get_all_turns()

	# 使用 PolitenessScoring 生成雷达数据
	var scenario_results_array: Array = []
	for key in all_scenarios.keys():
		scenario_results_array.append(all_scenarios[key])

	var radar_data := PolitenessScoring.generate_radar_data(scenario_results_array)
	var total_score := 0.0
	var count := 0
	for dim in radar_data.get("dimensions", {}).values():
		total_score += float(dim.get("average_level", 0))
		count += 1
	var avg_score: float = total_score / max(count, 1)

	return {
		"total_score": avg_score,
		"radar_data": radar_data,
		"scenario_results": all_scenarios,
		"all_turns": all_turns,
		"total_stars": AssessmentGameManager.get_total_stars(),
	}


# ===== 语音识别回调 =====
func _on_voice_recognized(text: String) -> void:
	_refresh_mic_button()
	if _is_waiting_input:
		_input_field.text = text
		_voice_status.text = "识别完成"
		_on_send_pressed()


func _on_voice_failed(error: String) -> void:
	_refresh_mic_button()
	_voice_status.text = "识别失败: " + error


func _on_voice_status(msg: String) -> void:
	_voice_status.text = msg


func _on_mic_button_pressed() -> void:
	if not IFlytekSR.is_configured():
		_voice_status.text = "讯飞API未配置，请在设置页面填写"
		return
	if IFlytekSR.is_recognizing():
		_voice_status.text = "正在识别中，请稍候……"
		return
	if IFlytekSR.is_recording():
		_mic_button.text = "🎤 识别中..."
		IFlytekSR.stop_and_recognize()
	else:
		IFlytekSR.start_recording()
		_mic_button.text = "⛔ 停止录音"
		_voice_status.text = "正在录音…再次点击停止并识别"
