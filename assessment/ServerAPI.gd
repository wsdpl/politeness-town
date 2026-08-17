class_name ServerAPI
extends Node
## 服务器API客户端：将测评数据发送到MySQL服务器
## 通过HTTP请求与Node.js后端通信

const SERVER_URL := "http://192.144.163.234:3000"
const API_TOKEN := "PoliteTown@2026"
const TIMEOUT := 10.0

var _http: HTTPRequest
var _active_path := ""

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)
	print("[ServerAPI] 服务器API客户端已就绪: %s" % SERVER_URL)


## 测评完成后一次性上传全部数据（推荐用法）
func upload_session_complete(child_info: Dictionary, turns: Array, scenario_results: Dictionary, final_results: Dictionary) -> void:
	var payload := {
		"child_info": child_info,
		"turns": turns,
		"scenario_results": scenario_results,
		"final_results": final_results
	}
	_post("/api/session-complete", payload)


## 单独注册被试（如果需要实时注册）
func register_participant(child_info: Dictionary) -> void:
	_post("/api/participant", child_info)


## 单独保存任务得分
func save_task_score(child_id: int, task_data: Dictionary) -> void:
	task_data["child_id"] = child_id
	_post("/api/task-score", task_data)


## 单独批量保存话轮
func save_turns(child_id: int, task_id: int, turns: Array) -> void:
	_post("/api/turns", {
		"child_id": child_id,
		"task_id": task_id,
		"turns": turns
	})


## 健康检查
func check_health() -> void:
	var url := SERVER_URL + "/api/health"
	_active_path = "/api/health"
	var err := _http.request(url, [], HTTPClient.METHOD_GET)
	if err != OK:
		print("[ServerAPI] 健康检查失败 (错误码: %d)" % err)


func _post(path: String, data: Dictionary) -> void:
	var url := SERVER_URL + path
	var authenticated_data := data.duplicate(true)
	authenticated_data["token"] = API_TOKEN
	var body := JSON.stringify(authenticated_data)
	var headers := PackedStringArray(["Content-Type: application/json"])
	_active_path = path
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		print("[ServerAPI] POST请求失败: %s (错误码: %d)" % [path, err])
	else:
		print("[ServerAPI] 已发送: %s (%d字节)" % [path, body.length()])


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var path := _active_path
	_active_path = ""
	if result != HTTPRequest.RESULT_SUCCESS:
		print("[ServerAPI] 请求失败: %s (网络错误码: %d)" % [path, result])
		return
	if response_code < 200 or response_code >= 300:
		print("[ServerAPI] 服务器拒绝请求: %s (HTTP %d) %s" % [path, response_code, body.get_string_from_utf8().left(300)])
		return
	print("[ServerAPI] 服务器已确认: %s (HTTP %d)" % [path, response_code])
