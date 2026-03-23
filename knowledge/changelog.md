# Claude Code / OpenClaw 变更追踪

> 记录本 skill 真正依赖的版本变化和实测发现。
> 最后更新：2026-03-23

## 当前基线

- Claude Code（本机）：`2.1.80`
- Claude Code（npm 查询时）：`2.1.81`
- OpenClaw CLI（本机）：`2026.3.11`

## 2026-03-23 升级结论

### Claude Code 侧新增/确认

- `--settings` 与 `--setting-sources` 现在是托管 overlay 的首选入口
- `--session-id` 可显式指定 Claude 会话 ID
- `--effort` 已进入 CLI 主帮助
- `--plugin-dir`、`--ide`、`--no-session-persistence`、`--allow-dangerously-skip-permissions` 已进入 CLI 主帮助
- `--permission-mode` 当前含 `auto`
- `remote-control` 命令存在，但本机账号仍提示未开通

### 本项目升级后的关键架构变化

- wrappers 改为每次启动都动态生成 Claude managed settings overlay
- 不再要求“要用托管会话就必须先手工把 hooks 写进全局 `~/.claude/settings.json`”
- hook 唤醒改为显式 `openclaw agent --session-id ...`
- 每个 Claude 托管会话映射到独立 OpenClaw 会话，避免共享 agent `main` 上下文

## 实测发现

### 会话与路由

- 只传 `--agent main` 容易把多个 Claude 托管会话压进同一条 OpenClaw 上下文
- 使用显式 `--session-id` 后，托管会话之间的上下文边界清晰得多

### Hooks

- `Stop` hook 的 `last_assistant_message` 仍可用于快速摘要
- `Notification` 中继续能收到 `permission_prompt` 与 `idle_prompt`
- 本项目当前只接入最关键的 4 类 hook；`PermissionRequest` 等仍待后续评估

### Agent Teams

- 文档仍保留 Agent Teams 用法
- 但 CLI 主帮助并不会把所有团队相关 flag 都列出来
- 使用前应优先核对官方最新文档，而不是只看 `claude --help`

### 权限

- `auto` 已成为官方列出的 permission mode 之一
- “危险跳权”与“允许启用危险跳权”已经是两个不同 flag
- 不应再把跳权模式宣传成绝对无阻塞

## 后续待验证

- `PermissionRequest` hook 是否值得接入本项目的审批链
- `--settings` overlay 与用户自定义 hooks 的合并细节边界
- Agent Teams 在不同终端环境下的 `--teammate-mode` 细节
