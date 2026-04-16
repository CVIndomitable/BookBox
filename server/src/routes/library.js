import { Router } from 'express';
import prisma from '../utils/prisma.js';
import { parseOptionalId } from '../utils/validate.js';

const router = Router();

// 书库总览（支持按 libraryId 筛选）
router.get('/overview', async (req, res, next) => {
  try {
    const libraryId = parseOptionalId(req.query.libraryId);
    const bookWhere = libraryId ? { libraryId } : {};
    const containerWhere = libraryId ? { libraryId } : {};

    const [totalBooks, unlocated, rooms, shelves, boxes] = await Promise.all([
      prisma.book.count({ where: bookWhere }),
      prisma.book.count({ where: { ...bookWhere, locationType: 'none' } }),
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

    res.json({ totalBooks, unlocated, rooms, shelves, boxes });
  } catch (err) {
    next(err);
  }
});

export default router;
