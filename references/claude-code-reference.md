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
claude update
claude install
claude auth status
claude agents
claude mcp list
claude plugin --help
claude remote-control --help
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
--session-id <id>
-n, --name <name>
--max-turns <n>
--max-budget-usd <n>
--no-session-persistence
```

### 模型与推理

```bash
--model <model>
--fallback-model <model>
--effort <low|medium|high|max>
--system-prompt <text>
--append-system-prompt <text>
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

### 流式输入输出

```bash
--output-format text|json|stream-json
--input-format text|stream-json
--include-partial-messages
--replay-user-messages
```

## 常用 slash commands

```text
/help
/config
/permissions
/hooks
/model
/compact
/clear
/add-dir
/exit
```

## 当前对本项目最重要的认识

- 托管会话优先依赖 wrapper 动态注入 `--settings`
- 不再把“托管 hooks 可用”建立在全局 `~/.claude/settings.json` 修改之上
- OpenClaw 侧应该显式使用 `--session-id` 做一对一路由，而不是只依赖 `--agent main`
