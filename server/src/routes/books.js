import { Router } from 'express';
import prisma from '../utils/prisma.js';

const router = Router();

// 获取书籍列表（支持分页、搜索、按分类筛选）
router.get('/', async (req, res, next) => {
  try {
    const {
      page = 1,
      pageSize = 20,
      search,
      categoryId,
      verifyStatus,
      boxId,
    } = req.query;

    const skip = (parseInt(page, 10) - 1) * parseInt(pageSize, 10);
    const take = parseInt(pageSize, 10);

    const where = {};

    // 搜索：按书名或作者模糊匹配
    if (search) {
      where.OR = [
        { title: { contains: search } },
        { author: { contains: search } },
      ];
    }

    // 按分类筛选
    if (categoryId) {
      where.categoryId = parseInt(categoryId, 10);
    }

    // 按校验状态筛选
    if (verifyStatus) {
      where.verifyStatus = verifyStatus;
    }

    // 按箱子筛选
    if (boxId) {
      where.boxBooks = { some: { boxId: parseInt(boxId, 10) } };
    }

    const [books, total] = await Promise.all([
      prisma.book.findMany({
        where,
        include: { category: true },
        skip,
        take,
        orderBy: { createdAt: 'desc' },
      }),
      prisma.book.count({ where }),
    ]);

    res.json({
      data: books,
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

// 新增书籍
router.post('/', async (req, res, next) => {
  try {
    const {
      title,
      author,
      isbn,
      publisher,
      coverUrl,
      categoryId,
      verifyStatus,
      verifySource,
      rawOcrText,
    } = req.body;

    if (!title) {
      return res.status(400).json({ error: '书名不能为空' });
    }

    const book = await prisma.book.create({
      data: {
        title,
        author,
        isbn,
        publisher,
        coverUrl,
        categoryId: categoryId ? parseInt(categoryId, 10) : null,
        verifyStatus: verifyStatus || 'not_found',
        verifySource,
        rawOcrText,
      },
    });

    res.status(201).json(book);
  } catch (err) {
    next(err);
  }
});

// 批量新增书籍（装箱模式一次拍照多本）
router.post('/batch', async (req, res, next) => {
  try {
    const { books, boxId } = req.body;

    if (!Array.isArray(books) || books.length === 0) {
      return res.status(400).json({ error: '请提供书籍列表' });
    }

    const results = [];

    for (const bookData of books) {
      if (!bookData.title) continue;

      const book = await prisma.book.create({
        data: {
          title: bookData.title,
          author: bookData.author,
          isbn: bookData.isbn,
          publisher: bookData.publisher,
          coverUrl: bookData.coverUrl,
          categoryId: bookData.categoryId
            ? parseInt(bookData.categoryId, 10)
            : null,
          verifyStatus: bookData.verifyStatus || 'not_found',
          verifySource: bookData.verifySource,
          rawOcrText: bookData.rawOcrText,
        },
      });

      // 如果指定了箱子，建立关联
      if (boxId) {
        await prisma.boxBook.create({
          data: {
            boxId: parseInt(boxId, 10),
            bookId: book.id,
          },
        });
      }

      results.push(book);
    }

    // 更新箱子书籍数量
    if (boxId) {
      const count = await prisma.boxBook.count({
        where: { boxId: parseInt(boxId, 10) },
      });
      await prisma.box.update({
        where: { id: parseInt(boxId, 10) },
        data: { bookCount: count },
      });
    }

    res.status(201).json({ created: results.length, books: results });
  } catch (err) {
    next(err);
  }
});

// 获取书籍详情
router.get('/:id', async (req, res, next) => {
  try {
    const id = parseInt(req.params.id, 10);
    const book = await prisma.book.findUnique({
      where: { id },
      include: {
        category: true,
        boxBooks: {
          include: { box: true },
        },
      },
    });

    if (!book) {
      return res.status(404).json({ error: '书籍不存在' });
    }

    // 扁平化箱子信息
    const result = {
      ...book,
      boxes: book.boxBooks.map((bb) => bb.box),
    };
    delete result.boxBooks;

    res.json(result);
  } catch (err) {
    next(err);
  }
});

// 更新书籍信息
router.put('/:id', async (req, res, next) => {
  try {
    const id = parseInt(req.params.id, 10);
    const {
      title,
      author,
      isbn,
      publisher,
      coverUrl,
      categoryId,
      verifyStatus,
      verifySource,
    } = req.body;

    const data = {};
    if (title !== undefined) data.title = title;
    if (author !== undefined) data.author = author;
    if (isbn !== undefined) data.isbn = isbn;
    if (publisher !== undefined) data.publisher = publisher;
    if (coverUrl !== undefined) data.coverUrl = coverUrl;
    if (categoryId !== undefined)
      data.categoryId = categoryId ? parseInt(categoryId, 10) : null;
    if (verifyStatus !== undefined) data.verifyStatus = verifyStatus;
    if (verifySource !== undefined) data.verifySource = verifySource;

    const book = await prisma.book.update({
      where: { id },
      data,
    });

    res.json(book);
  } catch (err) {
    if (err.code === 'P2025') {
      return res.status(404).json({ error: '书籍不存在' });
    }
    next(err);
  }
});

// 删除书籍
router.delete('/:id', async (req, res, next) => {
  try {
    const id = parseInt(req.params.id, 10);

    await prisma.$transaction([
      prisma.boxBook.deleteMany({ where: { bookId: id } }),
      prisma.book.delete({ where: { id } }),
    ]);

    res.json({ message: '书籍已删除' });
  } catch (err) {
    if (err.code === 'P2025') {
      return res.status(404).json({ error: '书籍不存在' });
    }
    next(err);
  }
});

export default router;
