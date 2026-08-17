class_name TTSHelper
extends RefCounted
## NPC 语音朗读工具：使用 Godot 内置 DisplayServer TTS 朗读中文台词。
## 支持根据 NPC 角色类型自动选择不同音色（男女老少）。

# 音色配置
enum VoiceProfile {
	NARRATOR,       # 旁白/系统
	CHILD,          # 儿童
	YOUNG_FEMALE,   # 年轻女性
	YOUNG_MALE,     # 年轻男性
	OLD_FEMALE,     # 老年女性
	OLD_MALE        # 老年男性
}

static var _voices: Array[Dictionary] = []
static var _initialized: bool = false
static var _use_sapi_fallback: bool = false
static var _sapi_pid: int = 0

# 按音色分组的声音ID
static var _female_voices: Array[String] = []
static var _male_voices: Array[String] = []
static var _all_chinese_voices: Array[String] = []

# 音色参数：pitch（音调）和 rate（语速）
# pitch > 1.0 声音更高（女性/儿童），< 1.0 声音更低（男性/老人）
# rate = 1.0 正常语速
const PROFILE_PARAMS: Dictionary = {
	VoiceProfile.NARRATOR:     {"pitch": 1.0, "rate": 1.0},
	VoiceProfile.CHILD:        {"pitch": 1.4, "rate": 1.05},
	VoiceProfile.YOUNG_FEMALE: {"pitch": 1.15, "rate": 1.0},
	VoiceProfile.YOUNG_MALE:   {"pitch": 0.85, "rate": 1.0},
	VoiceProfile.OLD_FEMALE:   {"pitch": 0.95, "rate": 0.85},
	VoiceProfile.OLD_MALE:     {"pitch": 0.7, "rate": 0.8},
}

# NPC名称 → 音色映射
const NPC_VOICE_MAP: Dictionary = {
	# 板块一 NPC
	"小熊布布": VoiceProfile.CHILD,
	"小礼": VoiceProfile.CHILD,
	"布布": VoiceProfile.CHILD,
	# 板块二 NPC
	"乐乐": VoiceProfile.CHILD,
	"草莓老师": VoiceProfile.YOUNG_FEMALE,
	"陌生阿姨": VoiceProfile.OLD_FEMALE,
	"推车管理员": VoiceProfile.YOUNG_MALE,
	"贴纸姐姐": VoiceProfile.YOUNG_FEMALE,
	"收银员": VoiceProfile.OLD_MALE,
	"小熊": VoiceProfile.CHILD,
	"超市阿姨": VoiceProfile.OLD_FEMALE,
	"竞争者": VoiceProfile.CHILD,
}


static func _ensure_init() -> void:
	if _initialized:
		return
	_initialized = true

	_voices = DisplayServer.tts_get_voices()
	if _voices.is_empty():
		print("[TTSHelper] Godot TTS无可用语音，将使用Windows SAPI回退")
		_use_sapi_fallback = true
		return

	print("[TTSHelper] 发现 %d 个TTS语音" % _voices.size())

	for voice: Dictionary in _voices:
		var lang: String = String(voice.get("language", ""))
		if not lang.begins_with("zh"):
			continue

		var vid: String = String(voice.get("id", ""))
		var vname: String = String(voice.get("name", "")).to_lower()
		_all_chinese_voices.append(vid)

		# 尝试根据声音名称判断性别
		# Windows 中文TTS常见：Huihui(女), Kangkang(男), Yaoyao(女), Xiaoxiao(女), Yunxi(男)
		var is_female: bool = vname.find("female") != -1 or vname.find("huihui") != -1 or vname.find("yaoyao") != -1 or vname.find("xiaoxiao") != -1 or vname.find("女") != -1
		var is_male: bool = vname.find("male") != -1 or vname.find("kangkang") != -1 or vname.find("yunxi") != -1 or vname.find("yunyang") != -1 or vname.find("男") != -1

		if is_female:
			_female_voices.append(vid)
		elif is_male:
			_male_voices.append(vid)

		print("[TTSHelper] 中文语音: %s (id=%s, female=%s, male=%s)" % [voice.get("name", ""), vid, is_female, is_male])

	print("[TTSHelper] 女声 %d 个, 男声 %d 个" % [_female_voices.size(), _male_voices.size()])

	# 如果没有找到中文语音，用第一个可用语音
	if _all_chinese_voices.is_empty() and not _voices.is_empty():
		var first: Dictionary = _voices[0]
		_all_chinese_voices.append(String(first.get("id", "")))
		print("[TTSHelper] 未找到中文语音，使用默认语音: %s" % first.get("name", ""))


## 根据音色类型获取最佳声音ID和参数
static func _get_voice_for_profile(profile: VoiceProfile) -> Dictionary:
	_ensure_init()

	var params: Dictionary = PROFILE_PARAMS.get(profile, {"pitch": 1.0, "rate": 1.0})
	var voice_id: String = ""

	# 尝试根据性别匹配实际声音
	match profile:
		VoiceProfile.CHILD, VoiceProfile.YOUNG_FEMALE, VoiceProfile.OLD_FEMALE:
			# 女性/儿童优先用女声
			if not _female_voices.is_empty():
				voice_id = _female_voices[0]
		VoiceProfile.YOUNG_MALE, VoiceProfile.OLD_MALE:
			# 男性优先用男声
			if not _male_voices.is_empty():
				voice_id = _male_voices[0]
		_:
			pass

	# 如果没匹配到，用第一个中文声音
	if voice_id.is_empty() and not _all_chinese_voices.is_empty():
		voice_id = _all_chinese_voices[0]

	return {
		"voice_id": voice_id,
		"pitch": float(params.get("pitch", 1.0)),
		"rate": float(params.get("rate", 1.0)),
	}


## 根据 NPC 名称获取对应音色
static func get_profile_for_npc(npc_name: String) -> VoiceProfile:
	if npc_name.is_empty():
		return VoiceProfile.NARRATOR

	# 精确匹配
	if NPC_VOICE_MAP.has(npc_name):
		return NPC_VOICE_MAP[npc_name]

	# 模糊匹配
	var name_lower := npc_name.to_lower()
	if name_lower.find("老师") != -1 or name_lower.find("姐姐") != -1:
		return VoiceProfile.YOUNG_FEMALE
	if name_lower.find("阿姨") != -1 or name_lower.find("奶奶") != -1:
		return VoiceProfile.OLD_FEMALE
	if name_lower.find("叔叔") != -1 or name_lower.find("爷爷") != -1 or name_lower.find("伯伯") != -1:
		return VoiceProfile.OLD_MALE
	if name_lower.find("管理员") != -1 or name_lower.find("收银") != -1:
		return VoiceProfile.YOUNG_MALE
	if name_lower.find("小") != -1 or name_lower.find("乐") != -1 or name_lower.find("布") != -1:
		return VoiceProfile.CHILD

	return VoiceProfile.NARRATOR


## 朗读文本（指定音色类型）
static func speak(text: String, profile: VoiceProfile = VoiceProfile.NARRATOR, interrupt: bool = true) -> void:
	if text.strip_edges().is_empty():
		return
	var doubao := _get_doubao_service()
	if doubao and doubao.is_configured():
		doubao.speak(text, profile)
		return
	speak_system(text, profile, interrupt)


## 使用本机 Godot TTS/SAPI 播报，供豆包请求失败时回退。
static func speak_system(text: String, profile: VoiceProfile = VoiceProfile.NARRATOR, interrupt: bool = true) -> void:
	if text.strip_edges().is_empty():
		return
	_ensure_init()

	if _use_sapi_fallback:
		_sapi_speak(text, profile, interrupt)
		return

	var voice: Dictionary = _get_voice_for_profile(profile)
	if voice.voice_id.is_empty():
		print("[TTSHelper] 无可用语音，跳过朗读")
		return

	var pitch: float = voice.pitch
	var rate: float = voice.rate
	print("[TTSHelper] 朗读: profile=%d voice=%s pitch=%.2f rate=%.2f" % [profile, voice.voice_id, pitch, rate])
	# Godot 4.7 参数顺序：text, voice, volume, pitch, rate, utterance_id, interrupt。
	DisplayServer.tts_speak(text, voice.voice_id, 100, pitch, rate, 0, interrupt)


static func _get_doubao_service() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree and is_instance_valid(loop.root):
		return loop.root.get_node_or_null("TTSService")
	return null


## 根据 NPC 名称自动选择音色并朗读
static func speak_with_name(text: String, npc_name: String, interrupt: bool = true) -> void:
	var profile: VoiceProfile = get_profile_for_npc(npc_name)
	speak(text, profile, interrupt)


## 停止当前朗读。
static func stop() -> void:
	DisplayServer.tts_stop()
	var doubao := _get_doubao_service()
	if doubao:
		doubao.stop()
	if _sapi_pid != 0:
		OS.kill(_sapi_pid)
		_sapi_pid = 0


## Windows SAPI 回退朗读（当 Godot TTS 不可用时）
static func _sapi_speak(text: String, profile: VoiceProfile, interrupt: bool) -> void:
	if interrupt and _sapi_pid != 0:
		OS.kill(_sapi_pid)
		_sapi_pid = 0

	# 根据音色选择 SAPI 声音
	var voice_name := "Microsoft Huihui"
	match profile:
		VoiceProfile.YOUNG_MALE, VoiceProfile.OLD_MALE:
			voice_name = "Microsoft Kangkang"

	# 语速映射：Godot rate 1.0 = SAPI rate 0
	var params: Dictionary = PROFILE_PARAMS.get(profile, {"pitch": 1.0, "rate": 1.0})
	var sapi_rate := int((float(params.get("rate", 1.0)) - 1.0) * 10.0)
	sapi_rate = clamp(sapi_rate, -10, 10)

	# 转义 PowerShell 特殊字符；单行文本避免换行破坏命令行参数。
	var escaped := text.replace("\r", " ").replace("\n", " ").replace("'", "''").replace("`", "``").replace("$", "`$")

	# 使用同步标志 0。异步标志会让 PowerShell 在真正出声前退出，导致静音。
	var cmd := "$ErrorActionPreference='Stop'; $v=New-Object -ComObject SAPI.SpVoice; $vs=$v.GetVoices(); for($i=0;$i -lt $vs.Count;$i++){ if($vs.Item($i).GetDescription() -like '*%s*'){$v.Voice=$vs.Item($i);break} }; $v.Volume=100; $v.Rate=%d; $v.Speak('%s',0)" % [voice_name, sapi_rate, escaped]

	var powershell_path := "powershell.exe"
	var system_root := OS.get_environment("SystemRoot")
	if not system_root.is_empty():
		var candidate := system_root.path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
		if FileAccess.file_exists(candidate):
			powershell_path = candidate
	_sapi_pid = OS.create_process(powershell_path, ["-WindowStyle", "Hidden", "-NoProfile", "-Command", cmd], false)
	print("[TTSHelper] SAPI朗读: voice=%s rate=%d" % [voice_name, sapi_rate])
