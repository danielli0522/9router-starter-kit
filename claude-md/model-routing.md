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
| 其他编码/调试/架构 | 默认 | 由 combo 自动选择 opus/sonnet |

原则：**高 token 低复杂度走 haiku（省额度），Opus 留给强推理任务。**

### 模型路由说明

- `haiku` → 9Router alias → 实际走你配置的便宜模型（如 GLM-5.1）
- `默认` → 9Router combo fallback → 自动按优先级降级
- Quota 耗尽自动降级到下一个模型，不会停工
- 如需手动指定模型，使用 `/model` 命令

### 适用场景

- Claude Code: `/model haiku` 切换到便宜模型
- 派 Agent 子任务时指定 `model: "haiku"` 参数
- CLAUDE.md 中定义的规则会自动指导模型选择
