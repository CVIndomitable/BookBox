import { Router } from 'express';
import prisma from '../utils/prisma.js';
import { parseId, parseOptionalId } from '../utils/validate.js';

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
        parentId: parseOptionalId(parentId),
      },
    });

    res.status(201).json(category);
  } catch (err) {
    next(err);
  }
});

// 分类层级最大深度上限，防止异常数据导致过度递归
const MAX_CATEGORY_DEPTH = 50;

// 检测分类循环引用（A→B→C→A）
async function hasCycle(targetId, newParentId) {
  let current = newParentId;
  const visited = new Set();
  let depth = 0;
  while (current) {
    if (current === targetId) return true;
    if (visited.has(current)) return false; // 已有环，但不涉及 targetId
    if (depth >= MAX_CATEGORY_DEPTH) {
      // 超过合理深度视为可疑结构，拒绝本次操作
      const err = new Error(`分类层级超过上限 ${MAX_CATEGORY_DEPTH}，请检查数据`);
      err.statusCode = 400;
      throw err;
    }
    visited.add(current);
    depth++;
    const cat = await prisma.category.findUnique({ where: { id: current }, select: { parentId: true } });
    current = cat?.parentId;
  }
  return false;
}

// 更新分类
router.put('/:id', async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '分类 ID');
    const { name, parentId } = req.body;

    // 防止将分类设为自己的子分类（直接 + 间接循环）
    const parsedParentId = parseOptionalId(parentId);
    if (parsedParentId && parsedParentId === id) {
      return res.status(400).json({ error: '分类不能设为自己的子分类' });
    }
    if (parsedParentId && await hasCycle(id, parsedParentId)) {
      return res.status(400).json({ error: '不能设为子分类的子分类（会产生循环引用）' });
    }

    const data = {};
    if (name !== undefined) data.name = name;
    if (parentId !== undefined) data.parentId = parsedParentId;

    const category = await prisma.category.update({
      where: { id },
      data,
    });

    res.json(category);
  } catch (err) {
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    if (err.code === 'P2025') {
      return res.status(404).json({ error: '分类不存在' });
    }
    next(err);
  }
});

// 删除分类（子分类的 parentId 会被设为 null，书籍的 categoryId 也会被设为 null）
router.delete('/:id', async (req, res, next) => {
  try {
    const id = parseId(req.params.id, '分类 ID');

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
    if (err.statusCode) return res.status(err.statusCode).json({ error: err.message });
    if (err.code === 'P2025') {
      return res.status(404).json({ error: '分类不存在' });
    }
    next(err);
  }
});

export default router;
