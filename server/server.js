const express = require('express');
const mysql = require('mysql2/promise');
const cors = require('cors');
const bodyParser = require('body-parser');

const app = express();
const PORT = Number(process.env.PORT || 3000);
const API_TOKEN = process.env.API_TOKEN || 'PoliteTown@2026';

app.use(cors());
app.use(bodyParser.json({ limit: '50mb' }));

function authCheck(req, res, next) {
  const token = req.get('x-api-token') || req.query.token || req.body.token;
  if (token !== API_TOKEN) {
    return res.status(403).json({ success: false, error: '接口密钥错误，禁止访问' });
  }
  next();
}

const pool = mysql.createPool({
  host: process.env.MYSQL_HOST || 'localhost',
  port: Number(process.env.MYSQL_PORT || 3306),
  user: process.env.MYSQL_USER || 'politeness_town',
  password: process.env.MYSQL_PASSWORD || '',
  database: process.env.MYSQL_DATABASE || 'politeness_town',
  waitForConnections: true,
  connectionLimit: 10,
  charset: 'utf8mb4'
});

// ============================================================
// POST /api/participant - 注册被试
// ============================================================
app.post('/api/participant', authCheck, async (req, res) => {
  try {
    const c = req.body;
    const [result] = await pool.execute(
      `INSERT INTO participants
       (nickname, age_months, gender, ai_type, baseline_score, school, class_name,
        has_language_disorder, device_usage_level, test_date)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, CURDATE())`,
      [
        c.nickname || '',
        Number(c.age_months || (Number(c.age || 5) * 12)),
        c.gender === 'male' || c.gender === '男' ? 1 : 2,
        (c.ai_type === 'friend' || c.ai_type === '朋友型' || c.ai_type === '朋友') ? 1 : 2,
        c.baseline_score || null,
        c.school || null,
        c.class_name || null,
        c.has_language_disorder ? 1 : 0,
        c.device_usage_level === 'low' || c.device_usage_level === '低' ? 1 : (c.device_usage_level === 'high' || c.device_usage_level === '高' ? 3 : 2)
      ]
    );
    res.json({ success: true, child_id: result.insertId });
  } catch (err) {
    console.error('注册被试失败:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ============================================================
// POST /api/task-score - 保存任务得分（单条）
// ============================================================
app.post('/api/task-score', authCheck, async (req, res) => {
  try {
    const s = req.body;
    const [result] = await pool.execute(
      `INSERT INTO task_scores
       (child_id, task_id, dimension,
        marker_total_count, marker_qing_count, marker_xiexie_count,
        marker_duiqi_count, marker_haoma_count, marker_keyima_count,
        marker_frequency, average_level,
        level_1_count, level_2_count, level_3_count, level_4_count, level_5_count,
        level_1_ratio, level_2_ratio, level_3_ratio, level_4_ratio, level_5_ratio,
        duration_minutes, turn_count, task_score)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
       ON DUPLICATE KEY UPDATE
        marker_total_count=VALUES(marker_total_count),
        marker_frequency=VALUES(marker_frequency),
        average_level=VALUES(average_level),
        task_score=VALUES(task_score)`,
      [
        s.child_id, s.task_id, s.dimension,
        s.marker_total_count || 0,
        s.marker_qing_count || 0, s.marker_xiexie_count || 0,
        s.marker_duiqi_count || 0, s.marker_haoma_count || 0, s.marker_keyima_count || 0,
        s.marker_frequency || 0, s.average_level || null,
        s.level_1_count || 0, s.level_2_count || 0, s.level_3_count || 0,
        s.level_4_count || 0, s.level_5_count || 0,
        s.level_1_ratio || null, s.level_2_ratio || null, s.level_3_ratio || null,
        s.level_4_ratio || null, s.level_5_ratio || null,
        s.duration_minutes || null, s.turn_count || null, s.task_score || null
      ]
    );
    res.json({ success: true });
  } catch (err) {
    console.error('保存任务得分失败:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ============================================================
// POST /api/turns - 批量保存话轮明细
// ============================================================
app.post('/api/turns', authCheck, async (req, res) => {
  try {
    const { child_id, task_id, turns } = req.body;
    if (!turns || !Array.isArray(turns) || turns.length === 0) {
      return res.json({ success: true, inserted: 0 });
    }
    const values = turns.map(t => [
      child_id, task_id, t.turn_index,
      t.speaker || 'child', t.text || '', t.level || null,
      JSON.stringify(t.markers || []), t.dimension || '',
      t.timestamp_sec || null
    ]);
    const placeholders = values.map(() => '(?,?,?,?,?,?,?,?,?)').join(',');
    const flat = values.flat();
    await pool.execute(
      `INSERT INTO turn_details
       (child_id, task_id, turn_index, speaker, text, level, markers, dimension, timestamp_sec)
       VALUES ${placeholders}`,
      flat
    );
    res.json({ success: true, inserted: values.length });
  } catch (err) {
    console.error('保存话轮失败:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ============================================================
// POST /api/session-complete - 测评完成，一次性上传全部数据
// ============================================================
app.post('/api/session-complete', authCheck, async (req, res) => {
  const data = req.body;
  if (!data.child_info || typeof data.child_info !== 'object') {
    return res.status(400).json({ success: false, error: '缺少 child_info' });
  }
  let conn;
  try {
    conn = await pool.getConnection();
    await conn.beginTransaction();

    // 1. 插入被试
    const c = data.child_info;
    const [childResult] = await conn.execute(
      `INSERT INTO participants
       (nickname, age_months, gender, ai_type, school, class_name,
        has_language_disorder, device_usage_level, test_date)
       VALUES (?,?,?,?,?,?,?,?,CURDATE())`,
      [
        c.nickname || '', Number(c.age_months || (Number(c.age || 5) * 12)),
        c.gender === 'male' || c.gender === '男' ? 1 : 2,
        (c.ai_type === 'friend' || c.ai_type === '朋友型' || c.ai_type === '朋友') ? 1 : 2,
        c.school || null, c.class_name || null,
        c.has_language_disorder ? 1 : 0,
        c.device_usage_level === 'low' || c.device_usage_level === '低' ? 1 : (c.device_usage_level === 'high' || c.device_usage_level === '高' ? 3 : 2)
      ]
    );
    const childId = childResult.insertId;

    const dimensionMap = {
      'greeting': 1, 'request': 2, 'thanks': 3,
      'apology': 4, 'sharing': 5, 'share': 5, 'farewell': 6
    };

    // 2. 从话轮中统计具体标记词频次（请/谢谢/对不起/好吗/可以吗）
    const turns = data.turns || [];
    const markerCountsByTask = {}; // {taskId: {qing:0, xiexie:0, ...}}
    const markerWordMap = {
      '请': 'qing', '请啦': 'qing', '请问': 'qing',
      '谢谢': 'xiexie', '感谢': 'xiexie', '多谢': 'xiexie',
      '对不起': 'duiqi', '抱歉': 'duiqi', '不好意思': 'duiqi',
      '好吗': 'haoma', '好不好': 'haoma', '好不好嘛': 'haoma',
      '可以吗': 'keyima', '行不行': 'keyima', '能不能': 'keyima'
    };
    for (const t of turns) {
      const dim = t.dimension || t.expected_dimension || '';
      const taskId = dimensionMap[dim] || 1;
      if (!markerCountsByTask[taskId]) {
        markerCountsByTask[taskId] = {qing:0, xiexie:0, duiqi:0, haoma:0, keyima:0};
      }
      const markers = t.markers || [];
      for (const m of markers) {
        const key = markerWordMap[m];
        if (key) markerCountsByTask[taskId][key]++;
      }
    }

    // 3. 插入各场景任务得分
    const scenarioResults = data.scenario_results || {};
    for (const [scenarioKey, scenario] of Object.entries(scenarioResults)) {
      const stats = scenario.statistics || {};
      const dim = scenario.dimension || scenarioKey;
      const taskId = dimensionMap[dim] || dimensionMap[scenarioKey.toLowerCase()] || 1;
      const mc = markerCountsByTask[taskId] || {qing:0, xiexie:0, duiqi:0, haoma:0, keyima:0};

      // level_distribution 可能是 Dictionary {1:0, 2:1, ...} 或 Array
      const ld = stats.level_distribution || {};
      const lp = stats.level_proportions || {};
      const getLevelCount = (lv) => {
        if (Array.isArray(ld)) return ld[lv-1] || 0;
        return ld[lv] || ld[String(lv)] || 0;
      };
      const getLevelRatio = (lv) => {
        if (Array.isArray(lp)) return lp[lv-1] || null;
        return lp[lv] || lp[String(lv)] || null;
      };

      await conn.execute(
        `INSERT INTO task_scores
         (child_id, task_id, dimension,
          marker_total_count, marker_qing_count, marker_xiexie_count,
          marker_duiqi_count, marker_haoma_count, marker_keyima_count,
          marker_frequency, average_level,
          level_1_count, level_2_count, level_3_count, level_4_count, level_5_count,
          level_1_ratio, level_2_ratio, level_3_ratio, level_4_ratio, level_5_ratio,
          duration_minutes, turn_count, task_score)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
         ON DUPLICATE KEY UPDATE
          marker_total_count=VALUES(marker_total_count),
          marker_qing_count=VALUES(marker_qing_count),
          marker_xiexie_count=VALUES(marker_xiexie_count),
          marker_duiqi_count=VALUES(marker_duiqi_count),
          marker_haoma_count=VALUES(marker_haoma_count),
          marker_keyima_count=VALUES(marker_keyima_count),
          marker_frequency=VALUES(marker_frequency),
          average_level=VALUES(average_level)`,
        [
          childId, taskId, dim,
          stats.marker_total_count || 0,
          mc.qing, mc.xiexie, mc.duiqi, mc.haoma, mc.keyima,
          stats.marker_frequency || 0,
          stats.average_level || null,
          getLevelCount(1), getLevelCount(2), getLevelCount(3), getLevelCount(4), getLevelCount(5),
          getLevelRatio(1), getLevelRatio(2), getLevelRatio(3), getLevelRatio(4), getLevelRatio(5),
          stats.duration_minutes || null,
          stats.turn_count || null,
          scenario.score || null
        ]
      );
    }

    // 4. 批量插入话轮明细
    if (turns.length > 0) {
      const turnValues = [];
      for (let i = 0; i < turns.length; i++) {
        const t = turns[i];
        const dim = t.dimension || t.expected_dimension || '';
        const taskId = dimensionMap[dim] || 1;
        turnValues.push([
          childId, taskId, i + 1,
          t.speaker || 'child',
          t.text || t.child_input || t.response || '',
          t.level || null,
          JSON.stringify(t.markers || []),
          dim,
          t.timestamp ? (t.timestamp / 1000).toFixed(2) : null
        ]);
      }
      // 分批插入（每批500条）
      for (let i = 0; i < turnValues.length; i += 500) {
        const batch = turnValues.slice(i, i + 500);
        const placeholders = batch.map(() => '(?,?,?,?,?,?,?,?,?)').join(',');
        await conn.execute(
          `INSERT INTO turn_details
           (child_id, task_id, turn_index, speaker, text, level, markers, dimension, timestamp_sec)
           VALUES ${placeholders}`,
          batch.flat()
        );
      }
    }

    await conn.commit();
    console.log(`[完成] 被试 ${childId} (${c.nickname}): ${turns.length} 话轮, ${Object.keys(scenarioResults).length} 场景`);
    res.json({ success: true, child_id: childId, turns_inserted: turns.length });
  } catch (err) {
    if (conn) {
      await conn.rollback();
    }
    console.error('保存会话失败:', err.message);
    res.status(500).json({ success: false, error: err.message });
  } finally {
    if (conn) {
      conn.release();
    }
  }
});

// ============================================================
// GET /api/health - 健康检查
// ============================================================
app.get('/api/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok', database: 'connected', time: new Date().toISOString() });
  } catch (err) {
    console.error('健康检查数据库连接失败:', err.message);
    res.status(503).json({ status: 'degraded', database: 'disconnected', error: err.message });
  }
});

// ============================================================
// GET /api/stats - 查看统计概览
// ============================================================
app.get('/api/stats', async (req, res) => {
  try {
    const [participants] = await pool.execute('SELECT COUNT(*) as count FROM participants');
    const [scores] = await pool.execute('SELECT COUNT(*) as count FROM task_scores');
    const [turns] = await pool.execute('SELECT COUNT(*) as count FROM turn_details');
    const [byType] = await pool.execute(
      'SELECT ai_type, COUNT(*) as count FROM participants GROUP BY ai_type'
    );
    res.json({
      participants: participants[0].count,
      task_scores: scores[0].count,
      turns: turns[0].count,
      by_ai_type: byType
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`礼貌小镇API服务器已启动: http://0.0.0.0:${PORT}`);
});
