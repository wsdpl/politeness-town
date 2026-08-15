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


## 导出CSV格式数据（含儿童信息、各轮次明细、维度统计摘要）。
## 返回CSV文件路径，失败返回空字符串。
static func export_csv(session_id: String) -> String:
	var session := load_session_results(session_id)
	if session.is_empty():
		push_error("[AssessmentStorage] 无法导出CSV：会话数据为空 (%s)" % session_id)
		return ""
	_ensure_dirs()
	var csv_path := "%s/%s.csv" % [REPORTS_DIR, _sanitize_filename(session_id)]
	var file := FileAccess.open(csv_path, FileAccess.WRITE)
	if file == null:
		push_error("[AssessmentStorage] 无法写入CSV文件: %s (错误码: %d)" % [csv_path, FileAccess.get_open_error()])
		return ""

	var lines: Array[String] = []

	# --- 儿童信息 ---
	var child_info: Dictionary = session.get("child_info", {})
	lines.append("# 儿童信息")
	lines.append("字段,值")
	lines.append("昵称,%s" % _csv_escape(String(child_info.get("nickname", ""))))
	lines.append("年龄,%d" % int(child_info.get("age", 0)))
	lines.append("性别,%s" % _csv_escape(String(child_info.get("gender", ""))))
	lines.append("AI类型,%s" % _csv_escape(String(child_info.get("ai_type", ""))))
	lines.append("会话ID,%s" % _csv_escape(session_id))
	lines.append("")

	# --- 各轮次明细 ---
	var turns: Array = session.get("turns", [])
	lines.append("# 各轮次明细")
	lines.append("轮次序号,说话者,文本,等级,标记词,板块,维度,时间戳")
	for i in range(turns.size()):
		var turn: Dictionary = turns[i] if turns[i] is Dictionary else {}
		var speaker := String(turn.get("speaker", ""))
		var text := String(turn.get("text", turn.get("child_input", turn.get("response", ""))))
		var level: int = int(turn.get("level", 0))
		var markers: Array = turn.get("markers", [])
		var marker_str := ""
		for j in range(markers.size()):
			if j > 0:
				marker_str += ","
			marker_str += String(markers[j])
		var section := String(turn.get("section", ""))
		var dimension := String(turn.get("dimension", turn.get("expected_dimension", "")))
		var timestamp := String(turn.get("timestamp", ""))
		lines.append("%d,%s,%s,%d,%s,%s,%s,%s" % [
			i + 1, _csv_escape(speaker), _csv_escape(text), level,
			_csv_escape(marker_str), _csv_escape(section), _csv_escape(dimension), timestamp
		])
	lines.append("")

	# --- 维度统计摘要 ---
	var final_results: Dictionary = session.get("final_results", {})
	var per_dimension: Array = final_results.get("per_dimension", [])
	lines.append("# 核心维度统计")
	lines.append("维度,频次,平均等级,星章")
	for entry in per_dimension:
		if entry is Dictionary:
			lines.append("%s,%.4f,%.4f,%s" % [
				_csv_escape(String(entry.get("name", ""))),
				float(entry.get("frequency", 0.0)),
				float(entry.get("level", 0.0)),
				"★" if int(entry.get("star", 0)) > 0 else "—",
			])
	lines.append("")

	# --- 扩展维度 ---
	var extended: Array = final_results.get("extended_summary", [])
	lines.append("# 扩展维度评估")
	lines.append("维度,频次,等级")
	for entry in extended:
		if entry is Dictionary:
			lines.append("%s,%.4f,%.4f" % [
				_csv_escape(String(entry.get("name", ""))),
				float(entry.get("frequency", 0.0)),
				float(entry.get("level", 0.0)),
			])
	lines.append("")

	# --- 等级分布 ---
	var level_dist: Array = final_results.get("level_distribution", [])
	var level_labels: Array[String] = ["沉默/无回应", "直白无修饰", "消极礼貌", "积极礼貌+称呼", "复合策略"]
	lines.append("# 五级策略等级分布")
	lines.append("等级,描述,频次")
	for i in range(min(level_dist.size(), level_labels.size())):
		lines.append("%d,%s,%.0f" % [i + 1, _csv_escape(level_labels[i]), float(level_dist[i])])
	lines.append("")

	# --- 汇总指标 ---
	lines.append("# 汇总指标")
	lines.append("指标,值")
	lines.append("总星章,%d/%d" % [int(final_results.get("total_stars", 0)), int(final_results.get("max_stars", 6))])
	lines.append("总分,%.4f" % float(final_results.get("overall_score", 0.0)))
	lines.append("话轮数,%d" % int(final_results.get("turn_count", 0)))
	lines.append("评估建议,%s" % _csv_escape(String(final_results.get("recommendation", ""))))

	# 场景级统计
	var scenario_results: Dictionary = session.get("scenario_results", {})
	for scenario_key in scenario_results.keys():
		var scenario: Dictionary = scenario_results[scenario_key]
		if scenario is Dictionary and scenario.has("statistics"):
			var stats: Dictionary = scenario.get("statistics", {})
			lines.append("")
			lines.append("# 场景统计: %s" % _csv_escape(scenario_key))
			lines.append("指标,值")
			lines.append("标记词总频次,%d" % int(stats.get("marker_total_count", 0)))
			lines.append("每分钟频次,%.4f" % float(stats.get("marker_frequency", 0.0)))
			lines.append("平均等级,%.4f" % float(stats.get("average_level", 0.0)))
			lines.append("互动时长(分钟),%.4f" % float(stats.get("duration_minutes", 0.0)))
			lines.append("话轮数,%d" % int(stats.get("turn_count", 0)))

	file.store_string("\r\n".join(lines))
	file.close()
	print("[AssessmentStorage] CSV已导出: %s" % csv_path)
	return csv_path


## CSV字段转义：包含逗号、引号或换行时用双引号包裹，内部双引号翻倍。
static func _csv_escape(value: String) -> String:
	if value.find(",") != -1 or value.find("\"") != -1 or value.find("\n") != -1 or value.find("\r") != -1:
		return "\"%s\"" % value.replace("\"", "\"\"")
	return value


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
