import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import { authMiddleware } from './middleware/auth.js';
import boxesRouter from './routes/boxes.js';
import booksRouter from './routes/books.js';
import categoriesRouter from './routes/categories.js';
import scansRouter from './routes/scans.js';
import settingsRouter from './routes/settings.js';

const app = express();
const PORT = process.env.PORT || 3000;

// 基础中间件
app.use(cors());
app.use(express.json({ limit: '10mb' }));

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

// 全局错误处理
app.use((err, req, res, next) => {
  console.error('服务器错误:', err);
  res.status(500).json({ error: '服务器内部错误', message: err.message });
});

app.listen(PORT, () => {
  console.log(`BookBox 服务器已启动，端口: ${PORT}`);
});
