#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }

echo "=== 9Router Starter Kit — 回滚 ==="
echo ""

# 恢复 Claude Code 配置
if [ -f ~/.claude/settings.json.bak ]; then
  cp ~/.claude/settings.json.bak ~/.claude/settings.json
  info "已恢复 ~/.claude/settings.json"
else
  warn "无备份文件，跳过恢复"
fi

# 停止 9Router
if pm2 jlist 2>/dev/null | jq -e '.[] | select(.name=="9router")' > /dev/null 2>&1; then
  pm2 stop 9router 2>/dev/null
  pm2 delete 9router 2>/dev/null
  pm2 save
  info "9Router 已停止并从 pm2 移除"
else
  warn "9Router 未在 pm2 中运行"
fi

# 可选卸载
echo ""
read -p "是否卸载 9Router? (y/N) " uninstall
if [ "$uninstall" = "y" ] || [ "$uninstall" = "Y" ]; then
  npm uninstall -g 9router
  info "9Router 已卸载"
fi

echo ""
info "回滚完成"
echo "  9Router 数据保留在 ~/.9router/"
echo "  如需彻底清除: rm -rf ~/.9router"
