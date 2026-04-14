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
