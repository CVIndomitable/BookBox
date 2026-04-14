import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import { authMiddleware } from './middleware/auth.js';
import boxesRouter from './routes/boxes.js';
import booksRouter from './routes/books.js';
import categoriesRouter from './routes/categories.js';
import scansRouter from './routes/scans.js';
import settingsRouter from './routes/settings.js';
import shelvesRouter from './routes/shelves.js';
import logsRouter from './routes/logs.js';
import libraryRouter from './routes/library.js';
import librariesRouter from './routes/libraries.js';
import llmRouter from './routes/llm.js';

// 启动时检查关键环境变量
if (!process.env.API_TOKEN) {
  console.warn('⚠ 警告：API_TOKEN 未配置，所有认证请求将被拒绝');
}

const app = express();
const PORT = process.env.PORT || 3000;

// 基础中间件
app.use(cors());
app.use(express.json({ limit: '20mb' }));

// 健康检查（无需认证）
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// 认证中间件
app.use('/api', authMiddleware);

// 路由
app.use('/api/boxes', boxesRouter);
app.use('/api/books', booksRouter);
app.use('/api/categories', categoriesRouter);
app.use('/api/scans', scansRouter);
app.use('/api/settings', settingsRouter);
app.use('/api/shelves', shelvesRouter);
app.use('/api/logs', logsRouter);
app.use('/api/library', libraryRouter);
app.use('/api/libraries', librariesRouter);
app.use('/api/llm', llmRouter);

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

app.listen(PORT, () => {
  console.log(`BookBox 服务器已启动，端口: ${PORT}`);
});
