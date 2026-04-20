import express from 'express';
import bcrypt from 'bcrypt';
import { PrismaClient } from '@prisma/client';
import { generateToken, authenticate } from '../middleware/auth.js';

const router = express.Router();
const prisma = new PrismaClient();

// 注册
router.post('/register', async (req, res, next) => {
  try {
    const { username, email, password, displayName } = req.body;

    if (!username || !password) {
      return res.status(400).json({ error: '用户名和密码不能为空' });
    }

    if (password.length < 6) {
      return res.status(400).json({ error: '密码至少 6 位' });
    }

    const existing = await prisma.user.findFirst({
      where: {
        OR: [
          { username },
          ...(email ? [{ email }] : [])
        ]
      }
    });

    if (existing) {
      return res.status(400).json({ error: '用户名或邮箱已存在' });
    }

    const passwordHash = await bcrypt.hash(password, 10);
    const user = await prisma.user.create({
      data: {
        username,
        email: email || null,
        passwordHash,
        displayName: displayName || username
      },
      select: {
        id: true,
        username: true,
        email: true,
        displayName: true,
        defaultSunDays: true,
        createdAt: true
      }
    });

    const token = generateToken(user.id);
    res.json({ user, token });
  } catch (error) {
    next(error);
  }
});

// 登录
router.post('/login', async (req, res, next) => {
  try {
    const { username, password } = req.body;

    if (!username || !password) {
      return res.status(400).json({ error: '用户名和密码不能为空' });
    }

    const user = await prisma.user.findUnique({
      where: { username }
    });

    if (!user) {
      return res.status(401).json({ error: '用户名或密码错误' });
    }

    const valid = await bcrypt.compare(password, user.passwordHash);
    if (!valid) {
      return res.status(401).json({ error: '用户名或密码错误' });
    }

    const token = generateToken(user.id);
    res.json({
      user: {
        id: user.id,
        username: user.username,
        email: user.email,
        displayName: user.displayName,
        defaultSunDays: user.defaultSunDays,
        createdAt: user.createdAt
      },
      token
    });
  } catch (error) {
    next(error);
  }
});

// 获取当前用户信息
router.get('/me', authenticate, async (req, res) => {
  res.json({ user: req.user });
});

// 更新用户信息
router.patch('/me', authenticate, async (req, res, next) => {
  try {
    const { displayName, email, defaultSunDays, apnsToken } = req.body;
    const updateData = {};

    if (displayName !== undefined) updateData.displayName = displayName;
    if (email !== undefined) updateData.email = email || null;
    if (defaultSunDays !== undefined) {
      if (defaultSunDays < 1) {
        return res.status(400).json({ error: '晒书间隔至少 1 天' });
      }
      updateData.defaultSunDays = defaultSunDays;
    }
    if (apnsToken !== undefined) updateData.apnsToken = apnsToken;

    const user = await prisma.user.update({
      where: { id: req.user.id },
      data: updateData,
      select: {
        id: true,
        username: true,
        email: true,
        displayName: true,
        defaultSunDays: true,
        updatedAt: true
      }
    });

    res.json({ user });
  } catch (error) {
    next(error);
  }
});

// 修改密码
router.post('/change-password', authenticate, async (req, res, next) => {
  try {
    const { oldPassword, newPassword } = req.body;

    if (!oldPassword || !newPassword) {
      return res.status(400).json({ error: '旧密码和新密码不能为空' });
    }

    if (newPassword.length < 6) {
      return res.status(400).json({ error: '新密码至少 6 位' });
    }

    const user = await prisma.user.findUnique({
      where: { id: req.user.id }
    });

    const valid = await bcrypt.compare(oldPassword, user.passwordHash);
    if (!valid) {
      return res.status(401).json({ error: '旧密码错误' });
    }

    const passwordHash = await bcrypt.hash(newPassword, 10);
    await prisma.user.update({
      where: { id: req.user.id },
      data: { passwordHash }
    });

    res.json({ message: '密码修改成功' });
  } catch (error) {
    next(error);
  }
});

export default router;
