import { Router } from 'express';
import prisma from '../utils/prisma.js';
import { parseId, parsePagination, paginationResponse, resolveContainerPlacement } from '../utils/validate.js';

const router = Router();

// 更新容器的 book_count（统一用 COUNT 重算）
async function updateBoxCount(tx, boxId) {
  const count = await tx.book.count({
    where: { locationType: 'box', locationId: boxId },
  });
  await tx.box.update({ where: { id: boxId }, data: { bookCount: count } });
}

// 获取所有箱子列表（支持按书库/房间筛选）
router.get('/', async (req, res, next) => {
  try {
    const where = {};
    if (req.query.libraryId) {
      where.libraryId = parseId(req.query.libraryId, '书库 ID');
    }
    if (req.query.roomId) {
      where.roomId = parseId(req.query.roomId, '房间 ID');
    }

    const boxes = await prisma.box.findMany({
      where,
      orderBy: { createdAt: 'desc' },
    });
    res.json(boxes);
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    next(err);
  }
});

// 新建箱子（在事务内生成编号，避免竞态）
router.post('/', async (req, res, next) => {
  try {
    const { name, description, libraryId, roomId } = req.body;

    if (!name) {
      return res.status(400).json({ error: '箱子名称不能为空' });
    }

    // 先解析归属（事务外校验，避免 serializable 重试浪费 LLM 代价类资源）
    const placement = await resolveContainerPlacement(prisma, { libraryId, roomId });

    // 使用 Serializable 隔离级别防止并发生成重复 box_uid
    const box = await prisma.$transaction(async (tx) => {
      const today = new Date();
      const dateStr = today.toISOString().slice(0, 10).replace(/-/g, '');
      const prefix = dateStr + '-';

      const lastBox = await tx.box.findFirst({
        where: { boxUid: { startsWith: prefix } },
        orderBy: { boxUid: 'desc' },
      });

      let seq = 1;
      if (lastBox) {
        const lastSeq = parseInt(lastBox.boxUid.split('-')[1], 10);
        seq = lastSeq + 1;
      }

      const boxUid = `${prefix}${String(seq).padStart(3, '0')}`;

      return tx.box.create({
        data: { boxUid, name, description, ...placement },
      });
    }, { isolationLevel: 'Serializable' });

    res.status(201).json(box);
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    if (err.code === 'P2002') {
      return res.status(409).json({ error: '箱子编号冲突，请重试' });
    }
    next(err);
  }
});

// 获取箱子详情及其中的书
router.get('/:id', async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '箱子 ID');
    const { page, pageSize, skip, take } = parsePagination(req.query, 50);

    const box = await prisma.box.findUnique({ where: { id } });

    if (!box) {
      return res.status(404).json({ error: '箱子不存在' });
    }

    const [books, total] = await Promise.all([
      prisma.book.findMany({
        where: { locationType: 'box', locationId: id },
        include: { category: true },
        skip,
        take,
        orderBy: { createdAt: 'desc' },
      }),
      prisma.book.count({
        where: { locationType: 'box', locationId: id },
      }),
    ]);

    res.json({
      ...box,
      books,
      pagination: paginationResponse(page, pageSize, total),
    });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    next(err);
  }
});

// 更新箱子信息（支持搬动：roomId/libraryId 任一传入会重新计算归属）
router.put('/:id', async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '箱子 ID');
    const { name, description, libraryId, roomId } = req.body;

    const data = {};
    if (name !== undefined) data.name = name;
    if (description !== undefined) data.description = description;

    const hasRoom = Object.prototype.hasOwnProperty.call(req.body, 'roomId');
    const hasLib = Object.prototype.hasOwnProperty.call(req.body, 'libraryId');
    if (hasRoom || hasLib) {
      const placement = await resolveContainerPlacement(prisma, { libraryId, roomId });
      data.libraryId = placement.libraryId;
      data.roomId = placement.roomId;
    }

    const box = await prisma.box.update({ where: { id }, data });

    res.json(box);
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    if (err.code === 'P2025') {
      return res.status(404).json({ error: '箱子不存在' });
    }
    next(err);
  }
});

// 删除箱子（书不删除，只重置位置，并记录日志）
router.delete('/:id', async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '箱子 ID');

    const box = await prisma.box.findUnique({ where: { id } });
    if (!box) {
      return res.status(404).json({ error: '箱子不存在' });
    }

    await prisma.$transaction(async (tx) => {
      // 查找箱内所有书籍，为每本书写日志
      const booksInBox = await tx.book.findMany({
        where: { locationType: 'box', locationId: id },
        select: { id: true },
      });

      if (booksInBox.length > 0) {
        // 批量写入日志
        await tx.bookLog.createMany({
          data: booksInBox.map((b) => ({
            bookId: b.id,
            action: 'move',
            fromType: 'box',
            fromId: id,
            toType: 'none',
            method: 'manual',
            note: `箱子「${box.name}」被删除，书籍自动移出`,
          })),
        });

        // 重置书的位置
        await tx.book.updateMany({
          where: { locationType: 'box', locationId: id },
          data: { locationType: 'none', locationId: null },
        });
      }

      await tx.box.delete({ where: { id } });
    }, { isolationLevel: 'Serializable' });

    res.json({ message: '箱子已删除' });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    if (err.code === 'P2025') {
      return res.status(404).json({ error: '箱子不存在' });
    }
    next(err);
  }
});

// 向箱子中添加书籍
router.post('/:id/books', async (req, res, next) => {
  try {
    const boxId = parseId(req.params.id, '箱子 ID');
    const { bookIds } = req.body;

    if (!Array.isArray(bookIds) || bookIds.length === 0) {
      return res.status(400).json({ error: '请提供书籍 ID 列表' });
    }

    const box = await prisma.box.findUnique({ where: { id: boxId } });
    if (!box) {
      return res.status(404).json({ error: '箱子不存在' });
    }

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

      // 更新书的位置；箱子归属非空时同步把书的 libraryId 对齐到箱子所在书库
      const updateData = { locationType: 'box', locationId: boxId };
      if (box.libraryId) updateData.libraryId = box.libraryId;
      await tx.book.updateMany({
        where: { id: { in: bookIds } },
        data: updateData,
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

      // 用 COUNT 重算目标箱子的 book_count
      await updateBoxCount(tx, boxId);

      // 批量写入日志
      await tx.bookLog.createMany({
        data: books.map((book) => ({
          bookId: book.id,
          action: 'move',
          fromType: book.locationType || 'none',
          fromId: book.locationId,
          toType: 'box',
          toId: boxId,
          method: 'manual',
        })),
      });
    }, { isolationLevel: 'Serializable' });

    res.json({ message: `已添加 ${bookIds.length} 本书` });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    next(err);
  }
});

// 从箱子中移除书籍
router.delete('/:id/books/:bookId', async (req, res, next) => {
  try {
    const boxId = parseId(req.params.id, '箱子 ID');
    const bookId = parseId(req.params.bookId, '书籍 ID');

    const book = await prisma.book.findFirst({
      where: { id: bookId, locationType: 'box', locationId: boxId },
    });

    if (!book) {
      return res.status(404).json({ error: '该书不在此箱子中' });
    }

    await prisma.$transaction(async (tx) => {
      await tx.book.update({
        where: { id: bookId },
        data: { locationType: 'none', locationId: null },
      });

      await updateBoxCount(tx, boxId);

      await tx.bookLog.create({
        data: {
          bookId,
          action: 'remove',
          fromType: 'box',
          fromId: boxId,
          toType: 'none',
          method: 'manual',
        },
      });
    }, { isolationLevel: 'Serializable' });

    res.json({ message: '已从箱子中移除' });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    next(err);
  }
});

export default router;
