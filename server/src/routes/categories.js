import { Router } from 'express';
import prisma from '../utils/prisma.js';

const router = Router();

// 递归构建分类树
function buildTree(categories, parentId = null) {
  return categories
    .filter((c) => c.parentId === parentId)
    .map((c) => ({
      ...c,
      children: buildTree(categories, c.id),
    }));
}

// 获取分类树
router.get('/', async (req, res, next) => {
  try {
    const { flat } = req.query;

    const categories = await prisma.category.findMany({
      include: { _count: { select: { books: true } } },
      orderBy: { id: 'asc' },
    });

    if (flat === 'true') {
      return res.json(categories);
    }

    const tree = buildTree(categories);
    res.json(tree);
  } catch (err) {
    next(err);
  }
});

// 新增分类
router.post('/', async (req, res, next) => {
  try {
    const { name, parentId } = req.body;

    if (!name) {
      return res.status(400).json({ error: '分类名称不能为空' });
    }

    const category = await prisma.category.create({
      data: {
        name,
        parentId: parentId ? parseInt(parentId, 10) : null,
      },
    });

    res.status(201).json(category);
  } catch (err) {
    next(err);
  }
});

// 更新分类
router.put('/:id', async (req, res, next) => {
  try {
    const id = parseInt(req.params.id, 10);
    const { name, parentId } = req.body;

    // 防止将分类设为自己的子分类
    if (parentId && parseInt(parentId, 10) === id) {
      return res.status(400).json({ error: '分类不能设为自己的子分类' });
    }

    const data = {};
    if (name !== undefined) data.name = name;
    if (parentId !== undefined)
      data.parentId = parentId ? parseInt(parentId, 10) : null;

    const category = await prisma.category.update({
      where: { id },
      data,
    });

    res.json(category);
  } catch (err) {
    if (err.code === 'P2025') {
      return res.status(404).json({ error: '分类不存在' });
    }
    next(err);
  }
});

// 删除分类（子分类的 parentId 会被设为 null，书籍的 categoryId 也会被设为 null）
router.delete('/:id', async (req, res, next) => {
  try {
    const id = parseInt(req.params.id, 10);

    await prisma.$transaction([
      // 子分类解除关联
      prisma.category.updateMany({
        where: { parentId: id },
        data: { parentId: null },
      }),
      // 书籍解除分类关联
      prisma.book.updateMany({
        where: { categoryId: id },
        data: { categoryId: null },
      }),
      // 删除分类
      prisma.category.delete({ where: { id } }),
    ]);

    res.json({ message: '分类已删除' });
  } catch (err) {
    if (err.code === 'P2025') {
      return res.status(404).json({ error: '分类不存在' });
    }
    next(err);
  }
});

export default router;
