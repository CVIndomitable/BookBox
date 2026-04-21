import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import prisma from './utils/prisma.js';
import { authMiddleware } from './middleware/auth.js';
import { idempotencyMiddleware } from './middleware/idempotency.js';
import boxesRouter from './routes/boxes.js';
import booksRouter from './routes/books.js';
import categoriesRouter from './routes/categories.js';
import scansRouter from './routes/scans.js';
import settingsRouter from './routes/settings.js';
import shelvesRouter from './routes/shelves.js';
import roomsRouter from './routes/rooms.js';
import logsRouter from './routes/logs.js';
import libraryRouter from './routes/library.js';
import librariesRouter from './routes/libraries.js';
import llmRouter from './routes/llm.js';
import suppliersRouter from './routes/suppliers.js';
import authRouter from './routes/auth.js';
import libraryMembersRouter from './routes/library-members.js';
import sunRemindersRouter from './routes/sun-reminders.js';
import { pingSupplier } from './utils/llmPool.js';
import { initAPNs, startSunReminderScheduler } from './services/push-notification.js';

// 启动时检查关键环境变量
if (!process.env.DATABASE_URL) {
  console.error('❌ 致命错误：DATABASE_URL 未配置');
  process.exit(1);
}
if (!process.env.API_TOKEN) {
  console.warn('⚠ 警告：API_TOKEN 未配置，所有认证请求将被拒绝');
}
if (!process.env.SUPPLIER_ENCRYPTION_KEY) {
  console.warn('⚠ 警告：SUPPLIER_ENCRYPTION_KEY 未配置，供应商 API Key 将无法加密/解密');
  console.warn('   生成方式：node -e "console.log(require(\'crypto\').randomBytes(32).toString(\'hex\'))"');
}

const app = express();
const PORT = process.env.PORT || 3000;

// 基础中间件
// CORS：默认只允许同源与 iOS 原生客户端（均无 Origin 头）；
// 浏览器等跨域来源必须通过 CORS_ORIGIN 显式白名单启用（逗号分隔，* 表示放开）
const allowedOrigins = (process.env.CORS_ORIGIN || '')
  .split(',').map((s) => s.trim()).filter(Boolean);
app.use(cors({
  origin: (origin, cb) => {
    if (!origin) return cb(null, true); // 同源 / 原生客户端无 Origin
    if (allowedOrigins.includes('*')) return cb(null, true);
    if (allowedOrigins.includes(origin)) return cb(null, true);
    return cb(new Error(`跨域来源不被允许: ${origin}`));
  },
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Request-Id'],
}));

// 请求体大小限制（按路由按需放宽；首个 express.json 解析成功后后续调用是 no-op）：
// - /api/llm/recognize: 10MB（承载 base64 图片；压缩后常态 500KB–2MB，上限留足）
// - /api/books:         2MB（批量新增与含 rawOcrText 的写入可能偏大）
// - 其它所有 /api/*:    1MB（结构化 JSON 够用）
// 审计：剩余路由（rooms/shelves/boxes/categories/libraries/logs/scans/settings/suppliers
// /llm/voice-command/llm/find-book/auth/library-members/sun-reminders）均为小 JSON，无需单设上限。
app.use('/api/llm/recognize', express.json({ limit: '10mb' }));
app.use('/api/books', express.json({ limit: '2mb' }));
app.use(express.json({ limit: '1mb' }));

// 全局速率限制
const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 分钟
  max: 300,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: '请求过于频繁，请稍后再试' },
});
app.use('/api', apiLimiter);

// LLM 端点更严格的速率限制（防止刷接口产生费用）
const llmLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 分钟
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'AI 识别请求过于频繁，请稍后再试' },
});
app.use('/api/llm', llmLimiter);

// 健康检查（无需认证）
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// 认证相关路由（无需旧的 authMiddleware）
app.use('/api/auth', authRouter);

// 认证中间件（旧的 API Token 方式，保持向后兼容）
app.use('/api', authMiddleware);

// 请求去重（基于 X-Request-Id，仅拦截 POST/PUT/DELETE）
// 应在认证之后、业务路由之前；CORS 头已在前面配置允许该头
app.use('/api', idempotencyMiddleware);

// 详细健康检查（需要认证）— 检测服务器、数据库、AI 供应商池
app.get('/api/health/detailed', async (req, res) => {
  const results = {
    server: { status: 'ok' },
    database: { status: 'checking' },
    ai: { status: 'checking' },
    suppliers: [],
  };

  // 检查数据库连通性
  try {
    await prisma.$queryRawUnsafe('SELECT 1');
    results.database = { status: 'ok' };
  } catch (err) {
    results.database = { status: 'error', message: '数据库连接失败' };
  }

  // 检查 AI 供应商池
  try {
    const pool = await prisma.llmSupplier.findMany({
      where: { enabled: true },
      orderBy: [{ priority: 'asc' }, { id: 'asc' }],
    });

    if (pool.length === 0) {
      results.ai = { status: 'not_configured', message: '未配置任何启用的 AI 供应商' };
    } else {
      // 并发 ping 所有启用的供应商（带 10s 超时）
      const pingResults = await Promise.all(
        pool.map(async (s) => {
          const timed = { ...s, timeoutMs: 10000 };
          const r = await pingSupplier(timed);
          return {
            name: s.name,
            priority: s.priority,
            status: r.ok ? 'ok' : 'error',
            message: r.ok ? undefined : (r.error || '').slice(0, 200),
          };
        })
      );

      results.suppliers = pingResults;

      const firstOk = pingResults.find(r => r.status === 'ok');
      if (!firstOk) {
        results.ai = { status: 'error', message: '所有 AI 供应商均不可用' };
      } else if (firstOk !== pingResults[0]) {
        // 顶级供应商挂了但有备用
        results.ai = {
          status: 'degraded',
          message: `顶级供应商 ${pingResults[0].name} 不可用，已降级到 ${firstOk.name}`,
        };
      } else {
        results.ai = { status: 'ok' };
      }
    }
  } catch (err) {
    console.error('[health] 检查 AI 供应商池失败', err);
    results.ai = { status: 'error', message: '检查 AI 配置时出错' };
  }

  res.json(results);
});

// 路由
app.use('/api/boxes', boxesRouter);
app.use('/api/books', booksRouter);
app.use('/api/categories', categoriesRouter);
app.use('/api/scans', scansRouter);
app.use('/api/settings', settingsRouter);
app.use('/api/shelves', shelvesRouter);
app.use('/api/rooms', roomsRouter);
app.use('/api/logs', logsRouter);
app.use('/api/library', libraryRouter);
app.use('/api/libraries', librariesRouter);
app.use('/api/llm', llmRouter);
app.use('/api/suppliers', suppliersRouter);
app.use('/api/library-members', libraryMembersRouter);
app.use('/api/sun-reminders', sunRemindersRouter);

// 全局错误处理
app.use((err, req, res, next) => {
  console.error('服务器错误:', err);

  // 业务层抛出的带 statusCode 的错误
  if (err.statusCode) {
    return res.status(err.statusCode).json({ error: err.message });
  }

  // Prisma 校验错误（参数类型不匹配等）
  if (err.code === 'P2000' || err.code === 'P2006' || err.code === 'P2009') {
    return res.status(400).json({ error: '请求参数格式错误' });
  }

  // Prisma 记录不存在
  if (err.code === 'P2025') {
    return res.status(404).json({ error: '请求的资源不存在' });
  }

  res.status(500).json({ error: '服务器内部错误' });
});

const server = app.listen(PORT, () => {
  console.log(`BookBox 服务器已启动，端口: ${PORT}`);

  // 初始化 APNs 和晒书提醒定时任务
  initAPNs();
  startSunReminderScheduler();
});

// 优雅关闭：断开数据库连接
async function shutdown(signal) {
  console.log(`收到 ${signal}，正在关闭服务器...`);
  server.close(async () => {
    await prisma.$disconnect();
    console.log('数据库连接已断开，进程退出');
    process.exit(0);
  });
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
