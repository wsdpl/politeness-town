class_name AssessmentStorage
extends RefCounted
## 测评数据存储系统
## 使用 JSON 文件在 user://data 目录下持久化儿童信息、会话数据与报告。
## 全部方法为静态方法，可通过 AssessmentStorage.xxx() 直接调用。
#
# 数据目录结构：
#   user://data/children/   - 儿童信息（每名儿童一个 JSON，按昵称命名）
#   user://data/sessions/   - 会话数据（每场会话一个 JSON，按 session_id 命名）
#   user://data/reports/    - 报告数据（每场会话导出一个 JSON）

const DATA_ROOT := "user://data"
const CHILDREN_DIR := "user://data/children"
const SESSIONS_DIR := "user://data/sessions"
const REPORTS_DIR := "user://data/reports"

# 索引文件（记录摘要列表，便于快速列举）
const SESSIONS_INDEX := "user://data/sessions/_index.json"
const CHILDREN_INDEX := "user://data/children/_index.json"


# ============================================================
# 公开接口
# ============================================================

## 保存会话结果（含儿童信息、轮次、场景结果、最终结果）。
## 成功返回 true，失败返回 false。
static func save_session_results(session_id: String, child_info: Dictionary, turns: Array, scenario_results: Dictionary, final_results: Dictionary) -> bool:
	_ensure_dirs()
	var data := {
		"session_id": session_id,
		"saved_at": Time.get_unix_time_from_system(),
		"child_info": child_info,
		"turn_count": turns.size(),
		"turns": turns,
		"scenario_results": scenario_results,
		"final_results": final_results,
	}
	var path := "%s/%s.json" % [SESSIONS_DIR, _sanitize_filename(session_id)]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[AssessmentStorage] 无法写入会话文件: %s (错误码: %d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	_update_sessions_index(session_id, data)
	# 同时保存/更新儿童信息
	if not child_info.is_empty():
		save_child_info(child_info)
	print("[AssessmentStorage] 会话已保存: %s" % session_id)
	return true


## 加载会话结果。文件不存在或无效时返回空字典。
static func load_session_results(session_id: String) -> Dictionary:
	var path := "%s/%s.json" % [SESSIONS_DIR, _sanitize_filename(session_id)]
	if not FileAccess.file_exists(path):
		push_warning("[AssessmentStorage] 会话文件不存在: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[AssessmentStorage] 无法读取会话文件: %s (错误码: %d)" % [path, FileAccess.get_open_error()])
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		push_error("[AssessmentStorage] 会话文件格式无效: %s" % path)
		return {}
	return parsed


## 列出所有会话摘要（按保存顺序，每条含 session_id、saved_at、nickname、turn_count、total_stars）。
static func list_all_sessions() -> Array[Dictionary]:
	return _load_sessions_index()


## 保存儿童信息（按昵称命名文件）。成功返回 true。
static func save_child_info(child_info: Dictionary) -> bool:
	_ensure_dirs()
	var nickname := String(child_info.get("nickname", ""))
	if nickname.is_empty():
		push_error("[AssessmentStorage] 儿童信息缺少昵称，无法保存")
		return false
	var path := "%s/%s.json" % [CHILDREN_DIR, _sanitize_filename(nickname)]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[AssessmentStorage] 无法写入儿童信息: %s (错误码: %d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(child_info, "\t"))
	file.close()
	_update_children_index(nickname)
	return true


## 加载儿童信息。文件不存在时返回空字典。
static func load_child_info(nickname: String) -> Dictionary:
	var path := "%s/%s.json" % [CHILDREN_DIR, _sanitize_filename(nickname)]
	if not FileAccess.file_exists(path):
		push_warning("[AssessmentStorage] 儿童信息不存在: %s" % nickname)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[AssessmentStorage] 无法读取儿童信息: %s (错误码: %d)" % [path, FileAccess.get_open_error()])
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return {}
	return parsed


## 导出完整报告数据。
## 汇总会话中的儿童信息、轮次、场景结果、最终结果与统计摘要，
## 同时写入 user://data/reports/ 目录，并返回报告字典。
static func export_report(session_id: String) -> Dictionary:
	var session := load_session_results(session_id)
	if session.is_empty():
		return {}
	var report := {
		"session_id": session_id,
		"exported_at": Time.get_unix_time_from_system(),
		"child_info": session.get("child_info", {}),
		"turns": session.get("turns", []),
		"scenario_results": session.get("scenario_results", {}),
		"final_results": session.get("final_results", {}),
		"summary": _build_report_summary(session),
	}
	_ensure_dirs()
	var report_path := "%s/%s.json" % [REPORTS_DIR, _sanitize_filename(session_id)]
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	else:
		push_error("[AssessmentStorage] 无法写入报告文件: %s (错误码: %d)" % [report_path, FileAccess.get_open_error()])
	return report


# ============================================================
# 内部辅助函数
# ============================================================

## 确保数据目录存在。
static func _ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(CHILDREN_DIR)
	DirAccess.make_dir_recursive_absolute(SESSIONS_DIR)
	DirAccess.make_dir_recursive_absolute(REPORTS_DIR)


## 净化字符串为安全文件名（替换非法字符）。
static func _sanitize_filename(name: String) -> String:
	var sanitized := name.replace("/", "_").replace("\\", "_").replace(":", "_")
	sanitized = sanitized.replace(" ", "_").replace(".", "_").replace("?", "_")
	sanitized = sanitized.replace("*", "_").replace("\"", "_").replace("|", "_")
	sanitized = sanitized.replace("<", "_").replace(">", "_")
	if sanitized.is_empty():
		sanitized = "unnamed"
	return sanitized


## 加载会话索引。
static func _load_sessions_index() -> Array[Dictionary]:
	if not FileAccess.file_exists(SESSIONS_INDEX):
		return []
	var file := FileAccess.open(SESSIONS_INDEX, FileAccess.READ)
	if file == null:
		return []
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Array):
		return []
	var result: Array[Dictionary] = []
	for entry in parsed:
		if entry is Dictionary:
			result.append(entry)
	return result


## 更新会话索引（覆盖同 session_id 的旧记录）。
static func _update_sessions_index(session_id: String, data: Dictionary) -> void:
	var index := _load_sessions_index()
	var filtered: Array[Dictionary] = []
	for entry in index:
		if String(entry.get("session_id", "")) != session_id:
			filtered.append(entry)
	var child_info: Dictionary = data.get("child_info", {})
	var final_results: Dictionary = data.get("final_results", {})
	filtered.append({
		"session_id": session_id,
		"saved_at": data.get("saved_at", 0),
		"nickname": String(child_info.get("nickname", "")),
		"turn_count": int(data.get("turn_count", 0)),
		"total_stars": int(final_results.get("total_stars", 0)),
	})
	var file := FileAccess.open(SESSIONS_INDEX, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(filtered, "\t"))
		file.close()


## 更新儿童索引（覆盖同昵称的旧记录）。
static func _update_children_index(nickname: String) -> void:
	var existing: Array = []
	if FileAccess.file_exists(CHILDREN_INDEX):
		var f := FileAccess.open(CHILDREN_INDEX, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Array:
				existing = parsed
			f.close()
	var filtered: Array = []
	for entry in existing:
		if entry is Dictionary and String(entry.get("nickname", "")) != nickname:
			filtered.append(entry)
	filtered.append({"nickname": nickname})
	var file := FileAccess.open(CHILDREN_INDEX, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(filtered, "\t"))
		file.close()


## 构建报告统计摘要（含轮次数、场景数、星章数、雷达数据、稳定性与情境适配）。
static func _build_report_summary(session: Dictionary) -> Dictionary:
	var turns: Array = session.get("turns", [])
	var scenario_results: Dictionary = session.get("scenario_results", {})
	var final_results: Dictionary = session.get("final_results", {})
	var summary := {
		"total_turns": turns.size(),
		"total_scenarios": scenario_results.size(),
		"total_stars": int(final_results.get("total_stars", 0)),
		"overall_level": float(final_results.get("overall_level", 0.0)),
	}
	if not turns.is_empty():
		summary["radar_data"] = PolitenessScoring.generate_radar_data({"turns": turns})
		summary["average_level"] = PolitenessScoring.calculate_average_level(turns, "greeting")
		summary["stability"] = PolitenessScoring.calculate_stability(turns)
		summary["contextual_adaptation"] = PolitenessScoring.calculate_contextual_adaptation(turns)
	return summary
