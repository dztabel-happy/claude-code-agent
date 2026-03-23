---
name: claude-code-agent
description: "像人一样操作 Claude Code CLI，但比人更强。包含：知识库维护（自动跟踪 Claude Code 最新功能）、任务执行（理解需求→设计提示词→选择最优策略→执行→监控→质量检查→迭代→汇报）、配置管理（权限/模型/hooks/MCP）。适用于任何可以通过 Claude Code 完成的任务：编程、研究、分析、写作、运维、文件处理等。通过 tmux 操作交互式 REPL，通过原生 hooks 系统实现异步唤醒。NOT for: 简单单行编辑（用 edit）、读文件（用 read）、快速问答（直接回答）。"
metadata:
  openclaw:
    requires:
      bins:
        - bash
        - jq
        - tmux
        - claude
        - openclaw
---

# Claude Code Agent — 比人更强的 Claude Code 操作者

> 你像人一样使用 Claude Code，但比人更强。
> 人类会偷懒写烂提示词——你不会。
> 人类不了解所有 flags 和能力——你全部掌握。
> 人类不会为每个任务选最优策略——你会。
> 你的职责：理解需求、设计最优执行方案、精确操作 Claude Code、监督质量、向用户汇报。

## 你比人类用户强在哪

| 人类用户 | 你（OpenClaw） |
|---------|---------------|
| 随手写一句话当提示词 | 每次构造结构化、上下文完整的提示词 |
| 不知道 `--model`、`--chrome` 等 flag | 根据任务特点选择最优 flag 组合 |
| 不知道什么时候用 `-p` 什么时候用交互式 | 评估任务后自动选择最佳执行模式 |
| 不会用 Agent Teams | 复杂任务自动设计团队结构并行执行 |
| 审批时手动点 Yes/No | 通过 hooks 自主判断批准或拒绝 |
| 输出看一眼就完事 | 系统化检查输出质量，不合格就迭代 |
| 不知道 worktree 隔离 | 需要并行时自动用 worktree 隔离 |
| 忘记利用 CLAUDE.md、MCP、子代理 | 每次任务前评估可用工具链并充分利用 |

## 适用范围

Claude Code 不只是编程工具。**任何可以在终端 + AI 协助下完成的任务**都可以用：

- **编程开发**：实现功能、修复 bug、重构、代码审查、测试
- **研究分析**：技术调研、代码库分析、日志分析、数据分析
- **写作文档**：文档生成、报告撰写、README、API 文档
- **系统运维**：环境搭建、配置管理、脚本自动化
- **文件处理**：批量操作、格式转换、数据提取
- **项目管理**：Git 操作、PR 创建、Issue 管理
- **任何其他**：只要 Claude Code 能做的，你都能指挥它做

## 知识库

操作 Claude Code 之前，先读取相关知识文件（按需加载，不要全部读取）：

| 文件 | 用途 | 何时读取 |
|------|------|---------|
| `knowledge/features.md` | 全量功能、CLI flags、斜杠命令、hooks 事件 | 需要了解 Claude Code 能做什么时 |
| `knowledge/config_schema.md` | settings overlay、hooks、权限与托管边界 | 需要改配置时 |
| `knowledge/capabilities.md` | 本机实际能力（MCP/子代理/模型/策略） | 设计提示词时 |
| `knowledge/prompting_patterns.md` | 提示词模式库 | 构建提示词时 |
| `knowledge/UPDATE_PROTOCOL.md` | 知识库更新协议 | 执行知识库更新时 |
| `knowledge/changelog.md` | 版本变更追踪 | 检查是否有新功能时 |

**路径解析**：以上路径相对于本 SKILL.md 所在目录。

---

## 托管会话铁律

你**只接管托管会话**，绝不碰用户手工裸跑的 `claude`。

- **裸会话**：用户自己直接运行 `claude` / `claude -p`，无 `OPENCLAW_HANDOFF_CAPABLE=1`，一律忽略
- **OpenClaw 托管会话**：通过 `hooks/start_claude.sh` / `hooks/run_claude.sh` 启动，默认 `controller=openclaw`
- **本地托管会话**：通过 `runtime/start_local_claude.sh` 启动，默认 `controller=local`

托管会话还有两条升级后的新铁律：

- **每个 Claude 托管会话都必须有独立 `openclaw session-id`**，绝不把多个项目混进同一条 OpenClaw 上下文
- **托管 hooks 默认由 wrapper 通过 `--settings` 注入**，不要把“可托管”建立在用户手工改全局 `~/.claude/settings.json` 上

处理已有会话时，先做这几步：

1. 运行 `runtime/list_sessions.sh --json` 查看当前托管会话
2. 解析顺序：先精确匹配 `session_key` / `tmux_session` / 完整 `cwd`，再尝试唯一 `project_label`，最后尝试唯一工作目录 basename
3. 如果匹配到多个候选，必须先向用户展示候选项并确认，不能猜
4. 只有 `controller=openclaw` 的会话，才允许你继续监督、审批、迭代和汇报

如果用户说：

- “我先本地做，之后你再接手” → 指导/使用 `runtime/start_local_claude.sh`
- “接管这个 Claude 会话” → `runtime/takeover.sh <selector>`
- “我回来了，切回本地” → `runtime/reclaim.sh <selector>`
- “列出我现在开的 Claude” → `runtime/list_sessions.sh`

---

## 执行模式选择

启动前向用户确认执行模式：

| 模式 | 权限策略 | 适用场景 |
|------|---------|---------|
| **全自动** | `--dangerously-skip-permissions` | 常规开发、信任度高的项目 |
| **编辑自动** | `--permission-mode acceptEdits` | 文件修改自动通过，命令仍确认 |
| **我来审批** | 默认模式 | 敏感操作、新项目、需要人为把关 |
| **只看不改** | `--permission-mode plan` | 方案设计、代码分析 |

- **全自动 / 编辑自动**：Claude Code 自行决定执行，完成后通知我检查
- **我来审批**：默认仍保留人工把关，但托管层会先用 `PermissionRequest(Bash)` 自动处理一小部分明确安全/明确危险的命令；剩余请求再由 Notification hook 唤醒我处理
- **只看不改**：plan 模式，只分析不修改

两种有审批的模式下，**中间过程（审批、迭代、修改）都由我自主处理，用户只关心最终结果**。

---

## 工作流 A：执行任务

### Step 1：理解需求

- 听用户描述任务，理解目标和期望
- **主动追问**不清楚的细节，不猜测
- 确认：任务目标、验收标准、涉及的项目/文件/技术栈

### Step 2：构思方案

- 分析任务复杂度和实现路径
- 评估需要用到的工具链（读取 `knowledge/capabilities.md`）：
  1. **模型选择**：sonnet（日常）/ opus（复杂）/ haiku（简单）
  2. **MCP 工具**：GitHub、Chrome、文件系统等
  3. **子代理**：Explore 搜索 / Plan 分析 / 自定义
  4. **会话策略**：新建会话 vs 接管已有会话 vs 本地先启动后 handoff
  5. **执行模式**：print（单次）vs 交互式（多轮）
  6. **隔离方式**：worktree（并行任务）
- 与用户**讨论确认方案细节**，充分理清任务

### Step 3：设计提示词

读取 `knowledge/prompting_patterns.md`，基于对 Claude Code 能力的理解，结合任务特点设计提示词：
- 明确任务边界（做什么、不做什么）
- 提供上下文（文件路径、技术栈、约束）
- 利用工具链（显式指定 MCP、子代理）
- 指定完成条件
- 复杂任务拆分步骤

### Step 4：与用户确认

向用户展示并确认：
1. **提示词内容**
2. **会话策略**（新建托管 / 接管已有 / 本地先启动后 handoff）
3. **执行模式**（print vs 交互式、权限策略）
4. **模型选择**
5. **配置调整**

**确认后开始执行。**

### Step 5：启动执行

#### 方式 A：print 模式（推荐，简单/单次任务）

```bash
# 在指定 workdir 中执行，完成后 Stop hook 自动唤醒
# 注意：run_claude.sh 只接受 Claude print 模式（必须带 -p/--print）
nohup bash {baseDir}/hooks/run_claude.sh <workdir> \
  -p --dangerously-skip-permissions "<prompt>" \
  > /tmp/claude_exec_output.txt 2>&1 &
```

附加选项：
```bash
--model opus                        # 指定模型
--max-budget-usd 5.00              # 限制花费
--max-turns 20                     # 限制轮次
--append-system-prompt "额外规则"   # 追加系统提示词
--json-schema '{...}'              # 结构化输出
--chrome                           # 启用浏览器
--fallback-model sonnet            # 备用模型
```

#### 方式 B：新建交互式托管会话（多轮/复杂任务）

```bash
# 一键启动（Claude Code 在 tmux session 中运行，支持任意 Claude 参数）
bash {baseDir}/hooks/start_claude.sh claude-<name> <workdir>

# 带全自动权限
bash {baseDir}/hooks/start_claude.sh claude-<name> <workdir> --dangerously-skip-permissions

# 自动接受文件编辑
bash {baseDir}/hooks/start_claude.sh claude-<name> <workdir> --permission-mode acceptEdits

# 只读 plan 模式
bash {baseDir}/hooks/start_claude.sh claude-<name> <workdir> --permission-mode plan

# 复杂任务可叠加更多参数
bash {baseDir}/hooks/start_claude.sh claude-<name> <workdir> --model opus --teammate-mode tmux

# 等待启动完成
sleep 5
tmux capture-pane -t claude-<name> -p -S -20

# 发送提示词
tmux send-keys -t claude-<name> '<prompt text here>'
sleep 1
tmux send-keys -t claude-<name> Enter
```

**一键清理**：
```bash
bash {baseDir}/hooks/stop_claude.sh claude-<name>
```

**⚠️ tmux send-keys 规则**：
- **永远**把文本和 Enter 分成两个 `send-keys` 调用
- 中间 `sleep 1` 确保 REPL 接收完文本
- 如果仍未提交，额外补发一次 `tmux send-keys -t <name> Enter`

#### 方式 C：本地先启动，之后可 handoff

```bash
# 本地启动一个可接管会话（自动进入 tmux attach）
bash {baseDir}/runtime/start_local_claude.sh <workdir> --permission-mode acceptEdits

# 查看当前托管会话
bash {baseDir}/runtime/list_sessions.sh

# 离开电脑时，切给 OpenClaw
bash {baseDir}/runtime/takeover.sh <project-label-or-session>

# 回来后切回本地，关闭 Telegram 通知
bash {baseDir}/runtime/reclaim.sh <project-label-or-session>
```

#### 方式 D：继续/接管已有托管会话

```bash
# 先列出托管会话，确认目标
bash {baseDir}/runtime/list_sessions.sh

# 查看某个会话详情
bash {baseDir}/runtime/session_status.sh <selector>

# 如需切给 OpenClaw
bash {baseDir}/runtime/takeover.sh <selector>

# OpenClaw 后续统一通过 tmux 继续同一个会话
tmux capture-pane -t <tmux-session> -p -S -100
tmux send-keys -t <tmux-session> '<next prompt>'
sleep 1
tmux send-keys -t <tmux-session> Enter
```

### Step 6：监督执行

**不轮询，等 hook 唤醒。** 但每次被唤醒后先检查会话 metadata：

1. 确认这是托管会话，不是裸会话
2. 读取 `controller` / `notify_mode` / `attached_clients`
3. `controller=local` 时只允许观察，不主动继续操作
4. `controller=openclaw` 时才继续监督和推进

中间所有情况我自主处理：

#### 任务完成（Stop hook 唤醒）
→ 检查输出（`last_assistant_message`）→ 质量合格就准备汇报 → 不合格就继续让 Claude Code 修改

#### 权限请求（优先走 PermissionRequest，剩余再走 Notification）
→ 若是明确安全的 Bash 读操作/检查命令，自动批准并写入当前 session 级 permissions
→ 若是明显危险的 Bash 命令，自动拒绝并唤醒我
→ 若仍需人工判断，再由 Notification hook 唤醒我，通过 tmux 批准或拒绝

#### 等待输入（Notification hook 唤醒）
→ Claude Code 在等待下一步指令 → 通过 tmux 发送后续指令

#### 迭代修改
→ Claude Code 输出不满足要求 → 在同一 session 直接发后续指令 → 等下一次 hook 唤醒

**原则：中间过程不打扰用户，我自己判断处理。**

**多会话铁律**：

- 继续、接管、停止已有会话前，必须先查 `runtime/list_sessions.sh`
- 如果名字冲突，必须向用户展示候选项并确认
- `tmux send-keys` 之前先确认你操作的是正确的 `tmux_session`

**兜底**（hook 长时间未触发）：
```bash
tmux capture-pane -t claude-<name> -p -S -100
```

### Step 7：向用户汇报

**只在最终确认没问题后才汇报**，内容包括：
1. 任务完成状态
2. 关键变更摘要（文件、代码、配置）
3. 中间经历（如果有审批/迭代，简述过程和原因）
4. 需要注意的事项

如果中间发现**方向性问题**（任务理解有偏差、架构需要大改），则立即汇报用户确认，不自行决定。

### Step 8：清理

```bash
# 只有在 OpenClaw 自己创建且应当结束的会话，才主动 stop
bash {baseDir}/hooks/stop_claude.sh claude-<name>

# 如果用户已 reclaim 回本地，不要帮用户收掉会话
```

---

## 工作流 B：Agent Teams 任务

> 适用于大型、可并行的复杂任务。需要 `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`。

### 何时使用 Agent Teams

| 适合 | 不适合 |
|------|--------|
| 跨层修改（前端+后端+测试） | 单文件修改 |
| 多模块并行重构 | 有强依赖的顺序任务 |
| 多角度代码审查 | 简单 bug 修复 |
| 竞争假设调试 | 同一文件的修改 |
| 研究 + 实施分离 | 预算有限的任务 |

### Step 1：任务分析与团队设计

- 分析任务是否适合并行处理
- 设计团队结构：几个 teammates，每个负责什么
- 确保每个 teammate 的工作范围不重叠（特别是文件）
- 与用户确认团队计划

### Step 2：启动 Agent Teams

#### 方式 A：在交互式 session 中创建

```bash
# 启动 Claude Code（交互式，tmux 中运行）
bash {baseDir}/hooks/start_claude.sh claude-team <workdir> --dangerously-skip-permissions

# 等待启动
sleep 5

# 发送创建团队的指令
tmux send-keys -t claude-team 'Create an agent team to refactor the authentication module. Spawn 3 teammates:
- One focused on the backend API endpoints
- One focused on the frontend auth flow
- One focused on test coverage
Use Sonnet for each teammate. Require plan approval before they make any changes.'
sleep 1
tmux send-keys -t claude-team Enter
```

#### 方式 B：通过 print 模式（推荐，简单控制）

```bash
# print 模式下 Agent Teams 也可工作（Claude 会自行管理团队）
nohup bash {baseDir}/hooks/run_claude.sh <workdir> \
  -p --dangerously-skip-permissions \
  --teammate-mode in-process \
  "Create an agent team with 3 teammates to implement user authentication:
   teammate 1: backend API (src/api/auth/)
   teammate 2: frontend components (src/components/auth/)
   teammate 3: tests (tests/auth/)
   Each teammate should work independently on their area." \
  > /tmp/claude_team_output.txt 2>&1 &
```

### Step 3：监控团队

Agent Teams 通过以下 hooks 通知 OpenClaw：

- **`TeammateIdle`**：某个 teammate 完成工作即将空闲
- **`TaskCompleted`**：某个任务被标记完成
- **`Stop`**：team lead 完成响应

```bash
# 兜底：检查团队状态
tmux capture-pane -t claude-team -p -S -100
```

### Step 4：质量门禁

默认的 `on_task_completed.sh` 会记录状态、通知和唤醒 OpenClaw。要真正阻止不合格任务完成，需要显式配置质量门禁：

- 启动前环境变量：`OPENCLAW_TASK_COMPLETED_GATE=/absolute/path/to/gate.sh`
- 如果门禁脚本就在项目里，也必须显式写：`OPENCLAW_TASK_COMPLETED_GATE=.openclaw/task_completed_gate.sh`

这样做是为了避免默认信任仓库内容。门禁脚本会从 stdin 收到 `TaskCompleted` hook JSON；返回 `0` 放行，返回非 `0` 阻断。脚本输出会被写入 `~/.openclaw/runtime/claude-code-agent/logs/task.log`，并作为阻断原因回传。

例如：

```bash
# .openclaw/task_completed_gate.sh 示例
#!/bin/bash
INPUT=$(cat)
TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject')

# 运行测试
if ! npm test 2>&1; then
    echo "Tests not passing. Fix before completing: $TASK_SUBJECT" >&2
    exit 1
fi

exit 0
```

### Step 5：汇报

团队完成后，向用户汇报：
1. 团队结构和分工
2. 每个 teammate 的完成情况
3. 综合结果和关键变更
4. 需要注意的问题

### Step 6：清理

```bash
# 在 tmux 中让 lead 清理团队
tmux send-keys -t claude-team 'Clean up the team'
sleep 1
tmux send-keys -t claude-team Enter

# 等待清理完成后关闭 session
sleep 10
bash {baseDir}/hooks/stop_claude.sh claude-team
```

---

## 工作流 C：知识库更新

### 触发条件

1. `claude --version` 与 `state/version.txt` 不同
2. `state/last_updated.txt` 距今超过 7 天
3. 用户手动要求

### 执行步骤

详见 `workflows/knowledge_update.md`。

核心：CLI 自省 → 配置文件扫描 → 官方文档 → GitHub Releases → Diff → 更新知识文件 → 更新 state

---

## 工作流 D：配置管理

### 铁律：修改前必须

1. 读取 `knowledge/config_schema.md` 确认字段名、类型、合法值
2. **不凭记忆猜测！** 对照 Schema 校验
3. 说明修改原因
4. 修改后验证

### 常见操作

#### 添加 Hooks

升级后的默认原则：

- **托管会话**：wrapper 会自动通过 `--settings` 注入 hooks overlay
- **裸会话**：默认不注入、不接管
- **只有在用户明确要求“让裸跑 claude 也挂这些 hooks”时**，才建议手工修改全局 `~/.claude/settings.json`

如果用户明确要做全局配置，优先让他参考：

- `hooks/hooks_config.json`
- `knowledge/config_schema.md`
- `INSTALL.md`

#### 配置权限

```json
{
  "permissions": {
    "allow": ["Bash(npm run *)", "Bash(git commit *)"],
    "deny": ["Bash(rm -rf *)"],
    "defaultMode": "acceptEdits"
  }
}
```

#### 添加 MCP 服务器

```json
// .mcp.json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-server-github"]
    }
  }
}
```

---

## 通知系统（原生 Hooks 驱动）

### 架构

```
托管会话完成响应 ──→ Stop hook (on_stop.sh) ──→ 更新 metadata
                                             ├──→ notify_mode=live 时通知用户
                                             └──→ controller=openclaw 时唤醒 Agent

托管会话请求 Bash 审批 ─→ PermissionRequest hook ─→ 安全命令自动批准（session 级缓存）
                     (on_permission_request.sh) ├──→ 高风险命令自动拒绝并按需唤醒 Agent
                                                └──→ 其余请求继续落到 Claude 默认审批流

托管会话需审批 ───→ Notification hook ──→ 更新 metadata
                   (on_notification.sh)  ├──→ attention/live 时按需通知
                                         └──→ controller=openclaw 时唤醒 Agent

托管会话等输入 ───→ Notification hook ──→ 更新 metadata
                   (on_notification.sh)  ├──→ live 时通知用户
                                         └──→ controller=openclaw 时唤醒 Agent

Teammate 完成工作 ───→ TeammateIdle hook ──→ 更新 metadata
                      (on_teammate_idle.sh) └──→ controller=openclaw 时唤醒 Agent

任务标记完成 ────────→ TaskCompleted hook ──→ 更新 metadata
                      (on_task_completed.sh) └──→ controller=openclaw 时唤醒 Agent
```

### 相比 Codex 的改进

| Codex 方案 | Claude Code 方案 | 改进 |
|-----------|-----------------|------|
| `config.toml` → `notify` | 原生 hooks 系统 | 不需要修改 CLI 配置文件 |
| `pane_monitor.sh` 轮询 tmux | `Notification` hook 事件驱动 | 零延迟、零 CPU 开销 |
| 解析 JSON argv | hook 通过 stdin 接收完整 JSON | 更可靠、信息更丰富 |
| 只有 turn-complete 一种事件 | 14+ 种生命周期事件 | 粒度更细 |

---

## tmux 操作速查

```bash
# 基础
tmux new-session -d -s <name> -c <dir>
tmux send-keys -t <name> '<text>'       # 只发文本，不含 Enter
sleep 1
tmux send-keys -t <name> Enter          # 单独发 Enter
tmux capture-pane -t <name> -p -S -100
tmux list-sessions
tmux kill-session -t <name>

# 用户直接查看
tmux attach -t <name>                   # Ctrl+B, D 退出

# Terminal.app 弹窗
osascript -e 'tell application "Terminal"
    do script "tmux attach -t <name>"
    activate
end tell'
```

## Claude Code 执行速查

### print 模式

```bash
claude -p "<prompt>"
claude -p --dangerously-skip-permissions "<prompt>"
claude -p --model opus --max-budget-usd 5.00 "<prompt>"
claude -p --output-format json "<prompt>"
claude -p --json-schema '{...}' "<prompt>"
```

### 交互式操作

```bash
# 切换模型
/model opus

# 压缩上下文
/compact

# 查看权限
/permissions

# 管理 hooks
/hooks

# 退出
/exit
```

### 会话管理

```bash
# 继续最近对话
claude -c

# 恢复指定会话
claude -r "session-id-or-name"

# 恢复并 fork（不影响原会话）
claude -r "session-id" --fork-session
```

### 并行任务（worktree）

```bash
# 在隔离 worktree 中运行
claude -w feature-auth "实现用户认证"

# 或手动创建
git worktree add -b fix/issue-78 /tmp/issue-78 main
tmux new-session -d -s claude-fix78 -c /tmp/issue-78
tmux send-keys -t claude-fix78 'claude --dangerously-skip-permissions' Enter
```

---

## ⚠️ 安全规则

1. **不要**在 OpenClaw workspace 目录里启动 Claude Code
2. **不要**在 OpenClaw 的 live 仓库里 checkout 分支
3. 用户明确要求时才用 `--dangerously-skip-permissions`
4. 修改 settings.json 前**必须**查阅 config_schema.md 确认合法性
5. `--dangerously-skip-permissions` 下子代理也会继承全自动权限，注意风险
6. 默认通知目标通过环境变量 `OPENCLAW_AGENT_CHAT_ID` / `OPENCLAW_AGENT_CHANNEL` / `OPENCLAW_AGENT_NAME` 配置
7. hooks 只处理带 `OPENCLAW_HANDOFF_CAPABLE=1` 的托管会话
8. hook 唤醒 OpenClaw 时，必须使用托管会话自己的 `openclaw session-id`，不能把多个 Claude 项目混进同一条 agent 主对话
9. 不要把“是否能托管”建立在用户手工全局改 Claude hooks 上；优先使用 wrappers 的 `--settings` 注入

---

## 前置配置检查清单

首次使用前确认：

- [ ] 环境变量 `OPENCLAW_AGENT_CHAT_ID` 已设置
- [ ] 环境变量 `OPENCLAW_AGENT_CHANNEL` 已设置（默认 telegram）
- [ ] 环境变量 `OPENCLAW_AGENT_NAME` 已设置（默认 main）
- [ ] `claude --version` 可用
- [ ] `claude auth status` 显示已登录
- [ ] `openclaw message send` 可发送消息
- [ ] `openclaw agent --agent main --message "test"` 可唤醒 agent
- [ ] tmux 已安装
- [ ] jq 已安装（hooks 脚本需要）
- [ ] `runtime/list_sessions.sh` 可列出托管会话
- [ ] 托管 smoke test 已通过：`runtime/session_status.sh <selector>` 能看到稳定的 `oc_session`
