import { Router } from 'express';
import crypto from 'crypto';
import prisma from '../utils/prisma.js';
import { callWithFallback } from '../utils/llmPool.js';

const router = Router();

// ---- 语音指令缓存 ----
// key: 归一化后的文本，value: { result, createdAt }
const voiceCache = new Map();
const CACHE_TTL = 3600_000; // 1 小时过期
const MAX_CACHE_SIZE = 500;

// ---- 缓存命中率统计（持久化） ----
const CACHE_STAT_NAME = 'voice_command';
const cacheStats = {
  hits: 0,
  misses: 0,
  startedAt: Date.now(),
  loaded: false,
};

let flushTimer = null;
const FLUSH_DELAY = 5000;

async function loadCacheStats() {
  if (cacheStats.loaded) return;
  try {
    const row = await prisma.cacheStat.findUnique({ where: { name: CACHE_STAT_NAME } });
    if (row) {
      cacheStats.hits = row.hits;
      cacheStats.misses = row.misses;
      cacheStats.startedAt = row.startedAt.getTime();
    }
    cacheStats.loaded = true;
  } catch {
    // 表可能还未迁移，静默忽略
  }
}

function scheduleFlush() {
  if (flushTimer) clearTimeout(flushTimer);
  flushTimer = setTimeout(async () => {
    try {
      await prisma.cacheStat.upsert({
        where: { name: CACHE_STAT_NAME },
        update: { hits: cacheStats.hits, misses: cacheStats.misses },
        create: { name: CACHE_STAT_NAME, hits: cacheStats.hits, misses: cacheStats.misses, startedAt: new Date(cacheStats.startedAt) },
      });
    } catch {
      // 静默忽略
    }
  }, FLUSH_DELAY);
}

loadCacheStats();

function normalizeText(text) {
  return text.trim().replace(/\s+/g, '').toLowerCase();
}

function cleanExpiredCache() {
  const now = Date.now();
  for (const [key, entry] of voiceCache) {
    if (now - entry.createdAt > CACHE_TTL) {
      voiceCache.delete(key);
    }
  }
}

// 清理 markdown 包裹的 JSON
function cleanJson(text) {
  return text.replace(/```json/g, '').replace(/```/g, '').trim();
}

// 清理并验证 base64 图片数据
function cleanBase64Image(raw) {
  let b64 = raw.replace(/^data:image\/[a-z]+;base64,/i, '');
  b64 = b64.replace(/\s/g, '');
  const remainder = b64.length % 4;
  if (remainder === 2) b64 += '==';
  else if (remainder === 3) b64 += '=';
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(b64)) {
    return null;
  }
  return b64;
}

// 将供应商池失败中的常见错误信息归一化为用户可读的中文
function humanizeSupplierError(err) {
  const msg = err.message || '';
  if (/invalid api key/i.test(msg) || /401/.test(msg) || /403/.test(msg)) {
    return 'AI API Key 被供应商拒绝，已尝试全部备用供应商';
  }
  if (/超时|timeout/i.test(msg)) {
    return 'AI 服务请求超时，已尝试全部备用供应商';
  }
  return 'AI 识别服务异常，已尝试全部备用供应商';
}

// POST /recognize — 多模态识别书籍
router.post('/recognize', async (req, res, next) => {
  try {
    const { image } = req.body;
    if (!image) {
      return res.status(400).json({ error: '缺少图片数据' });
    }

    const cleanedImage = cleanBase64Image(image);
    if (!cleanedImage) {
      console.warn('[LLM] base64 验证失败, 原始长度:', image.length);
      return res.status(400).json({ error: '图片数据格式无效，请重新拍照' });
    }

    const buf = Buffer.from(cleanedImage, 'base64');
    // 限制解码后图片大小 5MB，防止大图拖垮内存和 AI 调用费用
    const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
    if (buf.length > MAX_IMAGE_BYTES) {
      console.warn('[LLM] 图片过大:', buf.length, '字节');
      return res.status(413).json({ error: '图片过大（上限 5MB），请重新拍照或压缩后上传' });
    }
    const isJpeg = buf.length > 2 && buf[0] === 0xFF && buf[1] === 0xD8;
    const isPng = buf.length > 4 && buf[0] === 0x89 && buf[1] === 0x50;
    const mediaType = isPng ? 'image/png' : 'image/jpeg';
    if (!isJpeg && !isPng) {
      console.warn('[LLM] 图片格式异常, 头部字节:', buf.slice(0, 4).toString('hex'));
    }

    const prompt = `请按以下两步分析这张照片：

第一步：识别书籍。仔细观察照片，找出所有是"书"的物体。书可能以任意姿态出现：书脊朝外、封面朝上、摊开、歪斜、堆叠等。注意区分书籍和其他物品（文件夹、笔记本、平板电脑、纸张等不算书）。

第二步：提取书名。对第一步中识别出的每一本书，尝试从书脊、封面或内页上读取书名和作者。如果文字模糊、被遮挡或角度太大无法辨认，仍然记录这本书但标注为低置信度。

请以 JSON 数组返回结果，每项包含：
- title：书名（如果完全无法辨认文字，写"无法辨认"）
- author：作者（看不到则为 null）
- confidence：置信度（high = 书名清晰可读；medium = 能大致辨认但不完全确定；low = 能看到是书但书名很难辨认）
- category：根据书名和作者推断最合适的分类，从以下选项中选一个：文学小说、历史文化、哲学思想、科学技术、经济管理、艺术设计、教育学习、社科心理、生活休闲、儿童读物、其他

只返回 JSON 数组，不要其他文字。`;

    const { text, supplier } = await callWithFallback({
      kind: 'vision',
      maxTokens: 2048,
      userText: prompt,
      image: { mediaType, data: cleanedImage },
    });

    if (!text) {
      return res.status(502).json({ error: 'AI 模型未返回有效内容，请重试' });
    }

    const cleaned = cleanJson(text);
    let books = [];
    try {
      books = JSON.parse(cleaned);
    } catch {
      console.warn('[LLM] JSON 解析失败，原始内容:', text.slice(0, 500));
      return res.status(502).json({ error: 'AI 返回格式异常，请重试', supplier });
    }

    if (!Array.isArray(books)) {
      books = [books];
    }

    res.json({ books, supplier });
  } catch (err) {
    console.error('[LLM recognize]', err.message);
    if (err.statusCode) {
      return res.status(err.statusCode).json({
        error: err.statusCode === 502 ? humanizeSupplierError(err) : err.message,
        attempts: err.attempts,
      });
    }
    return res.status(502).json({ error: humanizeSupplierError(err) });
  }
});

// 基于书库上下文构建固定格式的 system prompt
// 客户端仅传结构化上下文，禁止直接拼接 prompt，避免提示注入
function buildVoiceSystemPrompt(context) {
  const parts = ['你是 BookBox 书库助手。用户通过语音管理自己的书库。'];

  const rooms = Array.isArray(context?.rooms) ? context.rooms : [];
  const shelves = Array.isArray(context?.shelves) ? context.shelves : [];
  const boxes = Array.isArray(context?.boxes) ? context.boxes : [];

  if (rooms.length || shelves.length || boxes.length) {
    parts.push('当前书库状态（层级：书库 → 房间 → 书架/箱子 → 书）：');
  }
  if (rooms.length) {
    const desc = rooms
      .slice(0, 30)
      .map((r) => String(r.name || '').slice(0, 40))
      .join('、');
    parts.push(`房间：${desc}`);
  }
  if (shelves.length) {
    const desc = shelves
      .slice(0, 50)
      .map((s) => {
        const room = s.roomName ? `@${String(s.roomName).slice(0, 20)}` : '';
        return `${String(s.name || '').slice(0, 40)}${room}（${Number(s.bookCount) || 0}本）`;
      })
      .join('、');
    parts.push(`书架：${desc}`);
  }
  if (boxes.length) {
    const desc = boxes
      .slice(0, 50)
      .map((b) => {
        const room = b.roomName ? `@${String(b.roomName).slice(0, 20)}` : '';
        return `${String(b.uid || '').slice(0, 20)} ${String(b.name || '').slice(0, 40)}${room}（${Number(b.bookCount) || 0}本）`;
      })
      .join('、');
    parts.push(`箱子（已归档）：${desc}`);
  }

  parts.push('');
  parts.push('请根据用户指令返回 JSON：');
  parts.push('{"action": "move|query|edit|list", "bookTitle": "书名", "bookId": null, "target": {"type": "shelf|box|room", "name": "名称"}, "reply": "回复用户的话"}');
  parts.push('说明：target.type 为 room 时表示移动书架/箱子到指定房间；为 shelf/box 时表示移动书籍到书架/箱子。');
  parts.push('只返回 JSON，不要添加解释或 markdown 代码块。');
  return parts.join('\n');
}

// POST /voice-command — 语音指令解析（带缓存）
// 请求体：{ text, context?: { shelves: [{name, bookCount}], boxes: [{name, uid, bookCount}] }, noCache? }
router.post('/voice-command', async (req, res, next) => {
  try {
    const { text, context, noCache } = req.body;
    if (!text) {
      return res.status(400).json({ error: '缺少语音文本' });
    }

    const systemPrompt = buildVoiceSystemPrompt(context);

    // 缓存键包含上下文指纹，不同书库状态不会误命中
    const contextHash = crypto
      .createHash('md5')
      .update(systemPrompt)
      .digest('hex')
      .slice(0, 12);
    const cacheKey = normalizeText(text) + '|' + contextHash;
    if (!noCache) {
      const cached = voiceCache.get(cacheKey);
      if (cached && Date.now() - cached.createdAt < CACHE_TTL) {
        cacheStats.hits++;
        scheduleFlush();
        return res.json({ ...cached.result, cached: true });
      }
    }
    cacheStats.misses++;
    scheduleFlush();

    const { text: responseText, supplier } = await callWithFallback({
      kind: 'text',
      maxTokens: 1024,
      system: systemPrompt,
      userText: text,
    });

    const cleaned = cleanJson(responseText);
    let result;
    try {
      result = JSON.parse(cleaned);
    } catch {
      result = { action: 'query', reply: responseText };
    }

    // 附带供应商元信息（用于降级提醒）
    result.supplier = supplier;

    // 仅缓存只读查询，变更指令不缓存
    const readOnlyActions = ['query', 'search', 'list', 'count'];
    if (result.action && readOnlyActions.includes(result.action)) {
      if (voiceCache.size >= MAX_CACHE_SIZE) {
        cleanExpiredCache();
        if (voiceCache.size >= MAX_CACHE_SIZE) {
          const oldest = voiceCache.keys().next().value;
          voiceCache.delete(oldest);
        }
      }
      // 缓存时剥离 supplier，避免命中缓存时对应的供应商已切换
      const { supplier: _, ...cacheable } = result;
      voiceCache.set(cacheKey, { result: cacheable, createdAt: Date.now() });
    }

    res.json(result);
  } catch (err) {
    if (err.statusCode) {
      return res.status(err.statusCode).json({
        error: err.statusCode === 502 ? humanizeSupplierError(err) : err.message,
        attempts: err.attempts,
      });
    }
    next(err);
  }
});

// GET /cache-stats — 缓存命中率统计
router.get('/cache-stats', (req, res) => {
  const total = cacheStats.hits + cacheStats.misses;
  const hitRate = total > 0 ? ((cacheStats.hits / total) * 100).toFixed(1) : '0.0';

  const now = Date.now();
  let activeEntries = 0;
  for (const entry of voiceCache.values()) {
    if (now - entry.createdAt < CACHE_TTL) activeEntries++;
  }

  res.json({
    hits: cacheStats.hits,
    misses: cacheStats.misses,
    total,
    hitRate: `${hitRate}%`,
    cacheSize: voiceCache.size,
    activeEntries,
    maxSize: MAX_CACHE_SIZE,
    ttlMinutes: CACHE_TTL / 60000,
    startedAt: new Date(cacheStats.startedAt).toISOString(),
  });
});

// POST /cache-stats/reset — 重置统计
router.post('/cache-stats/reset', async (req, res) => {
  cacheStats.hits = 0;
  cacheStats.misses = 0;
  cacheStats.startedAt = Date.now();
  try {
    await prisma.cacheStat.upsert({
      where: { name: CACHE_STAT_NAME },
      update: { hits: 0, misses: 0, startedAt: new Date(cacheStats.startedAt) },
      create: { name: CACHE_STAT_NAME, hits: 0, misses: 0, startedAt: new Date(cacheStats.startedAt) },
    });
  } catch {
    // 静默忽略
  }
  res.json({ message: '缓存统计已重置' });
});

export default router;
