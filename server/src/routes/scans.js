import { Router } from 'express';
import prisma from '../utils/prisma.js';

const router = Router();

// 保存扫描记录
router.post('/', async (req, res, next) => {
  try {
    const { mode, boxId, photoPath, ocrResult, extractedTitles } = req.body;

    if (!mode || !['preclassify', 'boxing'].includes(mode)) {
      return res.status(400).json({ error: '无效的扫描模式' });
    }

    const record = await prisma.scanRecord.create({
      data: {
        mode,
        boxId: boxId ? parseInt(boxId, 10) : null,
        photoPath,
        ocrResult: ocrResult || undefined,
        extractedTitles: extractedTitles || undefined,
      },
    });

    res.status(201).json(record);
  } catch (err) {
    next(err);
  }
});

// 获取扫描历史
router.get('/', async (req, res, next) => {
  try {
    const { page = 1, pageSize = 20, mode } = req.query;

    const skip = (parseInt(page, 10) - 1) * parseInt(pageSize, 10);
    const take = parseInt(pageSize, 10);

    const where = {};
    if (mode) where.mode = mode;

    const [records, total] = await Promise.all([
      prisma.scanRecord.findMany({
        where,
        skip,
        take,
        orderBy: { createdAt: 'desc' },
      }),
      prisma.scanRecord.count({ where }),
    ]);

    res.json({
      data: records,
      pagination: {
        page: parseInt(page, 10),
        pageSize: take,
        total,
        totalPages: Math.ceil(total / take),
      },
    });
  } catch (err) {
    next(err);
  }
});

export default router;
