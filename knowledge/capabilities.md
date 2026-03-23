# 本机能力清单

> OpenClaw 在设计提示词前优先读取本文件，再决定模型、模式、MCP 和会话策略。
> 最后核对：2026-03-23

## 自省命令

```bash
claude --version
claude --help
claude agents
claude mcp list
openclaw --version
openclaw agent --help
codex --version
```

## 当前版本

| 组件 | 当前值 |
|------|--------|
| Claude Code（本机） | `2.1.80` |
| Claude Code（npm 最新） | `2.1.81` |
| OpenClaw CLI（本机） | `2026.3.11` |
| OpenClaw（npm 最新） | `2026.3.22` |
| Codex CLI（本机） | `0.111.0` |

## 可用模型策略

| 模型别名 | 适用场景 |
|---------|---------|
| `haiku` | 非常简单、低成本、短任务 |
| `sonnet` | 默认主力；日常开发、分析、文档 |
| `opus` | 深度推理、架构决策、复杂审计 |

### 思考强度

Claude Code 当前支持 `--effort <level>`：

- `low`
- `medium`
- `high`
- `max`

默认建议：

- 简单任务：`haiku` 或 `sonnet` + `--effort low`
- 常规任务：`sonnet` + `--effort medium`
- 审计 / 架构 / 困难调试：`opus` + `--effort high|max`

## 当前内置 agents（本机 `claude agents` 实测）

| Agent | 说明 |
|-------|------|
| `Explore` | 快速探索代码与上下文 |
| `general-purpose` | 通用代理 |
| `Plan` | 偏规划 / 分析 |
| `statusline-setup` | 状态栏相关内建 agent |

> 不再依赖旧知识里的固定内置 agent 枚举。

## 当前已连接 MCP（本机 `claude mcp list` 实测）

| 服务器 | 用途 |
|--------|------|
| `chrome-devtools` | 浏览器 DevTools 级操作 |
| `chrome-mcp-server` | 浏览器交互与页面读取 |
| `exa` | 语义检索、网页 / 研究类补充 |
| `grok-search` | 实时网络搜索与抓取 |
| `scrape-do` | 强抓取、动态页面、SERP / Amazon |

## 对本 skill 最重要的 Claude Code 能力

| 能力 | 这个 skill 如何使用 |
|------|--------------------|
| `--settings` | 为托管会话动态注入 managed hooks |
| `--setting-sources` | 必要时控制静态配置来源 |
| `-p/--print` | 一次性任务的主入口 |
| tmux 交互式会话 | 多轮任务、handoff、实时监督 |
| hooks | Claude 回复、审批等待的事件驱动唤醒 |
| `--effort` | 根据任务复杂度调推理强度 |
| `--agent` / `--agents` | 会话级 agent 策略 |
| `--worktree` | 并行或隔离型改动 |
| `--chrome` | 浏览器参与的任务 |
| `--json-schema` | 结构化输出 |

## OpenClaw 侧当前可用关键能力

| 能力 | 用法 |
|------|------|
| 显式 session routing | `openclaw agent --session-id <id>` |
| 指定 agent | `openclaw agent --agent <id>` |
| 指定回传通道 | `openclaw agent --deliver --channel <channel>` |
| 主动消息发送 | `openclaw message send --channel ... --target ... --message ...` |
| skills 目录 | `~/.openclaw/skills` 与 `~/.openclaw/workspace/skills` |

## 托管会话策略

### 默认推荐

| 场景 | 推荐方式 |
|------|---------|
| 明确的一次性任务 | `hooks/run_claude.sh` + `claude -p` |
| 多轮交互或复杂迭代 | `hooks/start_claude.sh` |
| 用户先本地用、之后再 handoff | `runtime/start_local_claude.sh` |
| 大型、确实可并行的任务 | 显式 `--agent-teams` |

### 权限模式建议

| 场景 | 建议 |
|------|------|
| 常规可信仓库 | `acceptEdits` |
| 审计 / 方案设计 | `plan` |
| 受控自动化 | `dontAsk` + `--allowed-tools` |
| 完全隔离环境 | 只在明确授权时用 `--dangerously-skip-permissions` |

## 当前已知限制

- `claude remote-control` 在本机账号上仍提示“not yet enabled for your account”
- Agent Teams 文档仍在演进，CLI `--help` 与文档并不完全同步
- `auto` permission mode 已出现，但还需要更多实测
- 本 repo 当前没有把 Codex / Claude 的多 agent 生态直接接成统一运行时，只吸收了“聚焦 skill、简单默认值、显式 opt-in”的设计原则
