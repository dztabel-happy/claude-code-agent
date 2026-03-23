---
name: claude-code-agent
description: "把 Claude Code 作为 OpenClaw 可托管运行时来使用。负责启动、监督和通过对话控制 Claude Code 托管会话，并利用 hooks、tmux 和显式 session routing 持续推进复杂任务。适用于复杂、多轮、可验证任务；不适用于简单读写或直接问答。"
metadata: {"openclaw":{"requires":{"bins":["bash","jq","tmux","claude","openclaw"]}}}
---

# Claude Code Agent

这个 skill 的职责很单一：**让 OpenClaw 以可托管、可恢复、可审计的方式驱动 Claude Code**。

它不是通用百科，也不是“任何事都先开 Claude”。优先用它处理：

- 复杂、多轮、需要持续监督的任务
- 需要 tmux 介入、handoff / reclaim 的任务
- 需要 Claude hooks 唤醒 OpenClaw 的任务
- 需要把多个 Claude 托管会话和多个 OpenClaw 上下文严格隔离的任务

不要用它处理：

- 简单单行编辑
- 只读文件查看
- 直接回答型问题

## 核心原则

- 只接管**托管会话**，不碰用户手工裸跑的 `claude`
- 每个托管会话都必须有独立的 `openclaw session-id`
- 默认不要求用户改全局 `~/.claude/settings.json`
- 默认不启用 Agent Teams
- 默认不推荐 `--dangerously-skip-permissions`

## 默认策略

### 会话策略

- 单次任务：优先 `hooks/run_claude.sh` + `-p`
- 多轮任务：优先 `hooks/start_claude.sh`
- 用户先本地做：用 `runtime/start_local_claude.sh`
- 已有托管会话的查看 / 接管 / 归还 / 停止：优先 `runtime/control_session.sh`

### 权限策略

- 只读分析：`--permission-mode plan`
- 常规可信仓库：`--permission-mode acceptEdits`
- 敏感任务：Claude 默认审批流
- `--dangerously-skip-permissions` 只在**用户明确要求且环境隔离可信**时使用

### 并行策略

- 默认关闭 Agent Teams
- 只有任务天然可并行、且收益明显时，才显式加 `--agent-teams`

## 常用命令

### 新建一次性任务

```bash
bash {baseDir}/hooks/run_claude.sh <workdir> \
  -p --permission-mode acceptEdits "<prompt>"
```

### 新建交互式托管会话

```bash
bash {baseDir}/hooks/start_claude.sh claude-<name> <workdir> \
  --permission-mode acceptEdits
```

### 显式启用 Agent Teams

```bash
bash {baseDir}/hooks/start_claude.sh claude-<name> <workdir> \
  --permission-mode acceptEdits \
  --agent-teams
```

### 本地先启动，后续 handoff

```bash
bash {baseDir}/runtime/start_local_claude.sh <workdir> \
  --permission-mode acceptEdits
```

### 对话式控制已有会话

```bash
bash {baseDir}/runtime/control_session.sh list
bash {baseDir}/runtime/control_session.sh status [selector]
bash {baseDir}/runtime/control_session.sh reclaim [selector]
bash {baseDir}/runtime/control_session.sh takeover [selector]
bash {baseDir}/runtime/control_session.sh stop [selector]
```

### 低层脚本（仅在排障或特殊场景下）

```bash
bash {baseDir}/runtime/list_sessions.sh
bash {baseDir}/runtime/session_status.sh <selector>
bash {baseDir}/runtime/takeover.sh <selector>
bash {baseDir}/runtime/reclaim.sh <selector>
bash {baseDir}/hooks/stop_claude.sh <selector>
```

## 对话意图映射

当用户不是在“新开一个 Claude 任务”，而是在“控制已有托管会话”时，优先按自然语言意图映射：

- “切回本地 / 我来接手 / 先别由你托管” -> `runtime/control_session.sh reclaim`
- “继续交给你 / 恢复托管 / 你继续跑刚才那个会话” -> `runtime/control_session.sh takeover`
- “看看现在有哪些 Claude 会话” -> `runtime/control_session.sh list`
- “看看当前会话状态” -> `runtime/control_session.sh status`
- “把那个会话停掉” -> `runtime/control_session.sh stop`

## 处理已有会话时

按这个顺序：

1. 优先用 `runtime/control_session.sh`
2. 如果用户给了项目路径、session 名、tmux 名，直接当 selector 传入
3. 如果用户说“当前这个 / 刚才那个 / 这个项目”，先尝试**不带 selector**调用 `runtime/control_session.sh <action>`
4. 只有脚本返回歧义时，才向用户追问要操作哪个会话
5. 仅在 `runtime/control_session.sh` 不足以表达需求时，才退回低层脚本

## 执行工作流

### 1. 理解需求

- 明确目标、范围、验收标准
- 只在关键决策点打断用户
- 如果存在大方向风险，再请求确认

### 2. 读取最少必要知识

按需读，不要全量灌入：

| 文件 | 何时读取 |
|------|---------|
| `knowledge/features.md` | 需要查 Claude Code CLI / hooks / permissions |
| `knowledge/config_schema.md` | 需要调 settings / hooks / overlay |
| `knowledge/capabilities.md` | 需要看本机实际版本、MCP、默认策略 |
| `knowledge/prompting_patterns.md` | 需要设计复杂提示词 |
| `knowledge/UPDATE_PROTOCOL.md` | 需要更新知识库 |
| `knowledge/changelog.md` | 需要判断近期变化 |

### 3. 选择执行模式

- 优先简单路径，不要先上交互式和团队模式
- 能一次完成就用 print
- 需要持续观察才用 tmux 会话
- 只有明确并行收益时才开 `--agent-teams`

### 4. 设计高质量提示词

提示词应包含：

- 任务边界
- 项目上下文
- 必要的工具或 MCP
- 完成条件
- 验证要求

### 5. 启动并监督

- 启动后优先看 hook 回调
- hook 长时间没动静时，再看 tmux pane
- 用户要求“切回本地”时，不要建议他先去终端；优先直接执行 `runtime/control_session.sh reclaim`
- 用户要求“继续交给 OpenClaw”时，不要要求他自己跑脚本；优先直接执行 `runtime/control_session.sh takeover`
- 交互式会话里发送文本与 `Enter` 要分开

```bash
tmux send-keys -t claude-<name> '<prompt>'
sleep 1
tmux send-keys -t claude-<name> Enter
```

### 6. 验证后再汇报

只在确认输出没问题后再向用户汇报：

- 完成状态
- 关键变更
- 风险与注意事项

如果发现方向性偏差或架构需要大改，先暂停并征求用户确认。

## Agent Teams 规则

- 默认关闭
- 必须显式使用 `--agent-teams`
- 仅在大任务、可并行、职责可切分时使用
- 不要为单文件修改、简单修 bug、强顺序依赖任务启用

如果启用了 Agent Teams：

- `TeammateIdle` 与 `TaskCompleted` hooks 会自动注入
- 可选质量门禁通过 `OPENCLAW_TASK_COMPLETED_GATE=/abs/path/to/gate.sh` 开启

## 安全规则

1. 不在 OpenClaw workspace 的 live 仓库里乱切分支
2. 不默认接管用户手工裸跑的 `claude`
3. 不默认要求用户改全局 Claude hooks
4. `--dangerously-skip-permissions` 只在明确授权且环境隔离时使用
5. 修改 Claude settings 前先读 `knowledge/config_schema.md`
6. hook 唤醒 OpenClaw 时，必须使用托管会话自己的 `openclaw session-id`

## 可选的全局 hooks 配置

如果用户明确要求“让裸跑 `claude` 也带这些 hooks”，再参考：

- `hooks/hooks_config.json`
- `INSTALL.md`
- `knowledge/config_schema.md`

注意：

- `hooks/hooks_config.json` 里的 `__SKILL_DIR__` 需要替换成实际绝对路径
- 这个动作是**可选增强**，不是托管会话的必需前提
