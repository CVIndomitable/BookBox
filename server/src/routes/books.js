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
import { checkLibraryAccess, checkBookAccess } from '../middleware/auth.js';

const router = Router();

// 断言当前用户对目标 libraryId 至少是 member；供 batch / move 等多书操作内部使用
async function assertMemberWithClient(client, userId, libraryId, requiredRole = 'member') {
  const rank = { owner: 3, admin: 2, member: 1 };
  const m = await client.libraryMember.findUnique({
    where: { userId_libraryId: { userId, libraryId } },
  });
  if (!m) return { ok: false, status: 403, error: '无权访问此书库' };
  if (rank[m.role] < rank[requiredRole]) {
    return { ok: false, status: 403, error: `需要 ${requiredRole} 权限` };
  }
  return { ok: true };
}

async function assertMember(userId, libraryId, requiredRole = 'member') {
  return assertMemberWithClient(prisma, userId, libraryId, requiredRole);
}

function throwHttp(statusCode, message) {
  const err = new Error(message);
  err.statusCode = statusCode;
  throw err;
}

async function requireMemberWithClient(client, userId, libraryId, requiredRole = 'member') {
  if (!libraryId) {
    throwHttp(400, '目标位置未归属书库');
  }
  const membership = await assertMemberWithClient(client, userId, libraryId, requiredRole);
  if (!membership.ok) {
    throwHttp(membership.status, membership.error);
  }
}

async function validateLocationInLibrary(client, locationType, locationId, libraryId) {
  const containerLibraryId = await validateLocation(client, locationType, locationId);
  if (!containerLibraryId) {
    throwHttp(400, '目标位置未归属书库');
  }
  if (containerLibraryId !== libraryId) {
    throwHttp(403, '目标位置不属于当前书库');
  }
  return containerLibraryId;
}

// 合法的地区模式
const VALID_REGIONS = ['mainland', 'overseas'];


// 回收站保留天数：超过此天数的软删书籍会被 purgeExpiredTrash 物理删除
export const TRASH_RETENTION_DAYS = 30;

let _systemLibraryId = undefined;
async function getSystemLibraryId() {
  if (_systemLibraryId !== undefined) return _systemLibraryId;
  const sysLib = await prisma.library.findFirst({
    where: { libraryType: 'system' },
    select: { id: true },
  });
  _systemLibraryId = sysLib?.id ?? null;
  return _systemLibraryId;
}

// 将客户端可能传来的 "29.80元" / "¥29.8" 等形式标准化为 number 或 null，
// 非法值一律返回 null 而不是抛错——定价是弱字段，不应阻塞整个写入。
function parsePrice(raw) {
  if (raw === undefined || raw === null || raw === '') return null;
  if (typeof raw === 'number') {
    return Number.isFinite(raw) && raw >= 0 ? raw : null;
  }
  const m = String(raw).replace(/[¥￥$,\s元RMB]/gi, '');
  const n = Number(m);
  return Number.isFinite(n) && n >= 0 ? n : null;
}

function csvCell(value) {
  return `"${String(value ?? '').replace(/"/g, '""')}"`;
}

// 获取书籍列表（支持分页、搜索、按分类/状态/位置筛选）
router.get('/', checkLibraryAccess('member'), async (req, res, next) => {
  try {
    const { search, categoryId, verifyStatus, locationType, locationId, shelfId, boxId } = req.query;
    const { page, pageSize, skip, take } = parsePagination(req.query);

    // 回收站里的书不出现在任何正常列表中；强制按 libraryId 过滤避免跨库泄露
    // 不展示系统书库的书
    // 注：用 AND 数组组合所有条件，避免 Prisma 在 NOT + OR 同层时可能产生的意外交互
    const systemLibraryId = await getSystemLibraryId();
    const conditions = [{ libraryId: req.libraryId }];
    if (systemLibraryId) {
      conditions.push({ libraryId: { not: systemLibraryId } });
    }

    if (search) {
      conditions.push({
        OR: [
          { title: { contains: search } },
          { author: { contains: search } },
        ],
      });
    }

    const where = { deletedAt: null, AND: conditions };

    if (categoryId) {
      where.categoryId = parseId(categoryId, '分类 ID');
    }

    if (verifyStatus) {
      where.verifyStatus = verifyStatus;
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
router.post('/', checkLibraryAccess('member'), async (req, res, next) => {
  try {
    const {
      title, author, isbn, publisher, edition, price, coverUrl,
      categoryId, verifyStatus, verifySource, rawOcrText,
      locationType, locationId, cacheSourceBookId,
      adaptation, translator, authorNationality, publisherPerson,
      responsibleEditor, responsiblePrinting, coverDesign,
      phone, address, postalCode, printingHouse,
      impression, format, printedSheets, wordCount,
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
      if (finalLocationType !== 'none') {
        await validateLocationInLibrary(tx, finalLocationType, finalLocationId, req.libraryId);
      }

      const created = await tx.book.create({
        data: {
          title,
          author,
          isbn,
          publisher,
          edition: edition || null,
          price: parsePrice(price),
          coverUrl,
          categoryId: parseOptionalId(categoryId),
          verifyStatus: verifyStatus || 'not_found',
          verifySource,
          rawOcrText,
          locationType: finalLocationType,
          locationId: finalLocationId,
          libraryId: req.libraryId,
          cacheSourceBookId: parseOptionalId(cacheSourceBookId),
          adaptation: adaptation || null,
          translator: translator || null,
          authorNationality: authorNationality || null,
          publisherPerson: publisherPerson || null,
          responsibleEditor: responsibleEditor || null,
          responsiblePrinting: responsiblePrinting || null,
          coverDesign: coverDesign || null,
          phone: phone || null,
          address: address || null,
          postalCode: postalCode || null,
          printingHouse: printingHouse || null,
          impression: impression || null,
          format: format || null,
          printedSheets: printedSheets || null,
          wordCount: wordCount || null,
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
// 规则：title 去首尾空白 + 小写后相等；请求未给 publisher 时只按书名匹配（AI 常漏出版社）
// 注意：只在当前用户有访问权的书库集合内查重，防止探测他人书籍
// 包含未归位书籍（libraryId 为 null）的查重，避免批量导入时产生重复
router.post('/check-duplicates', async (req, res, next) => {
  try {
    const { books } = req.body || {};
    if (!Array.isArray(books) || books.length === 0) {
      return res.status(400).json({ error: '请提供书籍列表' });
    }

    const memberships = await prisma.libraryMember.findMany({
      where: { userId: req.user.id },
      select: { libraryId: true },
    });
    const allowedLibraryIds = memberships.map((m) => m.libraryId);
    if (allowedLibraryIds.length === 0) {
      return res.json({ duplicates: [] });
    }

    const norm = (s) => (s ?? '').toString().trim().toLowerCase();

    const titles = Array.from(new Set(books.map((b) => norm(b?.title)).filter(Boolean)));
    if (titles.length === 0) {
      return res.json({ duplicates: [] });
    }

    // 一次性按候选书名的 OR 条件拉回来，再在内存里按精确规则匹配
    // 包含 libraryId 在允许列表中的书 + libraryId 为 null 的未归位书籍
    const where = {
      OR: titles.map((t) => ({ title: { equals: t } })),
      AND: [
        {
          OR: [
            { libraryId: { in: allowedLibraryIds } },
            { libraryId: null },
          ],
        },
      ],
    };

    // 回收站里的书不参与查重
    where.deletedAt = null;
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

    // 限定在当前用户参与的书库集合内
    const memberships = await prisma.libraryMember.findMany({
      where: { userId: req.user.id },
      select: { libraryId: true },
    });
    const allowedLibraryIds = memberships.map((m) => m.libraryId);
    if (allowedLibraryIds.length === 0) {
      return res.json({ groups: [], totalGroups: 0, totalDuplicateBooks: 0 });
    }

    // 一次性拉全量书（只取查重所需字段），按分组逻辑在内存里聚合
    // 注：当前场景量级不大；若将来几十万本可改用 SQL GROUP BY
    const all = await prisma.book.findMany({
      where: { deletedAt: null, libraryId: { in: allowedLibraryIds } },
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

// 回收站：列出软删书籍；未指定 libraryId 时仅列出当前用户参与书库中的条目
// 必须声明在 /:id 之前，避免被通配路由捕获
// 响应：{ data: [...books with locationInfo], retentionDays }
router.get('/trash', async (req, res, next) => {
  try {
    const rawLibraryId = req.query.libraryId;
    const libraryId = parseOptionalId(rawLibraryId);
    let libraryFilter;

    if (rawLibraryId !== undefined && rawLibraryId !== null && rawLibraryId !== '' && !libraryId) {
      return res.status(400).json({ error: 'libraryId 非法' });
    }

    if (libraryId) {
      const mm = await assertMember(req.user.id, libraryId, 'member');
      if (!mm.ok) return res.status(mm.status).json({ error: mm.error });
      libraryFilter = libraryId;
    } else {
      const memberships = await prisma.libraryMember.findMany({
        where: { userId: req.user.id },
        select: { libraryId: true },
      });
      libraryFilter = { in: memberships.map((m) => m.libraryId) };
    }

    const books = await prisma.book.findMany({
      where: { deletedAt: { not: null }, libraryId: libraryFilter },
      include: { category: true },
      orderBy: { deletedAt: 'desc' },
    });

    // 解析书原来所在的容器名（软删时 locationType/locationId 保留；用户还原时能看出回到哪里）
    const locMap = await batchResolveLocationInfo(prisma, books);
    const data = books.map((b) => ({
      ...b,
      locationInfo: b.locationId
        ? locMap.get(`${b.locationType}:${b.locationId}`) ?? null
        : null,
    }));

    res.json({ data, retentionDays: TRASH_RETENTION_DAYS });
  } catch (err) {
    next(err);
  }
});

// 回收站：还原一本书到原位（locationType/locationId 未动，只清 deletedAt）
// 如果原容器已被删了，只把书还原到「未归位」
router.post('/:id/restore', checkBookAccess('member'), async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '书籍 ID');
    const book = await prisma.book.findFirst({ where: { id, deletedAt: { not: null } } });
    if (!book) {
      return res.status(404).json({ error: '回收站中没有该书籍' });
    }

    await prisma.$transaction(async (tx) => {
      // 校验原容器是否还存在；不存在则把书挂到「未归位」
      let restoredLocationType = book.locationType;
      let restoredLocationId = book.locationId;
      let restoredLibraryId = book.libraryId;
      if (book.locationType !== 'none' && book.locationId) {
        try {
          const libId = await validateLocation(tx, book.locationType, book.locationId);
          restoredLibraryId = libId ?? restoredLibraryId ?? null;
        } catch (e) {
          if (e.statusCode === 404) {
            restoredLocationType = 'none';
            restoredLocationId = null;
            restoredLibraryId = book.libraryId;
          } else {
            throw e;
          }
        }
      }

      await tx.book.update({
        where: { id },
        data: {
          deletedAt: null,
          locationType: restoredLocationType,
          locationId: restoredLocationId,
          libraryId: restoredLibraryId,
        },
      });

      await tx.bookLog.create({
        data: {
          bookId: id,
          action: 'add',
          toType: restoredLocationType,
          toId: restoredLocationId,
          method: 'manual',
          note: `从回收站还原: ${book.title}${book.author ? ` / ${book.author}` : ''}`,
        },
      });

      if (restoredLocationType !== 'none' && restoredLocationId) {
        await updateContainerCount(tx, restoredLocationType, restoredLocationId);
      }
    }, { isolationLevel: 'Serializable' });

    res.json({ message: '已还原' });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    if (handleTxConflict(res, err)) return;
    next(err);
  }
});

// 回收站：立即彻底删除一本书（跳过 30 天等待）
router.delete('/:id/purge', checkBookAccess('admin'), async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '书籍 ID');
    const book = await prisma.book.findFirst({ where: { id, deletedAt: { not: null } } });
    if (!book) {
      return res.status(404).json({ error: '回收站中没有该书籍' });
    }

    // 物理删除。外键 onDelete:SetNull 会把日志里的 bookId 置空
    await prisma.book.delete({ where: { id } });
    res.json({ message: '已彻底删除' });
  } catch (err) {
    if (err.code === 'P2025') {
      return res.status(404).json({ error: '回收站中没有该书籍' });
    }
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

// 批量新增书籍（必须指定 libraryId 或由 location 推出）
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
    if (finalLocationType !== 'none' && !finalLocationId) {
      return res.status(400).json({ error: '指定位置类型时必须提供位置 ID' });
    }

    // 判定最终 libraryId：无位置时必须由 body.libraryId 指定；有位置时必须与容器归属一致
    let targetLibraryId = parseOptionalId(libraryId);
    if (!targetLibraryId) {
      if (finalLocationType !== 'none' && finalLocationId) {
        const model = finalLocationType === 'shelf' ? 'shelf' : finalLocationType === 'box' ? 'box' : null;
        if (model) {
          const row = await prisma[model].findUnique({ where: { id: finalLocationId }, select: { libraryId: true } });
          if (!row) return res.status(404).json({ error: '目标位置不存在' });
          if (!row.libraryId) return res.status(400).json({ error: '目标位置未归属书库' });
          targetLibraryId = row.libraryId;
        }
      }
    }
    if (!targetLibraryId) {
      return res.status(400).json({ error: '缺少书库 ID' });
    }
    const mm = await assertMember(req.user.id, targetLibraryId, 'member');
    if (!mm.ok) return res.status(mm.status).json({ error: mm.error });

    const skipped = [];
    const results = await prisma.$transaction(async (tx) => {
      // 事务内校验目标存在并属于最终书库，防止校验后、写入前目标被并发挪走
      if (finalLocationType !== 'none' && finalLocationId) {
        await validateLocationInLibrary(tx, finalLocationType, finalLocationId, targetLibraryId);
      }

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
            edition: bookData.edition || bookData.publishDate || null,
            price: parsePrice(bookData.price),
            coverUrl: bookData.coverUrl,
            categoryId: parseOptionalId(bookData.categoryId),
            verifyStatus: bookData.verifyStatus || 'not_found',
            verifySource: bookData.verifySource,
            rawOcrText: bookData.rawOcrText,
            locationType: finalLocationType,
            locationId: finalLocationId,
            libraryId: targetLibraryId,
            adaptation: bookData.adaptation || null,
            translator: bookData.translator || null,
            authorNationality: bookData.authorNationality || null,
            publisherPerson: bookData.publisherPerson || null,
            responsibleEditor: bookData.responsibleEditor || null,
            responsiblePrinting: bookData.responsiblePrinting || null,
            coverDesign: bookData.coverDesign || null,
            phone: bookData.phone || null,
            address: bookData.address || null,
            postalCode: bookData.postalCode || null,
            printingHouse: bookData.printingHouse || null,
            impression: bookData.impression || null,
            format: bookData.format || null,
            printedSheets: bookData.printedSheets || null,
            wordCount: bookData.wordCount || null,
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

// 导出书籍为 CSV（不含回收站；必须指定 libraryId）
// 必须声明在 /:id 之前，避免被通配路由捕获
router.get('/export', checkLibraryAccess('member'), async (req, res, next) => {
  try {
    const where = { deletedAt: null, libraryId: req.libraryId };

    const booksList = await prisma.book.findMany({
      where,
      orderBy: { createdAt: 'desc' }
    });

    const csv = [
      '书名,作者,改编,译者,作者国籍,ISBN,出版社,版次,出版人,责任编辑,责任印制,封面设计,电话,地址,邮编,印刷,印次,开本,印张,字数,定价,位置类型,位置ID',
      ...booksList.map((book) => [
        book.title,
        book.author,
        book.adaptation,
        book.translator,
        book.authorNationality,
        book.isbn,
        book.publisher,
        book.edition,
        book.publisherPerson,
        book.responsibleEditor,
        book.responsiblePrinting,
        book.coverDesign,
        book.phone,
        book.address,
        book.postalCode,
        book.printingHouse,
        book.impression,
        book.format,
        book.printedSheets,
        book.wordCount,
        book.price ?? '',
        book.locationType,
        book.locationId || '',
      ].map(csvCell).join(','))
    ].join('\n');

    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="books-${Date.now()}.csv"`);
    res.send('﻿' + csv); // BOM for Excel
  } catch (err) {
    next(err);
  }
});

// 在系统图书馆中搜索缓存书籍
router.get('/library-cache/search', async (req, res, next) => {
  try {
    const { title, author, isbn } = req.query;
    if (!title && !isbn) {
      return res.status(400).json({ error: '请提供书名或 ISBN' });
    }

    const systemLibraryId = await getSystemLibraryId();
    if (!systemLibraryId) {
      return res.json({ hits: [] });
    }

    const where = {
      deletedAt: null,
      libraryId: systemLibraryId,
    };
    const OR = [];
    if (title) {
      OR.push({ title: { contains: title } });
    }
    if (author) {
      OR.push({ author: { contains: author } });
    }
    if (isbn) {
      OR.push({ isbn: { equals: isbn } });
    }
    if (OR.length > 0) {
      where.OR = OR;
    }

    const hits = await prisma.book.findMany({
      where,
      take: 5,
      orderBy: { updatedAt: 'desc' },
    });

    res.json({ hits });
  } catch (err) {
    next(err);
  }
});

// 批量删除书籍
router.post('/batch-delete', checkLibraryAccess('member'), async (req, res, next) => {
  try {
    const { bookIds, returnToLibrary } = req.body;

    if (!Array.isArray(bookIds) || bookIds.length === 0) {
      return res.status(400).json({ error: '请提供书籍 ID 列表' });
    }

    const ids = bookIds.map((id, i) => {
      const parsed = parseId(id, `书籍 ID[${i}]`);
      return parsed;
    });

    const toLibrary = returnToLibrary === true;
    const errors = [];
    let processed = 0;

    if (toLibrary) {
      const systemLibraryId = await getSystemLibraryId();
      if (!systemLibraryId) {
        return res.status(500).json({ error: '系统图书馆未初始化' });
      }

      await prisma.$transaction(async (tx) => {
        for (const id of ids) {
          const book = await tx.book.findFirst({
            where: { id, deletedAt: null, libraryId: req.libraryId },
          });
          if (!book) {
            errors.push(`书籍 ${id} 不存在或无权操作`);
            continue;
          }

          await tx.bookLog.create({
            data: {
              bookId: id,
              action: 'move',
              fromType: book.locationType,
              fromId: book.locationId,
              toType: 'library',
              method: 'manual',
              note: `还给图书馆: ${book.title}${book.author ? ` / ${book.author}` : ''}`,
            },
          });

          await tx.book.update({
            where: { id },
            data: {
              libraryId: systemLibraryId,
              locationType: 'none',
              locationId: null,
            },
          });

          if (book.locationType !== 'none' && book.locationId) {
            await updateContainerCount(tx, book.locationType, book.locationId);
          }

          processed++;
        }
      }, { isolationLevel: 'Serializable' });
    } else {
      await prisma.$transaction(async (tx) => {
        for (const id of ids) {
          const book = await tx.book.findFirst({
            where: { id, deletedAt: null, libraryId: req.libraryId },
          });
          if (!book) {
            errors.push(`书籍 ${id} 不存在或无权操作`);
            continue;
          }

          await tx.bookLog.create({
            data: {
              bookId: id,
              action: 'remove',
              fromType: book.locationType,
              fromId: book.locationId,
              toType: 'none',
              method: 'manual',
              note: `移入回收站: ${book.title}${book.author ? ` / ${book.author}` : ''}`,
            },
          });

          await tx.book.update({
            where: { id },
            data: { deletedAt: new Date() },
          });

          if (book.locationType !== 'none' && book.locationId) {
            await updateContainerCount(tx, book.locationType, book.locationId);
          }

          processed++;
        }
      }, { isolationLevel: 'Serializable' });
    }

    res.json({ processed, errors });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    if (handleTxConflict(res, err)) return;
    next(err);
  }
});

// 批量移动书籍
router.post('/batch-move', checkLibraryAccess('member'), async (req, res, next) => {
  try {
    const { bookIds, toType, toId } = req.body;

    if (!Array.isArray(bookIds) || bookIds.length === 0) {
      return res.status(400).json({ error: '请提供书籍 ID 列表' });
    }
    validateLocationType(toType);
    const targetId = parseOptionalId(toId);
    if (toType !== 'none' && !targetId) {
      return res.status(400).json({ error: '指定位置类型时必须提供位置 ID' });
    }

    const ids = bookIds.map((id, i) => parseId(id, `书籍 ID[${i}]`));
    const errors = [];
    let processed = 0;

    await prisma.$transaction(async (tx) => {
      // 确定目标容器归属
      let targetLibraryId = req.libraryId;
      if (toType !== 'none') {
        const model = toType === 'shelf' ? 'shelf' : toType === 'box' ? 'box' : null;
        if (model) {
          const container = await tx[model].findUnique({
            where: { id: targetId },
            select: { libraryId: true },
          });
          if (!container) throwHttp(404, '目标位置不存在');
          targetLibraryId = container.libraryId || req.libraryId;
        }
      }

      for (const id of ids) {
        const book = await tx.book.findFirst({
          where: { id, deletedAt: null, libraryId: req.libraryId },
        });
        if (!book) {
          errors.push(`书籍 ${id} 不存在或无权操作`);
          continue;
        }

        await tx.bookLog.create({
          data: {
            bookId: id,
            action: 'move',
            fromType: book.locationType,
            fromId: book.locationId,
            toType,
            toId: targetId,
            method: 'manual',
          },
        });

        await tx.book.update({
          where: { id },
          data: {
            locationType: toType,
            locationId: targetId,
            libraryId: toType === 'none' ? book.libraryId : targetLibraryId,
          },
        });

        // 更新原容器 book_count
        if (book.locationType !== 'none' && book.locationId) {
          await updateContainerCount(tx, book.locationType, book.locationId);
        }

        processed++;
      }

      // 更新目标容器 book_count
      if (toType !== 'none' && targetId && processed > 0) {
        await updateContainerCount(tx, toType, targetId);
      }
    }, { isolationLevel: 'Serializable' });

    res.json({ processed, errors });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    if (handleTxConflict(res, err)) return;
    next(err);
  }
});

// 获取书籍详情
router.get('/:id', checkBookAccess('member'), async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '书籍 ID');
    const book = await prisma.book.findFirst({
      where: { id, deletedAt: null },
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
router.put('/:id', checkBookAccess('member'), async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '书籍 ID');
    const {
      title, author, isbn, publisher, edition, price, coverUrl,
      categoryId, verifyStatus, verifySource,
      locationType, locationId,
      adaptation, translator, authorNationality, publisherPerson,
      responsibleEditor, responsiblePrinting, coverDesign,
      phone, address, postalCode, printingHouse,
      impression, format, printedSheets, wordCount,
    } = req.body;

    const existingBook = await prisma.book.findFirst({ where: { id, deletedAt: null } });
    if (!existingBook) {
      return res.status(404).json({ error: '书籍不存在' });
    }

    const data = {};
    if (title !== undefined) data.title = title;
    if (author !== undefined) data.author = author;
    if (isbn !== undefined) data.isbn = isbn;
    if (publisher !== undefined) data.publisher = publisher;
    if (edition !== undefined) data.edition = edition || null;
    if (price !== undefined) data.price = parsePrice(price);
    if (coverUrl !== undefined) data.coverUrl = coverUrl;
    if (categoryId !== undefined)
      data.categoryId = categoryId ? parseId(categoryId, '分类 ID') : null;
    if (verifyStatus !== undefined) data.verifyStatus = verifyStatus;
    if (verifySource !== undefined) data.verifySource = verifySource;
    if (adaptation !== undefined) data.adaptation = adaptation || null;
    if (translator !== undefined) data.translator = translator || null;
    if (authorNationality !== undefined) data.authorNationality = authorNationality || null;
    if (publisherPerson !== undefined) data.publisherPerson = publisherPerson || null;
    if (responsibleEditor !== undefined) data.responsibleEditor = responsibleEditor || null;
    if (responsiblePrinting !== undefined) data.responsiblePrinting = responsiblePrinting || null;
    if (coverDesign !== undefined) data.coverDesign = coverDesign || null;
    if (phone !== undefined) data.phone = phone || null;
    if (address !== undefined) data.address = address || null;
    if (postalCode !== undefined) data.postalCode = postalCode || null;
    if (printingHouse !== undefined) data.printingHouse = printingHouse || null;
    if (impression !== undefined) data.impression = impression || null;
    if (format !== undefined) data.format = format || null;
    if (printedSheets !== undefined) data.printedSheets = printedSheets || null;
    if (wordCount !== undefined) data.wordCount = wordCount || null;

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
      //   - 未归位（none）：保留原书库归属
      if (isMoving) {
        if (data.locationType !== 'none' && data.locationId) {
          const targetLibraryId = await validateLocation(tx, data.locationType, data.locationId);
          await requireMemberWithClient(tx, req.user.id, targetLibraryId, 'member');
          data.libraryId = targetLibraryId;
        } else {
          data.libraryId = existingBook.libraryId;
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

// 删除书籍 — 软删进回收站（保留 locationType/locationId，还原时能回到原位）
// 30 天后由定时任务物理删除；容器 bookCount 立即重算（updateContainerCount 已过滤 deletedAt:null）
// 删除书籍：默认软删除（移入回收站），可选 returnToLibrary=true 归还到系统图书馆
router.delete('/:id', checkBookAccess('member'), async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '书籍 ID');
    const returnToLibrary = req.query.returnToLibrary === 'true';

    const book = await prisma.book.findFirst({ where: { id, deletedAt: null } });
    if (!book) {
      return res.status(404).json({ error: '书籍不存在' });
    }

    if (returnToLibrary) {
      const systemLibraryId = await getSystemLibraryId();
      if (!systemLibraryId) {
        return res.status(500).json({ error: '系统图书馆未初始化' });
      }

      await prisma.$transaction(async (tx) => {
        await tx.bookLog.create({
          data: {
            bookId: id,
            action: 'move',
            fromType: book.locationType,
            fromId: book.locationId,
            toType: 'library',
            method: 'manual',
            note: `还给图书馆: ${book.title}${book.author ? ` / ${book.author}` : ''}`,
          },
        });

        await tx.book.update({
          where: { id },
          data: {
            libraryId: systemLibraryId,
            locationType: 'none',
            locationId: null,
          },
        });

        // 更新原容器 book_count
        if (book.locationType !== 'none' && book.locationId) {
          await updateContainerCount(tx, book.locationType, book.locationId);
        }
      }, { isolationLevel: 'Serializable' });

      return res.json({ message: '已还给图书馆' });
    }

    // 原有软删除逻辑
    await prisma.$transaction(async (tx) => {
      await tx.bookLog.create({
        data: {
          bookId: id,
          action: 'remove',
          fromType: book.locationType,
          fromId: book.locationId,
          toType: 'none',
          method: 'manual',
          note: `移入回收站: ${book.title}${book.author ? ` / ${book.author}` : ''}`,
        },
      });

      await tx.book.update({
        where: { id },
        data: { deletedAt: new Date() },
      });

      if (book.locationType !== 'none' && book.locationId) {
        await updateContainerCount(tx, book.locationType, book.locationId);
      }
    }, { isolationLevel: 'Serializable' });

    res.json({ message: '已移入回收站' });
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
router.post('/:id/move', checkBookAccess('member'), async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '书籍 ID');
    const { toType, toId, method = 'manual', rawInput } = req.body;

    if (!toType) {
      return res.status(400).json({ error: '请指定目标位置类型' });
    }
    validateLocationType(toType);

    const book = await prisma.book.findFirst({ where: { id, deletedAt: null } });
    if (!book) {
      return res.status(404).json({ error: '书籍不存在' });
    }

    const targetId = parseOptionalId(toId);

    // 位置类型非 none 时必须提供 toId
    if (toType !== 'none' && !targetId) {
      return res.status(400).json({ error: '指定位置类型时必须提供位置 ID' });
    }

    // 跨书库搬动时需校验对目标书库的成员身份
    if (toType !== 'none' && targetId) {
      const model = toType === 'shelf' ? 'shelf' : toType === 'box' ? 'box' : null;
      if (model) {
        const container = await prisma[model].findUnique({ where: { id: targetId }, select: { libraryId: true } });
        if (container?.libraryId && container.libraryId !== req.libraryId) {
          const mm = await assertMember(req.user.id, container.libraryId, 'member');
          if (!mm.ok) return res.status(mm.status).json({ error: mm.error });
        }
      }
    }

    await prisma.$transaction(async (tx) => {
      // 事务内校验目标存在，防止校验后、写入前目标被删
      // 同时拿到目标容器的 libraryId，用来同步 book.libraryId：
      //   - 有目标容器：同步到容器所在书库
      //   - 未归位（none）：保留原书库归属
      const targetLibraryId = await validateLocation(tx, toType, targetId);
      if (toType !== 'none') {
        await requireMemberWithClient(tx, req.user.id, targetLibraryId, 'member');
      }

      const updateData = {
        locationType: toType,
        locationId: targetId,
        libraryId: toType === 'none' ? book.libraryId : targetLibraryId,
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
router.get('/:id/logs', checkBookAccess('member'), async (req, res, next) => {
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

// 批量导入书籍（支持可选的位置参数，与 /batch 接口行为对齐）
router.post('/batch-import', checkLibraryAccess('member'), async (req, res, next) => {
  try {
    const { books, locationType, locationId } = req.body;

    if (!Array.isArray(books) || books.length === 0) {
      return res.status(400).json({ error: '请提供书籍列表' });
    }

    // 支持可选的位置参数
    const finalLocationType = locationType || 'none';
    validateLocationType(finalLocationType);
    const finalLocationId = parseOptionalId(locationId);

    // 位置类型非 none 时必须提供 locationId
    if (finalLocationType !== 'none' && !finalLocationId) {
      return res.status(400).json({ error: '指定位置类型时必须提供位置 ID' });
    }

    const created = await prisma.$transaction(async (tx) => {
      // 如果指定了位置，事务内校验目标存在并属于当前书库
      if (finalLocationType !== 'none' && finalLocationId) {
        await validateLocationInLibrary(tx, finalLocationType, finalLocationId, req.libraryId);
      }

      const result = [];
      for (const bookData of books) {
        if (!bookData.title) continue;

        const book = await tx.book.create({
          data: {
            title: bookData.title,
            author: bookData.author || null,
            isbn: bookData.isbn || null,
            publisher: bookData.publisher || null,
            edition: bookData.edition || bookData.publishDate || null,
            price: parsePrice(bookData.price),
            libraryId: req.libraryId,
            locationType: finalLocationType,
            locationId: finalLocationId,
            verifyStatus: bookData.verifyStatus || 'manual',
            adaptation: bookData.adaptation || null,
            translator: bookData.translator || null,
            authorNationality: bookData.authorNationality || null,
            publisherPerson: bookData.publisherPerson || null,
            responsibleEditor: bookData.responsibleEditor || null,
            responsiblePrinting: bookData.responsiblePrinting || null,
            coverDesign: bookData.coverDesign || null,
            phone: bookData.phone || null,
            address: bookData.address || null,
            postalCode: bookData.postalCode || null,
            printingHouse: bookData.printingHouse || null,
            impression: bookData.impression || null,
            format: bookData.format || null,
            printedSheets: bookData.printedSheets || null,
            wordCount: bookData.wordCount || null,
          }
        });

        result.push(book);
      }

      // 更新容器 book_count
      if (finalLocationType !== 'none' && finalLocationId) {
        await updateContainerCount(tx, finalLocationType, finalLocationId);
      }

      return result;
    }, { isolationLevel: 'Serializable' });

    res.json({ count: created.length, books: created });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    if (handleTxConflict(res, err)) return;
    next(err);
  }
});

// 清理过期的回收站条目（超过 TRASH_RETENTION_DAYS 天的软删书籍）
// 物理删除即可：容器 bookCount 早在软删时已经重算过，不需要再动
export async function purgeExpiredTrash() {
  const cutoff = new Date(Date.now() - TRASH_RETENTION_DAYS * 24 * 60 * 60 * 1000);
  try {
    const result = await prisma.book.deleteMany({
      where: { deletedAt: { lt: cutoff } },
    });
    if (result.count > 0) {
      console.log(`[回收站] 清理 ${result.count} 本过期书籍（> ${TRASH_RETENTION_DAYS} 天）`);
    }
    return result.count;
  } catch (err) {
    console.error('[回收站] 清理失败:', err);
    return 0;
  }
}

// 启动回收站定时清理：启动时立即跑一次 + 每 24 小时一次
export function startTrashPurgeScheduler() {
  purgeExpiredTrash();
  setInterval(purgeExpiredTrash, 24 * 60 * 60 * 1000);
}

export default router;
