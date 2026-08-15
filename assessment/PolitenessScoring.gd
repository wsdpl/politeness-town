class_name PolitenessScoring
extends RefCounted
## 礼貌计分系统
## 对儿童与 AI 交互中的礼貌用语进行五级策略编码与多维度评估。
## 全部方法为静态方法，可通过 PolitenessScoring.xxx() 直接调用。

# ===== 五级礼貌策略等级 =====
enum Level {
	SILENT = 1,    # 等级1：沉默/无回应
	DIRECT = 2,    # 等级2：直白无修饰（如"给你""我要"）
	NEGATIVE = 3,  # 等级3：消极礼貌（使用"请""谢谢"等基本礼貌词）
	POSITIVE = 4,  # 等级4：积极礼貌+称呼（如"阿姨请""老师谢谢"）
	COMPOSITE = 5, # 等级5：复合策略（道歉+请求、感谢+分享等多策略组合）
}

# ===== 礼貌标记词库（六大维度） =====
const MARKER_LIBRARY := {
	"greeting": ["你好", "嗨", "早上好", "再见", "拜拜"],          # 问候类
	"request": ["请", "可以吗", "能不能", "好吗", "拜托"],          # 请求类
	"thanks": ["谢谢", "多谢", "感谢"],                            # 道谢类
	"apology": ["对不起", "抱歉", "不好意思"],                     # 道歉类
	"sharing": ["给你", "一起", "分享"],                           # 分享类
	"farewell": ["再见", "拜拜", "回头见"],                        # 告别类
}

# 维度中文名映射
const DIMENSION_NAMES := {
	"greeting": "问候",
	"request": "请求",
	"thanks": "道谢",
	"apology": "致歉",
	"sharing": "分享",
	"farewell": "告别",
}

# 维度别名映射（兼容项目中 AssessmentData 的"问候维度"与 AssessmentAIManager 的"请求"等中文维度名）
const DIMENSION_ALIASES := {
	"问候": "greeting", "问候维度": "greeting", "greeting": "greeting",
	"请求": "request", "请求维度": "request", "request": "request",
	"道谢": "thanks", "道谢维度": "thanks", "感谢": "thanks", "thanks": "thanks",
	"致歉": "apology", "致歉维度": "apology", "道歉": "apology", "道歉维度": "apology", "apology": "apology",
	"分享": "sharing", "分享维度": "sharing", "sharing": "sharing",
	"告别": "farewell", "告别维度": "farewell", "farewell": "farewell",
}

# 板块二补充维度
const EXTENDED_DIMENSIONS := {
	"basic_politeness": "基础礼貌",
	"strategy_flexibility": "策略灵活性",
	"stress_response": "压力应对",
}

# 称呼词（用于等级4判定）
const ADDRESS_TERMS := [
	"阿姨", "叔叔", "老师", "哥哥", "姐姐",
	"爷爷", "奶奶", "伯伯", "婶婶", "先生",
	"女士", "小朋友",
]

# 六大核心维度列表（用于雷达图顺序）
const CORE_DIMENSIONS := ["greeting", "request", "thanks", "apology", "sharing", "farewell"]

# 功能分组（用于复合策略判定，问候与告别同属"社交常规"组，
# 避免仅因"再见""拜拜"同时归属问候/告别而被误判为复合策略）
const FUNCTIONAL_GROUPS := {
	"greeting": "social",
	"farewell": "social",
	"request": "request",
	"thanks": "thanks",
	"apology": "apology",
	"sharing": "sharing",
}

# 功能分组去重列表（用于策略灵活性归一化分母）
const DISTINCT_GROUPS := ["social", "request", "thanks", "apology", "sharing"]

# 等级描述
const LEVEL_DESCRIPTIONS := {
	1: "沉默/无回应",
	2: "直白无修饰",
	3: "消极礼貌（基本礼貌词）",
	4: "积极礼貌+称呼",
	5: "复合策略（多策略组合）",
}

# 默认每轮时长（分钟），用于时间戳不足时估算总时长
const DEFAULT_TURN_MINUTES := 0.5


# ============================================================
# 计分函数
# ============================================================

## 评分单条回应。
## [param text] 儿童发言文本
## [param dimension] 所属维度（场景上下文，不参与标记过滤，礼貌等级按全部标记综合判定）
## 返回 {level: int, markers: Array, description: String}
static func score_response(text: String, dimension: String) -> Dictionary:
	var result := {
		"level": Level.SILENT,
		"markers": [],
		"description": LEVEL_DESCRIPTIONS[Level.SILENT],
	}
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return result

	# 收集命中的标记词及所属维度
	var found_markers: Array = []
	var categories: Array = []
	for dim in MARKER_LIBRARY.keys():
		for marker in MARKER_LIBRARY[dim]:
			if trimmed.find(marker) != -1:
				if marker not in found_markers:
					found_markers.append(marker)
				if dim not in categories:
					categories.append(dim)

	# 检测称呼词
	var has_address := false
	for term in ADDRESS_TERMS:
		if trimmed.find(term) != -1:
			has_address = true
			break

	# 计算功能分组数（问候/告别合并为社交常规，避免同词双算）
	var found_groups: Dictionary = {}
	for dim in categories:
		found_groups[FUNCTIONAL_GROUPS.get(dim, dim)] = true

	# 等级判定
	var level: int
	if found_markers.is_empty():
		level = Level.DIRECT
	elif found_groups.size() >= 2:
		level = Level.COMPOSITE
	elif has_address:
		level = Level.POSITIVE
	else:
		level = Level.NEGATIVE

	result["level"] = level
	result["markers"] = found_markers
	result["description"] = LEVEL_DESCRIPTIONS[level]
	return result


## 计算每分钟礼貌标记词频次（某维度标记词出现总次数 / 总时长分钟数）。
## [param dimension] 支持英文键（"request"）或中文维度名（"请求""请求维度"）
static func calculate_frequency(turns: Array, dimension: String) -> float:
	if turns.is_empty():
		return 0.0
	var dim_key := _resolve_dimension(dimension)
	var marker_count := 0
	for turn in turns:
		if turn is Dictionary:
			marker_count += _count_markers_in_dimension(_extract_text(turn), dim_key)
	var minutes := _calculate_duration_minutes(turns)
	if minutes <= 0.0:
		minutes = float(turns.size()) * DEFAULT_TURN_MINUTES
	if minutes <= 0.0:
		return 0.0
	return float(marker_count) / minutes


## 计算平均策略等级（各轮等级的算术平均）。
static func calculate_average_level(turns: Array, dimension: String) -> float:
	if turns.is_empty():
		return 0.0
	var total := 0.0
	var count := 0
	for turn in turns:
		if turn is Dictionary:
			var result := score_response(_extract_text(turn), dimension)
			total += float(result["level"])
			count += 1
	if count == 0:
		return 0.0
	return total / float(count)


## 计算情境适配正确率。
## 期望每轮带有 expected_dimension / context / scenario_dimension 字段标明该情境期望的维度，
## 比较儿童实际使用的标记维度是否命中期望维度（支持中文或英文维度名）。
## 返回 {accuracy: float, correct: int, total: int, per_dimension: Dictionary}
static func calculate_contextual_adaptation(turns: Array) -> Dictionary:
	var correct := 0
	var total := 0
	var per_dimension: Dictionary = {}
	for turn in turns:
		if not (turn is Dictionary):
			continue
		var expected_dim := String(turn.get("expected_dimension", turn.get("context", turn.get("scenario_dimension", ""))))
		if expected_dim.is_empty():
			continue
		var expected_key := _resolve_dimension(expected_dim)
		total += 1
		var found_dims := _find_marker_dimensions(_extract_text(turn))
		var is_correct := found_dims.has(expected_key)
		if is_correct:
			correct += 1
		if not per_dimension.has(expected_key):
			per_dimension[expected_key] = {"correct": 0, "total": 0}
		per_dimension[expected_key]["total"] = int(per_dimension[expected_key]["total"]) + 1
		if is_correct:
			per_dimension[expected_key]["correct"] = int(per_dimension[expected_key]["correct"]) + 1
	var accuracy := 0.0
	if total > 0:
		accuracy = float(correct) / float(total)
	var per_dimension_accuracy: Dictionary = {}
	for dim in per_dimension.keys():
		var d: Dictionary = per_dimension[dim]
		var dim_total := int(d["total"])
		var dim_correct := int(d["correct"])
		per_dimension_accuracy[dim] = float(dim_correct) / float(dim_total) if dim_total > 0 else 0.0
	return {
		"accuracy": accuracy,
		"correct": correct,
		"total": total,
		"per_dimension": per_dimension_accuracy,
	}


## 计算礼貌用语稳定性（各轮等级的标准差，数值越小越稳定）。
static func calculate_stability(turns: Array) -> float:
	if turns.size() < 2:
		return 0.0
	var levels: Array = []
	for turn in turns:
		if turn is Dictionary:
			var result := score_response(_extract_text(turn), "greeting")
			levels.append(float(result["level"]))
	if levels.size() < 2:
		return 0.0
	var mean := 0.0
	for lv in levels:
		mean += lv
	mean /= float(levels.size())
	var variance := 0.0
	for lv in levels:
		var diff: float = float(lv) - mean
		variance += diff * diff
	variance /= float(levels.size())
	return sqrt(variance)


# ============================================================
# 雷达图数据生成
# ============================================================

## 生成频次雷达图与等级雷达图数据。
## [param scenario_results] 可包含 "turns" 汇总数组，或每个场景结果各自带有 "turns"。
## 返回 {frequency_radar, level_radar, extended_frequency_radar, extended_level_radar,
##       dimensions, extended_dimensions, dimension_names, turn_count}
static func generate_radar_data(scenario_results: Dictionary) -> Dictionary:
	var all_turns: Array = _collect_turns(scenario_results)

	# 核心六维雷达
	var frequency_radar: Dictionary = {}
	var level_radar: Dictionary = {}
	for dim in CORE_DIMENSIONS:
		frequency_radar[dim] = calculate_frequency(all_turns, dim)
		level_radar[dim] = calculate_average_level(all_turns, dim)

	# 板块二补充维度
	var extended_frequency: Dictionary = {}
	var extended_level: Dictionary = {}
	extended_frequency["basic_politeness"] = _calculate_basic_politeness(all_turns)
	extended_frequency["strategy_flexibility"] = _calculate_strategy_flexibility(all_turns)
	extended_frequency["stress_response"] = _calculate_stress_response(scenario_results, all_turns)
	extended_level["basic_politeness"] = calculate_average_level(all_turns, "thanks")
	extended_level["strategy_flexibility"] = _calculate_flexibility_level(all_turns)
	extended_level["stress_response"] = _calculate_stress_level(scenario_results, all_turns)

	# 维度中文名
	var dim_names: Dictionary = {}
	for dim in CORE_DIMENSIONS:
		dim_names[dim] = DIMENSION_NAMES[dim]
	for dim in EXTENDED_DIMENSIONS.keys():
		dim_names[dim] = EXTENDED_DIMENSIONS[dim]

	return {
		"frequency_radar": frequency_radar,
		"level_radar": level_radar,
		"extended_frequency_radar": extended_frequency,
		"extended_level_radar": extended_level,
		"dimensions": CORE_DIMENSIONS.duplicate(),
		"extended_dimensions": EXTENDED_DIMENSIONS.keys(),
		"dimension_names": dim_names,
		"turn_count": all_turns.size(),
	}


# ============================================================
# 内部辅助函数
# ============================================================

## 从轮次字典中提取儿童发言文本（兼容多种字段名）。
static func _extract_text(turn: Dictionary) -> String:
	for key in ["child_input", "child_response", "response", "text", "child_text", "utterance", "message", "content", "input"]:
		if turn.has(key):
			var value = turn[key]
			if value is String:
				return value
			return String(value)
	return ""


## 将中文维度名或英文键统一解析为 MARKER_LIBRARY 内部使用的英文键。
## 未识别的维度名原样返回（调用方自行保证有效性）。
static func _resolve_dimension(dimension: String) -> String:
	if DIMENSION_ALIASES.has(dimension):
		return DIMENSION_ALIASES[dimension]
	return dimension


## 统计某维度标记词在文本中的出现次数（含重复出现）。
static func _count_markers_in_dimension(text: String, dimension: String) -> int:
	if not MARKER_LIBRARY.has(dimension):
		return 0
	var count := 0
	for marker in MARKER_LIBRARY[dimension]:
		var idx := text.find(marker)
		while idx != -1:
			count += 1
			idx = text.find(marker, idx + marker.length())
	return count


## 找出文本命中的所有维度。
static func _find_marker_dimensions(text: String) -> Array:
	var dims: Array = []
	for dim in MARKER_LIBRARY.keys():
		for marker in MARKER_LIBRARY[dim]:
			if text.find(marker) != -1:
				if dim not in dims:
					dims.append(dim)
				break
	return dims


## 根据时间戳计算时长（分钟），时间戳不足时按每轮默认时长估算。
static func _calculate_duration_minutes(turns: Array) -> float:
	if turns.is_empty():
		return 0.0
	var timestamps: Array = []
	for turn in turns:
		if turn is Dictionary and turn.has("timestamp"):
			timestamps.append(int(turn["timestamp"]))
	if timestamps.size() < 2:
		return float(turns.size()) * DEFAULT_TURN_MINUTES
	var min_ts := int(timestamps[0])
	var max_ts := int(timestamps[0])
	for ts in timestamps:
		if ts < min_ts:
			min_ts = ts
		if ts > max_ts:
			max_ts = ts
	var duration_ms := max_ts - min_ts
	if duration_ms <= 0:
		return float(turns.size()) * DEFAULT_TURN_MINUTES
	return float(duration_ms) / 60000.0


## 汇总所有轮次：优先取 scenario_results["turns"]，否则合并各场景结果的 "turns"。
static func _collect_turns(scenario_results: Dictionary) -> Array:
	var all_turns: Array = []
	if scenario_results.has("turns") and scenario_results["turns"] is Array:
		all_turns = scenario_results["turns"]
	else:
		for scenario_id in scenario_results.keys():
			var result = scenario_results[scenario_id]
			if result is Dictionary and result.has("turns") and result["turns"] is Array:
				all_turns.append_array(result["turns"])
	return all_turns


## 基础礼貌频次（问候+道谢+告别的平均频次）。
static func _calculate_basic_politeness(turns: Array) -> float:
	if turns.is_empty():
		return 0.0
	var total := 0.0
	for dim in ["greeting", "thanks", "farewell"]:
		total += calculate_frequency(turns, dim)
	return total / 3.0


## 策略灵活性（使用的功能分组数 / 功能分组总数，0~1）。
static func _calculate_strategy_flexibility(turns: Array) -> float:
	if turns.is_empty():
		return 0.0
	var used_groups: Dictionary = {}
	for turn in turns:
		if not (turn is Dictionary):
			continue
		for dim in _find_marker_dimensions(_extract_text(turn)):
			used_groups[FUNCTIONAL_GROUPS.get(dim, dim)] = true
	return float(used_groups.size()) / float(DISTINCT_GROUPS.size())


## 压力应对频次（压力轮次中的平均标记频次；无压力标记时退化为整体频次）。
static func _calculate_stress_response(scenario_results: Dictionary, turns: Array) -> float:
	var pressure_turns: Array = _collect_pressure_turns(turns)
	var target: Array = pressure_turns if not pressure_turns.is_empty() else turns
	var total := 0.0
	for dim in CORE_DIMENSIONS:
		total += calculate_frequency(target, dim)
	return total / float(CORE_DIMENSIONS.size())


## 策略灵活性等级（使用分组数映射到 1~5）。
static func _calculate_flexibility_level(turns: Array) -> float:
	if turns.is_empty():
		return 0.0
	var used_groups: Dictionary = {}
	for turn in turns:
		if not (turn is Dictionary):
			continue
		for dim in _find_marker_dimensions(_extract_text(turn)):
			used_groups[FUNCTIONAL_GROUPS.get(dim, dim)] = true
	return float(clampi(used_groups.size() + 1, 1, 5))


## 压力场景平均等级（无压力标记时退化为整体平均等级）。
static func _calculate_stress_level(scenario_results: Dictionary, turns: Array) -> float:
	var pressure_turns: Array = _collect_pressure_turns(turns)
	var target: Array = pressure_turns if not pressure_turns.is_empty() else turns
	return calculate_average_level(target, "greeting")


## 收集标记为压力的轮次（兼容 is_pressure / pressure / high_pressure 字段）。
static func _collect_pressure_turns(turns: Array) -> Array:
	var pressure_turns: Array = []
	for turn in turns:
		if turn is Dictionary:
			var pressure = turn.get("is_pressure", turn.get("pressure", turn.get("high_pressure", false)))
			if bool(pressure):
				pressure_turns.append(turn)
	return pressure_turns
