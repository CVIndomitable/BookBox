#!/bin/bash
# 中途岛服务器部署脚本 - 开发环境

SERVER="47.113.221.26"
USER="root"
REMOTE_DIR="/home/bookbox-dev"

echo "📦 同步代码到开发环境..."
rsync -avz --delete \
  --exclude 'node_modules' \
  --exclude '.env' \
  --exclude 'logs' \
  server/ ${USER}@${SERVER}:${REMOTE_DIR}/

echo "🔧 远程配置开发环境..."
ssh ${USER}@${SERVER} << 'ENDSSH'
cd /home/bookbox-dev

# 安装依赖
npm install --production

# 复制开发环境配置
cp .env.dev .env

# 数据库迁移
npx prisma migrate deploy
npx prisma generate

# 重启 PM2 服务
pm2 restart bookbox-dev || pm2 start src/index.js --name bookbox-dev

echo "✅ 开发环境部署完成"
ENDSSH
