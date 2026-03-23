# Claude Code Agent

**[English](README.md)** | 中文

`claude-code-agent` 是一个给 OpenClaw 使用的 skill。它把 Claude Code 包装成可接管、可恢复、可审计的托管会话，补上多会话路由、hook 驱动唤醒、handoff 和审批链这些 OpenClaw 真正需要的运行时能力。

## 它解决什么问题

Claude Code 本身很强，但原生 CLI 更偏向“人坐在终端前盯着跑”。

这个项目补的是托管层：

- 用 wrapper 启动 Claude 会话，而不是直接裸跑 `claude`
- 为每个托管会话生成独立 metadata 和 `--settings` overlay
- 把 Claude hooks 接到 OpenClaw 的消息/唤醒链路
- 支持本地先启动，再交给 OpenClaw 接管
- 保留 `tmux attach` 介入能力，不把状态藏进黑盒

如果你只是想手工使用 Claude Code，这个仓库不是必需的。它主要服务于“OpenClaw 代表用户去操作 Claude Code”这个场景。

## 核心设计

- 不默认要求修改全局 `~/.claude/settings.json`
- 托管会话的 hooks 通过运行时 `--settings` 注入
- 每个 Claude 托管会话都有独立的 `openclaw session-id`
- OpenClaw 只接管 wrapper 启动的托管会话，不碰用户手工裸跑的 `claude`
- 允许用户随时通过 `tmux` 直接接管现场

## 当前能力

- 交互式托管会话：`hooks/start_claude.sh`
- 一次性 print 执行：`hooks/run_claude.sh`
- 本地优先、后续 handoff：`runtime/start_local_claude.sh`
- 会话接管与归还：`runtime/takeover.sh` / `runtime/reclaim.sh`
- 会话注册与状态查询：`runtime/list_sessions.sh` / `runtime/session_status.sh`
- Claude hooks:
  - `Stop`
  - `Notification`
  - `PermissionRequest(Bash)`
  - `TeammateIdle`
  - `TaskCompleted`
- `TaskCompleted` 质量门禁
- 保守的 Bash 审批策略：
  - 明确安全的只读/检查命令可自动批准
  - 明显危险的命令可自动拒绝
  - 其余请求继续走 Claude 默认审批流

## 工作方式

运行时大致分成三层：

1. Claude Code 负责真正执行任务。
2. 本项目的 wrappers 和 hooks 负责托管边界、metadata、路由和唤醒。
3. OpenClaw 负责提示词、策略、推进节奏，以及在正确的 Claude 会话里继续工作。

托管会话里最重要的几个字段是：

- `session_key`
- `project_label`
- `tmux_session`
- `cwd`
- `openclaw_session_id`
- `permission_mode`
- `permission_policy`

## 快速开始

详细安装看 [INSTALL.md](INSTALL.md)。

最常见的三种用法如下。

### 1. 直接启动一个托管的交互式会话

```bash
bash hooks/start_claude.sh claude-demo /path/to/project --permission-mode acceptEdits
tmux attach -t claude-demo
```

### 2. 本地先跑，之后交给 OpenClaw

```bash
bash runtime/start_local_claude.sh /path/to/project --permission-mode acceptEdits
bash runtime/takeover.sh my-project
bash runtime/reclaim.sh my-project
```

### 3. 一次性执行

```bash
bash hooks/run_claude.sh /path/to/project -p --model sonnet "Analyze the repository and summarize the architecture."
```

## 常用脚本

| 脚本 | 作用 |
|------|------|
| `hooks/start_claude.sh` | 启动交互式托管 tmux 会话 |
| `hooks/run_claude.sh` | 启动 print 模式托管执行 |
| `hooks/stop_claude.sh` | 停止托管会话 |
| `runtime/start_local_claude.sh` | 启动本地控制、可 handoff 的会话 |
| `runtime/takeover.sh` | 把现有托管会话交给 OpenClaw |
| `runtime/reclaim.sh` | 把会话切回本地控制 |
| `runtime/list_sessions.sh` | 列出托管会话 |
| `runtime/session_status.sh` | 查看会话详情 |

## 目录结构

| 目录 | 内容 |
|------|------|
| `hooks/` | Claude hook 脚本与启动 wrapper |
| `runtime/` | 会话存储、接管、状态查询等运行时脚本 |
| `tests/` | 回归测试 |
| `knowledge/` | 本项目依赖的 Claude Code / OpenClaw 知识整理 |

## 安装和运行要求

- OpenClaw 可用
- Claude Code 已安装并完成认证
- `tmux`
- `jq`

建议安装后先跑：

```bash
bash tests/regression.sh
```

## 当前版本状态

- 最新 release tag：`v0.2.0`
- 当前 `main` 分支已经继续向前推进，包含 `PermissionRequest` 审批链集成
- 兼容基线：
  - OpenClaw `2026.3.11+`
  - Claude Code `2.1.80+`

变更细节见 [CHANGELOG.md](CHANGELOG.md)。

## 不做什么

- 不尝试替代 Claude Code 本身
- 不默认接管用户手工启动的裸 `claude` 会话
- 不把托管行为偷偷写进所有用户全局配置
- 不承诺对所有 Bash 请求做自动审批；当前策略是故意保守的

## 相关文档

- [INSTALL.md](INSTALL.md)
- [CHANGELOG.md](CHANGELOG.md)
- [SKILL.md](SKILL.md)
- [knowledge/](knowledge)
