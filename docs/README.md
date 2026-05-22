# 9Router Starter Kit

5 分钟完成 AI 编码工具的多模型智能路由配置。

## 它解决什么问题？

- 额度耗尽就停工 → 自动 fallback 到下一个模型
- Opus 额度浪费在低复杂度任务 → haiku 子任务自动走便宜模型
- 手动切模型太麻烦 → 全自动路由 + 降级

## 支持的工具

Claude Code | Cursor | Cline | Codex | Gemini CLI | OpenClaw

## 快速开始

```bash
# 1. 安装
./install.sh

# 2. 交互式配置（选工具、选模型、填 API Key）
./configure.sh

# 3. 验证
./verify.sh
```

就是这样。

## configure.sh 做了什么？

1. 检测 9Router 是否运行
2. 让你选择 AI 编码工具（Claude Code / Cursor / ...）
3. 让你选择拥有的模型服务（Claude 订阅 / GLM / DeepSeek / ...）
4. 收集 API Key
5. 通过 9Router API 自动写入 Provider、Alias、Combo
6. 生成各工具的配置文件
7. 验证通过后自动应用

## 前置要求

- Node.js >= 18
- curl、jq（macOS 自带或 `brew install jq`）
- 至少一个 AI 模型服务的 API Key

## 回滚

```bash
./uninstall.sh
```

恢复原有配置，停止 9Router。

## 目录结构

```
├── install.sh          # 一键安装
├── configure.sh        # 交互式配置（核心）
├── verify.sh           # 自动验证
├── uninstall.sh        # 一键回滚
├── config/             # 预设模板
│   ├── combos/         # 4 套 combo 预设
│   ├── aliases.json    # 默认 alias
│   └── tool-configs/   # 6 种工具配置模板
├── claude-md/          # CLAUDE.md 路由规则片段
├── output/             # configure.sh 生成的配置（gitignored）
└── docs/
    ├── architecture.md
    └── faq.md
```

## 套餐预设

| 套餐 | 模型组合 | 适合谁 |
|------|---------|--------|
| 全订阅版 | Claude Max + GLM + DeepSeek | 重度 Claude 用户 |
| 混合版 | Claude API Key + 国产模型 | 有 Claude API 但无订阅 |
| 纯国产版 | GLM + DeepSeek + Qwen | 不用 Claude |
| 免费版 | Qwen + Kiro | 零成本体验 |

configure.sh 会根据你选择的模型自动匹配最接近的套餐。

## 常见问题

见 [faq.md](faq.md)
