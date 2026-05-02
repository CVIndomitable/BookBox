import { Router } from 'express';
import prisma from '../utils/prisma.js';
import { parseId } from '../utils/validate.js';
import { authenticate, checkLibraryAccess } from '../middleware/auth.js';

const router = Router();

// 获取当前用户可访问的书库列表
// bookCount 按"容器 bookCount 之和 + 未归位"计算，保持每库独立且与总览口径一致
router.get('/', authenticate, async (req, res, next) => {
  try {
    const memberships = await prisma.libraryMember.findMany({
      where: { userId: req.user.id },
      include: {
        library: {
          include: {
            shelves: { select: { bookCount: true } },
            boxes: { select: { bookCount: true } },
          },
        },
      },
      orderBy: { createdAt: 'desc' }
    });

    const libraryIds = memberships.map((m) => m.library.id);
    const unlocatedCounts = libraryIds.length > 0
      ? await prisma.book.groupBy({
          by: ['libraryId'],
          where: { libraryId: { in: libraryIds }, locationType: 'none', deletedAt: null },
          _count: { _all: true },
        })
      : [];
    const unlocatedMap = new Map(
      unlocatedCounts.map((r) => [r.libraryId, r._count._all])
    );

    const result = memberships.map((m) => {
      const { shelves, boxes, ...rest } = m.library;
      const shelfSum = shelves.reduce((a, s) => a + (s.bookCount || 0), 0);
      const boxSum = boxes.reduce((a, b) => a + (b.bookCount || 0), 0);
      const unlocated = unlocatedMap.get(m.library.id) || 0;
      return {
        ...rest,
        bookCount: shelfSum + boxSum + unlocated,
        role: m.role
      };
    });

    res.json(result);
  } catch (err) {
    next(err);
  }
});

// 新建书库（同时创建"默认房间"并设置创建者为 owner）
router.post('/', authenticate, async (req, res, next) => {
  try {
    const { name, location, description, sunDays } = req.body;

    if (!name) {
      return res.status(400).json({ error: '书库名称不能为空' });
    }

    const library = await prisma.$transaction(async (tx) => {
      const lib = await tx.library.create({
        data: { name, location, description, sunDays: sunDays || null },
      });
      await tx.room.create({
        data: { name: '默认房间', isDefault: true, libraryId: lib.id },
      });
      await tx.libraryMember.create({
        data: {
          userId: req.user.id,
          libraryId: lib.id,
          role: 'owner'
        }
      });
      return lib;
    });

    res.status(201).json(library);
  } catch (err) {
    next(err);
  }
});

// 获取书库详情（含总览统计）
router.get('/:id', authenticate, checkLibraryAccess('member'), async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '书库 ID');

    const library = await prisma.library.findUnique({ where: { id } });
    if (!library) {
      return res.status(404).json({ error: '书库不存在' });
    }

    // totalBooks 严格按书库独立：取显示的 shelves/boxes.bookCount 之和 + 本库未归位
    const [unlocated, rooms, shelves, boxes] = await Promise.all([
      prisma.book.count({ where: { libraryId: id, locationType: 'none', deletedAt: null } }),
      prisma.room.findMany({
        where: { libraryId: id },
        select: { id: true, name: true, isDefault: true, description: true, createdAt: true },
        orderBy: [{ isDefault: 'desc' }, { createdAt: 'asc' }],
      }),
      prisma.shelf.findMany({
        where: { libraryId: id },
        select: { id: true, name: true, location: true, bookCount: true, roomId: true },
        orderBy: { createdAt: 'desc' },
      }),
      prisma.box.findMany({
        where: { libraryId: id },
        select: { id: true, boxUid: true, name: true, bookCount: true, roomId: true },
        orderBy: { createdAt: 'desc' },
      }),
    ]);

    const shelfSum = shelves.reduce((a, s) => a + (s.bookCount || 0), 0);
    const boxSum = boxes.reduce((a, b) => a + (b.bookCount || 0), 0);
    const totalBooks = shelfSum + boxSum + unlocated;

    res.json({
      ...library,
      totalBooks,
      unlocated,
      rooms,
      shelves,
      boxes,
      role: req.libraryMembership.role
    });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    next(err);
  }
});

// 更新书库信息
router.put('/:id', authenticate, checkLibraryAccess('admin'), async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '书库 ID');
    const { name, location, description, sunDays } = req.body;

    const data = {};
    if (name !== undefined) data.name = name;
    if (location !== undefined) data.location = location;
    if (description !== undefined) data.description = description;
    if (sunDays !== undefined) data.sunDays = sunDays || null;

    const library = await prisma.library.update({
      where: { id },
      data,
    });

    res.json(library);
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    if (err.code === 'P2025') {
      return res.status(404).json({ error: '书库不存在' });
    }
    next(err);
  }
});

// 删除书库（书架/箱子/书籍的 libraryId 置空）
router.delete('/:id', authenticate, checkLibraryAccess('owner'), async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '书库 ID');

    const library = await prisma.library.findUnique({ where: { id } });
    if (!library) {
      return res.status(404).json({ error: '书库不存在' });
    }

    await prisma.$transaction(async (tx) => {
      // 重置关联数据的 libraryId 与 roomId
      await tx.book.updateMany({ where: { libraryId: id }, data: { libraryId: null } });
      await tx.shelf.updateMany({ where: { libraryId: id }, data: { libraryId: null, roomId: null } });
      await tx.box.updateMany({ where: { libraryId: id }, data: { libraryId: null, roomId: null } });

      // members 和 rooms 通过 onDelete: Cascade 自动删除
      await tx.library.delete({ where: { id } });
    });

    res.json({ message: '书库已删除' });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    if (err.code === 'P2025') {
      return res.status(404).json({ error: '书库不存在' });
    }
    next(err);
  }
});

export default router;
