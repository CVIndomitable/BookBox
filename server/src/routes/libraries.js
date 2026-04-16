import { Router } from 'express';
import prisma from '../utils/prisma.js';
import { parseId } from '../utils/validate.js';

const router = Router();

// 获取所有书库列表（附带统计，使用聚合避免 N+1 查询）
router.get('/', async (req, res, next) => {
  try {
    const libraries = await prisma.library.findMany({
      include: { _count: { select: { books: true } } },
      orderBy: { createdAt: 'desc' },
    });

    const result = libraries.map((lib) => {
      const { _count, ...rest } = lib;
      return { ...rest, bookCount: _count.books };
    });

    res.json(result);
  } catch (err) {
    next(err);
  }
});

// 新建书库（同时创建"默认房间"）
router.post('/', async (req, res, next) => {
  try {
    const { name, location, description } = req.body;

    if (!name) {
      return res.status(400).json({ error: '书库名称不能为空' });
    }

    const library = await prisma.$transaction(async (tx) => {
      const lib = await tx.library.create({
        data: { name, location, description },
      });
      await tx.room.create({
        data: { name: '默认房间', isDefault: true, libraryId: lib.id },
      });
      return lib;
    });

    res.status(201).json(library);
  } catch (err) {
    next(err);
  }
});

// 获取书库详情（含总览统计）
router.get('/:id', async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '书库 ID');

    const library = await prisma.library.findUnique({ where: { id } });
    if (!library) {
      return res.status(404).json({ error: '书库不存在' });
    }

    const [totalBooks, unlocated, rooms, shelves, boxes] = await Promise.all([
      prisma.book.count({ where: { libraryId: id } }),
      prisma.book.count({ where: { libraryId: id, locationType: 'none' } }),
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

    res.json({ ...library, totalBooks, unlocated, rooms, shelves, boxes });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    next(err);
  }
});

// 更新书库信息
router.put('/:id', async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '书库 ID');
    const { name, location, description } = req.body;

    const data = {};
    if (name !== undefined) data.name = name;
    if (location !== undefined) data.location = location;
    if (description !== undefined) data.description = description;

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
router.delete('/:id', async (req, res, next) => {
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

      // rooms 通过 onDelete: Cascade 自动删除
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
