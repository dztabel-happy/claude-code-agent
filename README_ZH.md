# Claude Code Agent

**[English](README.md)** | 中文

`claude-code-agent` 是一个给 OpenClaw 使用的 skill。它把 Claude Code 包装成可托管、可恢复、可审计的运行时，而不是一段必须人工盯着的终端会话。

它补上的能力主要是：

- wrapper 启动的 Claude 会话
- 每会话独立 metadata 和路由
- Claude hooks 驱动的 OpenClaw 唤醒
- 本地先跑、之后 handoff / reclaim
- 需要时可直接 `tmux attach`

## 它是什么

这个仓库服务于“OpenClaw 代表用户去驱动 Claude Code”这个场景。

它不是 Claude Code 的替代品，也不会默认去接管用户手工裸跑的 `claude` 会话。

## 设计目标

- 托管会话不要求用户先改全局 `~/.claude/settings.json`
- 每个托管 Claude 会话对应独立的 OpenClaw session
- 默认流程尽量简单
- 实验能力必须显式 opt-in
- 审批自动化保持保守

## 当前运行时模型

运行时分三层：

1. Claude Code 真正执行任务。
2. 本仓库负责 wrapper、session state、hooks 和路由。
3. OpenClaw 负责策略、推进和接收 hook 唤醒。

托管会话里最重要的字段包括：

- `session_key`
- `project_label`
- `tmux_session`
- `cwd`
- `openclaw_session_id`
- `permission_mode`
- `permission_policy`
- `agent_teams_enabled`

## 当前能力

### 托管会话

- `hooks/start_claude.sh`：启动交互式托管会话
- `hooks/run_claude.sh`：启动 print 模式托管执行
- `runtime/start_local_claude.sh`：本地优先启动，后续可 handoff

### 会话控制

- `runtime/takeover.sh`：把托管会话交给 OpenClaw
- `runtime/reclaim.sh`：把会话切回本地控制
- `runtime/list_sessions.sh` / `runtime/session_status.sh`：查看会话状态

### Hooks

默认始终注入：

- `Stop`
- `Notification`
- `PermissionRequest(Bash)`

只有显式启用 Agent Teams 才注入：

- `TeammateIdle`
- `TaskCompleted`

### Bash 审批链

当前策略是故意保守的：

- 明确安全的只读 / 校验型 Bash 可自动批准
- 明显危险的 Bash 可自动拒绝
- 其余请求继续走 Claude 默认审批流

## 更简单的默认值

- 单次任务优先 `run_claude.sh`
- 常规可信仓库优先 `--permission-mode acceptEdits`
- 只读分析优先 `--permission-mode plan`
- `--dangerously-skip-permissions` 视为特殊模式，不作为默认建议
- Agent Teams 默认关闭，只有显式传 `--agent-teams` 才开启

## 快速开始

详细安装见 [INSTALL.md](INSTALL.md)。

### 1. 启动交互式托管会话

```bash
bash hooks/start_claude.sh claude-demo /path/to/project --permission-mode acceptEdits
tmux attach -t claude-demo
```

### 2. 本地先跑，之后 handoff

```bash
bash runtime/start_local_claude.sh /path/to/project --permission-mode acceptEdits
bash runtime/takeover.sh my-project
bash runtime/reclaim.sh my-project
```

### 3. 一次性执行

```bash
bash hooks/run_claude.sh /path/to/project -p --model sonnet "Analyze the repository and summarize the architecture."
```

### 4. 显式启用 Agent Teams

```bash
bash hooks/start_claude.sh claude-team /path/to/project --permission-mode acceptEdits --agent-teams
```

## 安装说明摘要

这个项目可以安装在：

- `~/.openclaw/skills/claude-code-agent`，适合作为共享 skill
- `~/.openclaw/workspace/skills/claude-code-agent`，适合作为 workspace 内副本

wrappers 本身不依赖硬编码安装路径。

如果你想给**非托管裸会话**额外挂全局 hooks，可把 [hooks/hooks_config.json](hooks/hooks_config.json) 当模板使用，并先把其中的 `__SKILL_DIR__` 替换成真实绝对路径。

## 目录结构

| 目录 | 内容 |
|------|------|
| `hooks/` | Claude hook 脚本与启动 wrapper |
| `runtime/` | 会话存储、接管、状态查询等运行时脚本 |
| `tests/` | 回归测试 |
| `knowledge/` | Claude Code / OpenClaw 相关知识整理 |

## 运行要求

- OpenClaw 可用
- Claude Code 已安装并完成认证
- `tmux`
- `jq`

建议安装后先跑：

```bash
bash tests/regression.sh
```

## 当前状态

- 最新 release tag：`v0.2.0`
- 当前 `main` 分支包含面向“更简单默认值”的整理
- 兼容基线：
  - OpenClaw `2026.3.11+`
  - Claude Code `2.1.80+`

变更见 [CHANGELOG.md](CHANGELOG.md)。

## 不做什么

- 不尝试替代 Claude Code 本身
- 不默认接管用户手工裸跑的 `claude`
- 不偷偷修改所有全局 Claude 配置
- 不对所有 Bash 请求做自动审批
- 不默认给每个托管会话都打开 Agent Teams

## 相关文档

- [INSTALL.md](INSTALL.md)
- [CHANGELOG.md](CHANGELOG.md)
- [SKILL.md](SKILL.md)
- [knowledge/](knowledge)
