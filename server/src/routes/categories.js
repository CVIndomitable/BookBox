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
    const { flat, type } = req.query;

    const where = {};
    if (type === 'user') {
      where.categoryType = 'user';
    } else if (type === 'statutory') {
      where.categoryType = 'statutory';
    }
    // type=all 或无 type 参数时不过滤

    const categories = await prisma.category.findMany({
      where,
      include: { _count: { select: { books: true } } },
      orderBy: { categoryType: 'asc' },
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

// 新增分类（仅允许创建用户分类）
router.post('/', async (req, res, next) => {
  try {
    const { name, parentId, categoryType } = req.body;

    if (!name) {
      return res.status(400).json({ error: '分类名称不能为空' });
    }

    // 禁止通过 API 创建法定分类
    if (categoryType === 'statutory') {
      return res.status(403).json({ error: '无法手动创建法定分类' });
    }

    const category = await prisma.category.create({
      data: {
        name,
        parentId: parseOptionalId(parentId),
        categoryType: 'user',
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

    // 法定分类禁止编辑
    const existing = await prisma.category.findUnique({ where: { id }, select: { categoryType: true } });
    if (!existing) {
      return res.status(404).json({ error: '分类不存在' });
    }
    if (existing.categoryType === 'statutory') {
      return res.status(403).json({ error: '法定分类不可编辑' });
    }

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

    // 法定分类禁止删除
    const existing = await prisma.category.findUnique({ where: { id }, select: { categoryType: true } });
    if (!existing) {
      return res.status(404).json({ error: '分类不存在' });
    }
    if (existing.categoryType === 'statutory') {
      return res.status(403).json({ error: '法定分类不可删除' });
    }

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
