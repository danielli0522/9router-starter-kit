#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
fail()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# --- 检查 Node.js >= 18 ---
check_node() {
  if ! command -v node &>/dev/null; then
    fail "Node.js 未安装。请先安装 Node.js >= 18: https://nodejs.org"
  fi
  local ver=$(node -v | sed 's/v//' | cut -d. -f1)
  if [ "$ver" -lt 18 ]; then
    fail "Node.js 版本过低 (当前 $(node -v))，需要 >= 18"
  fi
  info "Node.js $(node -v)"
}

# --- 检查端口 20128 ---
check_port() {
  if lsof -i :20128 &>/dev/null; then
    if curl -sf http://localhost:20128 &>/dev/null; then
      warn "端口 20128 已被 9Router 占用，跳过安装"
      return 1
    else
      fail "端口 20128 被其他进程占用。请先释放该端口。"
    fi
  fi
  return 0
}

# --- 安装 ---
do_install() {
  info "安装 9Router..."
  npm install -g 9router || fail "9Router 安装失败"

  if ! command -v pm2 &>/dev/null; then
    info "安装 pm2..."
    npm install -g pm2 || fail "pm2 安装失败"
  fi
}

# --- 启动 ---
do_start() {
  info "启动 9Router..."
  pm2 start 9router --name 9router 2>/dev/null || true
  pm2 save
  info "9Router 已启动"
}

# --- 验证 ---
do_verify() {
  sleep 2
  if curl -sf http://localhost:20128 &>/dev/null; then
    info "9Router 响应正常 — http://localhost:20128"
  else
    fail "9Router 启动失败。手动排查: pm2 logs 9router"
  fi
}

# --- 主流程 ---
echo "=== 9Router Starter Kit — 安装 ==="
echo ""

check_node

SKIP_INSTALL=0
check_port || SKIP_INSTALL=1

if [ "$SKIP_INSTALL" -eq 0 ]; then
  do_install
  do_start
fi

do_verify

echo ""
echo "========================================="
echo "  接下来运行: ./configure.sh"
echo "========================================="
echo ""
warn "如需开机自启，请执行: pm2 startup"
warn "然后执行它输出的 sudo 命令"
