# Claude Code Agent 安装指南

> 当前版本的默认思路是：
> 托管 wrappers 会自动给 Claude 会话注入 managed settings overlay。
> 对托管会话来说，不需要先手工修改全局 `~/.claude/settings.json`。

## 前提条件

- OpenClaw 已安装并能正常工作
- Claude Code 已安装并已完成认证
- `tmux`
- `jq`
- 至少一个 OpenClaw 消息通道可用

建议先验证：

```bash
openclaw health
claude --version
claude auth status
claude -p --model haiku --max-turns 1 "Reply with exactly: CLAUDE_HEALTH_OK"
tmux -V
jq --version
```

## 第一步：选择安装目录

推荐二选一：

### 方案 A：共享 skill 目录

```bash
export OPENCLAW_SKILLS_DIR="${OPENCLAW_SKILLS_DIR:-$HOME/.openclaw/skills}"
mkdir -p "$OPENCLAW_SKILLS_DIR"
git clone https://github.com/dztabel-happy/claude-code-agent.git "$OPENCLAW_SKILLS_DIR/claude-code-agent"
```

### 方案 B：workspace 内 skill 目录

```bash
mkdir -p "$HOME/.openclaw/workspace/skills"
git clone https://github.com/dztabel-happy/claude-code-agent.git "$HOME/.openclaw/workspace/skills/claude-code-agent"
```

建议随后固定一个环境变量，后面所有命令都用它：

```bash
export CLAUDE_CODE_AGENT_DIR="$(cd "$HOME/.openclaw/skills/claude-code-agent" 2>/dev/null || cd "$HOME/.openclaw/workspace/skills/claude-code-agent" && pwd)"
```

验证：

```bash
ls "$CLAUDE_CODE_AGENT_DIR/SKILL.md"
```

## 第二步：给脚本加执行权限

```bash
cd "$CLAUDE_CODE_AGENT_DIR"
chmod +x hooks/*.sh runtime/*.sh tests/regression.sh
```

## 第三步：配置 OpenClaw 默认通知目标

这一步不是 Claude hooks 配置，而是托管 wrappers 在需要给用户发消息、唤醒 OpenClaw 时使用的默认路由信息。

推荐写进 shell 配置：

```bash
export OPENCLAW_AGENT_CHAT_ID="你的Chat_ID"
export OPENCLAW_AGENT_CHANNEL="telegram"
export OPENCLAW_AGENT_NAME="main"
```

然后重新加载 shell：

```bash
source ~/.zshrc
```

> 即使配置了这些变量，手工裸跑 `claude` 也不会被本项目接管。
> 只有 wrapper 启动的托管会话才会启用本项目 hooks。

## 第四步：跑回归测试

```bash
cd "$CLAUDE_CODE_AGENT_DIR"
bash tests/regression.sh
```

预期：输出 `All regression tests passed.`

## 第五步：做一次托管 smoke test

### 方式 A：本地托管会话

```bash
mkdir -p /tmp/claude-code-agent-test
bash "$CLAUDE_CODE_AGENT_DIR/runtime/start_local_claude.sh" /tmp/claude-code-agent-test --permission-mode plan
```

在 Claude 里输入一条简单消息，例如：

```text
Reply with exactly: HANDOFF_READY
```

退出 attach 后，另开终端：

```bash
bash "$CLAUDE_CODE_AGENT_DIR/runtime/control_session.sh" list
bash "$CLAUDE_CODE_AGENT_DIR/runtime/control_session.sh" status claude-claude-code-agent-test
```

你应当看到：

- `controller=local`
- `notify_mode=off`
- `oc_session=claude-code-agent-...`

### 方式 B：接管同一会话

```bash
bash "$CLAUDE_CODE_AGENT_DIR/runtime/control_session.sh" takeover claude-claude-code-agent-test
bash "$CLAUDE_CODE_AGENT_DIR/runtime/control_session.sh" status claude-claude-code-agent-test
```

你应当看到：

- `controller=openclaw`
- `notify_mode=attention`
- `oc_session` 保持稳定

### 方式 C：归还本地

```bash
bash "$CLAUDE_CODE_AGENT_DIR/runtime/control_session.sh" reclaim claude-claude-code-agent-test
```

## 当前推荐的使用方式

优先让 OpenClaw 通过对话使用这个 skill 来启动、继续、归还、查看或停止 Claude 会话。

如果你人在本机前，需要一个本地兜底入口，优先用：

```bash
bash "$CLAUDE_CODE_AGENT_DIR/runtime/control_session.sh" list
bash "$CLAUDE_CODE_AGENT_DIR/runtime/control_session.sh" status
bash "$CLAUDE_CODE_AGENT_DIR/runtime/control_session.sh" reclaim
bash "$CLAUDE_CODE_AGENT_DIR/runtime/control_session.sh" takeover /path/to/project
bash "$CLAUDE_CODE_AGENT_DIR/runtime/control_session.sh" stop claude-demo
```

### 默认单次任务

```bash
bash "$CLAUDE_CODE_AGENT_DIR/hooks/run_claude.sh" /path/to/project \
  -p --permission-mode acceptEdits "Analyze the repo and summarize the architecture."
```

### 默认交互式任务

```bash
bash "$CLAUDE_CODE_AGENT_DIR/hooks/start_claude.sh" claude-demo /path/to/project \
  --permission-mode acceptEdits
tmux attach -t claude-demo
```

### 显式启用 Agent Teams

Agent Teams 不再默认注入。只有确实需要并行任务时才显式开启：

```bash
bash "$CLAUDE_CODE_AGENT_DIR/hooks/start_claude.sh" claude-team /path/to/project \
  --permission-mode acceptEdits \
  --agent-teams
```

### 高风险模式

`--dangerously-skip-permissions` 只建议在用户明确授权、且环境隔离可信时使用：

```bash
bash "$CLAUDE_CODE_AGENT_DIR/hooks/start_claude.sh" claude-isolated /path/to/project \
  --dangerously-skip-permissions
```

## 可选：让裸跑 `claude` 也挂 hooks

这不是托管会话的必需步骤，只在你明确希望“裸 Claude 会话也带这些 hooks”时才做。

1. 打开 [hooks/hooks_config.json](hooks/hooks_config.json)
2. 把里面的 `__SKILL_DIR__` 全部替换成真实绝对路径
3. 再合并进你的 Claude settings

注意：

- 这个模板不再假设固定安装在 `~/.openclaw/workspace/skills/...`
- 模板默认不会自动打开 Agent Teams

## 常见排障

### `claude auth status` 正常，但真实请求卡住

优先直接验证：

```bash
claude -p --model haiku --max-turns 1 "Reply with exactly: OK"
```

如果这里不通，先修 Claude 自身环境。

### 看托管会话状态

```bash
bash "$CLAUDE_CODE_AGENT_DIR/runtime/control_session.sh" list
bash "$CLAUDE_CODE_AGENT_DIR/runtime/control_session.sh" status <selector>
```

### 确认是否路由到独立 OpenClaw session

`session_status.sh` 里应看到：

```text
oc_session: claude-code-agent-...
```

### hooks 没反应

先确认当前会话是不是通过本项目 wrapper 启动的托管会话，而不是手工裸跑的 `claude`。
