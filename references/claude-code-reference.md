# Claude Code CLI 快查

> 以本机 `claude --help` 与最新官方文档为准。
> 详细文档：https://code.claude.com/docs/en/cli-reference

## 常用命令

```bash
claude
claude "prompt"
claude -p "prompt"
claude -c
claude -r "<session-id>"
claude agents
claude mcp list
claude plugin --help
claude remote-control --help
claude update
claude install
```

## 高价值 flag 组合

```bash
# 一次性执行
claude -p "prompt"

# 指定模型 + effort
claude -p --model opus --effort high "prompt"

# 结构化输出
claude -p --output-format json --json-schema '{"type":"object"}' "prompt"

# worktree 隔离
claude -w feature-branch --tmux "prompt"

# 追加规则
claude --append-system-prompt "Always run tests before finishing." "prompt"

# 受控自动化
claude -p --permission-mode dontAsk --allowed-tools "Read Bash(git:*)" "prompt"

# session 级 overlay
claude --settings ./managed.settings.json "prompt"

# 恢复但 fork 新会话
claude -r "<session-id>" --fork-session "next step"
```

## 当前重点 flags

### 执行与会话

```bash
-p, --print
-c, --continue
-r, --resume
--fork-session
--session-id <uuid>
-n, --name <name>
--max-turns <n>
--max-budget-usd <n>
--no-session-persistence
```

### 模型、提示与 agents

```bash
--model <model>
--fallback-model <model>
--effort <low|medium|high|max>
--system-prompt <text>
--append-system-prompt <text>
--agent <agent>
--agents <json>
--json-schema <schema>
```

### 配置与扩展

```bash
--settings <file-or-json>
--setting-sources <sources>
--mcp-config <configs...>
--strict-mcp-config
--plugin-dir <path>
--add-dir <directories...>
--ide
--chrome / --no-chrome
--tmux
-w, --worktree [name]
```

### 权限

```bash
--permission-mode default
--permission-mode acceptEdits
--permission-mode plan
--permission-mode dontAsk
--permission-mode bypassPermissions
--permission-mode auto
--dangerously-skip-permissions
--allow-dangerously-skip-permissions
--allowed-tools "Read Bash(git:*)"
--disallowed-tools "Bash(curl:*)"
--tools "Read,Edit,Bash"
```

## 当前对本项目最重要的认识

- 托管会话优先依赖 wrapper 动态注入 `--settings`
- 默认不再把 Agent Teams 作为所有托管会话的前提
- `--dangerously-skip-permissions` 只适合明确授权、隔离可信的场景
- OpenClaw 侧应显式使用 `--session-id` 做一对一路由，而不是只依赖 `--agent main`

## 本项目 wrapper 额外约定

这些不是 Claude 原生命令，而是本 repo 的 wrapper 约定：

```bash
hooks/start_claude.sh ... --agent-teams
hooks/run_claude.sh ... --agent-teams
```

含义：只有显式传入时，wrapper 才会为 Claude 注入 Agent Teams 相关 env 与 hooks。
