import jwt from 'jsonwebtoken';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();
const JWT_SECRET = process.env.JWT_SECRET || 'bookbox-secret-change-in-production';

// 生成 JWT token
export function generateToken(userId) {
  return jwt.sign({ userId }, JWT_SECRET, { expiresIn: '30d' });
}

// 验证 JWT token 中间件
export async function authenticate(req, res, next) {
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

// 检查书库权限中间件（需要先执行 authenticate）
export async function checkLibraryAccess(requiredRole = 'member') {
  const roleHierarchy = { owner: 3, admin: 2, member: 1 };

  return async (req, res, next) => {
    try {
      const libraryId = parseInt(req.params.libraryId || req.body.libraryId);
      if (!libraryId) {
        return res.status(400).json({ error: '缺少书库 ID' });
      }

      const membership = await prisma.libraryMember.findUnique({
        where: {
          userId_libraryId: {
            userId: req.user.id,
            libraryId
          }
        }
      });

      if (!membership) {
        return res.status(403).json({ error: '无权访问此书库' });
      }

      if (roleHierarchy[membership.role] < roleHierarchy[requiredRole]) {
        return res.status(403).json({ error: `需要 ${requiredRole} 权限` });
      }

      req.libraryMembership = membership;
      next();
    } catch (error) {
      next(error);
    }
  };
}
