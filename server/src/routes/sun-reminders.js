import express from 'express';
import { PrismaClient } from '@prisma/client';
import { authenticate, checkLibraryAccess } from '../middleware/auth.js';

const router = express.Router();
const prisma = new PrismaClient();

// 获取用户的所有晒书提醒
router.get('/', authenticate, async (req, res, next) => {
  try {
    const reminders = await prisma.sunReminder.findMany({
      where: { userId: req.user.id },
      orderBy: { nextSunAt: 'asc' }
    });

    res.json({ reminders });
  } catch (error) {
    next(error);
  }
});

// 为书库创建晒书提醒
router.post('/library/:libraryId', authenticate, checkLibraryAccess('member'), async (req, res, next) => {
  try {
    const libraryId = parseInt(req.params.libraryId);
    const { sunDays } = req.body;

    const library = await prisma.library.findUnique({
      where: { id: libraryId },
      select: { name: true, sunDays: true }
    });

    if (!library) {
      return res.status(404).json({ error: '书库不存在' });
    }

    const effectiveSunDays = sunDays || library.sunDays || req.user.defaultSunDays;
    const nextSunAt = new Date();
    nextSunAt.setDate(nextSunAt.getDate() + effectiveSunDays);

    const existing = await prisma.sunReminder.findFirst({
      where: {
        userId: req.user.id,
        targetType: 'library',
        targetId: libraryId
      }
    });

    if (existing) {
      return res.status(400).json({ error: '该书库已有晒书提醒' });
    }

    const reminder = await prisma.sunReminder.create({
      data: {
        userId: req.user.id,
        targetType: 'library',
        targetId: libraryId,
        targetName: library.name,
        nextSunAt,
        sunDays: effectiveSunDays
      }
    });

    res.json({ reminder });
  } catch (error) {
    next(error);
  }
});

// 为箱子创建晒书提醒
router.post('/box/:boxId', authenticate, async (req, res, next) => {
  try {
    const boxId = parseInt(req.params.boxId);
    const { sunDays } = req.body;

    const box = await prisma.box.findUnique({
      where: { id: boxId },
      include: {
        library: {
          select: { id: true, sunDays: true }
        }
      }
    });

    if (!box) {
      return res.status(404).json({ error: '箱子不存在' });
    }

    const membership = await prisma.libraryMember.findUnique({
      where: {
        userId_libraryId: {
          userId: req.user.id,
          libraryId: box.libraryId
        }
      }
    });

    if (!membership) {
      return res.status(403).json({ error: '无权访问此箱子' });
    }

    const effectiveSunDays = sunDays || box.sunDays || box.library?.sunDays || req.user.defaultSunDays;
    const nextSunAt = new Date();
    nextSunAt.setDate(nextSunAt.getDate() + effectiveSunDays);

    const existing = await prisma.sunReminder.findFirst({
      where: {
        userId: req.user.id,
        targetType: 'box',
        targetId: boxId
      }
    });

    if (existing) {
      return res.status(400).json({ error: '该箱子已有晒书提醒' });
    }

    const reminder = await prisma.sunReminder.create({
      data: {
        userId: req.user.id,
        targetType: 'box',
        targetId: boxId,
        targetName: box.name,
        nextSunAt,
        sunDays: effectiveSunDays
      }
    });

    res.json({ reminder });
  } catch (error) {
    next(error);
  }
});

// 更新晒书提醒
router.patch('/:id', authenticate, async (req, res, next) => {
  try {
    const id = parseInt(req.params.id);
    const { sunDays } = req.body;

    const reminder = await prisma.sunReminder.findUnique({
      where: { id }
    });

    if (!reminder) {
      return res.status(404).json({ error: '提醒不存在' });
    }

    if (reminder.userId !== req.user.id) {
      return res.status(403).json({ error: '无权修改此提醒' });
    }

    if (sunDays !== undefined && sunDays < 1) {
      return res.status(400).json({ error: '晒书间隔至少 1 天' });
    }

    const updateData = {};
    if (sunDays !== undefined) {
      updateData.sunDays = sunDays;
      const nextSunAt = new Date(reminder.lastSunAt || reminder.createdAt);
      nextSunAt.setDate(nextSunAt.getDate() + sunDays);
      updateData.nextSunAt = nextSunAt;
      updateData.notified = false;
    }

    const updated = await prisma.sunReminder.update({
      where: { id },
      data: updateData
    });

    res.json({ reminder: updated });
  } catch (error) {
    next(error);
  }
});

// 标记已晒书
router.post('/:id/mark-sunned', authenticate, async (req, res, next) => {
  try {
    const id = parseInt(req.params.id);

    const reminder = await prisma.sunReminder.findUnique({
      where: { id }
    });

    if (!reminder) {
      return res.status(404).json({ error: '提醒不存在' });
    }

    if (reminder.userId !== req.user.id) {
      return res.status(403).json({ error: '无权操作此提醒' });
    }

    const now = new Date();
    const nextSunAt = new Date(now);
    nextSunAt.setDate(nextSunAt.getDate() + reminder.sunDays);

    const updated = await prisma.sunReminder.update({
      where: { id },
      data: {
        lastSunAt: now,
        nextSunAt,
        notified: false
      }
    });

    res.json({ reminder: updated });
  } catch (error) {
    next(error);
  }
});

// 删除晒书提醒
router.delete('/:id', authenticate, async (req, res, next) => {
  try {
    const id = parseInt(req.params.id);

    const reminder = await prisma.sunReminder.findUnique({
      where: { id }
    });

    if (!reminder) {
      return res.status(404).json({ error: '提醒不存在' });
    }

    if (reminder.userId !== req.user.id) {
      return res.status(403).json({ error: '无权删除此提醒' });
    }

    await prisma.sunReminder.delete({
      where: { id }
    });

    res.json({ message: '提醒已删除' });
  } catch (error) {
    next(error);
  }
});

export default router;
