extends Node
## 测评游戏管理器 (Autoload)
## 管理全局测评状态、儿童信息、会话数据

signal child_registered(child_info: Dictionary)
signal session_started(session: Dictionary)
signal session_completed(results: Dictionary)
signal turn_recorded(turn: Dictionary)
signal scenario_completed(scenario_id: String, result: Dictionary)
signal section_completed(section: int)

# 测评阶段
enum AssessmentSection {
	REGISTRATION,
	WARMUP,
	POLITENESS_HOUSE,  # 板块一
	SUNSHINE_MARKET,   # 板块二
	RESULTS
}

# AI 类型
enum AiType {
	FRIEND,  # 朋友型
	TOOL     # 工具型
}

# 当前状态
var _child_info: Dictionary = {}
var _current_section: AssessmentSection = AssessmentSection.REGISTRATION
var _ai_type: AiType = AiType.FRIEND
var _session_id: String = ""
var _session_start_time: int = 0
var _turns: Array[Dictionary] = []
var _scenario_results: Dictionary = {}
var _warmup_baseline: Dictionary = {}
var _current_scenario_index: int = 0
var _total_stars: int = 0

# 服务器API客户端
var _server_api: Node
const _ServerAPIScript = preload("res://assessment/ServerAPI.gd")

# API 配置
var _api_config: Dictionary = {
	"endpoint": "https://api.deepseek.com/chat/completions",
	"api_key": "",
	"model": "deepseek-chat"
}

# 获取单例
static var _instance: AssessmentGameManager = null

func _ready() -> void:
	_instance = self
	_load_api_config()
	_server_api = _ServerAPIScript.new()
	add_child(_server_api)

static func get_instance() -> AssessmentGameManager:
	return _instance

## 注册儿童信息
func register_child(info: Dictionary) -> void:
	_child_info = {
		"nickname": String(info.get("nickname", "")),
		"age": int(info.get("age", 5)),
		"gender": String(info.get("gender", "male")),
		"school": String(info.get("school", "")),
		"class_name": String(info.get("class_name", "")),
		"has_language_disorder": bool(info.get("has_language_disorder", false)),
		"device_usage_level": String(info.get("device_usage_level", "normal"))
	}
	_session_id = "session_%d_%d" % [Time.get_unix_time_from_system(), Time.get_ticks_msec()]
	_session_start_time = Time.get_ticks_msec()
	_turns.clear()
	_scenario_results.clear()
	_total_stars = 0
	child_registered.emit(_child_info)
	print("[AssessmentGameManager] 儿童已注册: %s, 会话ID: %s" % [_child_info.nickname, _session_id])

## 开始预热阶段
func start_warmup() -> void:
	_current_section = AssessmentSection.WARMUP
	_current_scenario_index = 0
	session_started.emit({
		"session_id": _session_id,
		"child": _child_info,
		"section": _current_section
	})

## 设置预热基线
func set_warmup_baseline(baseline: Dictionary) -> void:
	_warmup_baseline = baseline

## 开始板块一（礼貌小屋）
func start_politeness_house() -> void:
	_current_section = AssessmentSection.POLITENESS_HOUSE
	_current_scenario_index = 0

## 开始板块二（阳光超市）
func start_sunshine_market() -> void:
	_current_section = AssessmentSection.SUNSHINE_MARKET
	_current_scenario_index = 0
	section_completed.emit(AssessmentSection.POLITENESS_HOUSE)

## 记录交互轮次
func record_turn(turn: Dictionary) -> String:
	var turn_id := "%s_turn_%04d" % [_session_id, _turns.size() + 1]
	turn["turn_id"] = turn_id
	turn["timestamp"] = Time.get_ticks_msec()
	turn["session_id"] = _session_id
	turn["section"] = _current_section
	turn["scenario_index"] = _current_scenario_index
	_turns.append(turn)
	turn_recorded.emit(turn)
	return turn_id

## 按话轮ID回写异步评分，避免额外创建重复的“child_score”话轮。
func update_turn(turn_id: String, patch: Dictionary) -> bool:
	for index in range(_turns.size() - 1, -1, -1):
		if String(_turns[index].get("turn_id", "")) != turn_id:
			continue
		for key in patch.keys():
			_turns[index][key] = patch[key]
		turn_recorded.emit(_turns[index])
		return true
	return false

## 记录场景结果
func record_scenario_result(scenario_id: String, result: Dictionary) -> void:
	_scenario_results[scenario_id] = result
	if result.has("stars"):
		_total_stars += int(result["stars"])
	scenario_completed.emit(scenario_id, result)
	print("[AssessmentGameManager] 场景完成: %s, 星章: %d" % [scenario_id, int(result.get("stars", 0))])

## 推进到下一个场景
func advance_scenario() -> void:
	_current_scenario_index += 1

## 完成测评
func complete_assessment(final_results: Dictionary) -> void:
	_current_section = AssessmentSection.RESULTS
	section_completed.emit(AssessmentSection.SUNSHINE_MARKET)
	session_completed.emit(final_results)
	# 保存到本地JSON
	AssessmentStorage.save_session_results(_session_id, _child_info, _turns, _scenario_results, final_results)
	# 上传到服务器数据库
	_upload_to_server(final_results)

## 获取当前儿童信息
func get_child_info() -> Dictionary:
	return _child_info

## 获取当前阶段
func get_current_section() -> AssessmentSection:
	return _current_section

## 获取 AI 类型
func get_ai_type() -> AiType:
	return _ai_type

## 设置 AI 类型
func set_ai_type(ai_type: AiType) -> void:
	_ai_type = ai_type
	_child_info["ai_type"] = get_ai_type_name()

## 获取所有轮次记录
func get_all_turns() -> Array[Dictionary]:
	return _turns

## 获取场景结果
func get_scenario_results() -> Dictionary:
	return _scenario_results

## 获取总星章数
func get_total_stars() -> int:
	return _total_stars

## 获取预热基线
func get_warmup_baseline() -> Dictionary:
	return _warmup_baseline

## 获取当前会话 ID（用于导出报告等）
func get_session_id() -> String:
	return _session_id

## API 配置
func get_api_config() -> Dictionary:
	return _api_config

func set_api_config(config: Dictionary) -> void:
	_api_config = config.duplicate(true)
	_save_api_config()

func is_api_configured() -> bool:
	return not _api_config.get("api_key", "").is_empty()

func _load_api_config() -> void:
	var path := "user://api_config.json"
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_api_config = parsed
			file.close()

func _save_api_config() -> void:
	var path := "user://api_config.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_api_config))
		file.close()

## 获取 AI 类型显示名
func get_ai_type_name() -> String:
	match _ai_type:
		AiType.FRIEND:
			return "朋友型"
		AiType.TOOL:
			return "工具型"
		_:
			return "未知"

## 获取当前阶段显示名
func get_section_name() -> String:
	match _current_section:
		AssessmentSection.REGISTRATION:
			return "注册"
		AssessmentSection.WARMUP:
			return "预热"
		AssessmentSection.POLITENESS_HOUSE:
			return "礼貌小屋"
		AssessmentSection.SUNSHINE_MARKET:
			return "阳光超市"
		AssessmentSection.RESULTS:
			return "结果"
		_:
			return "未知"

## 上传测评数据到服务器数据库
func _upload_to_server(final_results: Dictionary) -> void:
	if not bool(ProjectSettings.get_setting("assessment/server_upload_enabled", false)):
		print("[AssessmentGameManager] 远程上传已关闭，测评数据仅保存在本地")
		return
	var upload_data := {
		"child_info": _child_info,
		"turns": _turns,
		"scenario_results": _scenario_results,
		"final_results": final_results
	}
	_server_api.upload_session_complete(_child_info, _turns, _scenario_results, final_results)
	print("[AssessmentGameManager] 测评数据已发送至服务器 (%d 话轮, %d 场景)" % [_turns.size(), _scenario_results.size()])
