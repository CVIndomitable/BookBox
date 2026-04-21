// 请求去重中间件（基于 X-Request-Id 头）
// 目标：客户端带 UUID 的非幂等写请求（POST/PUT/DELETE）在网络抖动重试时，
// 不会在数据库里制造重复记录。实现为进程内 LRU：够单机部署；多实例需改 Redis。
//
// 行为：
// - 只拦截带 X-Request-Id 的写请求；没头的请求直接放行（向后兼容）
// - 记录 (id, method, path) → 原始响应 (status + body)；TTL 10 分钟
// - 命中缓存：直接回放原响应，不再执行业务逻辑
// - 进行中：并发同 ID 请求返回 409（避免重复提交）

const TTL_MS = 10 * 60 * 1000;
const MAX_ENTRIES = 5000;

// key → { status, body, expiresAt }  |  { pending: true, expiresAt }
const cache = new Map();

function cleanup() {
  const now = Date.now();
  for (const [k, v] of cache) {
    if (v.expiresAt <= now) cache.delete(k);
  }
  // LRU 兜底：超过上限就把最早插入的删掉（Map 保留插入序）
  while (cache.size > MAX_ENTRIES) {
    const first = cache.keys().next().value;
    cache.delete(first);
  }
}

export function idempotencyMiddleware(req, res, next) {
  const id = req.get('X-Request-Id');
  // 无 ID 或非写操作直接放行
  if (!id || !['POST', 'PUT', 'DELETE'].includes(req.method)) {
    return next();
  }

  const key = `${id}|${req.method}|${req.path}`;
  const existing = cache.get(key);
  const now = Date.now();

  if (existing && existing.expiresAt > now) {
    if (existing.pending) {
      return res.status(409).json({
        error: '同一请求正在处理中，请稍候',
        code: 'REQUEST_IN_FLIGHT',
      });
    }
    res.setHeader('X-Idempotent-Replay', '1');
    return res.status(existing.status).json(existing.body);
  }

  cache.set(key, { pending: true, expiresAt: now + TTL_MS });

  // 拦截 res.json 以捕获响应体与状态码
  const origJson = res.json.bind(res);
  res.json = (body) => {
    cache.set(key, {
      status: res.statusCode,
      body,
      expiresAt: Date.now() + TTL_MS,
    });
    cleanup();
    return origJson(body);
  };

  // 请求失败（错误中间件或连接中断）时清理 pending，允许客户端重试
  res.on('close', () => {
    const entry = cache.get(key);
    if (entry?.pending) cache.delete(key);
  });

  next();
}
