// 解析并校验 ID 参数，返回正整数或抛出 400 错误
export function parseId(value, label = 'ID') {
  const id = parseInt(value, 10);
  if (isNaN(id) || id <= 0) {
    const err = new Error(`无效的${label}参数`);
    err.statusCode = 400;
    throw err;
  }
  return id;
}

// 解析可选的 ID 参数，返回正整数或 null
export function parseOptionalId(value) {
  if (value === undefined || value === null) return null;
  const id = parseInt(value, 10);
  if (isNaN(id) || id <= 0) return null;
  return id;
}

// 解析分页参数，返回安全的 page/pageSize/skip/take
export function parsePagination(query, defaultPageSize = 20) {
  const page = Math.max(1, parseInt(query.page, 10) || 1);
  const pageSize = Math.min(100, Math.max(1, parseInt(query.pageSize, 10) || defaultPageSize));
  const skip = (page - 1) * pageSize;
  return { page, pageSize, skip, take: pageSize };
}

// 构建分页响应
export function paginationResponse(page, pageSize, total) {
  return {
    page,
    pageSize,
    total,
    totalPages: Math.ceil(total / pageSize),
  };
}

// 根据 roomId 或 libraryId 解析书架/箱子的归属（libraryId, roomId）
// 规则：
//  - roomId 给出时，以房间所属书库为准（忽略传入的 libraryId）
//  - 只给 libraryId 时，自动选该书库的默认房间；若无默认房间则 roomId = null
//  - 都不给则视为"无归属"（libraryId: null, roomId: null）
// 抛出 statusCode=400/404 错误时需在路由层捕获
export async function resolveContainerPlacement(prisma, { libraryId, roomId }) {
  const out = { libraryId: null, roomId: null };

  if (roomId !== undefined && roomId !== null && roomId !== '') {
    const rid = parseInt(roomId, 10);
    if (isNaN(rid) || rid <= 0) {
      const err = new Error('无效的房间 ID 参数');
      err.statusCode = 400;
      throw err;
    }
    const room = await prisma.room.findUnique({
      where: { id: rid },
      select: { id: true, libraryId: true },
    });
    if (!room) {
      const err = new Error('房间不存在');
      err.statusCode = 404;
      throw err;
    }
    out.roomId = room.id;
    out.libraryId = room.libraryId;
    return out;
  }

  if (libraryId !== undefined && libraryId !== null && libraryId !== '') {
    const lid = parseInt(libraryId, 10);
    if (isNaN(lid) || lid <= 0) {
      const err = new Error('无效的书库 ID 参数');
      err.statusCode = 400;
      throw err;
    }
    const lib = await prisma.library.findUnique({ where: { id: lid }, select: { id: true } });
    if (!lib) {
      const err = new Error('书库不存在');
      err.statusCode = 404;
      throw err;
    }
    out.libraryId = lib.id;
    const defaultRoom = await prisma.room.findFirst({
      where: { libraryId: lid, isDefault: true },
      select: { id: true },
    });
    out.roomId = defaultRoom?.id ?? null;
  }

  return out;
}
