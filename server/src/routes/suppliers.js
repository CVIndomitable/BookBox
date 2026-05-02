import { Router } from 'express';
import prisma from '../utils/prisma.js';
import { parseId } from '../utils/validate.js';
import { pingSupplier, validateEndpoint } from '../utils/llmPool.js';
import { encrypt, decrypt, isEncrypted, isEncryptionConfigured } from '../utils/crypto.js';

const router = Router();

function envList(...names) {
  return new Set(
    names
      .flatMap((name) => (process.env[name] || '').split(','))
      .map((s) => s.trim())
      .filter(Boolean)
  );
}

function isSupplierAdmin(user) {
  const adminIds = envList('SUPPLIER_ADMIN_USER_IDS', 'ADMIN_USER_IDS');
  const adminUsernames = envList('SUPPLIER_ADMIN_USERNAMES', 'ADMIN_USERNAMES');
  return adminIds.has(String(user?.id)) || adminUsernames.has(user?.username);
}

function requireSupplierAdmin(req, res, next) {
  if (!isSupplierAdmin(req.user)) {
    return res.status(403).json({ error: '需要供应商管理权限' });
  }
  next();
}

// 打码 API Key，仅保留前 4 位 + 后 4 位
function maskKey(key) {
  if (!key) return null;
  // 若是密文（enc:v1:...），不暴露密文内容，统一打码
  let plain;
  try {
    plain = isEncrypted(key) ? decrypt(key) : key;
  } catch {
    return '***';
  }
  if (plain.length <= 10) return '***';
  return `${plain.slice(0, 4)}${'*'.repeat(Math.max(3, plain.length - 8))}${plain.slice(-4)}`;
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

// 写入前加密 API Key；若未配置密钥则抛错以避免落下新的明文
function encryptForStorage(apiKey) {
  if (!isEncryptionConfigured()) {
    const err = new Error('服务器未配置 SUPPLIER_ENCRYPTION_KEY，拒绝写入新的 API Key');
    err.statusCode = 500;
    throw err;
  }
  return encrypt(apiKey);
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
router.post('/', requireSupplierAdmin, async (req, res, next) => {
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
        name, protocol, endpoint,
        apiKey: encryptForStorage(apiKey),
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
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    next(err);
  }
});

// PUT /api/suppliers/:id — 更新（运维用）
router.put('/:id', requireSupplierAdmin, async (req, res, next) => {
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
    if (body.apiKey !== undefined && body.apiKey) data.apiKey = encryptForStorage(body.apiKey);
    if (body.visionModel !== undefined) data.visionModel = body.visionModel || null;
    if (body.textModel !== undefined) data.textModel = body.textModel || null;
    if (body.priority !== undefined) data.priority = Number(body.priority);
    if (body.enabled !== undefined) data.enabled = !!body.enabled;
    if (body.timeoutMs !== undefined) data.timeoutMs = Number(body.timeoutMs);
    if (body.note !== undefined) data.note = body.note || null;

    const updated = await prisma.llmSupplier.update({ where: { id }, data });
    res.json(toClientShape(updated));
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    next(err);
  }
});

// DELETE /api/suppliers/:id — 删除
router.delete('/:id', requireSupplierAdmin, async (req, res, next) => {
  try {
    const id = parseId(req.params.id);
    await prisma.llmSupplier.delete({ where: { id } });
    res.json({ message: '已删除' });
  } catch (err) {
    next(err);
  }
});

// POST /api/suppliers/:id/ping — 测试单个供应商连通性
router.post('/:id/ping', requireSupplierAdmin, async (req, res, next) => {
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
