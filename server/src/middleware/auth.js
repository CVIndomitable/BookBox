import jwt from 'jsonwebtoken';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();
const JWT_SECRET = process.env.JWT_SECRET;
if (!JWT_SECRET) {
  console.error('❌ 致命错误：JWT_SECRET 未配置（.env 加一条 JWT_SECRET=<64 位随机字符串>）');
  console.error('   生成方式：node -e "console.log(require(\'crypto\').randomBytes(32).toString(\'hex\'))"');
  process.exit(1);
}

// 生成 JWT token
export function generateToken(userId) {
  return jwt.sign({ userId }, JWT_SECRET, { expiresIn: '30d' });
}

// 验证 JWT token 中间件（幂等：若已认证则直接放行）
export async function authenticate(req, res, next) {
  if (req.user) return next();
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith('Bearer ')) {
      return res.status(401).json({ error: '未提供认证令牌' });
    }

    const token = authHeader.substring(7);
    const decoded = jwt.verify(token, JWT_SECRET);

    const user = await prisma.user.findUnique({
      where: { id: decoded.userId },
      select: { id: true, username: true, email: true, displayName: true, defaultSunDays: true }
    });

    if (!user) {
      return res.status(401).json({ error: '用户不存在' });
    }

    req.user = user;
    next();
  } catch (error) {
    if (error.name === 'JsonWebTokenError') {
      return res.status(401).json({ error: '无效的令牌' });
    }
    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({ error: '令牌已过期' });
    }
    next(error);
  }
}

// 兼容旧 index.js 的全局 API 认证挂载点
export { authenticate as authMiddleware };

// 检查书库权限中间件（需要先执行 authenticate）
// 以前这里误写成 async 返回 Promise，导致 Express 收到 Promise 而非函数——等于没挂
const ROLE_HIERARCHY = { owner: 3, admin: 2, member: 1 };

export function checkLibraryAccess(requiredRole = 'member') {
  return async (req, res, next) => {
    try {
      // libraryId 来源优先级：路径参数 > 查询参数 > body
      const rawId = req.params.libraryId ?? req.query.libraryId ?? req.body?.libraryId;
      const libraryId = parseInt(rawId, 10);
      if (!Number.isInteger(libraryId) || libraryId <= 0) {
        return res.status(400).json({ error: '缺少书库 ID' });
      }

      const membership = await prisma.libraryMember.findUnique({
        where: {
          userId_libraryId: {
            userId: req.user.id,
            libraryId,
          },
        },
      });

      if (!membership) {
        return res.status(403).json({ error: '无权访问此书库' });
      }

      if (ROLE_HIERARCHY[membership.role] < ROLE_HIERARCHY[requiredRole]) {
        return res.status(403).json({ error: `需要 ${requiredRole} 权限` });
      }

      req.libraryMembership = membership;
      req.libraryId = libraryId;
      next();
    } catch (error) {
      next(error);
    }
  };
}

// 通过容器（shelf/box/room）路径参数 id 反查 libraryId 再做权限校验的中间件工厂
// 用于 /rooms/:id、/shelves/:id、/boxes/:id 等
export function checkContainerAccess(containerKind, requiredRole = 'member') {
  const modelMap = { room: 'room', shelf: 'shelf', box: 'box' };
  const model = modelMap[containerKind];
  if (!model) throw new Error(`未知容器类型：${containerKind}`);

  return async (req, res, next) => {
    try {
      const id = parseInt(req.params.id, 10);
      if (!Number.isInteger(id) || id <= 0) {
        return res.status(400).json({ error: `缺少 ${containerKind} ID` });
      }
      const row = await prisma[model].findUnique({
        where: { id },
        select: { libraryId: true },
      });
      if (!row) {
        return res.status(404).json({ error: `${containerKind} 不存在` });
      }
      const membership = await prisma.libraryMember.findUnique({
        where: {
          userId_libraryId: { userId: req.user.id, libraryId: row.libraryId },
        },
      });
      if (!membership) {
        return res.status(403).json({ error: '无权访问此书库' });
      }
      if (ROLE_HIERARCHY[membership.role] < ROLE_HIERARCHY[requiredRole]) {
        return res.status(403).json({ error: `需要 ${requiredRole} 权限` });
      }
      req.libraryMembership = membership;
      req.libraryId = row.libraryId;
      next();
    } catch (error) {
      next(error);
    }
  };
}

// 通过书 ID 反查 libraryId 再做权限校验
export function checkBookAccess(requiredRole = 'member') {
  return async (req, res, next) => {
    try {
      const id = parseInt(req.params.id, 10);
      if (!Number.isInteger(id) || id <= 0) {
        return res.status(400).json({ error: '缺少书籍 ID' });
      }
      const book = await prisma.book.findUnique({
        where: { id },
        select: { libraryId: true },
      });
      if (!book) {
        return res.status(404).json({ error: '书籍不存在' });
      }
      const membership = await prisma.libraryMember.findUnique({
        where: {
          userId_libraryId: { userId: req.user.id, libraryId: book.libraryId },
        },
      });
      if (!membership) {
        return res.status(403).json({ error: '无权访问此书库' });
      }
      if (ROLE_HIERARCHY[membership.role] < ROLE_HIERARCHY[requiredRole]) {
        return res.status(403).json({ error: `需要 ${requiredRole} 权限` });
      }
      req.libraryMembership = membership;
      req.libraryId = book.libraryId;
      next();
    } catch (error) {
      next(error);
    }
  };
}
