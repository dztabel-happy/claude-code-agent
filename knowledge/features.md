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
| `claude agents` | 查看配置好的 agents | |
| `claude mcp ...` | MCP 管理 | |
| `claude plugin ...` | 插件管理 | |
| `claude remote-control` | 远程控制 | 本机账号仍未开通 |

## 当前高价值 CLI Flags

### 会话与执行

| Flag | 用途 |
|------|------|
| `-p, --print` | 单次输出后退出 |
| `-c, --continue` | 继续最近会话 |
| `-r, --resume` | 恢复指定会话 |
| `--fork-session` | 恢复时复制出新会话 |
| `--session-id <uuid>` | 显式指定 Claude 会话 ID，必须是合法 UUID |
| `-n, --name <name>` | 指定显示名称 |
| `--max-turns <n>` | 限制轮次，仅 print |
| `--max-budget-usd <n>` | 限制预算，仅 print |
| `--no-session-persistence` | print 模式不保存会话 |

### 权限与工具

| Flag | 用途 |
|------|------|
| `--permission-mode <mode>` | `acceptEdits` / `bypassPermissions` / `default` / `dontAsk` / `plan` / `auto` |
| `--dangerously-skip-permissions` | 跳过权限检查；只适合隔离环境 |
| `--allow-dangerously-skip-permissions` | 允许在会话中提供危险跳权选项 |
| `--allowed-tools` | 预授权工具 |
| `--disallowed-tools` | 禁用工具 |
| `--tools` | 限制内置工具集合 |

### 模型、提示与 agents

| Flag | 用途 |
|------|------|
| `--model <model>` | 指定模型 |
| `--fallback-model <model>` | print 模式备用模型 |
| `--effort <level>` | `low` / `medium` / `high` / `max` |
| `--system-prompt <text>` | 替换系统提示词 |
| `--append-system-prompt <text>` | 追加系统提示词 |
| `--agent <agent>` | 使用一个已配置 agent |
| `--agents <json>` | 会话级定义自定义 agents |
| `--json-schema <schema>` | 结构化输出 |

### 配置与扩展

| Flag | 用途 |
|------|------|
| `--settings <file-or-json>` | 加载额外 settings overlay |
| `--setting-sources <sources>` | 控制加载 `user,project,local` 哪些静态来源 |
| `--mcp-config <configs...>` | 额外 MCP 配置 |
| `--strict-mcp-config` | 只用显式指定的 MCP 配置 |
| `--plugin-dir <path>` | 加载 session 级插件目录 |
| `--add-dir <directories...>` | 添加额外可访问目录 |
| `--ide` | 自动连接 IDE |
| `--chrome` / `--no-chrome` | 启用或禁用 Chrome 集成 |
| `-w, --worktree [name]` | 新建隔离 worktree |
| `--tmux` | worktree 下使用 tmux / iTerm2 panes |

## 当前权限模式理解

| 模式 | 含义 | OpenClaw 使用建议 |
|------|------|------------------|
| `default` | 正常审批流 | 敏感任务默认值 |
| `acceptEdits` | 自动接受文件编辑 | 常规可信仓库首选 |
| `plan` | 只分析不修改 | 只读分析、方案评审 |
| `dontAsk` | 未预授权即拒绝 | 严格白名单环境 |
| `bypassPermissions` | 跳过大部分权限检查 | 仅隔离环境 |
| `auto` | Claude 自主决定策略 | 先小范围观察 |

> 即使是跳权模式，Claude Code 仍有 protected directories 等额外保护概念；不要把“全自动”描述成“任何路径、任何命令都无阻”。

## Hooks：本项目真正依赖的事件

### 默认始终注入

| Hook | 本项目用途 |
|------|-----------|
| `Stop` | Claude 有新回复后更新 metadata 并唤醒 OpenClaw |
| `Notification(permission_prompt)` | 审批等待 |
| `Notification(idle_prompt)` | 等待下一步输入 |
| `PermissionRequest(Bash)` | 对安全 Bash 自动批准、对高风险 Bash 自动拒绝 |

### 只有显式开启 Agent Teams 才注入

| Hook | 本项目用途 |
|------|-----------|
| `TeammateIdle` | teammate 即将空闲时通知 OpenClaw |
| `TaskCompleted` | 团队任务完成与质量门禁 |

官方还提供更多 hooks，例如 `SessionStart`、`SessionEnd`、`PreToolUse`、`PostToolUse`、`PreCompact`。本项目当前没有全部接入。

## Agent Teams

- 文档层仍把 Agent Teams 视为实验 / 灰度能力
- `claude --help` 不会列出所有团队相关实现细节
- 当前 repo 约定：**默认关闭，只有 wrapper 显式传 `--agent-teams` 才启用**
- 不再把 `--teammate-mode` 当成稳定默认依赖

## 本项目自己的托管层能力

Claude 原生支持会话恢复，但本项目额外提供：

- `hooks/start_claude.sh`：启动交互式托管会话
- `hooks/run_claude.sh`：启动 print 托管会话
- `runtime/start_local_claude.sh`：启动本地控制、可 handoff 的托管会话
- `runtime/takeover.sh` / `runtime/reclaim.sh`：在 `local` 和 `openclaw` 间切换控制权

### 关键设计

- wrappers 通过 `--settings` 注入 managed overlay
- 不再把托管 hooks 的正确性建立在用户手工改全局 `~/.claude/settings.json` 上
- 每个托管 Claude 会话映射到独立的 `openclaw session-id`
- hook 唤醒不再共享 agent `main` 对话上下文，避免多项目串线
- OpenClaw 接管时默认启用 `permission_policy=safe`
- Agent Teams 改为显式 opt-in，而不是默认全开
