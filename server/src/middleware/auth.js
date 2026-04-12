// 简单 token 认证中间件
export function authMiddleware(req, res, next) {
  const token = req.headers.authorization?.replace('Bearer ', '');

  if (!token || token !== process.env.API_TOKEN) {
    return res.status(401).json({ error: '未授权访问' });
  }

  next();
}
