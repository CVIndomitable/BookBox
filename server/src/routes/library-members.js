import express from 'express';
import { PrismaClient } from '@prisma/client';
import { authenticate, checkLibraryAccess } from '../middleware/auth.js';

const router = express.Router();
const prisma = new PrismaClient();

// 获取书库成员列表
router.get('/:libraryId/members', authenticate, checkLibraryAccess('member'), async (req, res, next) => {
  try {
    const libraryId = parseInt(req.params.libraryId);
    const members = await prisma.libraryMember.findMany({
      where: { libraryId },
      include: {
        user: {
          select: { id: true, username: true, displayName: true }
        }
      },
      orderBy: [
        { role: 'desc' },
        { createdAt: 'asc' }
      ]
    });

    res.json({ members });
  } catch (error) {
    next(error);
  }
});

// 添加成员（仅 owner 可邀请）
router.post('/:libraryId/members', authenticate, checkLibraryAccess('owner'), async (req, res, next) => {
  try {
    const libraryId = parseInt(req.params.libraryId);
    const { username, role = 'member' } = req.body;

    if (!username) {
      return res.status(400).json({ error: '缺少用户名' });
    }

    if (!['admin', 'member'].includes(role)) {
      return res.status(400).json({ error: '角色只能是 admin 或 member' });
    }

    const targetUser = await prisma.user.findUnique({
      where: { username }
    });

    if (!targetUser) {
      return res.status(404).json({ error: '用户不存在' });
    }

    const existing = await prisma.libraryMember.findUnique({
      where: {
        userId_libraryId: {
          userId: targetUser.id,
          libraryId
        }
      }
    });

    if (existing) {
      return res.status(400).json({ error: '该用户已是书库成员' });
    }

    const member = await prisma.libraryMember.create({
      data: {
        userId: targetUser.id,
        libraryId,
        role
      },
      include: {
        user: {
          select: { id: true, username: true, displayName: true }
        }
      }
    });

    res.json({ member });
  } catch (error) {
    next(error);
  }
});

// 更新成员角色
router.patch('/:libraryId/members/:userId', authenticate, checkLibraryAccess('owner'), async (req, res, next) => {
  try {
    const libraryId = parseInt(req.params.libraryId);
    const userId = parseInt(req.params.userId);
    const { role } = req.body;

    if (!['admin', 'member'].includes(role)) {
      return res.status(400).json({ error: '角色只能是 admin 或 member' });
    }

    const targetMember = await prisma.libraryMember.findUnique({
      where: {
        userId_libraryId: { userId, libraryId }
      }
    });

    if (!targetMember) {
      return res.status(404).json({ error: '成员不存在' });
    }

    if (targetMember.role === 'owner') {
      return res.status(400).json({ error: '不能修改所有者角色，请使用转让功能' });
    }

    const member = await prisma.libraryMember.update({
      where: {
        userId_libraryId: { userId, libraryId }
      },
      data: { role },
      include: {
        user: {
          select: { id: true, username: true, displayName: true }
        }
      }
    });

    res.json({ member });
  } catch (error) {
    next(error);
  }
});

// 移除成员
router.delete('/:libraryId/members/:userId', authenticate, checkLibraryAccess('admin'), async (req, res, next) => {
  try {
    const libraryId = parseInt(req.params.libraryId);
    const userId = parseInt(req.params.userId);

    const targetMember = await prisma.libraryMember.findUnique({
      where: {
        userId_libraryId: { userId, libraryId }
      }
    });

    if (!targetMember) {
      return res.status(404).json({ error: '成员不存在' });
    }

    if (targetMember.role === 'owner') {
      return res.status(400).json({ error: '不能移除所有者，请先转让书库' });
    }

    if (req.libraryMembership.role === 'admin' && targetMember.role === 'admin') {
      return res.status(403).json({ error: '管理员不能移除其他管理员' });
    }

    await prisma.libraryMember.delete({
      where: {
        userId_libraryId: { userId, libraryId }
      }
    });

    res.json({ message: '成员已移除' });
  } catch (error) {
    next(error);
  }
});

// 转让书库
router.post('/:libraryId/transfer', authenticate, checkLibraryAccess('owner'), async (req, res, next) => {
  try {
    const libraryId = parseInt(req.params.libraryId);
    const { username } = req.body;

    if (!username) {
      return res.status(400).json({ error: '缺少目标用户名' });
    }

    const targetUser = await prisma.user.findUnique({
      where: { username }
    });

    if (!targetUser) {
      return res.status(404).json({ error: '目标用户不存在' });
    }

    const targetMember = await prisma.libraryMember.findUnique({
      where: {
        userId_libraryId: {
          userId: targetUser.id,
          libraryId
        }
      }
    });

    if (!targetMember) {
      return res.status(400).json({ error: '目标用户不是书库成员' });
    }

    await prisma.$transaction([
      prisma.libraryMember.update({
        where: {
          userId_libraryId: {
            userId: req.user.id,
            libraryId
          }
        },
        data: { role: 'admin' }
      }),
      prisma.libraryMember.update({
        where: {
          userId_libraryId: {
            userId: targetUser.id,
            libraryId
          }
        },
        data: { role: 'owner' }
      })
    ]);

    res.json({ message: '书库已转让' });
  } catch (error) {
    next(error);
  }
});

// 退出书库
router.post('/:libraryId/leave', authenticate, checkLibraryAccess('member'), async (req, res, next) => {
  try {
    const libraryId = parseInt(req.params.libraryId);

    if (req.libraryMembership.role === 'owner') {
      return res.status(400).json({ error: '所有者不能退出书库，请先转让' });
    }

    await prisma.libraryMember.delete({
      where: {
        userId_libraryId: {
          userId: req.user.id,
          libraryId
        }
      }
    });

    res.json({ message: '已退出书库' });
  } catch (error) {
    next(error);
  }
});

export default router;
