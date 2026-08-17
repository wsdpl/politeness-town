# 礼貌小镇 (Politeness Town)

一个基于 Godot 4.7 开发的儿童礼貌教育 RPG 游戏，通过情景闯关帮助儿童学习礼貌用语和社交技能。

## 项目简介

本项目是一个儿童礼貌教育评估系统，采用 RPG 游戏形式，包含两个主要板块：

- **板块一：礼貌小屋** — 6个关卡，涵盖问候、请求、道谢、责任、分享、告别等礼貌维度
- **板块二：阳光超市** — 2条故事线，3个NPC交互，综合评估儿童礼貌表现

## 功能特性

- RPG 探索玩法：玩家控制角色在场景中移动，与NPC交互
- AI 评分系统：集成 DeepSeek API 对儿童回答进行礼貌评分
- 语音识别：集成科大讯飞 API 实现语音输入
- 星露谷风格对话框：大字体、头像、点击继续
- 互动小游戏：宝箱、积木、绘本
- 雷达图结果报告：多维度可视化评估结果

## 技术栈

- **游戏引擎**: Godot 4.7
- **编程语言**: GDScript
- **AI 接口**: DeepSeek API
- **语音识别**: 科大讯飞 WebAPI
- **美术素材**: AI Town 项目角色素材 + 自制场景贴图

## 项目结构

```
礼貌小镇/
├── project.godot              # Godot 项目配置
├── assessment/                # 评估系统核心
│   ├── AssessmentGameManager.gd
│   ├── AssessmentAIManager.gd
│   ├── AssessmentData.gd
│   ├── AssessmentStorage.gd
│   ├── AssessmentUiTheme.gd
│   ├── IFlytekSpeechRecognition.gd
│   └── PolitenessScoring.gd
├── ui/
│   ├── assessment/            # UI 组件（对话框、注册、结果等）
│   └── rpg/                   # RPG 场景（玩家、NPC、关卡）
│       ├── PolitenessHouseRpg.gd
│       ├── SunshineMarketRpg.gd
│       ├── RpgPlayer.gd
│       └── RpgNpc.gd
├── assets/                    # 美术资源
│   ├── characters/            # 角色精灵
│   ├── fonts/                 # 字体
│   ├── maps/                  # 地图背景
│   ├── minigames/             # 小游戏贴图
│   └── scene_objects/         # 场景物体贴图
└── export_presets.cfg         # 导出预设
```

## 快速开始

1. 安装 [Godot 4.7](https://godotengine.org/download/)
2. 用 Godot 编辑器打开本项目
3. 运行项目（F5）

已导出的 Windows 发布版位于 `build/礼貌小镇_v1.1.0.exe`。完整的功能完成度、测试方法和研究上线门禁见 `PROJECT_AUDIT.md`。

## API 配置

在游戏内的"API设置"页面配置：
- **DeepSeek API Key** — 用于AI评分
- **讯飞 APP_ID / API_KEY / API_SECRET** — 用于语音识别

未配置API时游戏可正常运行，AI评分会自动跳过。

正式测量在未配置 DeepSeek 时使用本地规则评分；配置后将 DeepSeek 作为可选语义复核。儿童数据会始终保存到本地，并在 `assessment/server_upload_enabled=true` 时上传到配置的服务器数据库。

## 许可证

本项目仅供教育用途。
