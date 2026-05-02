import { Router } from 'express';
import prisma from '../utils/prisma.js';
import { parsePagination, paginationResponse } from '../utils/validate.js';

const router = Router();

// 获取全部操作日志（支持分页、按 action/method 筛选）
router.get('/', async (req, res, next) => {
  try {
    const { action, method } = req.query;
    const { page, pageSize, skip, take } = parsePagination(req.query);

    const where = {};
    if (action) where.action = action;
    if (method) where.method = method;

    const [logs, total] = await Promise.all([
      prisma.bookLog.findMany({
        where,
        include: {
          book: { select: { id: true, title: true, author: true } },
        },
        skip,
        take,
        orderBy: { createdAt: 'desc' },
      }),
      prisma.bookLog.count({ where }),
    ]);

    res.json({
      data: logs,
      pagination: paginationResponse(page, pageSize, total),
    });
  } catch (err) {
    next(err);
  }
});

export default router;
