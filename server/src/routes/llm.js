import { Router } from 'express';
import crypto from 'crypto';
import prisma from '../utils/prisma.js';
import { callWithFallback, callWithFallbackStream } from '../utils/llmPool.js';

const router = Router();

// ---- AI 指令映射缓存 ----
// 缓存的是"用户的话 → AI 的语义解析"这层映射（action / bookTitle / target 等），不带过期时间。
// 不缓存书的存在性——命中缓存后仍由调用方用 DB 查一遍，书被删/被挪都能立刻反映。
// 只缓存只读指令（query/search/list/count），变更指令不进缓存。
// key: 归一化文本 + 上下文指纹，value: { result, createdAt }（createdAt 仅用于 FIFO 淘汰顺序）
const voiceCache = new Map();
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

// 清理 markdown 包裹的 JSON，并尽量从混入的解释性文字里抽出首个 JSON 块
// AI 偶尔会返回 "好的，识别结果如下：[...]" 或 "没有看到书籍" 这类裸文本，
// 先剥掉 ``` 围栏，再按 [ / { 成对匹配截取最外层 JSON。
function cleanJson(text) {
  if (!text) return '';
  let s = text.replace(/```json/gi, '').replace(/```/g, '').trim();

  // 扫描首个 [ 或 {，按深度配对找到匹配的右括号，剔除前后杂散文字
  const openIdx = (() => {
    for (let i = 0; i < s.length; i++) {
      const c = s[i];
      if (c === '[' || c === '{') return i;
    }
    return -1;
  })();
  if (openIdx === -1) return s;

  const open = s[openIdx];
  const close = open === '[' ? ']' : '}';
  let depth = 0;
  let inStr = false;
  let esc = false;
  for (let i = openIdx; i < s.length; i++) {
    const c = s[i];
    if (inStr) {
      if (esc) { esc = false; continue; }
      if (c === '\\') { esc = true; continue; }
      if (c === '"') inStr = false;
      continue;
    }
    if (c === '"') { inStr = true; continue; }
    if (c === open) depth++;
    else if (c === close) {
      depth--;
      if (depth === 0) return s.slice(openIdx, i + 1);
    }
  }
  // 未闭合（可能被 max_tokens 截断），把从第一个 [ / { 开始的全部返回
  return s.slice(openIdx);
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
// 附上最后一家失败原因，方便一眼看出是 key 挂了、限流、还是模型没配
function humanizeSupplierError(err) {
  const msg = err.message || '';
  let headline;
  if (/invalid api key/i.test(msg) || /401/.test(msg) || /403/.test(msg)) {
    headline = 'AI API Key 被供应商拒绝，已尝试全部备用供应商';
  } else if (/超时|timeout/i.test(msg)) {
    headline = 'AI 服务请求超时，已尝试全部备用供应商';
  } else {
    headline = 'AI 识别服务异常，已尝试全部备用供应商';
  }
  const attempts = Array.isArray(err.attempts) ? err.attempts : [];
  const last = [...attempts].reverse().find((a) => !a.ok && a.error);
  if (last) {
    const detail = String(last.error).slice(0, 200);
    return `${headline}（最后一家 ${last.name}：${detail}）`;
  }
  return headline;
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

    // 校验塞进 validate：若顶级模型返回"I can't analyze images"之类的拒答文本，
    // 这里解析失败会让 Pool 换下一家，而不是标 ok 然后路由层抛 502。
    const { parsed: books, supplier } = await callWithFallback({
      kind: 'vision',
      maxTokens: 2048,
      userText: prompt,
      image: { mediaType, data: cleanedImage },
      validate: (t) => {
        let parsed;
        try {
          parsed = JSON.parse(cleanJson(t));
        } catch {
          return { ok: false, error: `非 JSON 输出：${t.trim().slice(0, 80)}` };
        }
        // 兼容 AI 偶尔返回 {"books":[...]} / {"result":[...]} 之类的外壳
        if (parsed && !Array.isArray(parsed) && typeof parsed === 'object') {
          const wrapped = Array.isArray(parsed.books) ? parsed.books
            : Array.isArray(parsed.result) ? parsed.result
            : Array.isArray(parsed.data) ? parsed.data
            : Array.isArray(parsed.items) ? parsed.items
            : null;
          parsed = wrapped ?? [parsed];
        }
        if (!Array.isArray(parsed)) {
          return { ok: false, error: '返回结构不是数组' };
        }
        return { ok: true, parsed };
      },
    });

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

// POST /extract-book-details — 从照片里提取书籍详情（ISBN/出版时间/定价/出版社）
// 并尝试关联到库内已存在的那本书。
// 请求体：{ image: base64, libraryId?: number }
// 响应：{
//   extracted: { title, author, isbn, publisher, publishDate, price },
//   match: Book | null,              // 直接命中的唯一那本（优先 ISBN）
//   matchReason: 'isbn'|'title+author'|'title' | null,
//   candidates: Book[],              // 有多本疑似时列出来给用户挑
//   supplier?
// }
router.post('/extract-book-details', async (req, res, next) => {
  try {
    const { image, libraryId } = req.body || {};
    if (!image) {
      return res.status(400).json({ error: '缺少图片数据' });
    }

    const cleanedImage = cleanBase64Image(image);
    if (!cleanedImage) {
      return res.status(400).json({ error: '图片数据格式无效，请重新拍照' });
    }

    const buf = Buffer.from(cleanedImage, 'base64');
    const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
    if (buf.length > MAX_IMAGE_BYTES) {
      return res.status(413).json({ error: '图片过大（上限 5MB），请重新拍照或压缩后上传' });
    }
    const isPng = buf.length > 4 && buf[0] === 0x89 && buf[1] === 0x50;
    const mediaType = isPng ? 'image/png' : 'image/jpeg';

    const prompt = `请仔细观察这张书籍照片（封面、书脊、版权页、价签任意一种），提取书籍的详细信息。

要提取的字段：
- title: 书名（必填，看不到写"无法辨认"）
- author: 作者
- isbn: ISBN 号（10 位或 13 位数字，去除所有连字符和空格）
- publisher: 出版社
- publishDate: 出版时间（原样保留，可以是 "2023-05"/"2023年5月"/"1999" 等任意格式）
- price: 定价（只返回数字，如 29.8，不要带货币符号和"元"字）

只返回一个 JSON 对象，不要数组、不要 markdown、不要解释。看不到的字段写 null，不要编造。

示例：{"title":"活着","author":"余华","isbn":"9787506365437","publisher":"作家出版社","publishDate":"2012-08","price":20.00}`;

    const { text, supplier } = await callWithFallback({
      kind: 'vision',
      maxTokens: 512,
      userText: prompt,
      image: { mediaType, data: cleanedImage },
    });

    if (!text) {
      return res.status(502).json({ error: 'AI 模型未返回有效内容，请重试' });
    }

    const cleaned = cleanJson(text);
    let extracted;
    try {
      extracted = JSON.parse(cleaned);
    } catch {
      const snippet = text.trim().slice(0, 120);
      return res.status(502).json({ error: `AI 返回格式异常，请重试（原文片段：${snippet}）`, supplier });
    }
    if (Array.isArray(extracted)) extracted = extracted[0] || {};
    if (!extracted || typeof extracted !== 'object') extracted = {};

    // 规整字段（去空白、ISBN 去连字符、price 转数字）
    const norm = (v) => (v === null || v === undefined ? null : String(v).trim() || null);
    const title = norm(extracted.title);
    const author = norm(extracted.author);
    const rawIsbn = norm(extracted.isbn);
    const isbn = rawIsbn ? rawIsbn.replace(/[-\s]/g, '') : null;
    const publisher = norm(extracted.publisher);
    const publishDate = norm(extracted.publishDate);
    let price = null;
    if (extracted.price !== null && extracted.price !== undefined && extracted.price !== '') {
      const n = Number(String(extracted.price).replace(/[¥￥$,\s元RMB]/gi, ''));
      if (Number.isFinite(n) && n >= 0) price = n;
    }

    const cleanedExtracted = { title, author, isbn, publisher, publishDate, price };

    const baseWhere = {};
    if (libraryId !== undefined && libraryId !== null && libraryId !== '') {
      const id = Number(libraryId);
      if (Number.isInteger(id) && id > 0) baseWhere.libraryId = id;
    }

    let match = null;
    let matchReason = null;
    let candidates = [];

    // 匹配优先级：ISBN 精确 → title+author 精确 → title contains
    if (isbn) {
      const byIsbn = await prisma.book.findMany({
        where: { ...baseWhere, isbn },
        take: 5,
      });
      if (byIsbn.length === 1) {
        match = byIsbn[0];
        matchReason = 'isbn';
      } else if (byIsbn.length > 1) {
        candidates = byIsbn;
      }
    }

    if (!match && candidates.length === 0 && title && title !== '无法辨认') {
      if (author) {
        const byTitleAuthor = await prisma.book.findMany({
          where: { ...baseWhere, title, author },
          take: 5,
        });
        if (byTitleAuthor.length === 1) {
          match = byTitleAuthor[0];
          matchReason = 'title+author';
        } else if (byTitleAuthor.length > 1) {
          candidates = byTitleAuthor;
        }
      }
      if (!match && candidates.length === 0) {
        const byTitle = await prisma.book.findMany({
          where: { ...baseWhere, title: { contains: title } },
          take: 10,
          orderBy: { createdAt: 'desc' },
        });
        if (byTitle.length === 1) {
          match = byTitle[0];
          matchReason = 'title';
        } else if (byTitle.length > 1) {
          candidates = byTitle;
        }
      }
    }

    res.json({
      extracted: cleanedExtracted,
      match,
      matchReason,
      candidates,
      supplier,
    });
  } catch (err) {
    console.error('[LLM extract-book-details]', err.message);
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
      if (cached) {
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
      // FIFO 淘汰：Map 按插入顺序迭代，超限时直接踢最早插入的一条
      if (voiceCache.size >= MAX_CACHE_SIZE) {
        const oldest = voiceCache.keys().next().value;
        voiceCache.delete(oldest);
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

// POST /voice-command-stream — 语音指令解析（流式版本，测试版助手专用）
// 请求体：{ text, context?: { rooms, shelves, boxes } }
// 响应：Server-Sent Events (text/event-stream)
router.post('/voice-command-stream', async (req, res, next) => {
  try {
    const { text, context } = req.body;
    if (!text) {
      return res.status(400).json({ error: '缺少语音文本' });
    }

    const systemPrompt = buildVoiceSystemPrompt(context);

    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');

    const { stream, supplier } = await callWithFallbackStream({
      kind: 'text',
      maxTokens: 1024,
      system: systemPrompt,
      userText: text,
    });

    // 先发送供应商元信息
    res.write(`data: ${JSON.stringify({ type: 'supplier', supplier })}\n\n`);

    const reader = stream.getReader();
    const decoder = new TextDecoder();
    let buffer = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';

      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed || trimmed === 'data: [DONE]') continue;

        if (trimmed.startsWith('data: ')) {
          try {
            const json = JSON.parse(trimmed.slice(6));

            // Anthropic 格式
            if (json.type === 'content_block_delta' && json.delta?.text) {
              res.write(`data: ${JSON.stringify({ type: 'text', text: json.delta.text })}\n\n`);
            }
            // OpenAI 格式
            else if (json.choices?.[0]?.delta?.content) {
              res.write(`data: ${JSON.stringify({ type: 'text', text: json.choices[0].delta.content })}\n\n`);
            }
          } catch {
            // 忽略解析失败的行
          }
        }
      }
    }

    res.write(`data: ${JSON.stringify({ type: 'done' })}\n\n`);
    res.end();
  } catch (err) {
    console.error('[LLM voice-command-stream]', err.message);
    if (!res.headersSent) {
      if (err.statusCode) {
        return res.status(err.statusCode).json({
          error: err.statusCode === 502 ? humanizeSupplierError(err) : err.message,
          attempts: err.attempts,
        });
      }
      next(err);
    } else {
      res.write(`data: ${JSON.stringify({ type: 'error', error: humanizeSupplierError(err) })}\n\n`);
      res.end();
    }
  }
});

// 归一化书名：去空格、常见中英标点、书名号、括号等，并转小写
// 仅用于 Siri/语音的模糊查书，不改变数据库中存的原文
function normalizeTitle(s) {
  if (!s) return '';
  return String(s)
    .replace(/[\s\u3000]+/g, '')
    // eslint-disable-next-line no-useless-escape
    .replace(/[·・、，。：；！？…—\-_/\\|·."'`~!@#$%^&*+=<>?]/g, '')
    .replace(/[《》〈〉「」『』【】〖〗（）()\[\]{}""''""'']/g, '')
    .toLowerCase();
}

// POST /find-book — Siri/语音查书的智能搜索
// 请求体：{ query, libraryId?, useAI? }
//   - libraryId 指定时只搜这个库；未指定或 null 时跨全部库
//   - useAI 默认 true；调用方做级联反馈时前几轮可以传 false 只跑 DB，避免每库都等 AI
// 响应：{ books, method: 'strict'|'loose'|'ai'|'none', libraryId?, libraryName?, supplier? }
// 分层：严格子串 → 归一化后双向子串 → AI 兜底（仅 useAI=true 时）
router.post('/find-book', async (req, res, next) => {
  try {
    const { query, libraryId, useAI } = req.body;
    if (!query || typeof query !== 'string' || !query.trim()) {
      return res.status(400).json({ error: '缺少查询词' });
    }

    const aiEnabled = useAI !== false; // 默认开启，调用方显式传 false 才关闭

    const baseWhere = {};
    let libraryName = null;
    let libId = null;
    if (libraryId !== undefined && libraryId !== null && libraryId !== '') {
      const id = Number(libraryId);
      if (!Number.isInteger(id) || id <= 0) {
        return res.status(400).json({ error: 'libraryId 非法' });
      }
      baseWhere.libraryId = id;
      libId = id;
      const lib = await prisma.library.findUnique({ where: { id } });
      libraryName = lib?.name ?? null;
    }

    // Tier 1：原生子串匹配（命中直接返回，零额外开销）
    const strict = await prisma.book.findMany({
      where: {
        ...baseWhere,
        OR: [
          { title: { contains: query } },
          { author: { contains: query } },
        ],
      },
      take: 5,
      orderBy: { createdAt: 'desc' },
    });
    if (strict.length > 0) {
      return res.json({ books: strict, method: 'strict', libraryId: libId, libraryName });
    }

    const normalizedQuery = normalizeTitle(query);
    if (!normalizedQuery) {
      return res.json({ books: [], method: 'none', libraryId: libId, libraryName });
    }

    // 拉当前库（或跨库）所有书做内存侧匹配；limit 2000 作为保护
    const all = await prisma.book.findMany({
      where: baseWhere,
      take: 2000,
      orderBy: { createdAt: 'desc' },
    });
    if (all.length === 0) {
      return res.json({ books: [], method: 'none', libraryId: libId, libraryName });
    }

    // Tier 2：归一化后双向子串匹配
    // - 正向：用户输的词含 DB 书名（用户记全了、输入多了语气词/标点）
    // - 反向：DB 书名含用户的词（用户只记住几个字）
    // 反向需要防止单字误中（normalizedQuery 长度 >= 2 才允许反向）
    const looseMatches = all.filter((b) => {
      const nt = normalizeTitle(b.title);
      const na = normalizeTitle(b.author || '');
      if (!nt && !na) return false;
      if (nt && normalizedQuery.length >= 2) {
        if (nt.includes(normalizedQuery)) return true;
        if (normalizedQuery.length >= nt.length && normalizedQuery.includes(nt) && nt.length >= 2) return true;
      }
      if (na && normalizedQuery.length >= 2 && na.includes(normalizedQuery)) return true;
      return false;
    });
    if (looseMatches.length > 0) {
      return res.json({ books: looseMatches.slice(0, 5), method: 'loose', libraryId: libId, libraryName });
    }

    if (!aiEnabled) {
      return res.json({ books: [], method: 'none', libraryId: libId, libraryName });
    }

    // Tier 3：AI 兜底，从书名列表里挑最像的
    const MAX_TITLES = 500;
    const titles = all.slice(0, MAX_TITLES).map((b) => ({
      id: b.id,
      title: b.title,
      author: b.author || '',
    }));

    const systemPrompt = [
      '你是 BookBox 书库助手。用户想找一本书，但输入的名字可能有错字、近音、简繁体或漏字。',
      '请从给定的"书库书籍列表"中挑出**最可能**匹配的 1–3 本（按可能性降序）。',
      '如果完全没有可能匹配的，返回空数组。',
      '只返回 JSON：{"ids": [id1, id2, ...]}，不要解释、不要 markdown。',
    ].join('\n');
    const userText = `用户查询：${query}\n\n书籍列表：${JSON.stringify(titles)}`;

    const { text: aiResp, supplier } = await callWithFallback({
      kind: 'text',
      maxTokens: 256,
      system: systemPrompt,
      userText,
    });

    let ids = [];
    try {
      const parsed = JSON.parse(cleanJson(aiResp));
      if (Array.isArray(parsed?.ids)) ids = parsed.ids;
      else if (Array.isArray(parsed)) ids = parsed;
    } catch {
      ids = [];
    }

    const byId = new Map(all.map((b) => [b.id, b]));
    const aiMatches = ids
      .map((id) => byId.get(Number(id)))
      .filter(Boolean);

    if (aiMatches.length > 0) {
      return res.json({ books: aiMatches.slice(0, 3), method: 'ai', libraryId: libId, libraryName, supplier });
    }
    return res.json({ books: [], method: 'none', libraryId: libId, libraryName, supplier });
  } catch (err) {
    console.error('[LLM find-book]', err.message);
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

  res.json({
    hits: cacheStats.hits,
    misses: cacheStats.misses,
    total,
    hitRate: `${hitRate}%`,
    cacheSize: voiceCache.size,
    activeEntries: voiceCache.size,
    maxSize: MAX_CACHE_SIZE,
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
