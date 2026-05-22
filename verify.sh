#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL_COUNT=0
WARN_COUNT=0

check_pass() { echo -e "  ${GREEN}[✓]${NC} $1"; ((PASS++)); }
check_fail() { echo -e "  ${RED}[✗]${NC} $1"; ((FAIL_COUNT++)); FAILS+=("$1"); }
check_warn() { echo -e "  ${YELLOW}[!]${NC} $1"; ((WARN_COUNT++)); WARNS+=("$1"); }

BASE_URL="http://localhost:20128"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FAILS=()
WARNS=()

COOKIE_FILE="${COOKIE_FILE:-$SCRIPT_DIR/output/.9router-session}"

# Try login if no valid cookie
login_if_needed() {
  if [ -f "$COOKIE_FILE" ] && curl -sf "$BASE_URL/api/providers" -b "$COOKIE_FILE" > /dev/null 2>&1; then
    return 0
  fi

  # verify.sh is non-interactive — inform user and fail
  if ! curl -sf "$BASE_URL/api/providers" -b "$COOKIE_FILE" > /dev/null 2>&1; then
    echo "  ⚠ Dashboard 需要登录。请先运行: ./configure.sh"
    return 1
  fi
}

login_if_needed || true

echo "9Router 验证报告"
echo "================"

# ============================================
# 阶段 1: 基础连通
# ============================================
echo ""
echo "阶段 1: 基础连通"

if pm2 jlist 2>/dev/null | jq -e '.[] | select(.name=="9router") | .pm2_env.status' | grep -q "online"; then
  check_pass "9Router 进程在线"
else
  check_fail "9Router 进程未运行 (pm2 status)"
fi

if curl -sf "$BASE_URL" > /dev/null 2>&1; then
  check_pass "9Router HTTP 响应正常 ($BASE_URL)"
else
  check_fail "9Router HTTP 无响应"
fi

# ============================================
# 阶段 2: 9Router 配置检查
# ============================================
echo ""
echo "阶段 2: 9Router 配置检查"

PROVIDERS=$(curl -sf "$BASE_URL/api/providers" -b "$COOKIE_FILE" 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$PROVIDERS" ]; then
  PROVIDER_COUNT=$(echo "$PROVIDERS" | jq '.connections | length' 2>/dev/null)
  if [ "$PROVIDER_COUNT" -gt 0 ] 2>/dev/null; then
    check_pass "Provider: $PROVIDER_COUNT 个"
  else
    check_fail "Provider: 无配置"
  fi
else
  check_fail "Provider: 无法读取 (9Router API 异常)"
fi

ALIASES=$(curl -sf "$BASE_URL/api/models/alias" -b "$COOKIE_FILE" 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$ALIASES" ]; then
  ALIAS_COUNT=$(echo "$ALIASES" | jq 'length' 2>/dev/null)
  if [ "${ALIAS_COUNT:-0}" -ge 2 ]; then
    check_pass "Alias: $ALIAS_COUNT 条"
  else
    check_warn "Alias: 仅 $ALIAS_COUNT 条（建议 >= 4）"
  fi
else
  check_warn "Alias: 无法读取"
fi

COMBOS=$(curl -sf "$BASE_URL/api/combos" -b "$COOKIE_FILE" 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$COMBOS" ]; then
  COMBO_COUNT=$(echo "$COMBOS" | jq '.combos | length' 2>/dev/null)
  if [ "$COMBO_COUNT" -gt 0 ] 2>/dev/null; then
    check_pass "Combo: $COMBO_COUNT 个"
  else
    check_fail "Combo: 无配置"
  fi
else
  check_fail "Combo: 无法读取"
fi

SETTINGS=$(curl -sf "$BASE_URL/api/settings" -b "$COOKIE_FILE" 2>/dev/null)
if [ $? -eq 0 ]; then
  STRATEGY=$(echo "$SETTINGS" | jq -r '.comboStrategy // "unknown"' 2>/dev/null)
  if [ "$STRATEGY" = "fallback" ]; then
    check_pass "策略: fallback"
  else
    check_warn "策略: $STRATEGY (建议 fallback)"
  fi
fi

# ============================================
# 阶段 3: AI 工具配置检查
# ============================================
echo ""
echo "阶段 3: AI 工具配置检查"

# Claude Code
if [ -f ~/.claude/settings.json ]; then
  CC_URL=$(jq -r '.env.ANTHROPIC_BASE_URL // .env.ANTHROPIC_API_KEY // empty' ~/.claude/settings.json 2>/dev/null)
  if echo "$CC_URL" | grep -q "localhost:20128"; then
    check_pass "Claude Code: 指向 9Router"
  else
    check_warn "Claude Code: 未指向 9Router (当前: ${CC_URL:-未配置})"
  fi
else
  check_warn "Claude Code: settings.json 不存在"
fi

# OpenClaw
if [ -f ~/.openclaw/openclaw.json ]; then
  if jq -e '.models.providers | to_entries[] | select(.value.baseUrl | test("localhost:20128"))' ~/.openclaw/openclaw.json &>/dev/null; then
    check_pass "OpenClaw: 指向 9Router"
  else
    check_warn "OpenClaw: 未配置 9Router"
  fi
fi

# Codex
if [ -n "$OPENAI_BASE_URL" ] && echo "$OPENAI_BASE_URL" | grep -q "localhost:20128"; then
  check_pass "Codex: 指向 9Router"
elif [ -f ~/.codex/config.toml ]; then
  check_warn "Codex: 检查 OPENAI_BASE_URL 环境变量"
fi

# ============================================
# 阶段 4: 模型路由测试
# ============================================
echo ""
echo "阶段 4: 模型路由测试"

# 获取 API Key
ROUTER_KEY=$(curl -sf "$BASE_URL/api/keys" -b "$COOKIE_FILE" | jq -r '.keys[0].key' 2>/dev/null)

if [ -n "$ROUTER_KEY" ] && [ "$ROUTER_KEY" != "null" ]; then
  # 测试 haiku 路由
  HAIKU_RESP=$(curl -sf -X POST "$BASE_URL/v1/messages" \
    -H "x-api-key: $ROUTER_KEY" \
    -H "content-type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d '{"model":"claude-haiku-4-5","messages":[{"role":"user","content":"say ok"}],"max_tokens":10}' 2>/dev/null)

  if [ $? -eq 0 ] && echo "$HAIKU_RESP" | sed 's/data: \[DONE\]//' | jq -e '.content' &>/dev/null; then
    check_pass "haiku 路由正常"
  else
    check_fail "haiku 路由失败（检查 Dashboard 日志）"
  fi

  # 测试 opus 路由
  OPUS_RESP=$(curl -sf -X POST "$BASE_URL/v1/messages" \
    -H "x-api-key: $ROUTER_KEY" \
    -H "content-type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d '{"model":"claude-opus-4-7","messages":[{"role":"user","content":"say ok"}],"max_tokens":10}' 2>/dev/null)

  if [ $? -eq 0 ] && echo "$OPUS_RESP" | sed 's/data: \[DONE\]//' | jq -e '.content' &>/dev/null; then
    check_pass "opus 路由正常"
  else
    check_warn "opus 路由失败（可能未 OAuth 登录或 quota 不足）"
  fi
else
  check_fail "无法获取 API Key，跳过路由测试"
fi

# ============================================
# 阶段 5: CLAUDE.md 路由规则检查
# ============================================
echo ""
echo "阶段 5: CLAUDE.md 路由规则"

if [ -f CLAUDE.md ] && grep -q "模型路由\|9Router\|model.*routing" CLAUDE.md 2>/dev/null; then
  check_pass "CLAUDE.md 包含路由规则"
else
  check_warn "CLAUDE.md 未包含路由规则"
  echo "    → cat output/claude-md-snippet.md >> CLAUDE.md"
fi

# ============================================
# 总结
# ============================================
echo ""
echo "================"
TOTAL=$((PASS + FAIL_COUNT + WARN_COUNT))
echo -e "${GREEN}$PASS${NC}/$TOTAL 通过, ${RED}$FAIL_COUNT${NC} 失败, ${YELLOW}$WARN_COUNT${NC} 警告"

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo ""
  echo "失败项:"
  for f in "${FAILS[@]}"; do
    echo -e "  ${RED}→${NC} $f"
  done
  exit 1
elif [ "$WARN_COUNT" -gt 0 ]; then
  echo ""
  echo "建议修复:"
  for w in "${WARNS[@]}"; do
    echo -e "  ${YELLOW}→${NC} $w"
  done
fi

exit 0
