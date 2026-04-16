import { Router } from 'express';
import prisma from '../utils/prisma.js';
import { parseId } from '../utils/validate.js';
import { pingSupplier, validateEndpoint } from '../utils/llmPool.js';

const router = Router();

// 打码 API Key，仅保留前 4 位 + 后 4 位
function maskKey(key) {
  if (!key) return null;
  if (key.length <= 10) return '***';
  return `${key.slice(0, 4)}${'*'.repeat(Math.max(3, key.length - 8))}${key.slice(-4)}`;
}

function toClientShape(s) {
  return {
    id: s.id,
    name: s.name,
    protocol: s.protocol,
    endpoint: s.endpoint,
    apiKeyMasked: maskKey(s.apiKey),
    hasApiKey: !!s.apiKey,
    visionModel: s.visionModel,
    textModel: s.textModel,
    priority: s.priority,
    enabled: s.enabled,
    timeoutMs: s.timeoutMs,
    note: s.note,
    lastOkAt: s.lastOkAt,
    lastFailAt: s.lastFailAt,
    lastError: s.lastError,
    createdAt: s.createdAt,
    updatedAt: s.updatedAt,
  };
}

// 所有请求都不返回明文 API Key，供 iOS 只读展示

// GET /api/suppliers — 列出全部供应商
router.get('/', async (req, res, next) => {
  try {
    const list = await prisma.llmSupplier.findMany({
      orderBy: [{ priority: 'asc' }, { id: 'asc' }],
    });
    res.json(list.map(toClientShape));
  } catch (err) {
    next(err);
  }
});

// POST /api/suppliers — 新建（运维用）
router.post('/', async (req, res, next) => {
  try {
    const {
      name, protocol = 'anthropic', endpoint, apiKey,
      visionModel, textModel, priority = 100, enabled = true,
      timeoutMs = 120000, note,
    } = req.body || {};

    if (!name || !endpoint || !apiKey) {
      return res.status(400).json({ error: 'name、endpoint、apiKey 为必填' });
    }
    try { validateEndpoint(endpoint); } catch (e) {
      return res.status(422).json({ error: e.message });
    }

    const created = await prisma.llmSupplier.create({
      data: {
        name, protocol, endpoint, apiKey,
        visionModel: visionModel || null,
        textModel: textModel || null,
        priority: Number(priority),
        enabled: !!enabled,
        timeoutMs: Number(timeoutMs),
        note: note || null,
      },
    });
    res.status(201).json(toClientShape(created));
  } catch (err) {
    next(err);
  }
});

// PUT /api/suppliers/:id — 更新（运维用）
router.put('/:id', async (req, res, next) => {
  try {
    const id = parseId(req.params.id);
    const body = req.body || {};
    const data = {};

    if (body.name !== undefined) data.name = body.name;
    if (body.protocol !== undefined) data.protocol = body.protocol;
    if (body.endpoint !== undefined) {
      try { validateEndpoint(body.endpoint); } catch (e) {
        return res.status(422).json({ error: e.message });
      }
      data.endpoint = body.endpoint;
    }
    if (body.apiKey !== undefined && body.apiKey) data.apiKey = body.apiKey;
    if (body.visionModel !== undefined) data.visionModel = body.visionModel || null;
    if (body.textModel !== undefined) data.textModel = body.textModel || null;
    if (body.priority !== undefined) data.priority = Number(body.priority);
    if (body.enabled !== undefined) data.enabled = !!body.enabled;
    if (body.timeoutMs !== undefined) data.timeoutMs = Number(body.timeoutMs);
    if (body.note !== undefined) data.note = body.note || null;

    const updated = await prisma.llmSupplier.update({ where: { id }, data });
    res.json(toClientShape(updated));
  } catch (err) {
    next(err);
  }
});

// DELETE /api/suppliers/:id — 删除
router.delete('/:id', async (req, res, next) => {
  try {
    const id = parseId(req.params.id);
    await prisma.llmSupplier.delete({ where: { id } });
    res.json({ message: '已删除' });
  } catch (err) {
    next(err);
  }
});

// POST /api/suppliers/:id/ping — 测试单个供应商连通性
router.post('/:id/ping', async (req, res, next) => {
  try {
    const id = parseId(req.params.id);
    const sup = await prisma.llmSupplier.findUnique({ where: { id } });
    if (!sup) return res.status(404).json({ error: '供应商不存在' });
    const result = await pingSupplier(sup);
    res.json(result);
  } catch (err) {
    next(err);
  }
});

export default router;
