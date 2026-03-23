# Claude Code Agent

**[English](README_EN.md)** | 中文

让 OpenClaw 像资深操作者一样驱动 Claude Code，而且这次升级后更像一个稳定的“托管层”，不再只是 tmux 小技巧集合。

> 当前发布：`v0.2.0`
> 兼容基线：OpenClaw `2026.3.11+`，Claude Code `2.1.80+`

## 它是什么

这是一个专门给 OpenClaw 使用的 skill。它把 Claude Code 包成托管会话，让 OpenClaw 可以：

- 设计更强的提示词
- 选择合适的模型、effort、权限模式
- 在 tmux 中持续监督 Claude Code
- 通过 Claude 原生 hooks 感知回复、审批等待和 Agent Teams 状态
- 在用户离开电脑时接手，在用户回来时归还控制

## 这次升级后的关键变化

### 1. 不再默认要求全局改 `~/.claude/settings.json`

托管 wrappers 现在会在每次启动时自动生成 Claude managed settings overlay，并通过 `--settings` 注入当前会话。

这意味着：

- 托管会话不再依赖用户手工合并 hooks
- 裸跑 `claude` 不会被意外接管
- skill 的行为更可移植、更可预测

### 2. 每个 Claude 托管会话都有独立 OpenClaw session

之前最危险的设计缺陷是：多个 Claude 会话可能都唤醒到同一个 OpenClaw agent 主会话。

现在的行为是：

- 每个 Claude 托管会话都有独立的 `openclaw session-id`
- hook 唤醒使用显式 `openclaw agent --session-id ...`
- 多项目不会再轻易串上下文

### 3. 知识库同步到当前 Claude Code CLI

本仓库的知识库已经同步到：

- 本机 Claude Code：`2.1.80`
- 查询时 npm 最新：`2.1.81`

补齐了这些新能力认知：

- `--settings`
- `--setting-sources`
- `--session-id`
- `--effort`
- `--plugin-dir`
- `--ide`
- `--no-session-persistence`
- `permission-mode auto`

## v0.2.0 亮点

- 托管 Claude 会话不再共享同一条 OpenClaw agent 主对话
- wrappers 会自动注入 Claude managed settings overlay
- 文档和知识库改成“官方文档 + 本机 CLI 自省”双路径维护
- 回归测试开始覆盖托管路由与 settings 注入这种架构级行为

## 当前主线继续升级中

`v0.2.0` 发布之后，主线已经继续向前推进：

- 托管 overlay 开始接入 `PermissionRequest(Bash)` hook
- OpenClaw 接管后的默认 `permission_policy` 会切到 `safe`
- 一小部分明确安全的 Bash 读操作/检查命令会被自动批准，并写入当前 session 级 permissions
- 明显危险的 Bash 请求会在权限弹窗前被自动拒绝并唤醒 OpenClaw

这意味着“Claude 卡在审批里，OpenClaw 还得靠 tmux 人眼进场点 Yes/No”的频率会进一步下降。

## 工作原理

本项目的核心是三层：

### Claude Code

- 真正执行任务
- 提供 hooks、MCP、worktree、Agent Teams 等能力

### 托管 wrappers

- `hooks/start_claude.sh`
- `hooks/run_claude.sh`
- `runtime/start_local_claude.sh`

它们负责：

- 生成 session metadata
- 注入 managed settings overlay
- 建立 OpenClaw 与 Claude 的托管边界

### OpenClaw

- 理解用户任务
- 设计提示词与策略
- 响应 hook 唤醒
- 在正确的托管会话里继续推进任务

## 托管会话模型

- **裸会话**：用户直接运行 `claude`，本项目不接管
- **OpenClaw 托管会话**：由 wrapper 启动，`controller=openclaw`
- **本地托管会话**：由 `runtime/start_local_claude.sh` 启动，初始 `controller=local`

多会话管理的关键字段：

- `session_key`
- `project_label`
- `tmux_session`
- `cwd`
- `openclaw_session_id`
- `permission_mode`
- `permission_policy`

## 主要脚本

| 脚本 | 作用 |
|------|------|
| `hooks/run_claude.sh` | 一次性托管执行，必须 `-p/--print` |
| `hooks/start_claude.sh` | 启动交互式托管 tmux 会话 |
| `hooks/stop_claude.sh` | 停止托管 tmux 会话 |
| `runtime/start_local_claude.sh` | 启动本地控制、可 handoff 的会话 |
| `runtime/list_sessions.sh` | 列出托管会话 |
| `runtime/session_status.sh` | 查看托管会话详情 |
| `runtime/takeover.sh` | 交给 OpenClaw 接管 |
| `runtime/reclaim.sh` | 切回本地控制 |

## 什么时候适合它

- 你希望 OpenClaw 帮你操作 Claude Code，而不是自己坐在终端前 babysit
- 你需要长任务、迭代任务、多轮审批任务
- 你想保留“随时 tmux attach 介入”的透明度
- 你想让多个 Claude 项目会话稳定并存

## 快速开始

看 [INSTALL.md](INSTALL.md)。

最常用的两种方式：

```bash
# 方式 1：让 OpenClaw 启动托管会话
bash hooks/start_claude.sh claude-demo /path/to/project --permission-mode acceptEdits

# 方式 2：先本地开始，之后 handoff
bash runtime/start_local_claude.sh /path/to/project --permission-mode acceptEdits
bash runtime/takeover.sh my-project
bash runtime/reclaim.sh my-project
```

## 从旧版升级

如果你之前按旧文档做过这些事：

- 在全局 `~/.claude/settings.json` 里手工合并本项目 hooks
- 为了托管会话特意修改 OpenClaw session reset 策略

那么现在都不是托管功能的硬前提了。你可以保留旧配置，但新版本默认依赖 wrapper 的运行时 overlay，而不是全局配置污染。

## 当前状态

- 运行时脚本已升级为独立 OpenClaw session routing
- 托管 settings 注入已经内建到 wrappers
- 回归测试覆盖了：
  - 唤醒去重
  - 质量门禁
  - 歧义 selector 提示
  - `--session-id` 路由
  - managed settings overlay 注入

## 和旧版相比最重要的取舍

旧思路更像“教 OpenClaw 怎么在终端里像人一样点点点”。

现在的思路是：

- Claude Code 继续是执行引擎
- OpenClaw 负责策略和监督
- wrapper 负责托管边界和状态路由

这更像一个稳定产品，而不是一组巧妙脚本。
