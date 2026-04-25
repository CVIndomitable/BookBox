import { Router } from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs/promises';
import { fileURLToPath } from 'url';
import prisma from '../utils/prisma.js';
import { parseId } from '../utils/validate.js';
import { checkBookAccess } from '../middleware/auth.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const router = Router();

const UPLOAD_DIR = path.join(__dirname, '../../uploads/covers');

await fs.mkdir(UPLOAD_DIR, { recursive: true });

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, UPLOAD_DIR);
  },
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname);
    const timestamp = Date.now();
    const random = Math.random().toString(36).substring(2, 8);
    cb(null, `cover_${timestamp}_${random}${ext}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const allowedTypes = ['image/jpeg', 'image/png', 'image/jpg', 'image/heic', 'image/heif'];
    if (allowedTypes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('只支持 JPG、PNG、HEIC 格式的图片'));
    }
  },
});

router.post('/:bookId', checkBookAccess('member'), upload.single('cover'), async (req, res, next) => {
  try {
    const bookId = parseId(req.params.bookId, '书籍 ID');

    if (!req.file) {
      return res.status(400).json({ error: '未上传文件' });
    }

    const coverUrl = `/uploads/covers/${req.file.filename}`;

    const book = await prisma.book.findUnique({
      where: { id: bookId },
      select: { coverUrl: true },
    });

    if (book?.coverUrl) {
      const oldPath = path.join(__dirname, '../..', book.coverUrl);
      try {
        await fs.unlink(oldPath);
      } catch (err) {
        console.warn(`删除旧封面失败: ${oldPath}`, err.message);
      }
    }

    const updated = await prisma.book.update({
      where: { id: bookId },
      data: { coverUrl },
      include: { category: true },
    });

    res.json(updated);
  } catch (err) {
    if (req.file) {
      try {
        await fs.unlink(req.file.path);
      } catch {}
    }
    next(err);
  }
});

router.delete('/:bookId', checkBookAccess('member'), async (req, res, next) => {
  try {
    const bookId = parseId(req.params.bookId, '书籍 ID');

    const book = await prisma.book.findUnique({
      where: { id: bookId },
      select: { coverUrl: true },
    });

    if (book?.coverUrl) {
      const filePath = path.join(__dirname, '../..', book.coverUrl);
      try {
        await fs.unlink(filePath);
      } catch (err) {
        console.warn(`删除封面文件失败: ${filePath}`, err.message);
      }
    }

    const updated = await prisma.book.update({
      where: { id: bookId },
      data: { coverUrl: null },
      include: { category: true },
    });

    res.json(updated);
  } catch (err) {
    next(err);
  }
});

export default router;
