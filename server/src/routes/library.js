import { Router } from 'express';
import prisma from '../utils/prisma.js';
import { parseOptionalId } from '../utils/validate.js';

const router = Router();

// 书库总览（支持按 libraryId 筛选）
// 注意：totalBooks 必须严格按书库独立计算 —— 由显示出的 shelves/boxes.bookCount
// 之和 + 本库未归位书籍构成。不使用 book.libraryId 作为统计依据，避免历史数据
// 中 book.libraryId 与实际容器归属漂移时导致跨库计数
router.get('/overview', async (req, res, next) => {
  try {
    const libraryId = parseOptionalId(req.query.libraryId);
    const containerWhere = libraryId ? { libraryId } : {};

    const [rooms, shelves, boxes] = await Promise.all([
      libraryId
        ? prisma.room.findMany({
            where: { libraryId },
            select: { id: true, name: true, isDefault: true, description: true },
            orderBy: [{ isDefault: 'desc' }, { createdAt: 'asc' }],
          })
        : Promise.resolve([]),
      prisma.shelf.findMany({
        where: containerWhere,
        select: {
          id: true,
          name: true,
          location: true,
          bookCount: true,
          roomId: true,
        },
        orderBy: { createdAt: 'desc' },
      }),
      prisma.box.findMany({
        where: containerWhere,
        select: {
          id: true,
          boxUid: true,
          name: true,
          bookCount: true,
          roomId: true,
        },
        orderBy: { createdAt: 'desc' },
      }),
    ]);

    // 未归位：仅统计 book.libraryId=当前库 且 locationType='none' 的书；未选库时统计全部未归位
    // 回收站的书不计入
    const unlocatedWhere = libraryId
      ? { libraryId, locationType: 'none', deletedAt: null }
      : { locationType: 'none', deletedAt: null };
    const unlocated = await prisma.book.count({ where: unlocatedWhere });

    const shelfSum = shelves.reduce((a, s) => a + (s.bookCount || 0), 0);
    const boxSum = boxes.reduce((a, b) => a + (b.bookCount || 0), 0);
    const totalBooks = shelfSum + boxSum + unlocated;

    res.json({ totalBooks, unlocated, rooms, shelves, boxes });
  } catch (err) {
    next(err);
  }
});

export default router;
