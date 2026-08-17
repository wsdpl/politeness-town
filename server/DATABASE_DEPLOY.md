# 礼貌小镇 — 服务器数据库部署文档

> 供 Codex 协助部署服务器端数据库使用。请按以下步骤完成 MySQL 建库建表、Node.js 后端配置和防火墙开放。

---

## 1. 服务器信息

| 配置项 | 值 |
|---|---|
| 服务器公网 IP | `192.144.163.234` |
| SSH 登录方式 | `ssh ubuntu@192.144.163.234` |
| MySQL 端口 | `3306`（默认） |
| Node.js 服务端口 | `3000` |
| MySQL 用户名 | `politeness_town` |
| MySQL 密码 | 通过服务器环境变量 `MYSQL_PASSWORD` 注入，不写入源码 |
| MySQL 数据库名 | `politeness_town` |
| 字符集 | `utf8mb4` / `utf8mb4_unicode_ci` |

---

## 2. 已有建表脚本

完整建表 SQL 文件位于项目目录：

```
d:\礼貌小镇\server\database\politeness_town_schema.sql
```

**该文件包含全部 8 张表的 CREATE TABLE 语句**，可直接导入 MySQL。以下是要点摘要。

### 2.1 数据库创建

```sql
CREATE DATABASE IF NOT EXISTS politeness_town
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_unicode_ci;
USE politeness_town;
```

### 2.2 核心表（3 张 — 游戏运行时上传数据用）

#### 表1：`participants` — 被试信息表

| 字段 | 类型 | 说明 |
|---|---|---|
| `child_id` | INT AUTO_INCREMENT PK | 被试编号 |
| `nickname` | VARCHAR(50) NOT NULL | 昵称 |
| `age_months` | INT NOT NULL | 月龄（48-83 即 4-6 岁） |
| `gender` | TINYINT NOT NULL | 性别: 1=男 2=女 |
| `ai_type` | TINYINT NOT NULL | AI 角色类型: 1=朋友型 2=工具型 |
| `baseline_score` | DECIMAL(5,2) | 预热阶段礼貌基线分数 |
| `school` | VARCHAR(100) | 学校名称 |
| `class_name` | VARCHAR(50) | 班级 |
| `has_language_disorder` | TINYINT DEFAULT 0 | 是否有语言障碍: 0=无 1=有 |
| `device_usage_level` | TINYINT | 设备使用程度: 1=低 2=正常 3=高 |
| `test_date` | DATE | 正式施测日期 |
| `retest_date` | DATE | 重测日期（仅 30 名抽样） |
| `is_retest_sample` | TINYINT DEFAULT 0 | 是否重测样本 |
| `created_at` | DATETIME DEFAULT NOW | 记录创建时间 |

#### 表2：`task_scores` — 任务得分表（统计分析主表）

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | BIGINT AUTO_INCREMENT PK | 记录 ID |
| `child_id` | INT FK→participants | 被试编号 |
| `task_id` | TINYINT NOT NULL | 任务编号: 1=问候 2=请求 3=道谢 4=致歉 5=分享 6=告别 |
| `dimension` | VARCHAR(20) NOT NULL | 礼貌维度: greeting/request/thanks/apology/share/farewell |
| `marker_total_count` | INT DEFAULT 0 | 标记词总频次（去重后） |
| `marker_qing_count` | INT DEFAULT 0 | "请"频次 |
| `marker_xiexie_count` | INT DEFAULT 0 | "谢谢"频次 |
| `marker_duiqi_count` | INT DEFAULT 0 | "对不起"频次 |
| `marker_haoma_count` | INT DEFAULT 0 | "好吗"频次 |
| `marker_keyima_count` | INT DEFAULT 0 | "可以吗"频次 |
| `marker_frequency` | DECIMAL(8,2) | 每分钟标记词频次（因变量1） |
| `average_level` | DECIMAL(4,2) | 平均策略等级 1-5（因变量2） |
| `level_1_count` ~ `level_5_count` | INT | 各等级频次 |
| `level_1_ratio` ~ `level_5_ratio` | DECIMAL(5,4) | 各等级占比 |
| `duration_minutes` | DECIMAL(6,2) | 互动总时长（分钟） |
| `turn_count` | INT | 话轮总数 |
| `task_score` | DECIMAL(6,2) | 任务综合得分 |
| `created_at` | DATETIME DEFAULT NOW | 记录创建时间 |

- 唯一约束：`UNIQUE KEY uk_child_task (child_id, task_id)`
- 外键：`fk_score_child` → `participants(child_id)` ON DELETE CASCADE

#### 表3：`turn_details` — 话轮明细表

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | BIGINT AUTO_INCREMENT PK | 记录 ID |
| `child_id` | INT FK→participants | 被试编号 |
| `task_id` | TINYINT NOT NULL | 任务编号 |
| `turn_index` | INT NOT NULL | 话轮序号（从 1 开始） |
| `speaker` | VARCHAR(10) NOT NULL | child=儿童 ai=AI system=系统 |
| `text` | TEXT | 发言原文 |
| `level` | TINYINT | AI 编码策略等级 1-5 |
| `markers` | JSON | 命中的标记词列表，如 `["请","谢谢"]` |
| `dimension` | VARCHAR(20) NOT NULL | 礼貌维度 |
| `timestamp_sec` | DECIMAL(10,2) | 时间戳（秒） |
| `created_at` | DATETIME DEFAULT NOW | 记录创建时间 |

- 外键：`fk_turn_child` → `participants(child_id)` ON DELETE CASCADE

### 2.3 信度/效度表（5 张 — 研究阶段手动录入用）

这 5 张表在游戏运行时**不会自动上传数据**，仅用于后续研究阶段手动录入：

| 表名 | 用途 |
|---|---|
| `human_coding` | 人工编码表，2 名编码员评分者信度 |
| `retest_data` | 重测数据表，30 名儿童 2-4 周后重测 |
| `criterion_validity` | 效标关联效度表（教师评定） |
| `ecological_validity` | 生态效度表（AI vs 真人情境） |
| `expert_validity` | 专家内容效度评分表（I-CVI/S-CVI） |

---

## 3. 部署步骤

### 步骤 1：登录服务器并导入数据库

```bash
# SSH 登录
ssh ubuntu@192.144.163.234

# 上传建表脚本（在本地执行）
scp d:\礼貌小镇\server\database\politeness_town_schema.sql ubuntu@192.144.163.234:~/

# 在服务器上执行
mysql -u root -p < ~/politeness_town_schema.sql
```

### 步骤 2：创建 MySQL 用户并授权

```sql
-- 登录 MySQL
mysql -u root -p

-- 创建用户（请替换 YOUR_STRONG_PASSWORD 为实际密码）
CREATE USER 'politeness_town'@'localhost' IDENTIFIED BY 'YOUR_STRONG_PASSWORD';

-- 授权
GRANT ALL PRIVILEGES ON politeness_town.* TO 'politeness_town'@'localhost';
FLUSH PRIVILEGES;
```

### 步骤 3：配置并启动 Node.js 后端

```bash
# 创建服务目录
mkdir -p ~/politeness_town_server
cd ~/politeness_town_server

# 安装依赖
npm init -y
npm install express mysql2 cors body-parser

# 上传 server.js（在本地执行）
scp d:\礼貌小镇\server\server.js ubuntu@192.144.163.234:~/politeness_town_server/

# 使用环境变量配置 MySQL，密码不要写入 server.js
export PORT=3000
export MYSQL_USER=politeness_town
export MYSQL_DATABASE=politeness_town
export MYSQL_PASSWORD='你的实际密码'
export API_TOKEN='PoliteTown@2026'
```

**server.js 使用以下环境变量配置（无需修改源码）：**

```javascript
const PORT = Number(process.env.PORT || 3000);

const pool = mysql.createPool({
  host: process.env.MYSQL_HOST || 'localhost',
  port: Number(process.env.MYSQL_PORT || 3306),
  user: process.env.MYSQL_USER || 'politeness_town',
  password: process.env.MYSQL_PASSWORD,
  database: process.env.MYSQL_DATABASE || 'politeness_town',
  waitForConnections: true,
  connectionLimit: 10,
  charset: 'utf8mb4'
});
```

### 步骤 4：开放防火墙端口

```bash
# Ubuntu 24.04 使用 ufw 开放 Node.js API 端口
sudo ufw allow 3000/tcp
sudo ufw reload

# 验证
curl http://localhost:3000/api/health
# 应返回: {"status":"ok","database":"connected"}
```

### 步骤 5：启动服务（推荐用 PM2 守护进程）

```bash
# 安装 PM2
npm install -g pm2

# 启动服务
cd ~/politeness_town_server
pm2 start server.js --name politeness_town
pm2 save
pm2 startup  # 开机自启

# 查看日志
pm2 logs politeness_town
```

### 步骤 6：验证服务可用

```bash
# 健康检查
curl http://192.144.163.234:3000/api/health

# 统计概览（应返回 0 条数据）
curl http://192.144.163.234:3000/api/stats
```

---

## 4. 数据上传时机

### 何时上传

游戏在**测评全部完成时**（板块二阳光超市通关后）一次性上传所有数据。

### 上传流程

```
儿童完成全部测评（板块二通关）
  │
  ▼
AssessmentGameManager.complete_assessment()
  ├── 保存到本地 JSON（始终执行）
  └── 检查配置开关 assessment/server_upload_enabled
        │
        ▼ （如果为 true）
  ServerAPI.upload_session_complete()
        │  HTTP POST → http://192.144.163.234:3000/api/session-complete
        ▼
  server.js /api/session-complete（数据库事务）
        ├── INSERT INTO participants（被试信息）
        ├── INSERT INTO task_scores（每个场景的得分，6 条）
        └── INSERT INTO turn_details（所有话轮明细，分批每 500 条）
```

### 上传开关

当前默认**开启**，配置位于 `project.godot`：

```ini
[assessment]
server_upload_enabled=true
```

### API 端点一览

| 方法 | 端点 | 功能 |
|---|---|---|
| POST | `/api/session-complete` | **主用** — 测评完成一次性上传全部数据（事务） |
| POST | `/api/participant` | 注册单个被试 |
| POST | `/api/task-score` | 保存单条任务得分（ON DUPLICATE KEY UPDATE） |
| POST | `/api/turns` | 批量保存话轮明细 |
| GET | `/api/health` | 健康检查 |
| GET | `/api/stats` | 统计概览（各表记录数） |

---

## 5. 注意事项

1. **MySQL 密码**：通过服务器环境变量 `MYSQL_PASSWORD` 注入，不要写入源码
2. **上传开关**：`project.godot` 中 `server_upload_enabled` 当前为 `true`
3. **数据完整性**：`/api/session-complete` 使用数据库事务，要么全部成功要么全部回滚
4. **外键约束**：`task_scores` 和 `turn_details` 都有外键指向 `participants.child_id`，删除被试会级联删除相关数据
5. **唯一约束**：`task_scores` 表有 `UNIQUE KEY (child_id, task_id)`，重复上传会触发 `ON DUPLICATE KEY UPDATE`
6. **字符集**：所有表使用 `utf8mb4`，确保中文和 emoji 正确存储
7. **端口 3306**：MySQL 端口不需要对外暴露，Node.js 在服务器本地连接 `localhost:3306` 即可
8. **端口 3000**：Node.js 服务端口需要对外暴露，供游戏客户端 HTTP 请求使用
