import { Router } from 'express';
import crypto from 'crypto';
import prisma from '../utils/prisma.js';
import { parseId } from '../utils/validate.js';

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
  loaded: false,   // 是否已从 DB 加载
};

let flushTimer = null;
const FLUSH_DELAY = 5000; // 5 秒防抖写入

// 从数据库加载统计
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

// 防抖写入数据库
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

// 启动时加载
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

// 默认模型配置
const DEFAULT_ENDPOINT = 'https://api.xiaomimimo.com/anthropic';
const DEFAULT_VISION_MODEL = 'mimo-v2-omni';
const DEFAULT_TEXT_MODEL = 'mimo-v2-flash';

// 校验 endpoint URL，防止 SSRF
function validateEndpoint(endpoint) {
  let url;
  try {
    url = new URL(endpoint);
  } catch {
    const err = new Error('无效的 API 端点地址');
    err.statusCode = 422;
    throw err;
  }

  if (url.protocol !== 'https:' && url.protocol !== 'http:') {
    const err = new Error('API 端点仅支持 HTTP/HTTPS 协议');
    err.statusCode = 422;
    throw err;
  }

  const host = url.hostname;
  // 禁止内网地址
  if (
    host === 'localhost' ||
    host === '127.0.0.1' ||
    host === '0.0.0.0' ||
    host === '::1' ||
    host.startsWith('10.') ||
    host.startsWith('192.168.') ||
    host.startsWith('169.254.') ||
    /^172\.(1[6-9]|2\d|3[01])\./.test(host) ||
    /^100\.(6[4-9]|[7-9]\d|1[0-1]\d|12[0-7])\./.test(host) ||
    host.startsWith('fc') || host.startsWith('fd') ||
    host.startsWith('fe80') ||
    host.endsWith('.local') ||
    host.endsWith('.internal')
  ) {
    const err = new Error('API 端点不允许指向内网地址');
    err.statusCode = 422;
    throw err;
  }

  // 返回去除末尾斜杠的 origin + pathname
  return endpoint.replace(/\/+$/, '');
}

// 从数据库读取 LLM 配置
async function getLlmConfig() {
  const settings = await prisma.userSetting.findFirst();
  if (!settings || !settings.llmApiKey) {
    const err = new Error('未配置 AI API Key，请在设置中配置');
    err.statusCode = 422;
    throw err;
  }

  const rawEndpoint = settings.llmEndpoint || DEFAULT_ENDPOINT;
  const endpoint = validateEndpoint(rawEndpoint);

  return {
    apiKey: settings.llmApiKey,
    endpoint,
    visionModel: settings.llmModel || DEFAULT_VISION_MODEL,
    textModel: DEFAULT_TEXT_MODEL,
  };
}

// 调用 MiMo API（Anthropic 兼容协议）
async function callMiMo(config, body) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 120000);

  try {
    const response = await fetch(`${config.endpoint}/v1/messages`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': config.apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });

    clearTimeout(timeout);

    if (!response.ok) {
      const text = await response.text();
      throw new Error(`AI 模型请求失败(${response.status}): ${text}`);
    }

    const data = await response.json();
    if (data.content && Array.isArray(data.content) && data.content.length > 0) {
      return data.content[0].text || '';
    }
    return '';
  } catch (err) {
    clearTimeout(timeout);
    if (err.name === 'AbortError') {
      throw new Error('AI 模型请求超时，请稍后重试');
    }
    throw err;
  }
}

// 清理 markdown 包裹的 JSON
function cleanJson(text) {
  return text.replace(/```json/g, '').replace(/```/g, '').trim();
}

// 清理并验证 base64 图片数据
function cleanBase64Image(raw) {
  // 去掉可能的 data URI 前缀（如 data:image/jpeg;base64,）
  let b64 = raw.replace(/^data:image\/[a-z]+;base64,/i, '');
  // 去掉空白字符（换行、空格等）
  b64 = b64.replace(/\s/g, '');
  // 补齐 padding
  const remainder = b64.length % 4;
  if (remainder === 2) b64 += '==';
  else if (remainder === 3) b64 += '=';
  // 验证是否为合法 base64
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(b64)) {
    return null;
  }
  return b64;
}

// POST /recognize — 多模态识别书籍
router.post('/recognize', async (req, res, next) => {
  try {
    const { image } = req.body;
    if (!image) {
      return res.status(400).json({ error: '缺少图片数据' });
    }

    // 清理并验证 base64 数据
    const cleanedImage = cleanBase64Image(image);
    if (!cleanedImage) {
      console.warn('[LLM] base64 验证失败, 原始长度:', image.length, '前40字符:', image.slice(0, 40));
      return res.status(400).json({ error: '图片数据格式无效，请重新拍照' });
    }

    // 检查解码后是否为 JPEG（以 FFD8 开头）
    const buf = Buffer.from(cleanedImage, 'base64');
    const isJpeg = buf.length > 2 && buf[0] === 0xFF && buf[1] === 0xD8;
    const isPng = buf.length > 4 && buf[0] === 0x89 && buf[1] === 0x50;
    const mediaType = isPng ? 'image/png' : 'image/jpeg';
    if (!isJpeg && !isPng) {
      console.warn('[LLM] 图片格式异常, 头部字节:', buf.slice(0, 4).toString('hex'), '大小:', buf.length);
    }

    const config = await getLlmConfig();
    const text = await callMiMo(config, {
      model: config.visionModel,
      max_tokens: 2048,
      messages: [
        {
          role: 'user',
          content: [
            {
              type: 'image',
              source: {
                type: 'base64',
                media_type: mediaType,
                data: cleanedImage,
              },
            },
            {
              type: 'text',
              text: `请按以下两步分析这张照片：

第一步：识别书籍。仔细观察照片，找出所有是"书"的物体。书可能以任意姿态出现：书脊朝外、封面朝上、摊开、歪斜、堆叠等。注意区分书籍和其他物品（文件夹、笔记本、平板电脑、纸张等不算书）。

第二步：提取书名。对第一步中识别出的每一本书，尝试从书脊、封面或内页上读取书名和作者。如果文字模糊、被遮挡或角度太大无法辨认，仍然记录这本书但标注为低置信度。

请以 JSON 数组返回结果，每项包含：
- title：书名（如果完全无法辨认文字，写"无法辨认"）
- author：作者（看不到则为 null）
- confidence：置信度（high = 书名清晰可读；medium = 能大致辨认但不完全确定；low = 能看到是书但书名很难辨认）
- category：根据书名和作者推断最合适的分类，从以下选项中选一个：文学小说、历史文化、哲学思想、科学技术、经济管理、艺术设计、教育学习、社科心理、生活休闲、儿童读物、其他

只返回 JSON 数组，不要其他文字。`,
            },
          ],
        },
      ],
    });

    if (!text) {
      console.warn('[LLM] MiMo 返回空内容');
      return res.status(502).json({ error: 'AI 模型未返回有效内容，请重试' });
    }

    const cleaned = cleanJson(text);
    let books = [];
    try {
      books = JSON.parse(cleaned);
    } catch (parseErr) {
      console.warn('[LLM] JSON 解析失败，原始内容:', text.slice(0, 500));
      return res.status(502).json({ error: 'AI 返回格式异常，请重试' });
    }

    if (!Array.isArray(books)) {
      books = [books];
    }

    res.json({ books });
  } catch (err) {
    console.error('[LLM recognize]', err.message);
    if (err.statusCode) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    // 从 MiMo 错误信息中提取用户可读的描述
    const msg = err.message || '';
    if (msg.includes('Invalid API Key')) {
      return res.status(401).json({ error: 'AI API Key 无效，请在设置中重新配置' });
    }
    if (msg.includes('模型请求超时')) {
      return res.status(504).json({ error: 'AI 识别超时，请稍后重试' });
    }
    return res.status(502).json({ error: 'AI 识别服务异常，请稍后重试' });
  }
});

// POST /voice-command — 语音指令解析（带缓存）
router.post('/voice-command', async (req, res, next) => {
  try {
    const { text, systemPrompt, noCache } = req.body;
    if (!text) {
      return res.status(400).json({ error: '缺少语音文本' });
    }

    // 检查缓存（包含 systemPrompt 的哈希以区分不同书库上下文）
    const promptHash = crypto.createHash('md5').update(systemPrompt || '').digest('hex').slice(0, 12);
    const cacheKey = normalizeText(text) + '|' + promptHash;
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

    const config = await getLlmConfig();
    const responseText = await callMiMo(config, {
      model: config.textModel,
      max_tokens: 1024,
      system: systemPrompt || '',
      messages: [
        {
          role: 'user',
          content: text,
        },
      ],
    });

    const cleaned = cleanJson(responseText);
    let result;
    try {
      result = JSON.parse(cleaned);
    } catch {
      result = { action: 'query', reply: responseText };
    }

    // 仅缓存只读查询，不缓存会产生副作用的变更指令（move/add/remove 等）
    const readOnlyActions = ['query', 'search', 'list', 'count'];
    if (result.action && readOnlyActions.includes(result.action)) {
      // 控制缓存大小
      if (voiceCache.size >= MAX_CACHE_SIZE) {
        cleanExpiredCache();
        // 仍然超限则删除最早的
        if (voiceCache.size >= MAX_CACHE_SIZE) {
          const oldest = voiceCache.keys().next().value;
          voiceCache.delete(oldest);
        }
      }
      voiceCache.set(cacheKey, { result, createdAt: Date.now() });
    }

    res.json(result);
  } catch (err) {
    if (err.statusCode) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    next(err);
  }
});

// GET /cache-stats — 缓存命中率统计
router.get('/cache-stats', (req, res) => {
  const total = cacheStats.hits + cacheStats.misses;
  const hitRate = total > 0 ? ((cacheStats.hits / total) * 100).toFixed(1) : '0.0';

  // 统计缓存中未过期的条目数
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
