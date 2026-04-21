#!/usr/bin/env bash
# 一键部署脚本：同步代码到中途岛，装依赖，推数据库 schema，重启 PM2
# 用法：
#   ./scripts/deploy.sh main   # 生产
#   ./scripts/deploy.sh dev    # 开发
#
# 前置：本地已有 ssh root@47.113.221.26 免密；服务器已装 node/pm2/mysql

set -euo pipefail

TARGET="${1:-main}"
case "$TARGET" in
  main) REMOTE_DIR="/home/bookbox-main"; PM2_NAME="bookbox-main" ;;
  dev)  REMOTE_DIR="/home/bookbox-dev";  PM2_NAME="bookbox-dev"  ;;
  *) echo "用法: $0 {main|dev}"; exit 2 ;;
esac

SERVER="root@47.113.221.26"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> 同步 $SCRIPT_DIR -> $SERVER:$REMOTE_DIR"
rsync -avz --delete \
  --exclude 'node_modules' \
  --exclude '.env' \
  --exclude '.DS_Store' \
  "$SCRIPT_DIR/" "$SERVER:$REMOTE_DIR/"

echo "==> 远端安装依赖 + 推送 schema + 重启"
ssh "$SERVER" "bash -s" <<EOF
set -euo pipefail
cd $REMOTE_DIR
npm install --production=false
npx prisma generate
npx prisma db push --accept-data-loss=false || { echo "schema push 失败，终止"; exit 1; }

# 首次启动用 ecosystem，已存在则重启
if pm2 describe $PM2_NAME >/dev/null 2>&1; then
  pm2 reload $PM2_NAME --update-env
else
  pm2 start ecosystem.config.cjs --only $PM2_NAME
  pm2 save
fi
pm2 status $PM2_NAME
EOF

echo "==> 部署完成：$PM2_NAME"
