// 书籍位置相关的共享业务逻辑：
// - 位置类型校验
// - 事务内校验目标容器存在
// - 重算并写入容器 bookCount
// - 批量拉取位置详情（消除「取一本书再取其容器」的 1+1 模式）
// - Prisma 事务冲突识别（供路由层把 Serializable 冲突转成 409）

export const VALID_LOCATION_TYPES = ['none', 'shelf', 'box'];

export function validateLocationType(value) {
  if (value && !VALID_LOCATION_TYPES.includes(value)) {
    const err = new Error(`无效的位置类型: ${value}，合法值为 none/shelf/box`);
    err.statusCode = 400;
    throw err;
  }
}

// 校验目标容器存在，并返回其 libraryId（用于把书跨库搬动时同步 libraryId）
// 返回 null 表示无归属库（容器没设 libraryId）或 locationType 为 none
// 必须传入事务客户端 tx，避免「校验后但写入前目标被删」的 TOCTOU 窗口
export async function validateLocation(tx, locationType, locationId) {
  if (!locationType || locationType === 'none' || !locationId) return null;
  validateLocationType(locationType);
  if (locationType === 'shelf') {
    const shelf = await tx.shelf.findUnique({ where: { id: locationId } });
    if (!shelf) {
      const err = new Error('目标书架不存在');
      err.statusCode = 404;
      throw err;
    }
    return shelf.libraryId ?? null;
  }
  if (locationType === 'box') {
    const box = await tx.box.findUnique({ where: { id: locationId } });
    if (!box) {
      const err = new Error('目标箱子不存在');
      err.statusCode = 404;
      throw err;
    }
    return box.libraryId ?? null;
  }
  return null;
}

// 重新 COUNT 指定容器的书数并写回（排除回收站里的书）
export async function updateContainerCount(tx, type, id) {
  if (!type || !id || type === 'none') return;
  const count = await tx.book.count({
    where: { locationType: type, locationId: id, deletedAt: null },
  });
  if (type === 'shelf') {
    await tx.shelf.update({ where: { id }, data: { bookCount: count } });
  } else if (type === 'box') {
    await tx.box.update({ where: { id }, data: { bookCount: count } });
  }
}

// 批量拉取位置详情。避免「取一批书后再逐条查 shelf/box」的 N+1。
// 入参：prisma 客户端；书数组（至少含 locationType/locationId）。
// 返回：Map 键为 "shelf:12" / "box:34"；值为 shelf/box 记录。
export async function batchResolveLocationInfo(client, books) {
  const shelfIds = new Set();
  const boxIds = new Set();
  for (const b of books) {
    if (!b?.locationId) continue;
    if (b.locationType === 'shelf') shelfIds.add(b.locationId);
    else if (b.locationType === 'box') boxIds.add(b.locationId);
  }

  const [shelves, boxes] = await Promise.all([
    shelfIds.size
      ? client.shelf.findMany({ where: { id: { in: [...shelfIds] } } })
      : Promise.resolve([]),
    boxIds.size
      ? client.box.findMany({ where: { id: { in: [...boxIds] } } })
      : Promise.resolve([]),
  ]);

  const map = new Map();
  for (const s of shelves) map.set(`shelf:${s.id}`, s);
  for (const b of boxes) map.set(`box:${b.id}`, b);
  return map;
}

// Prisma Serializable 隔离下并发写入会产生事务冲突（P2034），
// MySQL 死锁（1213）同样被 Prisma 包装为 P2034。
// 路由层捕获后返回 409 告诉客户端"请重试"，比 500 清晰。
export function isTxConflict(err) {
  if (!err) return false;
  if (err.code === 'P2034') return true;
  // 兜底：消息包含 deadlock / write conflict 关键词
  const msg = (err.message || '').toLowerCase();
  return msg.includes('write conflict') || msg.includes('deadlock');
}

// 在路由 catch 里快速处理事务冲突：命中则返回 409 并 true；否则 false 让调用方继续。
export function handleTxConflict(res, err) {
  if (!isTxConflict(err)) return false;
  res.status(409).json({
    error: '操作冲突，请刷新后重试',
    code: 'TX_CONFLICT',
  });
  return true;
}
