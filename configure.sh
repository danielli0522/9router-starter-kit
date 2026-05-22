#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
fail()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step()  { echo -e "\n${CYAN}=== $1 ===${NC}"; }

# 多选: multiselect RESULT_ARRAY "选项1" "选项2" ...
# 输入序号（空格分隔），如: 1 3 5
multiselect() {
  local _result_var=$1; shift
  local _options=("$@")
  local _count=${#_options[@]}

  for ((i=0; i<_count; i++)); do
    echo "  $((i+1))) ${_options[$i]}"
  done

  local _input=""
  read -p "输入序号（空格分隔）: " _input

  eval "$_result_var=()"
  for num in $_input; do
    local idx=$((num - 1))
    if [ "$idx" -ge 0 ] 2>/dev/null && [ "$idx" -lt "$_count" ] 2>/dev/null; then
      eval "$_result_var+=(\"\$idx\")"
    fi
  done
}

BASE_URL="http://localhost:20128"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"

# ============================================
# Step 0: 检测环境
# ============================================
step "Step 0: 环境检测"

curl -sf "$BASE_URL" > /dev/null || fail "9Router 未启动。请先运行: ./install.sh"

if ! command -v jq &>/dev/null; then
  fail "jq 未安装。请先安装: brew install jq (macOS) 或 apt install jq (Linux)"
fi

# 备份 Claude Code 配置
BACKUP_CREATED=0
if [ -f ~/.claude/settings.json ]; then
  cp ~/.claude/settings.json ~/.claude/settings.json.bak
  info "已备份 ~/.claude/settings.json → .bak"
  BACKUP_CREATED=1
fi

mkdir -p "$OUTPUT_DIR"

# ============================================
# Step 1: 选择 AI 编码工具
# ============================================
step "Step 1: 选择 AI 编码工具"

echo "你用哪些工具？"
TOOL_INDICES=()
multiselect TOOL_INDICES \
  "Claude Code" \
  "Cursor" \
  "Cline" \
  "Codex" \
  "Gemini CLI" \
  "OpenClaw"

SELECTED_TOOLS=()
TOOL_NAMES=("claude-code" "cursor" "cline" "codex" "gemini-cli" "openclaw")
for idx in "${TOOL_INDICES[@]}"; do
  SELECTED_TOOLS+=("${TOOL_NAMES[$idx]}")
done

if [ ${#SELECTED_TOOLS[@]} -eq 0 ]; then
  fail "至少选择一个工具"
fi

info "已选工具: ${SELECTED_TOOLS[*]}"

# ============================================
# Step 2: 选择模型服务
# ============================================
step "Step 2: 选择模型服务"

echo "你有哪些模型服务？"
MODEL_INDICES=()
multiselect MODEL_INDICES \
  "Claude Max 订阅 (OAuth 登录)" \
  "Claude API Key" \
  "智谱 GLM (API Key)" \
  "DeepSeek (API Key)" \
  "通义千问 Qwen (免费 API)" \
  "其他 OpenAI 兼容模型 (自定义)"

HAS_CLAUDE_OAUTH=0
HAS_CLAUDE_APIKEY=0
HAS_GLM=0
HAS_DEEPSEEK=0
HAS_QWEN=0
HAS_CUSTOM=0
CUSTOM_BASE_URL=""
CUSTOM_API_KEY=""
CUSTOM_MODEL=""

for idx in "${MODEL_INDICES[@]}"; do
  case $idx in
    0) HAS_CLAUDE_OAUTH=1 ;;
    1) HAS_CLAUDE_APIKEY=1 ;;
    2) HAS_GLM=1 ;;
    3) HAS_DEEPSEEK=1 ;;
    4) HAS_QWEN=1 ;;
    5) HAS_CUSTOM=1 ;;
  esac
done

if [ $((HAS_CLAUDE_OAUTH + HAS_CLAUDE_APIKEY + HAS_GLM + HAS_DEEPSEEK + HAS_QWEN + HAS_CUSTOM)) -eq 0 ]; then
  fail "至少选择一个模型服务"
fi

# ============================================
# Step 3: 收集 API Key
# ============================================
step "Step 3: 填写 API Key"

CLAUDE_APIKEY=""
GLM_APIKEY=""
DEEPSEEK_APIKEY=""
QWEN_APIKEY=""

if [ "$HAS_CLAUDE_OAUTH" -eq 1 ]; then
  echo ""
  echo "请在 9Router Dashboard 手动 OAuth 登录:"
  echo "  打开 http://localhost:20128 → Providers → Connect Claude Code"
  echo ""
  read -p "OAuth 登录完成后按回车继续... " dummy
  info "Claude OAuth 已连接"
fi

if [ "$HAS_CLAUDE_APIKEY" -eq 1 ]; then
  read -p "输入 Anthropic API Key: " CLAUDE_APIKEY
  [ -z "$CLAUDE_APIKEY" ] && fail "API Key 不能为空"
fi

if [ "$HAS_GLM" -eq 1 ]; then
  read -p "输入智谱 API Key: " GLM_APIKEY
  [ -z "$GLM_APIKEY" ] && fail "API Key 不能为空"
fi

if [ "$HAS_DEEPSEEK" -eq 1 ]; then
  read -p "输入 DeepSeek API Key: " DEEPSEEK_APIKEY
  [ -z "$DEEPSEEK_APIKEY" ] && fail "API Key 不能为空"
fi

if [ "$HAS_QWEN" -eq 1 ]; then
  read -p "输入通义千问 API Key (可留空使用免费额度): " QWEN_APIKEY
fi

if [ "$HAS_CUSTOM" -eq 1 ]; then
  read -p "输入自定义 Base URL: " CUSTOM_BASE_URL
  read -p "输入自定义 API Key: " CUSTOM_API_KEY
  read -p "输入模型名: " CUSTOM_MODEL
  [ -z "$CUSTOM_BASE_URL" ] || [ -z "$CUSTOM_API_KEY" ] || [ -z "$CUSTOM_MODEL" ] && fail "自定义模型配置不完整"
fi

info "API Key 收集完成"

# ============================================
# Step 3.5: 登录 9Router Dashboard
# ============================================
step "Step 3.5: Dashboard 登录"

COOKIE_FILE="$OUTPUT_DIR/.9router-session"

# Try existing session first
if [ -f "$COOKIE_FILE" ]; then
  if curl -sf "$BASE_URL/api/providers" -b "$COOKIE_FILE" > /dev/null 2>&1; then
    info "使用已有 Dashboard 会话"
  else
    rm -f "$COOKIE_FILE"
  fi
fi

if [ ! -f "$COOKIE_FILE" ]; then
  echo "9Router Dashboard 需要登录（密码是你首次打开 Dashboard 时设置的）"
  read -sp "输入 Dashboard 密码: " dashboard_pwd
  echo ""

  LOGIN_RESP=$(curl -sf -X POST "$BASE_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"password\":\"$dashboard_pwd\"}" \
    -c "$COOKIE_FILE" 2>&1)

  if [ $? -ne 0 ] || echo "$LOGIN_RESP" | jq -e '.error' > /dev/null 2>&1; then
    rm -f "$COOKIE_FILE"
    fail "Dashboard 登录失败: $(echo "$LOGIN_RESP" | jq -r '.error // "未知错误"')"
  fi
  info "Dashboard 登录成功"
fi

# ============================================
# Step 4: 写入 Provider 到 9Router
# ============================================
step "Step 4: 写入 Provider"

write_provider() {
  local provider="$1" auth_type="$2" name="$3" apikey="$4"
  local payload="{\"provider\":\"$provider\",\"authType\":\"$auth_type\",\"name\":\"$name\""
  if [ -n "$apikey" ]; then
    payload="$payload,\"data\":{\"apiKey\":\"$apikey\"}"
  fi
  payload="$payload}"

  local result
  result=$(curl -sf -X POST "$BASE_URL/api/providers" \
    -b "$COOKIE_FILE" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>&1)
  if [ $? -eq 0 ]; then
    info "Provider '$name' 写入成功"
  else
    warn "Provider '$name' 写入失败: $result"
  fi
}

if [ "$HAS_CLAUDE_APIKEY" -eq 1 ]; then
  write_provider "anthropic" "apikey" "Claude API" "$CLAUDE_APIKEY"
fi

if [ "$HAS_GLM" -eq 1 ]; then
  write_provider "glm" "apikey" "GLM-5.1" "$GLM_APIKEY"
fi

if [ "$HAS_DEEPSEEK" -eq 1 ]; then
  write_provider "deepseek" "apikey" "DeepSeek" "$DEEPSEEK_APIKEY"
fi

if [ "$HAS_QWEN" -eq 1 ] && [ -n "$QWEN_APIKEY" ]; then
  write_provider "qwen" "apikey" "Qwen" "$QWEN_APIKEY"
fi

if [ "$HAS_CUSTOM" -eq 1 ]; then
  write_provider "openai" "apikey" "Custom ($CUSTOM_MODEL)" "$CUSTOM_API_KEY"
fi

# ============================================
# Step 5: 生成并写入 Model Alias
# ============================================
step "Step 5: 写入 Model Alias"

# 确定 haiku 路由目标
HAIKU_TARGET=""
if [ "$HAS_GLM" -eq 1 ]; then
  HAIKU_TARGET="glm/glm-5.1"
elif [ "$HAS_DEEPSEEK" -eq 1 ]; then
  HAIKU_TARGET="ds/deepseek-chat"
elif [ "$HAS_QWEN" -eq 1 ]; then
  HAIKU_TARGET="qw/qwen-plus"
fi

# 确定 opus/sonnet 路由目标
OPUS_PREFIX=""
SONNET_PREFIX=""
if [ "$HAS_CLAUDE_OAUTH" -eq 1 ]; then
  OPUS_PREFIX="cc"
  SONNET_PREFIX="cc"
elif [ "$HAS_CLAUDE_APIKEY" -eq 1 ]; then
  OPUS_PREFIX="anthropic"
  SONNET_PREFIX="anthropic"
fi

# 构建 alias JSON
ALIAS_JSON="{"
ALIAS_ENTRIES=()

if [ -n "$HAIKU_TARGET" ]; then
  ALIAS_ENTRIES+=("\"claude-haiku-4-5\":\"$HAIKU_TARGET\"")
  ALIAS_ENTRIES+=("\"claude-haiku-4-5-20251001\":\"$HAIKU_TARGET\"")
fi

if [ -n "$OPUS_PREFIX" ]; then
  ALIAS_ENTRIES+=("\"claude-opus-4-7\":\"$OPUS_PREFIX/claude-opus-4-7\"")
  ALIAS_ENTRIES+=("\"claude-sonnet-4-6\":\"$SONNET_PREFIX/claude-sonnet-4-6\"")
fi

if [ ${#ALIAS_ENTRIES[@]} -gt 0 ]; then
  ALIAS_JSON+=$(IFS=,; echo "${ALIAS_ENTRIES[*]}")
fi
ALIAS_JSON+="}"

curl -sf -X POST "$BASE_URL/api/models/alias" \
  -b "$COOKIE_FILE" \
  -H "Content-Type: application/json" \
  -d "{\"aliases\":$ALIAS_JSON}" > /dev/null

info "Alias 写入完成 ($(echo "$ALIAS_JSON" | jq 'length' 2>/dev/null || echo '?') 条)"

# ============================================
# Step 6: 生成并写入 Combo
# ============================================
step "Step 6: 写入 Combo"

COMBO_ENTRIES=()
if [ "$HAS_CLAUDE_OAUTH" -eq 1 ]; then
  COMBO_ENTRIES+=("\"cc/claude-opus-4-7\"")
  COMBO_ENTRIES+=("\"cc/claude-sonnet-4-6\"")
elif [ "$HAS_CLAUDE_APIKEY" -eq 1 ]; then
  COMBO_ENTRIES+=("\"anthropic/claude-opus-4-7\"")
  COMBO_ENTRIES+=("\"anthropic/claude-sonnet-4-6\"")
fi

if [ "$HAS_GLM" -eq 1 ]; then
  COMBO_ENTRIES+=("\"glm/glm-5.1\"")
fi

if [ "$HAS_DEEPSEEK" -eq 1 ]; then
  COMBO_ENTRIES+=("\"ds/deepseek-chat\"")
fi

if [ "$HAS_QWEN" -eq 1 ]; then
  COMBO_ENTRIES+=("\"qw/qwen-plus\"")
fi

if [ "$HAS_CUSTOM" -eq 1 ]; then
  COMBO_ENTRIES+=("\"openai/$CUSTOM_MODEL\"")
fi

COMBO_MODELS="[$(IFS=,; echo "${COMBO_ENTRIES[*]}")]"

curl -sf -X POST "$BASE_URL/api/combos" \
  -b "$COOKIE_FILE" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"smart-routing\",\"models\":$COMBO_MODELS}" > /dev/null

info "Combo 'smart-routing' 写入完成 (${#COMBO_ENTRIES[@]} 个模型)"

# ============================================
# Step 7: 设置 Combo 策略为 fallback
# ============================================
step "Step 7: 设置策略"

curl -sf -X PATCH "$BASE_URL/api/settings" \
  -b "$COOKIE_FILE" \
  -H "Content-Type: application/json" \
  -d '{"comboStrategy":"fallback"}' > /dev/null

info "Combo 策略已设为 fallback"

# ============================================
# Step 8: 获取 9Router API Key
# ============================================
step "Step 8: 获取 API Key"

ROUTER_KEY=$(curl -sf "$BASE_URL/api/keys" -b "$COOKIE_FILE" | jq -r '.keys[0].key' 2>/dev/null)

if [ -z "$ROUTER_KEY" ] || [ "$ROUTER_KEY" = "null" ]; then
  ROUTER_KEY=$(curl -sf -X POST "$BASE_URL/api/keys" \
    -b "$COOKIE_FILE" \
    -H "Content-Type: application/json" \
    -d '{"name":"starter-kit"}' | jq -r '.key' 2>/dev/null)
  info "已创建新 API Key"
else
  info "使用已有 API Key"
fi

if [ -z "$ROUTER_KEY" ] || [ "$ROUTER_KEY" = "null" ]; then
  fail "获取 API Key 失败。请检查 Dashboard: http://localhost:20128"
fi

# ============================================
# Step 9: 生成各工具配置文件
# ============================================
step "Step 9: 生成配置文件"

DEFAULT_MODEL="smart-routing"

for tool in "${SELECTED_TOOLS[@]}"; do
  mkdir -p "$OUTPUT_DIR/$tool"
  case $tool in
    claude-code)
      cat > "$OUTPUT_DIR/claude-code/settings.json" << EOF
{
  "env": {
    "ANTHROPIC_BASE_URL": "$BASE_URL/v1",
    "ANTHROPIC_AUTH_TOKEN": "$ROUTER_KEY"
  },
  "model": "claude-opus-4-7"
}
EOF
      info "Claude Code → output/claude-code/settings.json"
      ;;
    codex)
      cat > "$OUTPUT_DIR/codex/setup.sh" << EOF
#!/bin/bash
echo 'export OPENAI_BASE_URL=$BASE_URL/v1' >> ~/.zshrc
echo 'export OPENAI_API_KEY=$ROUTER_KEY' >> ~/.zshrc
echo 'Codex 环境变量已添加到 ~/.zshrc'
echo '运行 source ~/.zshrc 或新开终端生效'
EOF
      chmod +x "$OUTPUT_DIR/codex/setup.sh"
      info "Codex → output/codex/setup.sh"
      ;;
    gemini-cli)
      cat > "$OUTPUT_DIR/gemini-cli/settings.json" << EOF
{
  "baseUrl": "$BASE_URL/v1",
  "apiKey": "$ROUTER_KEY"
}
EOF
      info "Gemini CLI → output/gemini-cli/settings.json"
      ;;
    openclaw)
      cat > "$OUTPUT_DIR/openclaw/provider-patch.json" << EOF
{
  "models": {
    "providers": {
      "9router": {
        "baseUrl": "$BASE_URL/v1",
        "apiKey": "$ROUTER_KEY",
        "api": "anthropic-messages"
      }
    }
  }
}
EOF
      info "OpenClaw → output/openclaw/provider-patch.json"
      ;;
    cursor)
      sed "s|{{API_KEY}}|$ROUTER_KEY|g; s|{{BASE_URL}}|$BASE_URL/v1|g" \
        "$SCRIPT_DIR/config/tool-configs/cursor-guide.md" \
        > "$OUTPUT_DIR/cursor/guide.md"
      info "Cursor → output/cursor/guide.md (手动设置)"
      ;;
    cline)
      sed "s|{{API_KEY}}|$ROUTER_KEY|g; s|{{BASE_URL}}|$BASE_URL/v1|g" \
        "$SCRIPT_DIR/config/tool-configs/cline-guide.md" \
        > "$OUTPUT_DIR/cline/guide.md"
      info "Cline → output/cline/guide.md (手动设置)"
      ;;
  esac
done

# 生成 CLAUDE.md 路由规则片段
cat > "$OUTPUT_DIR/claude-md-snippet.md" << EOF
## Agent 模型路由（9Router）

派 Agent 子任务时的模型选择规则：

| 场景 | 模型 | 说明 |
|------|------|------|
| 代码 review | haiku | 检查模式匹配，高 input token |
| 单元测试生成 | haiku | 模板化任务 |
| E2E 测试验证 | haiku | 跑脚本+判断结果 |
| HTML 界面预览 | haiku | 生成简单 HTML |
| 大量文件读取后总结 | haiku | 信息提取，极高 input token |
| 重复性代码批量生成 | haiku | 模板化，模式固定 |
| 日志/错误分析 | haiku | 模式匹配+搜索 |
| 其他编码/调试/架构 | 默认 | 由 combo fallback 自动选择 |

原则：**高 token 低复杂度走 haiku（省额度），主力模型留给强推理任务。**
EOF

info "CLAUDE.md 片段 → output/claude-md-snippet.md"

# ============================================
# Step 10: 确认生效
# ============================================
step "Step 10: 确认生效"

echo ""
echo "配置已写入 9Router。工具配置已生成到 output/。"
echo ""

# 先运行 verify.sh 验证 9Router 自身配置
echo "正在验证 9Router 配置..."
VERIFY_RESULT=0
COOKIE_FILE="$COOKIE_FILE" "$SCRIPT_DIR/verify.sh" || VERIFY_RESULT=$?

if [ "$VERIFY_RESULT" -ne 0 ]; then
  echo ""
  fail "9Router 验证未通过，不切换 settings.json。请修复后重新运行 ./verify.sh"
  echo "原有配置未受影响。"
  exit 1
fi

echo ""
read -p "9Router 验证通过！是否立即应用到 AI 工具？(Y/n) " apply_choice

if [ "$apply_choice" = "n" ] || [ "$apply_choice" = "N" ]; then
  echo ""
  info "配置文件在 output/ 目录，手动应用："
  for tool in "${SELECTED_TOOLS[@]}"; do
    case $tool in
      claude-code) echo "  cp output/claude-code/settings.json ~/.claude/settings.json" ;;
      codex)       echo "  source output/codex/setup.sh" ;;
      gemini-cli)  echo "  cp output/gemini-cli/settings.json ~/.gemini/settings.json" ;;
      openclaw)    echo "  合并 output/openclaw/provider-patch.json 到 ~/.openclaw/openclaw.json" ;;
      cursor)      echo "  参考 output/cursor/guide.md 手动设置" ;;
      cline)       echo "  参考 output/cline/guide.md 手动设置" ;;
    esac
  done
  echo ""
  echo "  CLAUDE.md 路由规则:"
  echo "  cat output/claude-md-snippet.md >> CLAUDE.md"
  exit 0
fi

# 自动应用
for tool in "${SELECTED_TOOLS[@]}"; do
  case $tool in
    claude-code)
      cp "$OUTPUT_DIR/claude-code/settings.json" ~/.claude/settings.json
      info "Claude Code: settings.json 已应用"
      ;;
    codex)
      source "$OUTPUT_DIR/codex/setup.sh"
      ;;
    gemini-cli)
      mkdir -p ~/.gemini
      cp "$OUTPUT_DIR/gemini-cli/settings.json" ~/.gemini/settings.json
      info "Gemini CLI: settings.json 已应用"
      ;;
    openclaw)
      if [ -f ~/.openclaw/openclaw.json ]; then
        jq -s '.[0] * .[1]' ~/.openclaw/openclaw.json "$OUTPUT_DIR/openclaw/provider-patch.json" \
          > ~/.openclaw/openclaw.json.tmp && mv ~/.openclaw/openclaw.json.tmp ~/.openclaw/openclaw.json
        info "OpenClaw: provider 已合并"
      else
        mkdir -p ~/.openclaw
        cp "$OUTPUT_DIR/openclaw/provider-patch.json" ~/.openclaw/openclaw.json
        info "OpenClaw: 配置已创建"
      fi
      ;;
    cursor)
      info "Cursor: 请手动设置 — 参考 output/cursor/guide.md"
      ;;
    cline)
      info "Cline: 请手动设置 — 参考 output/cline/guide.md"
      ;;
  esac
done

echo ""
info "全部完成！"
echo ""
echo "  别忘了把路由规则加到 CLAUDE.md:"
echo "  cat output/claude-md-snippet.md >> CLAUDE.md"
echo ""
echo "  如需回滚: ./uninstall.sh"
