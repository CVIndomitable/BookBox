import { Router } from 'express';
import prisma from '../utils/prisma.js';
import { parseId, parsePagination, paginationResponse } from '../utils/validate.js';

const router = Router();

// 更新书架的 book_count（统一用 COUNT 重算）
async function updateShelfCount(tx, shelfId) {
  const count = await tx.book.count({
    where: { locationType: 'shelf', locationId: shelfId },
  });
  await tx.shelf.update({ where: { id: shelfId }, data: { bookCount: count } });
}

// 获取所有书架列表（支持按书库筛选）
router.get('/', async (req, res, next) => {
  try {
    const where = {};
    if (req.query.libraryId) {
      where.libraryId = parseId(req.query.libraryId, '书库 ID');
    }

    const shelves = await prisma.shelf.findMany({
      where,
      orderBy: { createdAt: 'desc' },
    });
    res.json(shelves);
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    next(err);
  }
});

// 新建书架
router.post('/', async (req, res, next) => {
  try {
    const { name, location, description, libraryId } = req.body;

    if (!name) {
      return res.status(400).json({ error: '书架名称不能为空' });
    }

    const data = { name, location, description };
    if (libraryId) {
      data.libraryId = parseId(libraryId, '书库 ID');
    }

    const shelf = await prisma.shelf.create({ data });

    res.status(201).json(shelf);
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    next(err);
  }
});

// 获取书架详情及其中的书（分页）
router.get('/:id', async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '书架 ID');
    const { page, pageSize, skip, take } = parsePagination(req.query);

    const shelf = await prisma.shelf.findUnique({ where: { id } });

    if (!shelf) {
      return res.status(404).json({ error: '书架不存在' });
    }

    const [books, total] = await Promise.all([
      prisma.book.findMany({
        where: { locationType: 'shelf', locationId: id },
        include: { category: true },
        skip,
        take,
        orderBy: { createdAt: 'desc' },
      }),
      prisma.book.count({
        where: { locationType: 'shelf', locationId: id },
      }),
    ]);

    res.json({
      ...shelf,
      books,
      pagination: paginationResponse(page, pageSize, total),
    });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    next(err);
  }
});

// 更新书架信息
router.put('/:id', async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '书架 ID');
    const { name, location, description } = req.body;

    const data = {};
    if (name !== undefined) data.name = name;
    if (location !== undefined) data.location = location;
    if (description !== undefined) data.description = description;

    const shelf = await prisma.shelf.update({
      where: { id },
      data,
    });

    res.json(shelf);
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    if (err.code === 'P2025') {
      return res.status(404).json({ error: '书架不存在' });
    }
    next(err);
  }
});

// 删除书架（书的 location 重置为 none，并记录日志）
router.delete('/:id', async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '书架 ID');

    const shelf = await prisma.shelf.findUnique({ where: { id } });
    if (!shelf) {
      return res.status(404).json({ error: '书架不存在' });
    }

    await prisma.$transaction(async (tx) => {
      // 查找书架上所有书籍，为每本书写日志
      const booksOnShelf = await tx.book.findMany({
        where: { locationType: 'shelf', locationId: id },
        select: { id: true },
      });

      if (booksOnShelf.length > 0) {
        // 批量写入日志
        await tx.bookLog.createMany({
          data: booksOnShelf.map((b) => ({
            bookId: b.id,
            action: 'move',
            fromType: 'shelf',
            fromId: id,
            toType: 'none',
            method: 'manual',
            note: `书架「${shelf.name}」被删除，书籍自动移出`,
          })),
        });

        // 重置书的位置
        await tx.book.updateMany({
          where: { locationType: 'shelf', locationId: id },
          data: { locationType: 'none', locationId: null },
        });
      }

      await tx.shelf.delete({ where: { id } });
    });

    res.json({ message: '书架已删除' });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    if (err.code === 'P2025') {
      return res.status(404).json({ error: '书架不存在' });
    }
    next(err);
  }
});

// 批量将书放入书架
router.post('/:id/books', async (req, res, next) => {
  try {
    const shelfId = parseId(req.params.id, '书架 ID');
    const { bookIds } = req.body;

    if (!Array.isArray(bookIds) || bookIds.length === 0) {
      return res.status(400).json({ error: '请提供书籍 ID 列表' });
    }

    const shelf = await prisma.shelf.findUnique({ where: { id: shelfId } });
    if (!shelf) {
      return res.status(404).json({ error: '书架不存在' });
    }

    // 获取这些书的当前位置，用于记录日志
    const books = await prisma.book.findMany({
      where: { id: { in: bookIds } },
    });

    await prisma.$transaction(async (tx) => {
      // 收集需要更新 book_count 的旧容器
      const oldContainers = new Set();
      for (const book of books) {
        if (book.locationType !== 'none' && book.locationId) {
          oldContainers.add(`${book.locationType}:${book.locationId}`);
        }
      }

      // 更新书的位置
      await tx.book.updateMany({
        where: { id: { in: bookIds } },
        data: { locationType: 'shelf', locationId: shelfId },
      });

      // 用 COUNT 重算旧容器的 book_count
      for (const key of oldContainers) {
        const [type, idStr] = key.split(':');
        const containerId = parseInt(idStr, 10);
        const count = await tx.book.count({
          where: { locationType: type, locationId: containerId },
        });
        if (type === 'shelf') {
          await tx.shelf.update({ where: { id: containerId }, data: { bookCount: count } });
        } else if (type === 'box') {
          await tx.box.update({ where: { id: containerId }, data: { bookCount: count } });
        }
      }

      // 用 COUNT 重算目标书架的 book_count
      await updateShelfCount(tx, shelfId);

      // 批量写入日志
      await tx.bookLog.createMany({
        data: books.map((book) => ({
          bookId: book.id,
          action: 'move',
          fromType: book.locationType || 'none',
          fromId: book.locationId,
          toType: 'shelf',
          toId: shelfId,
          method: 'manual',
        })),
      });
    });

    res.json({ message: `已将 ${bookIds.length} 本书放入书架` });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    next(err);
  }
});

// 从书架移走一本书（location 重置为 none）
router.delete('/:id/books/:bookId', async (req, res, next) => {
  try {
    const shelfId = parseId(req.params.id, '书架 ID');
    const bookId = parseId(req.params.bookId, '书籍 ID');

    const book = await prisma.book.findFirst({
      where: { id: bookId, locationType: 'shelf', locationId: shelfId },
    });

    if (!book) {
      return res.status(404).json({ error: '该书不在此书架上' });
    }

    await prisma.$transaction(async (tx) => {
      await tx.book.update({
        where: { id: bookId },
        data: { locationType: 'none', locationId: null },
      });

      await updateShelfCount(tx, shelfId);

      await tx.bookLog.create({
        data: {
          bookId,
          action: 'remove',
          fromType: 'shelf',
          fromId: shelfId,
          toType: 'none',
          method: 'manual',
        },
      });
    });

    res.json({ message: '已从书架移走' });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    next(err);
  }
});

export default router;
