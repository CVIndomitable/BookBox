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
npm install --omit=dev --no-audit --no-fund

# 首次部署时才写 .env（避免覆盖服务器上已有的正确密码）
[ -f .env ] || cp .env.dev .env

# 同步 schema（项目无 migrations/ 目录，用 db push）
npx prisma db push --skip-generate
npx prisma generate

# 重启 systemd 服务
systemctl restart bookbox-dev

echo "✅ 开发环境部署完成"
ENDSSH
