import { Router } from 'express';
import prisma from '../utils/prisma.js';
import { parseId } from '../utils/validate.js';
import { handleTxConflict } from '../services/bookLocation.js';
import { authenticate, checkLibraryAccess, checkContainerAccess } from '../middleware/auth.js';

const router = Router();

// 获取房间列表（可选 libraryId：传了则返回该书库的房间，不传则返回用户所有书库的房间）
router.get('/', authenticate, async (req, res, next) => {
  try {
    const where = {};

    // 如果指定了 libraryId，校验权限并过滤
    if (req.query.libraryId) {
      const libraryId = parseId(req.query.libraryId, '书库 ID');
      const membership = await prisma.libraryMember.findUnique({
        where: { userId_libraryId: { userId: req.user.id, libraryId } },
      });
      if (!membership) {
        return res.status(403).json({ error: '无权访问此书库' });
      }
      where.libraryId = libraryId;
    } else {
      // 不传 libraryId：返回用户所有书库的房间
      const memberships = await prisma.libraryMember.findMany({
        where: { userId: req.user.id },
        select: { libraryId: true },
      });
      const libraryIds = memberships.map(m => m.libraryId);
      if (libraryIds.length === 0) {
        return res.json([]);
      }
      where.libraryId = { in: libraryIds };
    }

    const rooms = await prisma.room.findMany({
      where,
      orderBy: [{ isDefault: 'desc' }, { createdAt: 'asc' }],
    });
    res.json(rooms);
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    next(err);
  }
});

// 新建房间（必须是该书库 admin 或以上）
router.post('/', checkLibraryAccess('admin'), async (req, res, next) => {
  try {
    const { name, description, libraryId } = req.body;

    if (!name || !name.trim()) {
      return res.status(400).json({ error: '房间名称不能为空' });
    }
    const libId = parseId(libraryId, '书库 ID');

    // 校验书库存在
    const lib = await prisma.library.findUnique({ where: { id: libId }, select: { id: true } });
    if (!lib) {
      return res.status(404).json({ error: '书库不存在' });
    }

    const room = await prisma.room.create({
      data: { name: name.trim(), description: description ?? null, libraryId: libId },
    });

    res.status(201).json(room);
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    next(err);
  }
});

// 房间详情（附带其中的书架/箱子）
router.get('/:id', checkContainerAccess('room', 'member'), async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '房间 ID');

    const room = await prisma.room.findUnique({ where: { id } });
    if (!room) {
      return res.status(404).json({ error: '房间不存在' });
    }

    const [shelves, boxes] = await Promise.all([
      prisma.shelf.findMany({
        where: { roomId: id },
        select: { id: true, name: true, location: true, bookCount: true },
        orderBy: { createdAt: 'desc' },
      }),
      prisma.box.findMany({
        where: { roomId: id },
        select: { id: true, boxUid: true, name: true, bookCount: true },
        orderBy: { createdAt: 'desc' },
      }),
    ]);

    res.json({ ...room, shelves, boxes });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    next(err);
  }
});

// 更新房间（name/description；默认房间不允许改名为空）
router.put('/:id', checkContainerAccess('room', 'admin'), async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '房间 ID');
    const { name, description } = req.body;

    const data = {};
    if (name !== undefined) {
      if (!name.trim()) return res.status(400).json({ error: '房间名称不能为空' });
      data.name = name.trim();
    }
    if (description !== undefined) data.description = description;

    const room = await prisma.room.update({ where: { id }, data });
    res.json(room);
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    if (err.code === 'P2025') return res.status(404).json({ error: '房间不存在' });
    next(err);
  }
});

// 删除房间
// - 默认房间不允许删除
// - 若房间下还有书架/箱子，将其转移到同书库的默认房间
router.delete('/:id', checkContainerAccess('room', 'admin'), async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '房间 ID');

    const room = await prisma.room.findUnique({ where: { id } });
    if (!room) return res.status(404).json({ error: '房间不存在' });
    if (room.isDefault) {
      return res.status(400).json({ error: '默认房间不能删除' });
    }

    // 默认房间的查询放到事务内，避免「查到默认房间后、转移前被并发删除」
    // 导致 shelf/box 指向不存在的房间。Serializable 隔离保证读写可串行化。
    const movedToRoomId = await prisma.$transaction(async (tx) => {
      const defaultRoom = await tx.room.findFirst({
        where: { libraryId: room.libraryId, isDefault: true },
      });
      if (defaultRoom && defaultRoom.id !== id) {
        await tx.shelf.updateMany({
          where: { roomId: id },
          data: { roomId: defaultRoom.id },
        });
        await tx.box.updateMany({
          where: { roomId: id },
          data: { roomId: defaultRoom.id },
        });
      } else {
        // 兜底：没有默认房间（通常不该发生），置空
        await tx.shelf.updateMany({ where: { roomId: id }, data: { roomId: null } });
        await tx.box.updateMany({ where: { roomId: id }, data: { roomId: null } });
      }
      await tx.room.delete({ where: { id } });
      return defaultRoom?.id ?? null;
    }, { isolationLevel: 'Serializable' });

    res.json({ message: '房间已删除', movedToRoomId });
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    if (err.code === 'P2025') return res.status(404).json({ error: '房间不存在' });
    if (handleTxConflict(res, err)) return;
    next(err);
  }
});

export default router;
