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

## 你平时到底怎么用它

日常使用时，你**不需要**先手工跑这些 wrapper 脚本。

你的正常入口应该是**直接和 OpenClaw 对话**，例如：

- “用 `claude-code-agent` 分析 `/path/to/project`。”
- “用 `claude-code-agent` 修复 `/path/to/project` 里的这个 bug，跑完测试再汇报。”
- “用 `claude-code-agent` 审查 `/path/to/project` 当前改动。”
- “用 `claude-code-agent` 对 `/path/to/project` 做一次只读审计。”

然后 OpenClaw 应该自己选择这个 skill，启动或复用一个托管的 Claude Code 会话，并通过 hooks 唤醒的方式继续推进任务。

这个仓库里的 shell 脚本主要用于：

- skill 内部控制面
- 人工排障和恢复
- 你想亲自查看、介入或临时接管某个 Claude 会话时的直接兜底入口

## OpenClaw 的睡眠 / 唤醒模型

是的：在这个设计里，OpenClaw 本来就应该在步骤之间“休眠”，等 Claude Code 通过 hooks 再把它唤醒。

托管流程通常是：

1. OpenClaw 启动或复用一个托管的 Claude Code 会话。
2. Claude Code 在那个会话里继续工作。
3. `Stop`、`Notification`、`PermissionRequest` 之类的 hook 事件唤醒 OpenClaw。
4. OpenClaw 再回到同一个托管会话继续推进，而不是一直盯着终端忙等。

所以它的预期运行方式是“事件驱动”，不是“OpenClaw 永远挂在终端前面盯着 Claude”。

## 人工介入、正式接管、再交还

你可以随时介入，但这里其实有两个不同层级。

### 1. 直接看现场，或临时和 Claude 对话

先 attach 到 tmux：

```bash
tmux attach -t <session-name>
```

这样你就能直接看到正在运行的 Claude Code 会话，也可以临时手动回复。

但这**不等于**正式把所有权从 OpenClaw 手里切走。它只是一次现场介入，不是路由关系变更。

### 2. 正式把控制权从 OpenClaw 切回本地

如果你希望这个会话不再由 OpenClaw 托管，而是明确切回本地控制，请执行：

```bash
bash runtime/reclaim.sh <selector>
```

之后如果你又想把同一个会话正式交还给 OpenClaw：

```bash
bash runtime/takeover.sh <selector>
```

实用记忆法就是：

- `tmux attach` = 查看现场 / 临时人工介入
- `runtime/reclaim.sh` = 正式把控制权切回本地
- `runtime/takeover.sh` = 正式把会话交还给 OpenClaw

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

理解这个项目最快的方式是：

1. 把 skill 安装到 OpenClaw 能发现的位置。
2. 直接让 OpenClaw 使用 `claude-code-agent` 执行任务。
3. 让 OpenClaw 在 Claude hook 唤醒之间休眠等待。
4. 只有在你需要人工查看或改控制权时，才使用 `tmux attach`、`runtime/reclaim.sh`、`runtime/takeover.sh`。

详细安装见 [INSTALL.md](INSTALL.md)。

### OpenClaw 驱动的日常用法

你平时对 OpenClaw 说的话，通常类似：

```text
用 claude-code-agent 分析 /path/to/project。
用 claude-code-agent 修复 /path/to/project 里的 bug，跑完测试再汇报。
用 claude-code-agent 审查 /path/to/project 当前改动。
用 claude-code-agent 对 /path/to/project 做一次只读审计。
```

### 手工兜底：启动交互式托管会话

```bash
bash hooks/start_claude.sh claude-demo /path/to/project --permission-mode acceptEdits
tmux attach -t claude-demo
```

### 手工兜底：本地先跑，之后 handoff

```bash
bash runtime/start_local_claude.sh /path/to/project --permission-mode acceptEdits
bash runtime/takeover.sh my-project
bash runtime/reclaim.sh my-project
```

### 手工兜底：一次性托管执行

```bash
bash hooks/run_claude.sh /path/to/project -p --model sonnet "Analyze the repository and summarize the architecture."
```

### 显式启用 Agent Teams

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
