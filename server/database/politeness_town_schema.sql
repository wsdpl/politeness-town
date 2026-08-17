-- ============================================================
-- 礼貌小镇测评系统数据库建表脚本
-- 适用于 MySQL 8.0+
-- 字符集: utf8mb4 (支持emoji和生僻字)
-- ============================================================

CREATE DATABASE IF NOT EXISTS politeness_town
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_unicode_ci;

USE politeness_town;

-- ============================================================
-- 表1：被试信息表 participants
-- 用途：组间比较、平衡检验、描述统计
-- ============================================================
DROP TABLE IF EXISTS `participants`;
CREATE TABLE `participants` (
    `child_id`              INT             NOT NULL AUTO_INCREMENT COMMENT '被试编号(主键)',
    `nickname`              VARCHAR(50)     NOT NULL COMMENT '昵称(朋友型AI称呼用)',
    `age_months`            INT             NOT NULL COMMENT '月龄(48-83即4-6岁)',
    `gender`                TINYINT         NOT NULL COMMENT '性别: 1=男 2=女',
    `ai_type`               TINYINT         NOT NULL COMMENT 'AI角色类型: 1=朋友型 2=工具型 (组间自变量)',
    `baseline_score`        DECIMAL(5,2)    DEFAULT NULL COMMENT '预热阶段礼貌基线分数',
    `school`                VARCHAR(100)    DEFAULT NULL COMMENT '学校名称',
    `class_name`            VARCHAR(50)     DEFAULT NULL COMMENT '班级',
    `has_language_disorder` TINYINT         NOT NULL DEFAULT 0 COMMENT '是否有语言障碍: 0=无 1=有(纳入标准)',
    `device_usage_level`    TINYINT         DEFAULT NULL COMMENT '设备使用程度: 1=低 2=正常 3=高',
    `test_date`             DATE            DEFAULT NULL COMMENT '正式施测日期',
    `retest_date`           DATE            DEFAULT NULL COMMENT '重测日期(仅30名抽样)',
    `is_retest_sample`      TINYINT         NOT NULL DEFAULT 0 COMMENT '是否重测样本: 0=否 1=是',
    `created_at`            DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '记录创建时间',
    PRIMARY KEY (`child_id`),
    INDEX `idx_ai_type`     (`ai_type`),
    INDEX `idx_gender_age`  (`gender`, `age_months`),
    INDEX `idx_school`      (`school`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='被试信息表';


-- ============================================================
-- 表2：任务得分表 task_scores （最核心）
-- 每个儿童×每个任务一行，共 140×6=840 行
-- 这是统计分析的主数据表
-- ============================================================
DROP TABLE IF EXISTS `task_scores`;
CREATE TABLE `task_scores` (
    `id`                    BIGINT          NOT NULL AUTO_INCREMENT COMMENT '记录ID',
    `child_id`              INT             NOT NULL COMMENT '被试编号(外键)',
    `task_id`               TINYINT         NOT NULL COMMENT '任务编号: 1=问候 2=请求 3=道谢 4=致歉 5=分享 6=告别',
    `dimension`             VARCHAR(20)     NOT NULL COMMENT '礼貌维度: greeting/request/thanks/apology/share/farewell',

    -- 因变量1：礼貌标记词频次
    `marker_total_count`    INT             NOT NULL DEFAULT 0 COMMENT '标记词总频次(去重后)',
    `marker_qing_count`     INT             NOT NULL DEFAULT 0 COMMENT '"请"频次',
    `marker_xiexie_count`   INT             NOT NULL DEFAULT 0 COMMENT '"谢谢"频次',
    `marker_duiqi_count`    INT             NOT NULL DEFAULT 0 COMMENT '"对不起"频次',
    `marker_haoma_count`    INT             NOT NULL DEFAULT 0 COMMENT '"好吗"频次',
    `marker_keyima_count`   INT             NOT NULL DEFAULT 0 COMMENT '"可以吗"频次',
    `marker_frequency`      DECIMAL(8,2)    NOT NULL DEFAULT 0 COMMENT '每分钟标记词频次 = 总频次/时长(因变量1)',

    -- 因变量2：五级礼貌策略等级
    `average_level`         DECIMAL(4,2)    DEFAULT NULL COMMENT '平均策略等级1-5(因变量2)',
    `level_1_count`         INT             NOT NULL DEFAULT 0 COMMENT '等级1频次(不实施威胁面子行为)',
    `level_2_count`         INT             NOT NULL DEFAULT 0 COMMENT '等级2频次(消极礼貌)',
    `level_3_count`         INT             NOT NULL DEFAULT 0 COMMENT '等级3频次(常规礼貌)',
    `level_4_count`         INT             NOT NULL DEFAULT 0 COMMENT '等级4频次(称呼+礼貌)',
    `level_5_count`         INT             NOT NULL DEFAULT 0 COMMENT '等级5频次(直白无饰)',
    `level_1_ratio`         DECIMAL(5,4)    DEFAULT NULL COMMENT '等级1占比',
    `level_2_ratio`         DECIMAL(5,4)    DEFAULT NULL COMMENT '等级2占比',
    `level_3_ratio`         DECIMAL(5,4)    DEFAULT NULL COMMENT '等级3占比',
    `level_4_ratio`         DECIMAL(5,4)    DEFAULT NULL COMMENT '等级4占比',
    `level_5_ratio`         DECIMAL(5,4)    DEFAULT NULL COMMENT '等级5占比',

    -- 辅助变量
    `duration_minutes`      DECIMAL(6,2)    DEFAULT NULL COMMENT '互动总时长(分钟)',
    `turn_count`            INT             DEFAULT NULL COMMENT '话轮总数',
    `task_score`            DECIMAL(6,2)    DEFAULT NULL COMMENT '任务综合得分(用于Cronbach α和CFA)',

    `created_at`            DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '记录创建时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_child_task` (`child_id`, `task_id`),
    INDEX `idx_child_id`    (`child_id`),
    INDEX `idx_task_id`     (`task_id`),
    INDEX `idx_ai_task`     (`child_id`, `task_id`),

    CONSTRAINT `fk_score_child`
        FOREIGN KEY (`child_id`)
        REFERENCES `participants` (`child_id`)
        ON DELETE CASCADE
        ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='任务得分表(统计分析主表)';


-- ============================================================
-- 表3：话轮明细表 turn_details
-- 供人工复核追溯(任务书: 记录每个标记词出现的话轮位置及上下文语境)
-- ============================================================
DROP TABLE IF EXISTS `turn_details`;
CREATE TABLE `turn_details` (
    `id`            BIGINT          NOT NULL AUTO_INCREMENT COMMENT '记录ID',
    `child_id`      INT             NOT NULL COMMENT '被试编号',
    `task_id`       TINYINT         NOT NULL COMMENT '任务编号1-6',
    `turn_index`    INT             NOT NULL COMMENT '话轮序号(从1开始)',
    `speaker`       VARCHAR(10)     NOT NULL COMMENT '说话者: child=儿童 ai=AI system=系统',
    `text`          TEXT            COMMENT '发言原文',
    `level`         TINYINT         DEFAULT NULL COMMENT 'AI编码策略等级1-5(用于Kappa)',
    `markers`       JSON            DEFAULT NULL COMMENT '命中的标记词列表, 如["请","谢谢"]',
    `dimension`     VARCHAR(20)     NOT NULL COMMENT '礼貌维度',
    `timestamp_sec` DECIMAL(10,2)   DEFAULT NULL COMMENT '该话轮相对开始的时间(秒)',
    `created_at`    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '记录创建时间',
    PRIMARY KEY (`id`),
    INDEX `idx_child_task`  (`child_id`, `task_id`),
    INDEX `idx_turn`        (`child_id`, `task_id`, `turn_index`),
    INDEX `idx_level`       (`level`),

    CONSTRAINT `fk_turn_child`
        FOREIGN KEY (`child_id`)
        REFERENCES `participants` (`child_id`)
        ON DELETE CASCADE
        ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='话轮明细表(人工复核追溯)';


-- ============================================================
-- 表4：人工编码表 human_coding
-- 评分者信度验证(抽取20%样本约28名, 2名编码员背对背编码)
-- ============================================================
DROP TABLE IF EXISTS `human_coding`;
CREATE TABLE `human_coding` (
    `id`            BIGINT          NOT NULL AUTO_INCREMENT COMMENT '记录ID',
    `child_id`      INT             NOT NULL COMMENT '被试编号',
    `task_id`       TINYINT         NOT NULL COMMENT '任务编号1-6',
    `turn_index`    INT             NOT NULL COMMENT '话轮序号',
    `coder_id`      TINYINT         NOT NULL COMMENT '编码员编号: 1或2',
    `human_level`   TINYINT         DEFAULT NULL COMMENT '人工编码策略等级1-5(与AI编码计算Kappa)',
    `human_markers` JSON            DEFAULT NULL COMMENT '人工标记词列表(与AI标记词计算Pearson r)',
    `coding_date`   DATE            DEFAULT NULL COMMENT '编码日期',
    `created_at`    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '记录创建时间',
    PRIMARY KEY (`id`),
    INDEX `idx_child_task`  (`child_id`, `task_id`),
    INDEX `idx_coder`       (`coder_id`),

    CONSTRAINT `fk_coding_child`
        FOREIGN KEY (`child_id`)
        REFERENCES `participants` (`child_id`)
        ON DELETE CASCADE
        ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='人工编码表(评分者信度)';


-- ============================================================
-- 表5：重测数据表 retest_data
-- 重测信度(30名儿童, 2-4周后重测, Pearson相关)
-- ============================================================
DROP TABLE IF EXISTS `retest_data`;
CREATE TABLE `retest_data` (
    `id`                    BIGINT          NOT NULL AUTO_INCREMENT COMMENT '记录ID',
    `child_id`              INT             NOT NULL COMMENT '被试编号',
    `test1_total_score`     DECIMAL(6,2)    NOT NULL COMMENT '首测总分(6个任务综合)',
    `test2_total_score`     DECIMAL(6,2)    NOT NULL COMMENT '重测总分',
    `test1_date`            DATE            NOT NULL COMMENT '首测日期',
    `test2_date`            DATE            NOT NULL COMMENT '重测日期',
    `interval_days`         INT             GENERATED ALWAYS AS (DATEDIFF(test2_date, test1_date)) STORED COMMENT '间隔天数(应在14-28天)',
    `test1_dim_scores`      JSON            DEFAULT NULL COMMENT '首测各维度得分',
    `test2_dim_scores`      JSON            DEFAULT NULL COMMENT '重测各维度得分',
    `created_at`            DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '记录创建时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_child`   (`child_id`),
    INDEX `idx_interval`    (`interval_days`),

    CONSTRAINT `fk_retest_child`
        FOREIGN KEY (`child_id`)
        REFERENCES `participants` (`child_id`)
        ON DELETE CASCADE
        ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='重测数据表(重测信度)';


-- ============================================================
-- 表6：效标关联效度表 criterion_validity
-- 以教师评定为效标, Pearson相关分析
-- ============================================================
DROP TABLE IF EXISTS `criterion_validity`;
CREATE TABLE `criterion_validity` (
    `id`                        BIGINT          NOT NULL AUTO_INCREMENT COMMENT '记录ID',
    `child_id`                  INT             NOT NULL COMMENT '被试编号',
    `teacher_rating_total`      DECIMAL(6,2)    NOT NULL COMMENT '教师评定总分',
    `teacher_rating_rule`       DECIMAL(6,2)    DEFAULT NULL COMMENT '常规规则能力维度分(含礼貌用语)',
    `teacher_rating_lang`       DECIMAL(6,2)    DEFAULT NULL COMMENT '语言能力维度分',
    `teacher_rating_social`     DECIMAL(6,2)    DEFAULT NULL COMMENT '社会交往维度分',
    `ai_test_total_score`      DECIMAL(6,2)    NOT NULL COMMENT 'AI测验总分',
    `ai_test_dim_scores`        JSON            DEFAULT NULL COMMENT 'AI测验各维度得分JSON',
    `rating_date`               DATE            DEFAULT NULL COMMENT '教师评定日期',
    `created_at`                DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '记录创建时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_child`       (`child_id`),
    INDEX `idx_teacher_score`   (`teacher_rating_total`),

    CONSTRAINT `fk_criterion_child`
        FOREIGN KEY (`child_id`)
        REFERENCES `participants` (`child_id`)
        ON DELETE CASCADE
        ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='效标关联效度表';


-- ============================================================
-- 表7：生态效度表 ecological_validity
-- AI得分 vs 真人情境得分相关分析
-- ============================================================
DROP TABLE IF EXISTS `ecological_validity`;
CREATE TABLE `ecological_validity` (
    `id`                BIGINT          NOT NULL AUTO_INCREMENT COMMENT '记录ID',
    `child_id`          INT             NOT NULL COMMENT '被试编号',
    `ai_toyshop_score`  DECIMAL(6,2)    DEFAULT NULL COMMENT 'AI"玩具商店求助站"得分',
    `ai_blocks_score`   DECIMAL(6,2)    DEFAULT NULL COMMENT 'AI"积木搭建广场"得分',
    `real_toy_score`    DECIMAL(6,2)    DEFAULT NULL COMMENT '真人"玩具角互动"得分',
    `real_craft_score`  DECIMAL(6,2)    DEFAULT NULL COMMENT '真人"手工互助台"得分',
    `test_date`         DATE            DEFAULT NULL COMMENT '真人测验日期',
    `notes`             VARCHAR(500)    DEFAULT NULL COMMENT '备注',
    `created_at`        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '记录创建时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_child`   (`child_id`),

    CONSTRAINT `fk_eco_child`
        FOREIGN KEY (`child_id`)
        REFERENCES `participants` (`child_id`)
        ON DELETE CASCADE
        ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='生态效度表(AI vs 真人)';


-- ============================================================
-- 表8：专家内容效度评分表 expert_validity
-- 内容效度(I-CVI / S-CVI), 3-5名专家5点量表评定
-- ============================================================
DROP TABLE IF EXISTS `expert_validity`;
CREATE TABLE `expert_validity` (
    `id`                BIGINT          NOT NULL AUTO_INCREMENT COMMENT '记录ID',
    `expert_id`         TINYINT         NOT NULL COMMENT '专家编号1-5',
    `item_id`           VARCHAR(50)     NOT NULL COMMENT '评定项目编号(如维度名/任务名)',
    `item_type`         VARCHAR(20)     NOT NULL COMMENT '项目类型: dimension=维度 task=任务 scoring=计分 standard=标准',
    `relevance_score`   TINYINT         NOT NULL COMMENT '相关性评分1-5(5=非常相关)',
    `clarity_score`     TINYINT         DEFAULT NULL COMMENT '清晰度评分1-5',
    `appropriateness`   TINYINT         DEFAULT NULL COMMENT '适切性评分1-5',
    `expert_comment`    TEXT            DEFAULT NULL COMMENT '专家意见',
    `rating_date`       DATE            DEFAULT NULL COMMENT '评定日期',
    `created_at`        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '记录创建时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_expert_item` (`expert_id`, `item_id`),
    INDEX `idx_item`   (`item_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='专家内容效度评分表';


-- ============================================================
-- 建表完成验证
-- ============================================================
SELECT TABLE_NAME, TABLE_COMMENT, TABLE_ROWS
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'politeness_town'
ORDER BY TABLE_NAME;
