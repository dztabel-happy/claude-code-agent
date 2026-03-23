# Claude Code / OpenClaw 变更追踪

> 记录本 skill 真正依赖的版本变化和实测发现。
> 最后更新：2026-03-23

## 当前基线

- Claude Code（本机）：`2.1.80`
- Claude Code（npm 查询时）：`2.1.81`
- OpenClaw CLI（本机）：`2026.3.11`
- OpenClaw（npm 查询时）：`2026.3.22`
- Codex CLI（本机）：`0.111.0`

## 2026-03-23 简化升级结论

### 官方约束确认

- Claude Code 侧：`--settings` 与 `--setting-sources` 仍是托管 overlay 的核心入口
- Claude Code 侧：`--permission-mode` 当前含 `auto`
- Claude Code 侧：`--dangerously-skip-permissions` 仍应视为隔离环境专用高风险模式
- OpenClaw skills 侧：skill metadata 需要更贴近最新 parser 约束，`metadata` 采用单行 JSON 更稳妥

### 本项目本轮升级

- `SKILL.md` 改为更短、更聚焦的运行规范
- `metadata` 改成单行 JSON 对象写法
- Agent Teams 改为显式 opt-in：只有传 `--agent-teams` 才注入实验 env 和团队 hooks
- 安装文档不再假设固定在 `~/.openclaw/workspace/skills/...`
- `hooks/hooks_config.json` 改成 `__SKILL_DIR__` 模板，不再硬编码路径
- 默认建议从“尽量全自动”收敛为“普通任务简单、危险能力显式开启”

### 设计层判断

- 运行时内核依然成立：wrapper、hooks、session store、handoff / reclaim、tmux 可观测性都保留价值
- 真正需要收敛的是默认值和说明方式，而不是继续加更多功能
- 参考 Codex 最新 docs 的设计倾向，本项目也应遵守：skill 聚焦、默认简单、进阶能力显式 opt-in

## 实测发现

### 会话与路由

- 只传 `--agent main` 容易把多个 Claude 托管会话压进同一条 OpenClaw 上下文
- 使用显式 `openclaw agent --session-id ...` 后，托管会话边界清晰得多

### Hooks

- `Stop`、`Notification(permission_prompt|idle_prompt)`、`PermissionRequest(Bash)` 仍是当前最稳定的托管 hooks 组合
- `PermissionRequest` 仍支持 session 级 `updatedPermissions`
- 团队相关 hooks 继续可用，但更适合作为 opt-in 能力而不是默认前提

### 权限

- `acceptEdits` 仍是常规可信仓库的高性价比默认值
- “危险跳权”与“允许启用危险跳权”仍是两个不同概念
- 不应把跳权模式宣传成绝对无阻塞

## 后续待验证

- `--settings` overlay 与用户自定义 hooks 的合并边界
- `PermissionRequest` safe allowlist 是否还应扩展到更多只读 / 校验命令
- Agent Teams 在不同环境下的更多行为差异
