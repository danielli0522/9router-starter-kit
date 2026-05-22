# 架构说明

## 整体架构

```
AI 编码工具 (Claude Code / Cursor / ...)
  ↓ 请求发送到 localhost:20128/v1
  ↓
9Router (本地代理, pm2 托管)
  │
  ├── Model Alias（模型别名映射）
  │     haiku → GLM-5.1（省额度）
  │     opus  → Claude Opus（OAuth 订阅）
  │
  ├── Combo "smart-routing"（fallback 策略）
  │     1. Claude Opus  → 主力
  │     2. Claude Sonnet → 降级
  │     3. GLM-5.1      → 备用
  │     4. DeepSeek      → 兜底
  │
  └── Provider（模型服务连接）
        claude  → OAuth / API Key
        glm     → API Key (智谱)
        deepseek → API Key
```

## 数据流

1. AI 工具发送请求到 `localhost:20128/v1`
2. 9Router 接收请求，解析 model 字段
3. 先查 Alias 表：`claude-haiku-4-5` → `glm/glm-5.1`
4. 如果 model 匹配 Combo 名：走 fallback 链
5. 选择第一个可用的 Provider 发送请求
6. Provider 返回错误（429/quota）→ 自动尝试下一个
7. 成功响应返回给 AI 工具

## Starter Kit 做了什么

- `install.sh`: 安装 9Router + pm2 进程管理
- `configure.sh`: 通过 9Router REST API 写入所有配置
- `verify.sh`: 5 阶段验证确保配置正确
- `uninstall.sh`: 恢复原有配置

## 配置存储

9Router 的所有配置存储在 SQLite 数据库 `~/.9router/db/data.sqlite`：

| 表 | 存什么 |
|----|--------|
| `providerConnections` | Provider 连接信息 + API Key |
| `kv` (scope=modelAliases) | 模型别名映射 |
| `combos` | Combo 定义 + 模型列表 |
| `settings` | 全局设置（策略等） |
| `apiKeys` | 9Router 自身的 API Key |

Starter Kit 通过 REST API 写入这些表，不直接操作数据库。

## 安全注意事项

- API Key 存储在 9Router 本地 SQLite，不外传
- 9Router 只监听 localhost，外部不可访问
- API Key 仅在 `~/.claude/settings.json` 等本地配置文件中明文存储
- `output/` 目录在 `.gitignore` 中，不会被提交
