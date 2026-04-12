import { Router } from 'express';
import prisma from '../utils/prisma.js';

const router = Router();

// 生成箱子编号：YYYYMMDD-NNN
async function generateBoxUid() {
  const today = new Date();
  const dateStr = today.toISOString().slice(0, 10).replace(/-/g, '');
  const prefix = dateStr + '-';

  // 查找今天已有的最大编号
  const lastBox = await prisma.box.findFirst({
    where: { boxUid: { startsWith: prefix } },
    orderBy: { boxUid: 'desc' },
  });

  let seq = 1;
  if (lastBox) {
    const lastSeq = parseInt(lastBox.boxUid.split('-')[1], 10);
    seq = lastSeq + 1;
  }

  return `${prefix}${String(seq).padStart(3, '0')}`;
}

// 获取所有箱子列表
router.get('/', async (req, res, next) => {
  try {
    const boxes = await prisma.box.findMany({
      orderBy: { createdAt: 'desc' },
    });
    res.json(boxes);
  } catch (err) {
    next(err);
  }
});

// 新建箱子
router.post('/', async (req, res, next) => {
  try {
    const { name, description } = req.body;

    if (!name) {
      return res.status(400).json({ error: '箱子名称不能为空' });
    }

    const boxUid = await generateBoxUid();
    const box = await prisma.box.create({
      data: { boxUid, name, description },
    });

    res.status(201).json(box);
  } catch (err) {
    next(err);
  }
});

// 获取箱子详情及其中的书
router.get('/:id', async (req, res, next) => {
  try {
    const id = parseInt(req.params.id, 10);
    const box = await prisma.box.findUnique({
      where: { id },
      include: {
        boxBooks: {
          include: { book: { include: { category: true } } },
          orderBy: { addedAt: 'desc' },
        },
      },
    });

    if (!box) {
      return res.status(404).json({ error: '箱子不存在' });
    }

    // 扁平化返回书籍列表
    const result = {
      ...box,
      books: box.boxBooks.map((bb) => ({
        ...bb.book,
        addedAt: bb.addedAt,
      })),
    };
    delete result.boxBooks;

    res.json(result);
  } catch (err) {
    next(err);
  }
});

// 更新箱子信息
router.put('/:id', async (req, res, next) => {
  try {
    const id = parseInt(req.params.id, 10);
    const { name, description } = req.body;

    const box = await prisma.box.update({
      where: { id },
      data: {
        ...(name !== undefined && { name }),
        ...(description !== undefined && { description }),
      },
    });

    res.json(box);
  } catch (err) {
    if (err.code === 'P2025') {
      return res.status(404).json({ error: '箱子不存在' });
    }
    next(err);
  }
});

// 删除箱子（书不删除，只解除关联）
router.delete('/:id', async (req, res, next) => {
  try {
    const id = parseInt(req.params.id, 10);

    await prisma.$transaction([
      prisma.boxBook.deleteMany({ where: { boxId: id } }),
      prisma.box.delete({ where: { id } }),
    ]);

    res.json({ message: '箱子已删除' });
  } catch (err) {
    if (err.code === 'P2025') {
      return res.status(404).json({ error: '箱子不存在' });
    }
    next(err);
  }
});

// 向箱子中添加书籍
router.post('/:id/books', async (req, res, next) => {
  try {
    const boxId = parseInt(req.params.id, 10);
    const { bookIds } = req.body;

    if (!Array.isArray(bookIds) || bookIds.length === 0) {
      return res.status(400).json({ error: '请提供书籍 ID 列表' });
    }

    // 批量创建关联
    await prisma.boxBook.createMany({
      data: bookIds.map((bookId) => ({ boxId, bookId })),
      skipDuplicates: true,
    });

    // 更新箱子书籍数量
    const count = await prisma.boxBook.count({ where: { boxId } });
    await prisma.box.update({
      where: { id: boxId },
      data: { bookCount: count },
    });

    res.json({ message: `已添加 ${bookIds.length} 本书` });
  } catch (err) {
    next(err);
  }
});

// 从箱子中移除书籍
router.delete('/:id/books/:bookId', async (req, res, next) => {
  try {
    const boxId = parseInt(req.params.id, 10);
    const bookId = parseInt(req.params.bookId, 10);

    await prisma.boxBook.deleteMany({ where: { boxId, bookId } });

    // 更新箱子书籍数量
    const count = await prisma.boxBook.count({ where: { boxId } });
    await prisma.box.update({
      where: { id: boxId },
      data: { bookCount: count },
    });

    res.json({ message: '已从箱子中移除' });
  } catch (err) {
    next(err);
  }
});

export default router;
