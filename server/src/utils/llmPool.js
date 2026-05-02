import prisma from './prisma.js';
import { decrypt } from './crypto.js';

// 从持久化字段获取明文 API Key；密文会被解密，明文（历史数据）原样返回
function readApiKey(supplier) {
  try {
    return decrypt(supplier.apiKey);
  } catch (err) {
    const e = new Error(`供应商 ${supplier.name} 的 API Key 解密失败: ${err.message}`);
    e.httpStatus = 500;
    throw e;
  }
}

// 供应商必须显式填写对应 kind 的模型名；未填写视为不参与该类型调用。
// 例如学鼎仅填 text_model，会自动从视觉池中跳过。

// 校验 endpoint URL，防止 SSRF
export function validateEndpoint(endpoint) {
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

  return endpoint.replace(/\/+$/, '');
}

// 获取所有启用的供应商，按优先级升序（数字越小越优先）
// kind 指定后只返回该类型模型字段非空的供应商（vision/text）。
export async function getEnabledSuppliers(kind) {
  const where = { enabled: true };
  if (kind === 'vision') {
    where.visionModel = { not: null };
  } else if (kind === 'text') {
    where.textModel = { not: null };
  }
  return await prisma.llmSupplier.findMany({
    where,
    orderBy: [{ priority: 'asc' }, { id: 'asc' }],
  });
}

// Anthropic 协议调用
async function callAnthropic(supplier, { model, maxTokens, system, userText, image }) {
  const base = validateEndpoint(supplier.endpoint);
  const url = `${base}/v1/messages`;

  const content = [];
  if (image) {
    content.push({
      type: 'image',
      source: { type: 'base64', media_type: image.mediaType, data: image.data },
    });
  }
  content.push({ type: 'text', text: userText });

  const body = {
    model,
    max_tokens: maxTokens,
    messages: [{ role: 'user', content }],
    // 关闭扩展思考：mimo-v2-omni 等推理模型默认会先输出 thinking 块，
    // 容易吃光 max_tokens 导致正文为空。此接口直出 JSON 不需要推理过程。
    thinking: { type: 'disabled' },
  };
  if (system) body.system = system;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), supplier.timeoutMs || 120000);
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': readApiKey(supplier),
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      const err = new Error(`HTTP ${res.status}: ${text.slice(0, 300)}`);
      err.httpStatus = res.status;
      throw err;
    }
    const data = await res.json();
    // content 数组可能包含 thinking / text 等多种块，拼接所有 text 块
    const blocks = Array.isArray(data?.content) ? data.content : [];
    return blocks.filter(b => b?.type === 'text').map(b => b.text || '').join('');
  } catch (err) {
    if (err.name === 'AbortError') {
      const e = new Error('请求超时');
      e.httpStatus = 504;
      throw e;
    }
    throw err;
  } finally {
    clearTimeout(timer);
  }
}

// Anthropic 协议流式调用，返回 ReadableStream
async function callAnthropicStream(supplier, { model, maxTokens, system, userText, image }) {
  const base = validateEndpoint(supplier.endpoint);
  const url = `${base}/v1/messages`;

  const content = [];
  if (image) {
    content.push({
      type: 'image',
      source: { type: 'base64', media_type: image.mediaType, data: image.data },
    });
  }
  content.push({ type: 'text', text: userText });

  const body = {
    model,
    max_tokens: maxTokens,
    messages: [{ role: 'user', content }],
    thinking: { type: 'disabled' },
    stream: true,
  };
  if (system) body.system = system;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), supplier.timeoutMs || 120000);
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': readApiKey(supplier),
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      const err = new Error(`HTTP ${res.status}: ${text.slice(0, 300)}`);
      err.httpStatus = res.status;
      throw err;
    }
    clearTimeout(timer);
    return res.body;
  } catch (err) {
    clearTimeout(timer);
    if (err.name === 'AbortError') {
      const e = new Error('请求超时');
      e.httpStatus = 504;
      throw e;
    }
    throw err;
  }
}

// OpenAI 兼容协议调用（chat/completions）
async function callOpenAI(supplier, { model, maxTokens, system, userText, image }) {
  const base = validateEndpoint(supplier.endpoint);
  const url = `${base}/chat/completions`;

  const messages = [];
  if (system) messages.push({ role: 'system', content: system });

  if (image) {
    messages.push({
      role: 'user',
      content: [
        { type: 'image_url', image_url: { url: `data:${image.mediaType};base64,${image.data}` } },
        { type: 'text', text: userText },
      ],
    });
  } else {
    messages.push({ role: 'user', content: userText });
  }

  const body = { model, max_tokens: maxTokens, messages };

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), supplier.timeoutMs || 120000);
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${readApiKey(supplier)}`,
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      const err = new Error(`HTTP ${res.status}: ${text.slice(0, 300)}`);
      err.httpStatus = res.status;
      throw err;
    }
    const data = await res.json();
    return data?.choices?.[0]?.message?.content || '';
  } catch (err) {
    if (err.name === 'AbortError') {
      const e = new Error('请求超时');
      e.httpStatus = 504;
      throw e;
    }
    throw err;
  } finally {
    clearTimeout(timer);
  }
}

// OpenAI 兼容协议流式调用，返回 ReadableStream
async function callOpenAIStream(supplier, { model, maxTokens, system, userText, image }) {
  const base = validateEndpoint(supplier.endpoint);
  const url = `${base}/chat/completions`;

  const messages = [];
  if (system) messages.push({ role: 'system', content: system });

  if (image) {
    messages.push({
      role: 'user',
      content: [
        { type: 'image_url', image_url: { url: `data:${image.mediaType};base64,${image.data}` } },
        { type: 'text', text: userText },
      ],
    });
  } else {
    messages.push({ role: 'user', content: userText });
  }

  const body = { model, max_tokens: maxTokens, messages, stream: true };

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), supplier.timeoutMs || 120000);
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${readApiKey(supplier)}`,
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      const err = new Error(`HTTP ${res.status}: ${text.slice(0, 300)}`);
      err.httpStatus = res.status;
      throw err;
    }
    clearTimeout(timer);
    return res.body;
  } catch (err) {
    clearTimeout(timer);
    if (err.name === 'AbortError') {
      const e = new Error('请求超时');
      e.httpStatus = 504;
      throw e;
    }
    throw err;
  }
}

// 单次调用某个供应商
export async function callOneSupplier(supplier, payload) {
  return callOne(supplier, payload);
}

async function callOne(supplier, payload) {
  const model = payload.kind === 'vision' ? supplier.visionModel : supplier.textModel;
  if (!model) {
    const err = new Error(`供应商 ${supplier.name} 未配置 ${payload.kind} 模型`);
    err.statusCode = 422;
    throw err;
  }

  const protocol = (supplier.protocol || 'anthropic').toLowerCase();
  const callFn = protocol === 'openai' ? callOpenAI : callAnthropic;

  return await callFn(supplier, { ...payload, model });
}

// 单次流式调用某个供应商，返回 ReadableStream
async function callOneStream(supplier, payload) {
  const model = payload.kind === 'vision' ? supplier.visionModel : supplier.textModel;
  if (!model) {
    const err = new Error(`供应商 ${supplier.name} 未配置 ${payload.kind} 模型`);
    err.statusCode = 422;
    throw err;
  }

  const protocol = (supplier.protocol || 'anthropic').toLowerCase();
  const callFn = protocol === 'openai' ? callOpenAIStream : callAnthropicStream;

  return await callFn(supplier, { ...payload, model });
}

// 记录成功（异步，失败忽略）
function markOk(id) {
  prisma.llmSupplier
    .update({ where: { id }, data: { lastOkAt: new Date(), lastError: null } })
    .catch(() => {});
}

// 记录失败（异步，失败忽略）
function markFail(id, message) {
  prisma.llmSupplier
    .update({
      where: { id },
      data: { lastFailAt: new Date(), lastError: String(message || '').slice(0, 500) },
    })
    .catch(() => {});
}

/**
 * 按优先级遍历供应商，任一成功即返回；全部失败抛错。
 * payload: { kind: 'vision'|'text', maxTokens, system?, userText, image?, validate? }
 *   validate?: (text) => { ok: true, parsed? } | { ok: false, error }
 *   校验失败视作本家失败，继续降级。避免模型返回"拒答/非合法 JSON"时顶家被误标 ok。
 * 返回: { text, parsed?, supplier: { id, name, priority, degraded, topName, topPriority, triedCount, attempts } }
 */
export async function callWithFallback(payload) {
  const { validate, ...callPayload } = payload;
  const suppliers = await getEnabledSuppliers(payload.kind);
  if (suppliers.length === 0) {
    const err = new Error(`未配置任何支持 ${payload.kind} 类型的 AI 供应商，请联系管理员`);
    err.statusCode = 422;
    throw err;
  }

  const top = suppliers[0];
  const attempts = [];

  for (const sup of suppliers) {
    try {
      const text = await callOne(sup, callPayload);
      if (!text) throw new Error('供应商返回空内容');

      let parsed;
      if (typeof validate === 'function') {
        const result = validate(text);
        if (!result || result.ok !== true) {
          throw new Error(result?.error || '返回内容校验失败');
        }
        parsed = result.parsed;
      }

      markOk(sup.id);
      attempts.push({ name: sup.name, priority: sup.priority, ok: true });

      return {
        text,
        parsed,
        supplier: {
          id: sup.id,
          name: sup.name,
          priority: sup.priority,
          degraded: sup.id !== top.id,
          topName: top.name,
          topPriority: top.priority,
          triedCount: attempts.length,
          attempts,
        },
      };
    } catch (err) {
      markFail(sup.id, err.message);
      attempts.push({ name: sup.name, priority: sup.priority, ok: false, error: err.message });
      console.warn(`[LLM pool] ${sup.name}(p=${sup.priority}) 失败: ${err.message}`);
    }
  }

  const summary = attempts.map(a => `${a.name}(p=${a.priority}): ${a.error}`).join('; ');
  const err = new Error(`所有 AI 供应商均调用失败 — ${summary}`);
  err.statusCode = 502;
  err.attempts = attempts;
  throw err;
}

/**
 * 流式版本：按优先级遍历供应商，任一成功即返回 ReadableStream；全部失败抛错。
 * payload: { kind: 'vision'|'text', maxTokens, system?, userText, image? }
 * 返回: { stream: ReadableStream, supplier: { id, name, priority, degraded, topName, topPriority, triedCount, attempts } }
 */
export async function callWithFallbackStream(payload) {
  const suppliers = await getEnabledSuppliers(payload.kind);
  if (suppliers.length === 0) {
    const err = new Error(`未配置任何支持 ${payload.kind} 类型的 AI 供应商，请联系管理员`);
    err.statusCode = 422;
    throw err;
  }

  const top = suppliers[0];
  const attempts = [];

  for (const sup of suppliers) {
    try {
      const stream = await callOneStream(sup, payload);
      if (!stream) throw new Error('供应商返回空流');

      markOk(sup.id);
      attempts.push({ name: sup.name, priority: sup.priority, ok: true });

      return {
        stream,
        supplier: {
          id: sup.id,
          name: sup.name,
          priority: sup.priority,
          degraded: sup.id !== top.id,
          topName: top.name,
          topPriority: top.priority,
          triedCount: attempts.length,
          attempts,
        },
      };
    } catch (err) {
      markFail(sup.id, err.message);
      attempts.push({ name: sup.name, priority: sup.priority, ok: false, error: err.message });
      console.warn(`[LLM pool] ${sup.name}(p=${sup.priority}) 流式失败: ${err.message}`);
    }
  }

  const summary = attempts.map(a => `${a.name}(p=${a.priority}): ${a.error}`).join('; ');
  const err = new Error(`所有 AI 供应商均调用失败 — ${summary}`);
  err.statusCode = 502;
  err.attempts = attempts;
  throw err;
}

// 仅供 health check 使用的单供应商 ping
// 配了哪个模型就 ping 哪个；两种都配则两种都 ping，任一失败整体视为失败。
// 历史只 ping text 会漏报 vision 端点故障（拍照识别是 vision 调用）。
export async function pingSupplier(supplier) {
  const kinds = [];
  if (supplier.textModel) kinds.push('text');
  if (supplier.visionModel) kinds.push('vision');
  if (kinds.length === 0) {
    return { ok: false, supplier: supplier.name, error: '未配置任何模型' };
  }

  const details = {};
  for (const kind of kinds) {
    try {
      const text = await callOne(supplier, {
        kind,
        maxTokens: 1,
        userText: 'ping',
      });
      details[kind] = { ok: true, text };
    } catch (err) {
      details[kind] = { ok: false, error: err.message, httpStatus: err.httpStatus };
    }
  }

  const failed = kinds.filter((k) => !details[k].ok);
  if (failed.length === 0) {
    return { ok: true, supplier: supplier.name, details };
  }
  const errorMsg = failed
    .map((k) => `${k} 模型: ${details[k].error}`)
    .join('; ');
  return {
    ok: false,
    supplier: supplier.name,
    error: errorMsg,
    httpStatus: details[failed[0]].httpStatus,
    details,
  };
}
