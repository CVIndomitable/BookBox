import { Router } from 'express';
import prisma from '../utils/prisma.js';
import { parseId, parseOptionalId, parsePagination, paginationResponse } from '../utils/validate.js';
import { verifyBook } from '../services/search/bookVerifier.js';
import {
  validateLocationType,
  validateLocation,
  updateContainerCount,
  batchResolveLocationInfo,
  handleTxConflict,
} from '../services/bookLocation.js';

const router = Router();

// 合法的地区模式
const VALID_REGIONS = ['mainland', 'overseas'];

// 获取书籍列表（支持分页、搜索、按分类/状态/位置筛选）
router.get('/', async (req, res, next) => {
  try {
    const { search, categoryId, verifyStatus, locationType, locationId, shelfId, boxId, libraryId } = req.query;
    const { page, pageSize, skip, take } = parsePagination(req.query);

    const where = {};

    if (search) {
      where.OR = [
        { title: { contains: search } },
        { author: { contains: search } },
      ];
    }

    if (categoryId) {
      where.categoryId = parseId(categoryId, '分类 ID');
    }

    if (verifyStatus) {
      where.verifyStatus = verifyStatus;
    }

    if (libraryId) {
      where.libraryId = parseId(libraryId, '书库 ID');
    }

    // 位置筛选
    if (shelfId) {
      where.locationType = 'shelf';
      where.locationId = parseId(shelfId, '书架 ID');
    } else if (boxId) {
      where.locationType = 'box';
      where.locationId = parseId(boxId, '箱子 ID');
    } else {
      if (locationType) {
        validateLocationType(locationType);
        where.locationType = locationType;
      }
      if (locationId) {
        where.locationId = parseId(locationId, '位置 ID');
      }
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
      pagination: paginationResponse(page, pageSize, total),
    });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    next(err);
  }
});

// 新增书籍
router.post('/', async (req, res, next) => {
  try {
    const {
      title, author, isbn, publisher, coverUrl,
      categoryId, verifyStatus, verifySource, rawOcrText,
      locationType, locationId, libraryId,
    } = req.body;

    if (!title) {
      return res.status(400).json({ error: '书名不能为空' });
    }

    const finalLocationType = locationType || 'none';
    validateLocationType(finalLocationType);
    const finalLocationId = parseOptionalId(locationId);

    // 位置类型非 none 时必须提供 locationId
    if (finalLocationType !== 'none' && !finalLocationId) {
      return res.status(400).json({ error: '指定位置类型时必须提供位置 ID' });
    }

    const book = await prisma.$transaction(async (tx) => {
      // 事务内校验目标存在，防止校验后、写入前目标被并发删除
      // 同时拿到目标容器的 libraryId，作为 book.libraryId 的默认来源
      let containerLibraryId = null;
      if (finalLocationType !== 'none') {
        containerLibraryId = await validateLocation(tx, finalLocationType, finalLocationId);
      }

      const created = await tx.book.create({
        data: {
          title,
          author,
          isbn,
          publisher,
          coverUrl,
          categoryId: parseOptionalId(categoryId),
          verifyStatus: verifyStatus || 'not_found',
          verifySource,
          rawOcrText,
          locationType: finalLocationType,
          locationId: finalLocationId,
          libraryId: parseOptionalId(libraryId) ?? containerLibraryId,
        },
      });

      // 更新容器 book_count
      if (finalLocationType !== 'none' && finalLocationId) {
        await updateContainerCount(tx, finalLocationType, finalLocationId);
      }

      // 写入日志
      await tx.bookLog.create({
        data: {
          bookId: created.id,
          action: 'add',
          toType: finalLocationType,
          toId: finalLocationId,
          method: 'manual',
        },
      });

      return created;
    }, { isolationLevel: 'Serializable' });

    res.status(201).json(book);
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    if (handleTxConflict(res, err)) return;
    next(err);
  }
});

// 查重：按「书名 + 出版社」精确匹配返回已存在的书
// 请求体：{ books: [{title, publisher?}] }
// 响应：{ duplicates: [{ index, existing: {id, title, publisher, author, libraryId, locationType, locationId} }] }
// 规则：title 去首尾空白 + 小写后相等；请求未给 publisher 时只按书名匹配（AI 常漏出版社）；跨全部书库查重
router.post('/check-duplicates', async (req, res, next) => {
  try {
    const { books } = req.body || {};
    if (!Array.isArray(books) || books.length === 0) {
      return res.status(400).json({ error: '请提供书籍列表' });
    }

    const norm = (s) => (s ?? '').toString().trim().toLowerCase();

    const titles = Array.from(new Set(books.map((b) => norm(b?.title)).filter(Boolean)));
    if (titles.length === 0) {
      return res.json({ duplicates: [] });
    }

    // 一次性按候选书名的 OR 条件拉回来，再在内存里按精确规则匹配
    const where = {
      OR: titles.map((t) => ({ title: { equals: t } })),
    };

    // Prisma 默认 collation 对中文大小写不敏感，title equals 已够用；这里宽松一点用 contains 也能命中，但保持精确
    const candidates = await prisma.book.findMany({
      where,
      select: {
        id: true,
        title: true,
        publisher: true,
        author: true,
        libraryId: true,
        locationType: true,
        locationId: true,
      },
      take: 2000,
    });

    const duplicates = [];
    books.forEach((b, index) => {
      const nt = norm(b?.title);
      const np = norm(b?.publisher);
      if (!nt) return;
      // 请求侧没给 publisher：只按 title 判重（AI 识别常拿不到出版社，此时宁可多提醒）
      const hit = candidates.find((c) => {
        if (norm(c.title) !== nt) return false;
        if (!np) return true;
        return norm(c.publisher) === np;
      });
      if (hit) duplicates.push({ index, existing: hit });
    });

    res.json({ duplicates });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    next(err);
  }
});

// 全库查重：扫描所有书，按「书名 + 出版社」分组，返回存在重复（count >= 2）的分组
// 必须声明在 /:id 之前，避免被通配路由捕获
// 规则：title/publisher 去首尾空白 + 小写后相等；publisher 两侧都为空也算相等
// 响应：{
//   groups: [{ title, publisher, count, books: [{id,title,publisher,author,libraryId,locationType,locationId,coverUrl,verifyStatus,createdAt}] }],
//   totalGroups, totalDuplicateBooks
// }
router.get('/duplicates', async (req, res, next) => {
  try {
    const norm = (s) => (s ?? '').toString().trim().toLowerCase();

    // 一次性拉全量书（只取查重所需字段），按分组逻辑在内存里聚合
    // 注：当前场景量级不大；若将来几十万本可改用 SQL GROUP BY
    const all = await prisma.book.findMany({
      select: {
        id: true,
        title: true,
        publisher: true,
        author: true,
        libraryId: true,
        locationType: true,
        locationId: true,
        coverUrl: true,
        verifyStatus: true,
        createdAt: true,
      },
      orderBy: { createdAt: 'asc' },
    });

    const groupsMap = new Map();
    for (const b of all) {
      const nt = norm(b.title);
      if (!nt) continue; // 空书名不参与查重
      const np = norm(b.publisher);
      const key = `${nt}\u0000${np}`;
      if (!groupsMap.has(key)) {
        groupsMap.set(key, {
          title: b.title,
          publisher: b.publisher ?? null,
          books: [],
        });
      }
      groupsMap.get(key).books.push(b);
    }

    const groups = [];
    let totalDuplicateBooks = 0;
    for (const g of groupsMap.values()) {
      if (g.books.length < 2) continue;
      totalDuplicateBooks += g.books.length;
      groups.push({
        title: g.title,
        publisher: g.publisher,
        count: g.books.length,
        books: g.books,
      });
    }

    // 重复最多的排前面；同等数量按书名排序方便人眼浏览
    groups.sort((a, b) => {
      if (b.count !== a.count) return b.count - a.count;
      return a.title.localeCompare(b.title, 'zh-CN');
    });

    res.json({
      groups,
      totalGroups: groups.length,
      totalDuplicateBooks,
    });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    next(err);
  }
});

// 书籍联网校验（豆瓣/Google Books/Open Library）
// 必须声明在 /:id 之前，避免被通配路由捕获
router.post('/verify', async (req, res, next) => {
  try {
    const { title, region = 'mainland' } = req.body || {};
    if (!title || typeof title !== 'string') {
      return res.status(400).json({ error: '请提供书名' });
    }
    const normalized = VALID_REGIONS.includes(region) ? region : 'mainland';
    const result = await verifyBook(title, normalized);
    res.json(result);
  } catch (err) {
    next(err);
  }
});

// 批量新增书籍
router.post('/batch', async (req, res, next) => {
  try {
    const { books, locationType, locationId, boxId, libraryId } = req.body;

    if (!Array.isArray(books) || books.length === 0) {
      return res.status(400).json({ error: '请提供书籍列表' });
    }

    // 兼容旧的 boxId 参数
    const finalLocationType = locationType || (boxId ? 'box' : 'none');
    validateLocationType(finalLocationType);
    const finalLocationId = parseOptionalId(locationId) || parseOptionalId(boxId);

    const skipped = [];
    const results = await prisma.$transaction(async (tx) => {
      // 事务内校验目标存在，同时拿到容器 libraryId 兜底
      let containerLibraryId = null;
      if (finalLocationType !== 'none' && finalLocationId) {
        containerLibraryId = await validateLocation(tx, finalLocationType, finalLocationId);
      }
      const resolvedLibraryId = parseOptionalId(libraryId) ?? containerLibraryId;

      const created = [];

      for (let i = 0; i < books.length; i++) {
        const bookData = books[i];
        if (!bookData.title) {
          skipped.push({ index: i, reason: '缺少书名' });
          continue;
        }

        const book = await tx.book.create({
          data: {
            title: bookData.title,
            author: bookData.author,
            isbn: bookData.isbn,
            publisher: bookData.publisher,
            coverUrl: bookData.coverUrl,
            categoryId: parseOptionalId(bookData.categoryId),
            verifyStatus: bookData.verifyStatus || 'not_found',
            verifySource: bookData.verifySource,
            rawOcrText: bookData.rawOcrText,
            locationType: finalLocationType,
            locationId: finalLocationId,
            libraryId: resolvedLibraryId,
          },
        });

        created.push(book);
      }

      // 批量写入日志
      if (created.length > 0) {
        await tx.bookLog.createMany({
          data: created.map((book) => ({
            bookId: book.id,
            action: 'add',
            toType: finalLocationType,
            toId: finalLocationId,
            method: 'scan',
          })),
        });
      }

      // 更新容器 book_count
      if (finalLocationType !== 'none' && finalLocationId) {
        await updateContainerCount(tx, finalLocationType, finalLocationId);
      }

      return created;
    }, { isolationLevel: 'Serializable' });

    res.status(201).json({ created: results.length, skipped: skipped.length, books: results, skippedDetails: skipped });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    if (handleTxConflict(res, err)) return;
    next(err);
  }
});

// 获取书籍详情
router.get('/:id', async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '书籍 ID');
    const book = await prisma.book.findUnique({
      where: { id },
      include: { category: true },
    });

    if (!book) {
      return res.status(404).json({ error: '书籍不存在' });
    }

    const locMap = await batchResolveLocationInfo(prisma, [book]);
    const locationInfo = book.locationId
      ? locMap.get(`${book.locationType}:${book.locationId}`) ?? null
      : null;

    res.json({ ...book, locationInfo });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    next(err);
  }
});

// 更新书籍信息
router.put('/:id', async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '书籍 ID');
    const {
      title, author, isbn, publisher, coverUrl,
      categoryId, verifyStatus, verifySource,
      locationType, locationId,
    } = req.body;

    const existingBook = await prisma.book.findUnique({ where: { id } });
    if (!existingBook) {
      return res.status(404).json({ error: '书籍不存在' });
    }

    const data = {};
    if (title !== undefined) data.title = title;
    if (author !== undefined) data.author = author;
    if (isbn !== undefined) data.isbn = isbn;
    if (publisher !== undefined) data.publisher = publisher;
    if (coverUrl !== undefined) data.coverUrl = coverUrl;
    if (categoryId !== undefined)
      data.categoryId = categoryId ? parseId(categoryId, '分类 ID') : null;
    if (verifyStatus !== undefined) data.verifyStatus = verifyStatus;
    if (verifySource !== undefined) data.verifySource = verifySource;

    // 如果更新了位置，执行移动逻辑
    const isMoving = locationType !== undefined;
    if (isMoving) {
      const newLocationType = locationType || 'none';
      validateLocationType(newLocationType);
      const newLocationId = parseOptionalId(locationId);

      // 位置类型非 none 时必须提供 locationId
      if (newLocationType !== 'none' && !newLocationId) {
        return res.status(400).json({ error: '指定位置类型时必须提供位置 ID' });
      }

      data.locationType = newLocationType;
      data.locationId = newLocationId;
    }

    const book = await prisma.$transaction(async (tx) => {
      // 事务内校验目标位置存在，并同步 libraryId：
      //   - 有目标容器：取容器的 libraryId
      //   - 未归位（none）：libraryId 置 null
      if (isMoving) {
        if (data.locationType !== 'none' && data.locationId) {
          const targetLibraryId = await validateLocation(tx, data.locationType, data.locationId);
          data.libraryId = targetLibraryId ?? null;
        } else {
          data.libraryId = null;
        }
      }

      const updated = await tx.book.update({ where: { id }, data });

      if (isMoving) {
        // 更新旧容器 book_count
        if (existingBook.locationType !== 'none' && existingBook.locationId) {
          await updateContainerCount(tx, existingBook.locationType, existingBook.locationId);
        }
        // 更新新容器 book_count
        if (data.locationType !== 'none' && data.locationId) {
          await updateContainerCount(tx, data.locationType, data.locationId);
        }
        // 写移动日志
        await tx.bookLog.create({
          data: {
            bookId: id,
            action: 'move',
            fromType: existingBook.locationType,
            fromId: existingBook.locationId,
            toType: data.locationType,
            toId: data.locationId,
            method: 'manual',
          },
        });
      } else {
        // 写编辑日志（仅在有字段变更时）
        const hasEdit = Object.keys(data).length > 0;
        if (hasEdit) {
          await tx.bookLog.create({
            data: {
              bookId: id,
              action: 'edit',
              method: 'manual',
            },
          });
        }
      }

      return updated;
    }, { isolationLevel: 'Serializable' });

    res.json(book);
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    if (err.code === 'P2025') {
      return res.status(404).json({ error: '书籍不存在' });
    }
    if (handleTxConflict(res, err)) return;
    next(err);
  }
});

// 删除书籍（日志通过外键 onDelete:SetNull 自动置空 bookId）
router.delete('/:id', async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '书籍 ID');

    const book = await prisma.book.findUnique({ where: { id } });
    if (!book) {
      return res.status(404).json({ error: '书籍不存在' });
    }

    await prisma.$transaction(async (tx) => {
      // 写入删除日志（在删除书籍之前，包含完整书籍信息便于审计追溯）
      await tx.bookLog.create({
        data: {
          bookId: id,
          action: 'remove',
          fromType: book.locationType,
          fromId: book.locationId,
          toType: 'none',
          method: 'manual',
          note: `删除书籍: ${book.title}${book.author ? ` / ${book.author}` : ''}`,
        },
      });

      // 删除书籍（外键 onDelete:SetNull 会自动将日志的 bookId 置空）
      await tx.book.delete({ where: { id } });

      // 更新容器 book_count
      if (book.locationType !== 'none' && book.locationId) {
        await updateContainerCount(tx, book.locationType, book.locationId);
      }
    }, { isolationLevel: 'Serializable' });

    res.json({ message: '书籍已删除' });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    if (err.code === 'P2025') {
      return res.status(404).json({ error: '书籍不存在' });
    }
    if (handleTxConflict(res, err)) return;
    next(err);
  }
});

// 移动书籍到指定位置
router.post('/:id/move', async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '书籍 ID');
    const { toType, toId, method = 'manual', rawInput } = req.body;

    if (!toType) {
      return res.status(400).json({ error: '请指定目标位置类型' });
    }
    validateLocationType(toType);

    const book = await prisma.book.findUnique({ where: { id } });
    if (!book) {
      return res.status(404).json({ error: '书籍不存在' });
    }

    const targetId = parseOptionalId(toId);

    // 位置类型非 none 时必须提供 toId
    if (toType !== 'none' && !targetId) {
      return res.status(400).json({ error: '指定位置类型时必须提供位置 ID' });
    }

    await prisma.$transaction(async (tx) => {
      // 事务内校验目标存在，防止校验后、写入前目标被删
      // 同时拿到目标容器的 libraryId，用来同步 book.libraryId：
      //   - 有目标容器：同步到容器所在书库
      //   - 未归位（none）：libraryId 置 null（没容器就没书库归属）
      const targetLibraryId = await validateLocation(tx, toType, targetId);

      const updateData = {
        locationType: toType,
        locationId: targetId,
        libraryId: toType === 'none' ? null : (targetLibraryId ?? null),
      };
      await tx.book.update({
        where: { id },
        data: updateData,
      });

      // 更新旧容器 book_count
      if (book.locationType !== 'none' && book.locationId) {
        await updateContainerCount(tx, book.locationType, book.locationId);
      }
      // 更新新容器 book_count
      if (toType !== 'none' && targetId) {
        await updateContainerCount(tx, toType, targetId);
      }

      // 写入日志
      await tx.bookLog.create({
        data: {
          bookId: id,
          action: 'move',
          fromType: book.locationType,
          fromId: book.locationId,
          toType,
          toId: targetId,
          method,
          rawInput,
        },
      });
    }, { isolationLevel: 'Serializable' });

    res.json({ message: '书籍已移动' });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    if (handleTxConflict(res, err)) return;
    next(err);
  }
});

// 获取单本书的操作历史
router.get('/:id/logs', async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '书籍 ID');
    const { page, pageSize, skip, take } = parsePagination(req.query);

    const [logs, total] = await Promise.all([
      prisma.bookLog.findMany({
        where: { bookId: id },
        skip,
        take,
        orderBy: { createdAt: 'desc' },
      }),
      prisma.bookLog.count({ where: { bookId: id } }),
    ]);

    res.json({
      data: logs,
      pagination: paginationResponse(page, pageSize, total),
    });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    next(err);
  }
});

export default router;
