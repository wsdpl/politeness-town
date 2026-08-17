## AssessmentData.gd
## 儿童礼貌测评系统 - 场景数据
## 包含板块一（礼貌小屋）6个关卡 和 板块二（阳光超市）两条故事线数据
## 所有数据为静态常量，通过函数接口获取

class_name AssessmentData
extends RefCounted

# ============================================================
# 板块一：礼貌小屋 - 6个关卡（固定顺序）
# ============================================================

const SECTION_ONE_LEVELS: Array = [
	# ---- 关卡1：迎宾问候 ----
	{
		"id": 1,
		"code": "L01",
		"name": "迎宾问候",
		"dimension": "问候维度",
		"scene": "礼貌小屋入口",
		"description": "儿童进入礼貌小屋时，观察其是否主动发起问候及能否延展互动。",
		"measure_point_count": 2,
		"measure_points": [
			{
				"id": "MP1-1",
				"name": "问候自发性",
				"description": "儿童是否在没有成人提示的情况下，主动向迎宾角色发起问候（如『你好』『早上好』），评估问候行为的内化程度。"
			},
			{
				"id": "MP1-2",
				"name": "互动延展性",
				"description": "儿童在完成基础问候后，能否追加互动内容（如称呼对方、询问近况、表达情绪），评估社交回合的延展能力。"
			}
		],
		"friend_ai": [
			{
				"step": 1,
				"speaker": "小熊布布",
				"text": "哇，你来啦！我是小熊布布，等你好久啦！你想跟我打个招呼吗？",
				"measure_point": "MP1-1 问候自发性"
			},
			{
				"step": 2,
				"speaker": "小熊布布",
				"text": "你跟我说了『你好』，真棒呀！布布好开心！你今天心情怎么样呀？",
				"measure_point": "MP1-2 互动延展性"
			},
			{
				"step": 3,
				"speaker": "小熊布布",
				"text": "谢谢你告诉我！你真是个有礼貌的好朋友，我们手拉手进去玩吧！",
				"measure_point": "MP1-2 互动延展性"
			}
		],
		"tool_ai": [
			{
				"step": 1,
				"speaker": "引导系统",
				"text": "请向门口的角色发出问候。",
				"measure_point": "MP1-1 问候自发性"
			},
			{
				"step": 2,
				"speaker": "引导系统",
				"text": "问候已完成。请尝试补充一句对话内容。",
				"measure_point": "MP1-2 互动延展性"
			},
			{
				"step": 3,
				"speaker": "引导系统",
				"text": "互动延展任务完成。记录数据，进入下一关卡。",
				"measure_point": "MP1-2 互动延展性"
			}
		]
	},

	# ---- 关卡2：玩具请求 ----
	{
		"id": 2,
		"code": "L02",
		"name": "玩具请求",
		"dimension": "请求维度",
		"scene": "玩具角",
		"description": "儿童面对心仪玩具时，观察其请求行为的基础表达、礼貌标记使用及高阶协商能力。",
		"measure_point_count": 3,
		"measure_points": [
			{
				"id": "MP2-1",
				"name": "基础请求",
				"description": "儿童能否用语言或手势表达『我想要XX』的基本请求意图，评估请求行为的发起能力。"
			},
			{
				"id": "MP2-2",
				"name": "礼貌标记诱发",
				"description": "在AI轻推提示后，儿童能否在请求中加入『请』『可以吗』等礼貌标记词，评估礼貌修饰语的使用意识。"
			},
			{
				"id": "MP2-3",
				"name": "高阶协商",
				"description": "当初始请求遇到条件限制（如需要等待、轮流）时，儿童能否进行协商（如『那我等一下』『换一个可以吗』），评估灵活协商能力。"
			}
		],
		"friend_ai": [
			{
				"step": 1,
				"speaker": "小兔朵朵",
				"text": "你看！这里好多玩具呀，有积木、小汽车、还有恐龙！你想要哪个呢？告诉朵朵好不好？",
				"measure_point": "MP2-1 基础请求"
			},
			{
				"step": 2,
				"speaker": "小兔朵朵",
				"text": "你想要小汽车呀！不过呀，说『请』的时候，别人会更愿意给你哦。你试试加上『请』好不好？",
				"measure_point": "MP2-2 礼貌标记诱发"
			},
			{
				"step": 3,
				"speaker": "小兔朵朵",
				"text": "你说了『请给我小汽车』，太有礼貌啦！不过小汽车现在被别的小朋友玩着呢，我们可以等一下，或者先玩积木好不好？你选哪个呀？",
				"measure_point": "MP2-3 高阶协商"
			}
		],
		"tool_ai": [
			{
				"step": 1,
				"speaker": "引导系统",
				"text": "请表达你想要的玩具。",
				"measure_point": "MP2-1 基础请求"
			},
			{
				"step": 2,
				"speaker": "引导系统",
				"text": "请在请求中加入礼貌用语（如『请』）。",
				"measure_point": "MP2-2 礼貌标记诱发"
			},
			{
				"step": 3,
				"speaker": "引导系统",
				"text": "当前玩具暂不可用。请尝试协商（等待或更换）。",
				"measure_point": "MP2-3 高阶协商"
			}
		]
	},

	# ---- 关卡3：礼物道谢 ----
	{
		"id": 3,
		"code": "L03",
		"name": "礼物道谢",
		"dimension": "道谢维度",
		"scene": "礼物桌",
		"description": "通过三次递进的礼物给予场景，观察儿童道谢行为的自发性、情境适应性和情感表达深度。",
		"measure_point_count": 3,
		"measure_points": [
			{
				"id": "MP3-1",
				"name": "贴纸道谢",
				"description": "收到小贴纸时，儿童是否自发道谢，评估对低价值礼物的感恩反应基线。"
			},
			{
				"id": "MP3-2",
				"name": "帮助后道谢",
				"description": "接受AI帮助（如捡起掉落物品）后，儿童是否道谢，评估对服务性行为的感恩意识。"
			},
			{
				"id": "MP3-3",
				"name": "勋章道谢",
				"description": "获得勋章等高价值/仪式性奖励时，儿童能否表达更丰富的道谢内容（如说明感谢原因），评估深层感恩表达。"
			}
		],
		"friend_ai": [
			{
				"step": 1,
				"speaker": "小猫喵喵",
				"text": "送你一颗亮闪闪的星星贴纸！这是喵喵特意给你挑的哦，你喜欢吗？",
				"measure_point": "MP3-1 贴纸道谢"
			},
			{
				"step": 2,
				"speaker": "小猫喵喵",
				"text": "哎呀，你的画笔掉地上了，喵喵帮你捡起来啦！给你～",
				"measure_point": "MP3-2 帮助后道谢"
			},
			{
				"step": 3,
				"speaker": "小猫喵喵",
				"text": "当当当当！这是礼貌小勇士勋章！因为你今天表现得特别好！你想跟喵喵说什么呀？",
				"measure_point": "MP3-3 勋章道谢"
			}
		],
		"tool_ai": [
			{
				"step": 1,
				"speaker": "引导系统",
				"text": "收到贴纸。请做出回应。",
				"measure_point": "MP3-1 贴纸道谢"
			},
			{
				"step": 2,
				"speaker": "引导系统",
				"text": "已获得帮助。请做出回应。",
				"measure_point": "MP3-2 帮助后道谢"
			},
			{
				"step": 3,
				"speaker": "引导系统",
				"text": "获得勋章。请表达感谢，可说明感谢原因。",
				"measure_point": "MP3-3 勋章道谢"
			}
		]
	},

	# ---- 关卡4：积木致歉 ----
	{
		"id": 4,
		"code": "L04",
		"name": "积木致歉",
		"dimension": "致歉维度",
		"scene": "积木区",
		"description": "通过积木倒塌情境，观察儿童的即时责任意识和致歉后的补偿行为。",
		"measure_point_count": 2,
		"measure_points": [
			{
				"id": "MP4-1",
				"name": "即时责任意识",
				"description": "积木被碰倒后，儿童是否在无提示下立即意识到自身责任并表达歉意（如『对不起』），评估致歉的自发性与责任归因。"
			},
			{
				"id": "MP4-2",
				"name": "后果陈述后补偿行为",
				"description": "在AI陈述后果（如『积木塌了，城堡没有了』）后，儿童能否提出补偿方案（如『我帮你重新搭』『下次我会小心』），评估致歉后的行为修复能力。"
			}
		],
		"friend_ai": [
			{
				"step": 1,
				"speaker": "小象笨笨",
				"text": "哇！积木城堡塌了……笨笨搭了好久好久的呢。呜呜，城堡没有了……",
				"measure_point": "MP4-1 即时责任意识"
			},
			{
				"step": 2,
				"speaker": "小象笨笨",
				"text": "没关系没关系，笨笨不生气。不过积木城堡真的塌了，我们得想想怎么办呀。你有什么好主意吗？",
				"measure_point": "MP4-2 后果陈述后补偿行为"
			}
		],
		"tool_ai": [
			{
				"step": 1,
				"speaker": "引导系统",
				"text": "积木已倒塌。请确认责任并回应。",
				"measure_point": "MP4-1 即时责任意识"
			},
			{
				"step": 2,
				"speaker": "引导系统",
				"text": "后果已陈述。请提出补偿方案。",
				"measure_point": "MP4-2 后果陈述后补偿行为"
			}
		]
	},

	# ---- 关卡5：绘本分享 ----
	{
		"id": 5,
		"code": "L05",
		"name": "绘本分享",
		"dimension": "分享维度",
		"scene": "阅读角",
		"description": "通过共读绘本情境，观察儿童初始分享意愿和在交换条件下的灵活性与妥协能力。",
		"measure_point_count": 2,
		"measure_points": [
			{
				"id": "MP5-1",
				"name": "初始分享意愿",
				"description": "小礼提出想看同一本绘本时，儿童是否愿意分享或轮流，评估无附加条件下的分享倾向。"
			},
			{
				"id": "MP5-2",
				"name": "交换条件下灵活性",
				"description": "当小礼提出用另一本绘本交换时，儿童能否接受交换或在协商中表现出灵活性（如『那你先看我这本，我再看你那本』），评估条件性分享的适应力。"
			}
		],
		"friend_ai": [
			{
				"step": 1,
				"speaker": "小狐狸粒粒",
				"text": "哇，你在看恐龙绘本呀！粒粒也好想看这本呢！可以跟粒粒一起看，或者让粒粒先看一小会儿吗？",
				"measure_point": "MP5-1 初始分享意愿"
			},
			{
				"step": 2,
				"speaker": "小狐狸粒粒",
				"text": "谢谢你愿意分享！那粒粒有一本超棒的太空绘本，我们交换看好不好？你先看太空的，粒粒看恐龙的，看完再换回来！",
				"measure_point": "MP5-2 交换条件下灵活性"
			}
		],
		"tool_ai": [
			{
				"step": 1,
				"speaker": "引导系统",
				"text": "有角色请求共同阅读。请做出分享回应。",
				"measure_point": "MP5-1 初始分享意愿"
			},
			{
				"step": 2,
				"speaker": "引导系统",
				"text": "对方提出绘本交换。请回应交换提议。",
				"measure_point": "MP5-2 交换条件下灵活性"
			}
		]
	},

	# ---- 关卡6：出口告别 ----
	{
		"id": 6,
		"code": "L06",
		"name": "出口告别",
		"dimension": "告别维度",
		"scene": "礼貌小屋出口",
		"description": "在离开礼貌小屋时，观察儿童自然道别的自发性和在轻度诱发下的告别能力。",
		"measure_point_count": 2,
		"measure_points": [
			{
				"id": "MP6-1",
				"name": "自然道别",
				"description": "到达出口时，儿童是否在无提示下主动道别（如『再见』『拜拜』），评估告别行为的内化程度。"
			},
			{
				"id": "MP6-2",
				"name": "轻度诱发下告别",
				"description": "在AI发出轻度提示（如『我要走了哦』）后，儿童能否回应告别并附加内容（如『下次再来玩』），评估诱发条件下的告别延展能力。"
			}
		],
		"friend_ai": [
			{
				"step": 1,
				"speaker": "小熊布布",
				"text": "我们到出口啦！今天玩得好开心呀！布布要回去休息了，你呢？",
				"measure_point": "MP6-1 自然道别"
			},
			{
				"step": 2,
				"speaker": "小熊布布",
				"text": "布布要跟你说再见啦！希望你下次还来找我玩哦！你要跟布布说什么呀？",
				"measure_point": "MP6-2 轻度诱发下告别"
			}
		],
		"tool_ai": [
			{
				"step": 1,
				"speaker": "引导系统",
				"text": "已到达出口。请进行告别。",
				"measure_point": "MP6-1 自然道别"
			},
			{
				"step": 2,
				"speaker": "引导系统",
				"text": "对方已发出告别提示。请回应告别。",
				"measure_point": "MP6-2 轻度诱发下告别"
			}
		]
	}
]

# ============================================================
# 板块二：阳光超市 - 故事线一（社会距离事件）
# ============================================================

const SECTION_TWO_STORY_LINE_1: Array = [
	# ---- 事件1：小朋友乐乐的球卡在树上 ----
	{
		"event_id": "S1-E1",
		"name": "球卡树上",
		"description": "在超市门口广场，小朋友乐乐的球卡在树上取不下来，需要儿童主动帮助或请求协助。",
		"pressure_level": "低",
		"social_distance": {
			"type": "低",
			"label": "亲近",
			"description": "对方为同龄玩伴，社会距离近，互动压力低。"
		},
		"expected_politeness_level": "3-4",
		"npc": {
			"character_id": "lele",
			"name": "乐乐",
			"role": "同龄玩伴",
			"age": 5,
			"appearance": "穿蓝色T恤的小男孩，手里拿着一个够不到树枝的网兜",
			"personality": "活泼开朗，略带焦急"
		},
		"scene_context": "超市门口的小广场，一棵矮树下，乐乐踮着脚想够卡在树枝上的红色皮球。",
		"interaction_goal": "儿童需观察乐乐的困境，主动询问或提供帮助，使用适当的请求和协商语言。",
		"dialogue_steps": [
			{
				"step": 1,
				"speaker": "小礼",
				"text": "看，前面是乐乐小朋友！他的球卡在树上了。你先跟他打个招呼吧。",
				"intent": "问候诱发",
				"measure_point": "问候自发性"
			},
			{
				"step": 2,
				"speaker": "乐乐",
				"text": "你好呀！我的球卡在上面了，你能帮帮我吗？",
				"intent": "请求帮助",
				"measure_point": "请求礼貌"
			},
			{
				"step": 3,
				"speaker": "乐乐",
				"text": "可是我没有长棍子，也不敢爬树。你有什么好办法吗？",
				"intent": "协商与合作",
				"measure_point": "协商与合作"
			},
			{
				"step": 4,
				"speaker": "乐乐",
				"text": "哇，球真的掉下来了！太谢谢你了，你真是我的好朋友！",
				"intent": "感谢与社交延展",
				"measure_point": "道谢回应"
			}
		]
	},

	# ---- 事件2：草莓老师提重物找路 ----
	{
		"event_id": "S1-E2",
		"name": "老师找路",
		"description": "在超市走廊，草莓老师提着很重的教具箱子迷路了，需要儿童以对长辈/权威的礼貌方式提供帮助。",
		"pressure_level": "中",
		"social_distance": {
			"type": "高",
			"label": "权威",
			"description": "对方为老师角色，社会距离远，存在权威层级，需使用尊称和更规范的礼貌用语。"
		},
		"expected_politeness_level": "4或3",
		"npc": {
			"character_id": "strawberry_teacher",
			"name": "草莓老师",
			"role": "幼儿园老师",
			"age": 28,
			"appearance": "穿粉色围裙的年轻女老师，双手提着两个装满教具的大纸箱，额头有汗珠",
			"personality": "温和但疲惫，说话轻柔"
		},
		"scene_context": "超市二楼走廊岔路口，草莓老师站在指示牌前左右为难，手里提着沉重的教具箱。",
		"interaction_goal": "儿童需识别老师的需求，使用尊称主动询问，提供指路或帮助提物，语言规范程度需高于同伴互动。",
		"dialogue_steps": [
			{
				"step": 1,
				"speaker": "小礼",
				"text": "前面是草莓老师，她抱着好多书。你先跟老师问个好吧。",
				"intent": "问候诱发",
				"measure_point": "对老师问候"
			},
			{
				"step": 2,
				"speaker": "草莓老师",
				"text": "小朋友你好呀！请问阳光超市是往左边走还是右边走？",
				"intent": "请求指引",
				"measure_point": "礼貌指路"
			},
			{
				"step": 3,
				"speaker": "草莓老师",
				"text": "谢谢你告诉我方向！这些书实在太沉了，你能帮我拿一本最薄的吗？",
				"intent": "请求助人",
				"measure_point": "助人回应"
			},
			{
				"step": 4,
				"speaker": "草莓老师",
				"text": "谢谢你呀！你真是个懂礼貌、爱助人的好孩子！",
				"intent": "感谢与评价",
				"measure_point": "道谢回应"
			}
		]
	},

	# ---- 事件3：陌生人阿姨找钥匙 ----
	{
		"event_id": "S1-E3",
		"name": "陌生人找钥匙",
		"description": "在超市停车场附近，一位陌生阿姨在地上找钥匙，需要儿童在保持安全距离的前提下以适当礼貌方式回应。",
		"pressure_level": "中",
		"social_distance": {
			"type": "中等",
			"label": "陌生人",
			"description": "对方为不认识的成年人，社会距离中等，需平衡礼貌与安全意识。"
		},
		"expected_politeness_level": "3",
		"npc": {
			"character_id": "stranger_auntie",
			"name": "陌生阿姨",
			"role": "陌生人",
			"age": 35,
			"appearance": "穿灰色外套的女性，蹲在地上翻找手提包，表情焦急",
			"personality": "礼貌但急切"
		},
		"scene_context": "超市出口旁的花坛边，陌生阿姨蹲在地上翻找东西，嘴里念叨着『钥匙呢钥匙呢』。",
		"interaction_goal": "儿童需在保持适当距离的情况下，判断是否回应，使用基本礼貌用语，同时展现安全意识（不跟随、不接触随身物品）。",
		"dialogue_steps": [
			{
				"step": 1,
				"speaker": "小礼",
				"text": "那边有位阿姨好像在找东西。她转过来了，你先跟她打个招呼吧。",
				"intent": "问候诱发",
				"measure_point": "对陌生人问候"
			},
			{
				"step": 2,
				"speaker": "陌生阿姨",
				"text": "小朋友你好！你有没有看到一把红色的钥匙呀？",
				"intent": "请求帮助",
				"measure_point": "礼貌拒绝或提议"
			},
			{
				"step": 3,
				"speaker": "陌生阿姨",
				"text": "没看见啊……那你能不能陪我去长椅那边再找找？",
				"intent": "协商与安全边界",
				"measure_point": "同意或婉拒"
			},
			{
				"step": 4,
				"speaker": "陌生阿姨",
				"text": "找到了！太谢谢你了，阿姨要走了，拜拜！",
				"intent": "道谢与告别",
				"measure_point": "礼貌告别"
			}
		]
	}
]

# ============================================================
# 板块二：阳光超市 - 故事线二（压力递进购物任务）
# ============================================================

const SECTION_TWO_STORY_LINE_2: Array = [
	# ---- 阶段1：找购物车（低压力） ----
	{
		"phase_id": "S2-P1",
		"name": "找购物车",
		"pressure_level": "低",
		"pressure_description": "低压力情境，任务简单明确，社交互动需求低，观察儿童的基础礼貌基线。",
		"round_count": 3,
		"scene_context": "超市入口的购物车都被推走了，儿童需向店员询问、复述确认并道谢。",
		"interaction_goal": "观察儿童在简单购物任务中的基础礼貌表现，包括请求、道谢等基础行为。",
		"rounds": [
			{
				"round": 1,
				"title": "取购物车",
				"description": "儿童走到购物车区域，需要取一辆车。",
				"npc": {
					"character_id": "cart_attendant",
					"name": "店员阿姨",
					"role": "超市员工",
					"personality": "友善随和"
				},
				"ai_prompt_friend": "我们到超市啦！可是门口一辆购物车都没有。那边有店员阿姨，你去问问她哪里还有购物车吧？",
				"ai_prompt_tool": "服务台有工作人员。请提出购物车查询请求。",
				"measure_point": "基础请求礼貌",
				"expected_behavior": "使用请问、可以吗等礼貌请求"
			},
			{
				"round": 2,
				"title": "位置不确定",
				"description": "店员给出模糊位置，儿童需要复述或追问。",
				"npc": {
					"character_id": "cart_attendant",
					"name": "店员阿姨",
					"role": "超市员工",
					"personality": "友善随和"
				},
				"ai_prompt_friend": "购物车呀？停车场那边好像还有几辆，不过我不太确定。你是想问具体在哪边吗？",
				"ai_prompt_tool": "购物车可能位于停车场。请复述或追问位置。",
				"measure_point": "复述与追问",
				"expected_behavior": "礼貌复述请求或追问确切位置"
			},
			{
				"round": 3,
				"title": "道谢离开",
				"description": "管理员帮取出购物车后，儿童需道谢并推车进入超市。",
				"npc": {
					"character_id": "cart_attendant",
					"name": "店员阿姨",
					"role": "超市员工",
					"personality": "友善随和"
				},
				"ai_prompt_friend": "对对对，就是停车场那边！你找到了呀？太好了！",
				"ai_prompt_tool": "位置已确认，购物车已找到。",
				"measure_point": "道谢行为",
				"expected_behavior": "自发道谢并推车离开"
			}
		]
	},

	# ---- 阶段2：找限量贴纸（中压力-资源竞争） ----
	{
		"phase_id": "S2-P2",
		"name": "找限量贴纸",
		"pressure_level": "中",
		"pressure_description": "中压力情境，资源有限存在竞争，需协商与轮流，社交复杂度提升，观察儿童在资源竞争中的礼貌表现。",
		"round_count": 3,
		"scene_context": "超市文具区最高的货架上只剩最后一包限量贴纸，旁边的小妹妹也想要。",
		"interaction_goal": "观察儿童在资源竞争中的礼貌请求、分配协商和主动谦让。",
		"rounds": [
			{
				"round": 1,
				"title": "请店员取贴纸",
				"description": "贴纸位置过高，儿童需向店员提出礼貌请求。",
				"npc": {
					"character_id": "sticker_staff",
					"name": "店员叔叔",
					"role": "促销员",
					"personality": "热情但忙碌"
				},
				"ai_prompt_friend": "看，最上面那包就是限量贴纸，可是放得太高了。你去请店员叔叔帮忙拿下来吧？",
				"ai_prompt_tool": "物品位置过高。请向工作人员提出取物请求。",
				"measure_point": "升级请求策略",
				"expected_behavior": "使用请、可以吗并附带称呼"
			},
			{
				"round": 2,
				"title": "梯子资源竞争",
				"description": "梯子只有一把，旁边的小妹妹也需要使用。",
				"npc": {
					"character_id": "peer_kid",
					"name": "店员叔叔",
					"role": "同龄竞争者",
					"personality": "急切想要贴纸"
				},
				"ai_prompt_friend": "拿下来没问题！可是梯子只有一把，旁边那个小妹妹也要用，你说怎么办呢？",
				"ai_prompt_tool": "梯子资源唯一，存在使用竞争。请提出分配方案。",
				"measure_point": "分享与协商",
				"expected_behavior": "尝试协商或主动谦让"
			},
			{
				"round": 3,
				"title": "贴纸分配决策",
				"description": "贴纸已交给儿童，旁边的小妹妹仍在等待。",
				"npc": {
					"character_id": "sticker_staff",
					"name": "店员叔叔",
					"role": "促销员",
					"personality": "抱歉且安慰"
				},
				"ai_prompt_friend": "好的，就按你说的办！现在贴纸是你的了，但小妹妹一直在看你哦，你想怎么处理呀？",
				"ai_prompt_tool": "方案已采纳，物品已交付。竞争者仍在场。",
				"measure_point": "主动谦让与社交决策",
				"expected_behavior": "主动分享、轮流或礼貌说明决定"
			}
		]
	},

	# ---- 阶段3：打碎纪念品（高压-道歉+请求复合） ----
	{
		"phase_id": "S2-P3",
		"name": "纪念杯意外",
		"pressure_level": "高",
		"pressure_description": "高压情境，儿童不慎打碎店主珍贵的纪念杯，需完成主动道歉、礼貌请求、礼貌词坚持与告别。",
		"round_count": 4,
		"scene_context": "超市货架旁，儿童转身时碰掉了店主珍贵的纪念杯。店员手部受伤，备用杯在仓库，钥匙在收银台。",
		"interaction_goal": "观察儿童在高压情境下的主动道歉、道歉+请求复合策略、礼貌坚持性和最终道谢告别。",
		"rounds": [
			{
				"round": 1,
				"title": "纪念杯碎了",
				"description": "系统标准化触发纪念杯破碎事件。",
				"npc": {
					"character_id": "cashier_strict",
					"name": "店员阿姨",
					"role": "超市店员",
					"personality": "惊讶但不指责"
				},
				"ai_prompt_friend": "啊……这个杯子……有点贵呢……",
				"ai_prompt_tool": "物品记录：高价值商品。状态：已损坏。",
				"measure_point": "道歉主动性",
				"expected_behavior": "在第一次机会主动道歉"
			},
			{
				"round": 2,
				"title": "请求取备用杯",
				"description": "店员手部受伤，请儿童帮忙去仓库取备用杯。",
				"npc": {
					"character_id": "cashier_strict",
					"name": "店员阿姨",
					"role": "超市店员",
					"personality": "宽容、需要帮助"
				},
				"ai_prompt_friend": "没关系，我知道你不是故意的。仓库里还有一个备用杯，但我的手被碎片划了一下，你能帮我去拿吗？钥匙在收银台。",
				"ai_prompt_tool": "备用品位于仓库。工作人员手部受伤。请协助取物，钥匙位于收银台。",
				"measure_point": "道歉与礼貌请求复合",
				"expected_behavior": "在道歉后礼貌请求收银员提供钥匙"
			},
			{
				"round": 3,
				"title": "收银台礼貌词验证",
				"description": "收银员要求儿童说出今天学到的礼貌词才给钥匙。",
				"npc": {
					"character_id": "cashier_strict",
					"name": "收银员王阿姨",
					"role": "超市收银员",
					"personality": "严厉但开始缓和"
				},
				"ai_prompt_friend": "我可以给你钥匙，但你要说出今天学到的礼貌魔法词才行！快说一个吧。",
				"ai_prompt_tool": "权限验证：请输出今日礼貌关键词，方可获取钥匙。",
				"measure_point": "礼貌坚持性",
				"expected_behavior": "重复使用请、谢谢或对不起等礼貌词"
			},
			{
				"round": 4,
				"title": "取回备用杯",
				"description": "系统自动完成取杯动画，儿童做最后道谢与告别。",
				"npc": {
					"character_id": "cashier_strict",
					"name": "收银员王阿姨",
					"role": "超市收银员",
					"personality": "态度已缓和"
				},
				"ai_prompt_friend": "你帮我拿回来了！太感谢了！今天的冒险结束了，我们跟超市说拜拜吧。",
				"ai_prompt_tool": "备用品已取回。全部任务已完成，数据已保存。请道谢并告别。",
				"measure_point": "道谢 + 告别 + 反思承诺",
				"expected_behavior": "道谢、告别并表达今后注意"
			}
		]
	}
]


# ============================================================
# 数据获取函数接口
# ============================================================

## 获取板块一全部关卡数据
static func get_all_section_one_levels() -> Array:
	return SECTION_ONE_LEVELS.duplicate(true)

## 获取板块一关卡数量
static func get_section_one_level_count() -> int:
	return SECTION_ONE_LEVELS.size()

## 根据关卡ID获取板块一单个关卡数据
static func get_section_one_level(level_id: int) -> Dictionary:
	for level in SECTION_ONE_LEVELS:
		if int(level.get("id", -1)) == level_id:
			return level.duplicate(true)
	push_warning("[AssessmentData] 未找到板块一关卡ID: %d" % level_id)
	return {}

## 根据关卡索引获取板块一关卡数据（0-based）
static func get_section_one_level_by_index(index: int) -> Dictionary:
	if index < 0 or index >= SECTION_ONE_LEVELS.size():
		push_warning("[AssessmentData] 板块一关卡索引越界: %d" % index)
		return {}
	return SECTION_ONE_LEVELS[index].duplicate(true)

## 获取指定关卡的朋友型AI台词
static func get_friend_ai_lines(level_id: int) -> Array:
	var level := get_section_one_level(level_id)
	if level.is_empty():
		return []
	return level.get("friend_ai", []).duplicate(true)

## 获取指定关卡的工具型AI台词
static func get_tool_ai_lines(level_id: int) -> Array:
	var level := get_section_one_level(level_id)
	if level.is_empty():
		return []
	return level.get("tool_ai", []).duplicate(true)

## 获取指定关卡的测量节点列表
static func get_measure_points(level_id: int) -> Array:
	var level := get_section_one_level(level_id)
	if level.is_empty():
		return []
	return level.get("measure_points", []).duplicate(true)

## 获取指定关卡的测量节点数量
static func get_measure_point_count(level_id: int) -> int:
	var level := get_section_one_level(level_id)
	if level.is_empty():
		return 0
	return int(level.get("measure_point_count", 0))

## 获取板块二故事线一全部事件数据
static func get_story_line_1_events() -> Array:
	return SECTION_TWO_STORY_LINE_1.duplicate(true)

## 获取板块二故事线一事件数量
static func get_story_line_1_event_count() -> int:
	return SECTION_TWO_STORY_LINE_1.size()

## 根据事件ID获取故事线一单个事件数据
static func get_story_line_1_event(event_id: String) -> Dictionary:
	for event in SECTION_TWO_STORY_LINE_1:
		if String(event.get("event_id", "")) == event_id:
			return event.duplicate(true)
	push_warning("[AssessmentData] 未找到故事线一事件ID: %s" % event_id)
	return {}

## 根据事件索引获取故事线一事件数据（0-based）
static func get_story_line_1_event_by_index(index: int) -> Dictionary:
	if index < 0 or index >= SECTION_TWO_STORY_LINE_1.size():
		push_warning("[AssessmentData] 故事线一事件索引越界: %d" % index)
		return {}
	return SECTION_TWO_STORY_LINE_1[index].duplicate(true)

## 获取板块二故事线二全部阶段数据
static func get_story_line_2_phases() -> Array:
	return SECTION_TWO_STORY_LINE_2.duplicate(true)

## 获取板块二故事线二阶段数量
static func get_story_line_2_phase_count() -> int:
	return SECTION_TWO_STORY_LINE_2.size()

## 根据阶段ID获取故事线二单个阶段数据
static func get_story_line_2_phase(phase_id: String) -> Dictionary:
	for phase in SECTION_TWO_STORY_LINE_2:
		if String(phase.get("phase_id", "")) == phase_id:
			return phase.duplicate(true)
	push_warning("[AssessmentData] 未找到故事线二阶段ID: %s" % phase_id)
	return {}

## 根据阶段索引获取故事线二阶段数据（0-based）
static func get_story_line_2_phase_by_index(index: int) -> Dictionary:
	if index < 0 or index >= SECTION_TWO_STORY_LINE_2.size():
		push_warning("[AssessmentData] 故事线二阶段索引越界: %d" % index)
		return {}
	return SECTION_TWO_STORY_LINE_2[index].duplicate(true)

## 获取故事线二指定阶段的全部轮次
static func get_story_line_2_rounds(phase_index: int) -> Array:
	var phase := get_story_line_2_phase_by_index(phase_index)
	if phase.is_empty():
		return []
	return phase.get("rounds", []).duplicate(true)

## 获取故事线二指定阶段指定轮次数据
static func get_story_line_2_round(phase_index: int, round_number: int) -> Dictionary:
	var rounds := get_story_line_2_rounds(phase_index)
	for r in rounds:
		if int(r.get("round", -1)) == round_number:
			return r.duplicate(true)
	push_warning("[AssessmentData] 未找到阶段%d轮次%d" % [phase_index, round_number])
	return {}

## 获取故事线二全部轮次总数
static func get_story_line_2_total_rounds() -> int:
	var total := 0
	for phase in SECTION_TWO_STORY_LINE_2:
		total += int(phase.get("round_count", 0))
	return total

## 获取板块二全部数据（两条故事线）
static func get_all_section_two_data() -> Dictionary:
	return {
		"story_line_1": SECTION_TWO_STORY_LINE_1.duplicate(true),
		"story_line_2": SECTION_TWO_STORY_LINE_2.duplicate(true)
	}

## 获取全部测评数据
static func get_all_data() -> Dictionary:
	return {
		"section_one": SECTION_ONE_LEVELS.duplicate(true),
		"section_two": {
			"story_line_1": SECTION_TWO_STORY_LINE_1.duplicate(true),
			"story_line_2": SECTION_TWO_STORY_LINE_2.duplicate(true)
		}
	}
