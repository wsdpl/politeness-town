class_name AssessmentAIManager
extends Node
## 礼貌测评系统 AI 对话管理器
## 通过 HTTPRequest 调用 OpenAI 兼容 API（主要支持 DeepSeek），
## 提供两种调用模式：
##   1. 纯文本对话模式 —— 发送 system prompt + messages，获取自然语言回复
##   2. JSON 分析模式    —— 发送儿童回应文本，获取礼貌等级评分 JSON
##
## API 配置默认从 AssessmentGameManager autoload 获取，也可通过
## set_api_config() 手动覆盖。

# ---- 信号 ----

## 对话模式收到文本回复时触发
signal ai_response_received(text: String)

## 对话模式发生错误时触发
signal ai_response_error(error: String)

## 分析模式收到评分结果时触发
## result: {"level": 1-5, "markers": [String], "description": String, "strategy": String}
signal scoring_received(result: Dictionary)

## 分析模式发生错误时触发
signal scoring_error(error: String)


# ---- 常量 ----

const DEFAULT_TIMEOUT_SECONDS := 30.0
const DEFAULT_DIALOGUE_MAX_TOKENS := 512
const DEFAULT_SCORING_MAX_TOKENS := 512
const DEFAULT_DIALOGUE_TEMPERATURE := 0.8
const DEFAULT_SCORING_TEMPERATURE := 0.2

const DEFAULT_ENDPOINT := "https://api.deepseek.com/chat/completions"
const DEFAULT_MODEL := "deepseek-chat"

# 请求模式（内部使用）
enum _RequestMode {
	DIALOGUE,
	SCORING,
}

# 朋友型 AI 角色 prompt 模板
const FRIEND_SYSTEM_PROMPT_TEMPLATE := (
	"你是一个温暖友好的向导，名叫小礼。你正在陪一个{age}岁的儿童进行礼貌闯关游戏。"
	+ "请用亲切、鼓励的语气与儿童对话，使用儿童昵称{nickname}，"
	+ "多用情感化表达（如'哇''真好''我们一起吧'）。"
	+ "当前场景：{scenario_context}。请根据儿童的回应自然回复，控制在2-3句话以内。"
)

# 工具型 AI 角色 prompt 模板
const TOOL_SYSTEM_PROMPT_TEMPLATE := (
	"你是小礼，一个任务向导。你正在执行儿童礼貌测评任务。"
	+ "请用简洁、任务导向的语气与儿童对话。"
	+ "当前场景：{scenario_context}。请根据儿童的回应简洁回复，控制在2-3句话以内。"
)

# 礼貌分析 prompt 模板（包含五级策略编码标准与礼貌标记词库）
const SCORING_SYSTEM_PROMPT_TEMPLATE := (
	"你是一个儿童礼貌语言分析专家。请分析以下儿童回应的礼貌等级。\n"
	+ "五级策略编码：1=沉默/无回应，2=直白无修饰，3=消极礼貌(基本礼貌词)，"
	+ "4=积极礼貌+称呼，5=复合策略。\n"
	+ "礼貌标记词库：请、谢谢、不客气、对不起、没关系、您好、你好、再见、"
	+ "麻烦、劳驾、可以吗、好吗、谢谢您、请问、抱歉、打扰了、辛苦了。\n"
	+ "礼貌维度：{dimension}\n"
	+ "场景上下文：{scenario_context}\n"
	+ "儿童回应：{child_response}\n"
	+ '请返回JSON：{"level": 1-5, "markers": ["识别到的礼貌标记词"], '
	+ '"description": "分析说明", "strategy": "策略类型"}'
)


# ---- 内部状态 ----

# API 配置
var _api_config: Dictionary = {
	"endpoint": DEFAULT_ENDPOINT,
	"api_key": "",
	"model": DEFAULT_MODEL,
}

# 是否被 set_api_config() 手动覆盖（覆盖后不再从 AssessmentGameManager 刷新）
var _config_overridden: bool = false

# 活跃请求上下文：HTTPRequest 实例 -> { "mode": _RequestMode }
var _active_requests: Dictionary = {}


# ---- 生命周期 ----

func _ready() -> void:
	_refresh_config_from_manager()


# ============================================================
#  核心公开方法
# ============================================================

## 发送对话请求到 LLM API（纯文本回复模式）。
## [param system_prompt] 系统提示词，应包含当前 AI 类型的角色设定
## [param messages] 对话消息，格式: [{"role": "user/assistant/system", "content": "text"}]
## [param temperature] 采样温度，默认 0.8
## 回调通过 [signal ai_response_received] / [signal ai_response_error] 信号返回。
func send_dialogue(
	system_prompt: String,
	messages: Array,
	temperature: float = DEFAULT_DIALOGUE_TEMPERATURE
) -> void:
	if not is_ready():
		var err := _missing_config_error()
		push_error("[AssessmentAIManager] %s" % err)
		ai_response_error.emit(err)
		return

	if system_prompt.strip_edges().is_empty():
		var err := "system_prompt 不能为空"
		push_error("[AssessmentAIManager] %s" % err)
		ai_response_error.emit(err)
		return

	if messages.is_empty():
		var err := "messages 不能为空"
		push_error("[AssessmentAIManager] %s" % err)
		ai_response_error.emit(err)
		return

	# 在对话历史前插入 system 消息
	var full_messages: Array = [{"role": "system", "content": system_prompt}]
	full_messages.append_array(messages)

	var body := {
		"model": String(_api_config.get("model", DEFAULT_MODEL)),
		"messages": full_messages,
		"temperature": temperature,
		"max_tokens": int(_api_config.get("dialogue_max_tokens", DEFAULT_DIALOGUE_MAX_TOKENS)),
		"stream": false,
	}
	# 对话模式不强制 JSON 输出
	_send_request(body, _RequestMode.DIALOGUE)


## 分析儿童回应的礼貌等级（JSON 分析模式）。
## [param child_response] 儿童的实际回应文本
## [param dimension] 礼貌维度（如"请求""致谢""道歉"等）
## [param scenario_context] 当前场景上下文描述
## 返回 JSON 结构: {"level": 1-5, "markers": [String], "description": String, "strategy": String}
## 回调通过 [signal scoring_received] / [signal scoring_error] 信号返回。
func analyze_politeness(
	child_response: String,
	dimension: String,
	scenario_context: String
) -> void:
	if not is_ready():
		var err := _missing_config_error()
		push_error("[AssessmentAIManager] %s" % err)
		scoring_error.emit(err)
		return

	var system_prompt := build_scoring_system_prompt(
		child_response, dimension, scenario_context
	)

	var body := {
		"model": String(_api_config.get("model", DEFAULT_MODEL)),
		"messages": [
			{"role": "system", "content": system_prompt},
			{"role": "user", "content": "请分析并返回 JSON。"},
		],
		"temperature": DEFAULT_SCORING_TEMPERATURE,
		"max_tokens": int(_api_config.get("scoring_max_tokens", DEFAULT_SCORING_MAX_TOKENS)),
		"stream": false,
		# 分析模式强制 JSON 输出
		"response_format": {"type": "json_object"},
	}
	_send_request(body, _RequestMode.SCORING)


## 设置 API 配置（手动覆盖，覆盖后不再从 AssessmentGameManager 刷新）。
## [param config] {"endpoint": "...", "api_key": "...", "model": "..."}
func set_api_config(config: Dictionary) -> void:
	_api_config = {
		"endpoint": String(config.get("endpoint", DEFAULT_ENDPOINT)),
		"api_key": String(config.get("api_key", "")),
		"model": String(config.get("model", DEFAULT_MODEL)),
	}
	if config.has("dialogue_max_tokens"):
		_api_config["dialogue_max_tokens"] = int(config["dialogue_max_tokens"])
	if config.has("scoring_max_tokens"):
		_api_config["scoring_max_tokens"] = int(config["scoring_max_tokens"])
	_config_overridden = true
	print("[AssessmentAIManager] API 配置已手动设置: endpoint=%s, model=%s" % [
		_api_config.get("endpoint", ""), _api_config.get("model", "")
	])


## 检查 API 配置是否完整（endpoint、api_key、model 均非空）。
func is_ready() -> bool:
	if not _config_overridden:
		_refresh_config_from_manager()
	var endpoint := String(_api_config.get("endpoint", "")).strip_edges()
	var api_key := String(_api_config.get("api_key", "")).strip_edges()
	var model := String(_api_config.get("model", "")).strip_edges()
	return not endpoint.is_empty() and not api_key.is_empty() and not model.is_empty()


# ============================================================
#  System Prompt 构建辅助方法
# ============================================================

## 根据当前 AI 类型（从 AssessmentGameManager 获取）构建对话 system prompt。
func build_dialogue_system_prompt(scenario_context: String) -> String:
	var manager := _get_game_manager()
	var ai_type := 0 # 默认朋友型 (AssessmentGameManager.AiType.FRIEND == 0)
	if manager != null and manager.has_method("get_ai_type"):
		ai_type = int(manager.get_ai_type())
	# AssessmentGameManager.AiType.TOOL == 1
	if ai_type == 1:
		return build_tool_system_prompt(scenario_context)
	return build_friend_system_prompt(scenario_context)


## 构建朋友型 AI 角色 system prompt。
func build_friend_system_prompt(scenario_context: String) -> String:
	var age := 5
	var nickname := "小朋友"
	var manager := _get_game_manager()
	if manager != null and manager.has_method("get_child_info"):
		var child_info: Variant = manager.get_child_info()
		if child_info is Dictionary:
			age = int((child_info as Dictionary).get("age", 5))
			nickname = String((child_info as Dictionary).get("nickname", "小朋友"))
			if nickname.strip_edges().is_empty():
				nickname = "小朋友"
	var prompt := FRIEND_SYSTEM_PROMPT_TEMPLATE.replace("{age}", str(age))
	prompt = prompt.replace("{nickname}", nickname)
	prompt = prompt.replace("{scenario_context}", scenario_context)
	return prompt


## 构建工具型 AI 角色 system prompt。
func build_tool_system_prompt(scenario_context: String) -> String:
	return TOOL_SYSTEM_PROMPT_TEMPLATE.replace("{scenario_context}", scenario_context)


## 构建礼貌分析 system prompt（含五级策略编码标准与礼貌标记词库）。
func build_scoring_system_prompt(
	child_response: String,
	dimension: String,
	scenario_context: String
) -> String:
	var prompt := SCORING_SYSTEM_PROMPT_TEMPLATE.replace("{dimension}", dimension)
	prompt = prompt.replace("{scenario_context}", scenario_context)
	prompt = prompt.replace("{child_response}", child_response)
	return prompt


# ============================================================
#  内部：HTTP 请求与响应处理
# ============================================================

## 发送 HTTP 请求到 LLM API。
func _send_request(body: Dictionary, mode: _RequestMode) -> void:
	if not _config_overridden:
		_refresh_config_from_manager()
	var endpoint := String(_api_config.get("endpoint", DEFAULT_ENDPOINT))
	var api_key := String(_api_config.get("api_key", ""))

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
	])
	if not api_key.is_empty():
		headers.append("Authorization: Bearer %s" % api_key)

	var http_request := HTTPRequest.new()
	http_request.timeout = DEFAULT_TIMEOUT_SECONDS
	# 使用系统 CA 证书增强 HTTPS 安全性
	var system_ca_pem := OS.get_system_ca_certificates()
	if not system_ca_pem.is_empty():
		var system_ca := X509Certificate.new()
		if system_ca.load_from_string(system_ca_pem) == OK:
			http_request.set_tls_options(TLSOptions.client(system_ca))
	add_child(http_request)

	# 记录请求上下文，用于响应分发
	_active_requests[http_request] = {"mode": int(mode)}
	http_request.request_completed.connect(
		_on_request_completed.bind(http_request),
		CONNECT_ONE_SHOT,
	)

	var error := http_request.request(
		endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(body)
	)
	if error != OK:
		_active_requests.erase(http_request)
		http_request.queue_free()
		var err_msg := "请求启动失败：%s" % error_string(error)
		push_error("[AssessmentAIManager] %s" % err_msg)
		_emit_error(mode, err_msg)
		return

	print("[AssessmentAIManager] 已发送 %s 请求到 %s" % [
		"对话" if mode == _RequestMode.DIALOGUE else "分析", endpoint
	])


## HTTPRequest 请求完成回调。
func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	http_request: HTTPRequest
) -> void:
	# 取出并清理请求上下文
	var context_value: Variant = _active_requests.get(http_request, null)
	_active_requests.erase(http_request)
	if is_instance_valid(http_request):
		http_request.queue_free()

	var mode: int = _RequestMode.DIALOGUE
	if context_value is Dictionary:
		mode = int((context_value as Dictionary).get("mode", _RequestMode.DIALOGUE))

	# ---- 网络层错误 ----
	if result != HTTPRequest.RESULT_SUCCESS:
		var net_err := _network_error_text(result)
		push_error("[AssessmentAIManager] %s" % net_err)
		_emit_error(mode, net_err)
		return

	# ---- HTTP 状态码错误 ----
	if response_code < 200 or response_code >= 300:
		var body_text := body.get_string_from_utf8()
		var api_err := _extract_api_error(body_text, response_code)
		push_error("[AssessmentAIManager] %s" % api_err)
		_emit_error(mode, api_err)
		return

	# ---- 解析响应体 ----
	var body_text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(body_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		var err := "API 返回的内容不是合法 JSON"
		push_error("[AssessmentAIManager] %s" % err)
		_emit_error(mode, err)
		return

	var response_dict := parsed as Dictionary
	var choices: Variant = response_dict.get("choices")
	if typeof(choices) != TYPE_ARRAY or (choices as Array).is_empty():
		var err := "API 返回缺少 choices"
		push_error("[AssessmentAIManager] %s" % err)
		_emit_error(mode, err)
		return

	var choice: Variant = (choices as Array)[0]
	if typeof(choice) != TYPE_DICTIONARY:
		var err := "API 返回的 choice 格式无效"
		push_error("[AssessmentAIManager] %s" % err)
		_emit_error(mode, err)
		return

	var choice_dict := choice as Dictionary
	# 检查是否因达到输出上限被截断
	var finish_reason := String(choice_dict.get("finish_reason", ""))
	if finish_reason == "length":
		var err := "模型回答因达到输出上限而被截断"
		push_error("[AssessmentAIManager] %s" % err)
		_emit_error(mode, err)
		return

	var message_value: Variant = choice_dict.get("message")
	if typeof(message_value) != TYPE_DICTIONARY:
		var err := "API 返回缺少 message"
		push_error("[AssessmentAIManager] %s" % err)
		_emit_error(mode, err)
		return

	var content := String((message_value as Dictionary).get("content", "")).strip_edges()
	if content.is_empty():
		var err := "API 返回了空内容"
		push_error("[AssessmentAIManager] %s" % err)
		_emit_error(mode, err)
		return

	# ---- 根据模式分发结果 ----
	if mode == _RequestMode.DIALOGUE:
		ai_response_received.emit(content)
	else:
		_handle_scoring_response(content)


## 处理分析模式的响应内容，解析 JSON 并规范化后通过信号返回。
func _handle_scoring_response(content: String) -> void:
	var result: Variant = _parse_json_content(content)
	if typeof(result) != TYPE_DICTIONARY:
		var err := "无法解析礼貌评分 JSON：%s" % content.left(120)
		push_error("[AssessmentAIManager] %s" % err)
		scoring_error.emit(err)
		return
	var scoring := _normalize_scoring_result(result as Dictionary)
	print("[AssessmentAIManager] 礼貌评分完成: level=%d, markers=%s" % [
		scoring.get("level", 0), scoring.get("markers", [])
	])
	scoring_received.emit(scoring)


## 尝试从模型返回内容中解析 JSON。
## 兼容直接 JSON、markdown 代码块包裹、以及前后多余文本的情况。
func _parse_json_content(content: String) -> Variant:
	var trimmed := content.strip_edges()

	# 1. 直接解析
	var direct: Variant = JSON.parse_string(trimmed)
	if direct is Dictionary:
		return direct

	# 2. 去除 markdown 代码块 ```json ... ```
	if trimmed.begins_with("```"):
		var first_newline := trimmed.find("\n")
		var last_fence := trimmed.rfind("```")
		if first_newline >= 0 and last_fence > first_newline:
			var unfenced := trimmed.substr(
				first_newline + 1, last_fence - first_newline - 1
			).strip_edges()
			var fenced: Variant = JSON.parse_string(unfenced)
			if fenced is Dictionary:
				return fenced

	# 3. 提取最外层 { ... }
	var object_start := trimmed.find("{")
	var object_end := trimmed.rfind("}")
	if object_start >= 0 and object_end > object_start:
		var extracted := trimmed.substr(
			object_start, object_end - object_start + 1
		).strip_edges()
		var extracted_parsed: Variant = JSON.parse_string(extracted)
		if extracted_parsed is Dictionary:
			return extracted_parsed

	return null


## 规范化评分结果，确保字段完整且类型正确。
func _normalize_scoring_result(raw: Dictionary) -> Dictionary:
	var level := int(raw.get("level", 0))
	level = clampi(level, 1, 5)

	var markers: Array = []
	var markers_raw: Variant = raw.get("markers", [])
	if typeof(markers_raw) == TYPE_ARRAY:
		for marker: Variant in markers_raw:
			markers.append(String(marker))

	var description := String(raw.get("description", ""))
	var strategy := String(raw.get("strategy", ""))

	return {
		"level": level,
		"markers": markers,
		"description": description,
		"strategy": strategy,
	}


# ============================================================
#  内部：错误处理与辅助
# ============================================================

## 根据请求模式分发错误信号。
func _emit_error(mode: int, error: String) -> void:
	if mode == _RequestMode.DIALOGUE:
		ai_response_error.emit(error)
	else:
		scoring_error.emit(error)


## 将 HTTPRequest 结果码转换为可读的错误描述。
func _network_error_text(result: int) -> String:
	match result:
		HTTPRequest.RESULT_TIMEOUT:
			return "请求超时（%d 秒）" % int(DEFAULT_TIMEOUT_SECONDS)
		HTTPRequest.RESULT_CANT_CONNECT:
			return "无法连接到服务器"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "无法解析服务器地址"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "连接错误"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS 握手失败"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "服务器无响应"
		_:
			return "网络请求失败（错误码 %d）" % result


## 从 API 错误响应体中提取可读错误信息。
func _extract_api_error(body_text: String, status_code: int) -> String:
	var message := "API 返回 HTTP %d" % status_code
	var parsed: Variant = JSON.parse_string(body_text)
	if typeof(parsed) == TYPE_DICTIONARY:
		var error_value: Variant = (parsed as Dictionary).get("error")
		if typeof(error_value) == TYPE_DICTIONARY:
			var api_msg := String((error_value as Dictionary).get("message", ""))
			if not api_msg.is_empty():
				message += "：%s" % api_msg
		else:
			var api_msg := String((parsed as Dictionary).get("message", ""))
			if not api_msg.is_empty():
				message += "：%s" % api_msg
	return message


## 生成缺少配置的错误描述。
func _missing_config_error() -> String:
	var endpoint := String(_api_config.get("endpoint", "")).strip_edges()
	var api_key := String(_api_config.get("api_key", "")).strip_edges()
	var model := String(_api_config.get("model", "")).strip_edges()
	if endpoint.is_empty():
		return "API 配置不完整：缺少 endpoint"
	if api_key.is_empty():
		return "API 配置不完整：缺少 api_key"
	if model.is_empty():
		return "API 配置不完整：缺少 model"
	return "API 配置不完整"


## 从 AssessmentGameManager autoload 刷新 API 配置。
## 若已通过 set_api_config() 手动覆盖则跳过。
func _refresh_config_from_manager() -> void:
	if _config_overridden:
		return
	var manager := _get_game_manager()
	if manager == null:
		return
	if not manager.has_method("get_api_config"):
		return
	var config: Variant = manager.get_api_config()
	if not (config is Dictionary) or (config as Dictionary).is_empty():
		return
	var cfg := config as Dictionary
	_api_config = {
		"endpoint": String(cfg.get("endpoint", DEFAULT_ENDPOINT)),
		"api_key": String(cfg.get("api_key", "")),
		"model": String(cfg.get("model", DEFAULT_MODEL)),
	}


## 获取 AssessmentGameManager autoload 单例节点。
func _get_game_manager() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("/root/AssessmentGameManager")
