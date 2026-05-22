# 常见问题

## 安装相关

**Q: install.sh 报 "Node.js 未安装"**
A: 需要先安装 Node.js >= 18。推荐用 nvm: `curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash && nvm install 22`

**Q: install.sh 报 "端口 20128 被占用"**
A: 运行 `lsof -i :20128` 查看是什么进程占用。如果是 9Router 则正常（已安装）；如果是其他进程，需要先停止它。

**Q: 安装后 Dashboard 打不开**
A: 检查 `pm2 logs 9router`。常见原因：Node.js 版本过低、端口被防火墙阻断。

## 配置相关

**Q: configure.sh 报 "jq 未安装"**
A: macOS: `brew install jq` | Linux: `apt install jq` 或 `yum install jq`

**Q: Claude OAuth 登录后 configure.sh 还是检测不到**
A: OAuth 连接存储在 9Router 的 `claude` provider 中，configure.sh 会自动检测已有连接。

**Q: 我有 Claude Max 订阅也有 API Key，选哪个？**
A: 选 "Claude Max 订阅"（OAuth）。OAuth 模式自动刷新 token，更省心。API Key 模式按量付费。

**Q: 可以只配一个模型吗？**
A: 可以。但 combo fallback 的意义在于多模型冗余。至少建议配 2 个。

**Q: haiku 路由到 GLM 后质量够用吗？**
A: haiku 子任务是低复杂度任务（review、测试、总结），GLM-5.1 完全胜任。需要强推理的任务仍走 Opus。

## 工具相关

**Q: Cursor 怎么配置？**
A: Cursor 是 GUI 设置，无法脚本化。configure.sh 会生成 `output/cursor/guide.md`，按步骤在 Settings → Models 里填。

**Q: Codex 用什么端点？**
A: Codex 使用 OpenAI 格式，9Router 的 `/v1/chat/completions` 端点兼容。configure.sh 会设置 `OPENAI_BASE_URL` 环境变量。

**Q: 可以同时给多个工具配置吗？**
A: 可以。configure.sh 支持多选，会为每个选中的工具生成配置。

## 故障排查

**Q: verify.sh 阶段 4 路由测试失败**
A: 检查 Dashboard 日志（http://localhost:20128 → Logs）。常见原因：
- API Key 无效
- Provider 未正确配置
- 网络问题（GLM/DeepSeek 端点不可达）

**Q: 配置后 Claude Code 启动报错**
A: 运行 `./uninstall.sh` 恢复原配置，然后检查 `~/.claude/settings.json` 内容是否正确。

**Q: 9Router 日志在哪里？**
A: `pm2 logs 9router` 或 `~/.9router/logs/`

**Q: 如何回滚？**
A: `./uninstall.sh` 一键恢复。
