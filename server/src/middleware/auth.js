// 简单 token 认证中间件
export function authMiddleware(req, res, next) {
  const apiToken = process.env.API_TOKEN;
  if (!apiToken) {
    console.error('严重：API_TOKEN 环境变量未配置，拒绝所有请求');
    return res.status(500).json({ error: '服务器认证配置缺失' });
  }

  const token = req.headers.authorization?.replace('Bearer ', '');

  if (!token || token !== apiToken) {
    return res.status(401).json({ error: '未授权访问' });
  }

  next();
}
