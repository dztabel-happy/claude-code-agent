# 本机能力清单

> OpenClaw 在设计提示词前优先读取本文件，再决定模型、模式、MCP、会话策略。
> 最后核对：2026-03-23

## 自省命令

```bash
claude --version
claude --help
claude agents
claude mcp list
openclaw agent --help
```

## 当前版本

| 组件 | 当前值 |
|------|--------|
| Claude Code | `2.1.80` |
| OpenClaw CLI | `2026.3.11` |
| npm 上 Claude Code 最新版本（查询时） | `2.1.81` |

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
- 审计/架构/困难调试：`opus` + `--effort high|max`

## 当前内置 agents（本机 `claude agents` 实测）

| Agent | 说明 |
|-------|------|
| `Explore` | 快速探索代码与上下文 |
| `general-purpose` | 通用代理 |
| `Plan` | 偏规划/分析 |
| `statusline-setup` | 状态栏相关内建 agent |

> 旧知识里把内置 agents 写成 `Explore / Plan / Bash`。当前本机实测已不一致，不要继续依赖旧枚举。

## 当前已连接 MCP（本机 `claude mcp list` 实测）

| 服务器 | 用途 |
|--------|------|
| `chrome-devtools` | 浏览器 DevTools 级操作 |
| `chrome-mcp-server` | 浏览器交互与页面读取 |
| `exa` | 语义检索、网页/研究类补充 |
| `grok-search` | 实时网络搜索与抓取 |
| `scrape-do` | 强抓取、动态页面、SERP/Amazon |

## 对本 skill 最重要的 Claude Code 能力

| 能力 | 这个 skill 如何使用 |
|------|--------------------|
| `--settings` | 为托管会话动态注入 hooks 与 Agent Teams 环境 |
| `--session-id` | OpenClaw 侧用显式 session id 做一对一路由 |
| `-p/--print` | 一次性任务的主入口 |
| tmux 交互式会话 | 多轮任务、handoff、实时监督 |
| hooks | Claude 回复、审批等待、团队状态的事件驱动唤醒 |
| `--effort` | 根据任务复杂度调推理强度 |
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

## 托管会话策略

### 默认推荐

| 场景 | 推荐方式 |
|------|---------|
| 明确的一次性任务 | `hooks/run_claude.sh` + `claude -p` |
| 多轮交互或复杂迭代 | `hooks/start_claude.sh` |
| 用户先本地用、之后再 handoff | `runtime/start_local_claude.sh` |
| 多模块并行 / 高风险 | `--worktree` 或 Agent Teams |

### 权限模式建议

| 场景 | 建议 |
|------|------|
| 常规可信仓库 | `acceptEdits` 或 `default` |
| 完全隔离环境 | `--dangerously-skip-permissions` |
| 审计/方案设计 | `plan` |
| 受控自动化 | `dontAsk` + `--allowed-tools` |

## 当前已知限制

- `claude remote-control` 在本机账号上仍提示“not yet enabled for your account”
- Agent Teams 文档仍在演进，CLI `--help` 与文档并不完全同步
- `auto` permission mode 已出现，但还需要更多实测才能决定是否作为默认策略
