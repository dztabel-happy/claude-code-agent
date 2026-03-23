# Claude Code 功能特性

> 最后更新：2026-03-23
> 本机实测版本：2.1.80
> npm 最新版本（查询时）：2.1.81

## 核心命令

| 命令 | 用途 | 备注 |
|------|------|------|
| `claude` | 启动交互式会话 | 默认模式 |
| `claude "prompt"` | 带初始提示词启动交互式会话 | |
| `claude -p "prompt"` | print 模式 | 非交互、适合脚本 |
| `claude -c` | 继续当前目录最近会话 | |
| `claude -r [id]` | 恢复指定会话 | 可结合 `--fork-session` |
| `claude update` / `claude install` | 更新或安装 native build | |
| `claude auth ...` | 认证管理 | |
| `claude agents` | 查看可用 agents | |
| `claude mcp ...` | MCP 管理 | |
| `claude plugin ...` | 插件管理 | |
| `claude remote-control` | 远程控制 | 当前本机账号仍未开通 |

## 当前高价值 CLI Flags

### 会话与执行

| Flag | 用途 |
|------|------|
| `-p, --print` | 单次输出后退出 |
| `-c, --continue` | 继续最近会话 |
| `-r, --resume` | 恢复指定会话 |
| `--fork-session` | 恢复时复制出新会话 |
| `--session-id <id>` | 显式指定会话 ID |
| `-n, --name <name>` | 指定显示名称 |
| `--max-turns <n>` | 限制轮次，仅 print |
| `--max-budget-usd <n>` | 限制预算，仅 print |
| `--no-session-persistence` | print 模式不保存会话 |

### 权限与工具

| Flag | 用途 |
|------|------|
| `--permission-mode <mode>` | `acceptEdits` / `bypassPermissions` / `default` / `dontAsk` / `plan` / `auto` |
| `--dangerously-skip-permissions` | 直接跳过权限检查 |
| `--allow-dangerously-skip-permissions` | 允许在会话中启用危险跳权能力 |
| `--allowed-tools` | 预授权工具 |
| `--disallowed-tools` | 禁用工具 |
| `--tools` | 显式限制内置工具集合 |

### 模型、思考与提示

| Flag | 用途 |
|------|------|
| `--model <model>` | 指定模型 |
| `--fallback-model <model>` | print 模式备用模型 |
| `--effort <level>` | `low` / `medium` / `high` / `max` |
| `--system-prompt <text>` | 替换系统提示词 |
| `--append-system-prompt <text>` | 追加系统提示词 |
| `--json-schema <schema>` | 结构化输出 |

### 环境、配置与扩展

| Flag | 用途 |
|------|------|
| `--settings <file-or-json>` | 加载额外 settings overlay |
| `--setting-sources <sources>` | 控制加载 `user,project,local` 哪些配置源 |
| `--mcp-config <configs...>` | 额外 MCP 配置 |
| `--strict-mcp-config` | 只用显式指定的 MCP 配置 |
| `--plugin-dir <path>` | 加载 session 级插件目录 |
| `--add-dir <directories...>` | 添加额外可访问目录 |
| `--ide` | 自动连接 IDE |
| `--chrome` / `--no-chrome` | 启用或禁用 Chrome 集成 |
| `-w, --worktree [name]` | 新建隔离 worktree |
| `--tmux` | worktree 下使用 tmux / iTerm2 panes |

### 流式输入输出

| Flag | 用途 |
|------|------|
| `--output-format text/json/stream-json` | 输出格式 |
| `--input-format text/stream-json` | print 模式输入格式 |
| `--include-partial-messages` | stream-json 下输出 partial chunks |
| `--replay-user-messages` | stream-json 下重放 user 输入 |

## 当前权限模式理解

| 模式 | 含义 | OpenClaw 使用建议 |
|------|------|------------------|
| `default` | 正常审批流 | 谨慎任务默认值 |
| `acceptEdits` | 自动接受文件编辑 | 常规项目高性价比选项 |
| `plan` | 只分析不修改 | 方案评审、只读审计 |
| `dontAsk` | 未预授权即拒绝 | 严格白名单环境 |
| `bypassPermissions` | 跳过绝大部分权限检查 | 仅隔离环境 |
| `auto` | Claude 自主决定策略 | 可实验，但需要观测真实行为 |

> 注意：即使是跳权模式，Claude Code 官方权限模型仍有 protected directories 等额外保护概念；不要把“全自动”描述成“任何路径、任何命令永远无阻”。

## Hooks：本项目当前真正依赖的事件

| Hook | 本项目用途 |
|------|-----------|
| `Stop` | Claude 有新回复后更新 metadata 并唤醒 OpenClaw |
| `Notification(permission_prompt)` | 审批等待 |
| `Notification(idle_prompt)` | 等待下一步输入 |
| `TeammateIdle` | Agent Teams teammate 即将空闲 |
| `TaskCompleted` | 团队任务完成与质量门禁 |

官方还提供更多 hook 事件，例如 `SessionStart`、`SessionEnd`、`PermissionRequest`、`PreToolUse`、`PostToolUse`、`PreCompact` 等。本项目当前没有全部接入。

## Agent Teams

- 文档层仍然把 Agent Teams 视为实验/灰度能力。
- 本机知识与当前 skill 仍保留对 `--teammate-mode tmux/in-process` 的使用策略，因为官方文档仍有说明。
- 但在实际 CLI 自省中，`claude --help` 没有直接列出 `--teammate-mode`，因此使用前应优先参考最新官方文档与本机实测。

## 本项目自己的托管层能力

Claude 原生支持会话恢复，但本项目在其上再加了一层“托管会话”：

- `hooks/start_claude.sh`：启动交互式托管会话
- `hooks/run_claude.sh`：启动 print 托管会话
- `runtime/start_local_claude.sh`：启动本地控制、可 handoff 的托管会话
- `runtime/takeover.sh` / `runtime/reclaim.sh`：在 `local` 和 `openclaw` 间切换控制权

### 当前升级后的关键设计

- 托管 wrappers 会自动通过 `--settings` 注入 managed settings overlay
- 不再把托管 hooks 的正确性建立在用户手工改全局 `~/.claude/settings.json` 上
- 每个 Claude 托管会话都映射到独立的 `openclaw session-id`
- hook 唤醒不再共享 agent `main` 对话上下文，避免多项目串线
