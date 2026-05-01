import { Router } from 'express';
import prisma from '../utils/prisma.js';

const router = Router();

function parseLibraryId(value) {
  if (value === undefined || value === null || value === '') return null;
  const id = Number(value);
  if (!Number.isInteger(id) || id <= 0) {
    const err = new Error('libraryId 非法');
    err.statusCode = 400;
    throw err;
  }
  return id;
}

async function getAccessibleLibraryIds(userId) {
  const memberships = await prisma.libraryMember.findMany({
    where: { userId },
    select: { libraryId: true },
  });
  return memberships.map((m) => m.libraryId);
}

// 书库总览（支持按 libraryId 筛选）
// 注意：totalBooks 必须严格按书库独立计算 —— 由显示出的 shelves/boxes.bookCount
// 之和 + 本库未归位书籍构成。不使用 book.libraryId 作为统计依据，避免历史数据
// 中 book.libraryId 与实际容器归属漂移时导致跨库计数
router.get('/overview', async (req, res, next) => {
  try {
    const libraryId = parseLibraryId(req.query.libraryId);
    let containerWhere;
    let unlocatedWhere;
    let roomsQuery;

    if (libraryId) {
      const membership = await prisma.libraryMember.findUnique({
        where: { userId_libraryId: { userId: req.user.id, libraryId } },
      });
      if (!membership) {
        return res.status(403).json({ error: '无权访问此书库' });
      }
      containerWhere = { libraryId };
      unlocatedWhere = { libraryId, locationType: 'none', deletedAt: null };
      roomsQuery = prisma.room.findMany({
        where: { libraryId },
        select: { id: true, name: true, isDefault: true, description: true },
        orderBy: [{ isDefault: 'desc' }, { createdAt: 'asc' }],
      });
    } else {
      const allowedLibraryIds = await getAccessibleLibraryIds(req.user.id);
      containerWhere = { libraryId: { in: allowedLibraryIds } };
      unlocatedWhere = { libraryId: { in: allowedLibraryIds }, locationType: 'none', deletedAt: null };
      roomsQuery = Promise.resolve([]);
    }

    const [rooms, shelves, boxes] = await Promise.all([
      roomsQuery,
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

    const unlocated = await prisma.book.count({ where: unlocatedWhere });

    const shelfSum = shelves.reduce((a, s) => a + (s.bookCount || 0), 0);
    const boxSum = boxes.reduce((a, b) => a + (b.bookCount || 0), 0);
    const totalBooks = shelfSum + boxSum + unlocated;

    res.json({ totalBooks, unlocated, rooms, shelves, boxes });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    next(err);
  }
});

export default router;
