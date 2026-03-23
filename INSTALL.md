# Claude Code Agent 安装指南

> 这份安装指南对应升级后的新架构：
> 托管 wrappers 会自动给 Claude 会话注入 managed settings overlay。
> 对“托管会话”来说，你**不再需要**先手工修改全局 `~/.claude/settings.json`。

## 前提条件

- OpenClaw 已安装并运行
- Claude Code 已安装并可正常请求
- tmux 已安装
- jq 已安装
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

## 第一步：安装 Skill

```bash
cd ~/.openclaw/workspace/skills
git clone https://github.com/dztabel-happy/claude-code-agent.git
```

或手工复制到：

```bash
~/.openclaw/workspace/skills/claude-code-agent
```

验证：

```bash
ls ~/.openclaw/workspace/skills/claude-code-agent/SKILL.md
```

## 第二步：给脚本加执行权限

```bash
cd ~/.openclaw/workspace/skills/claude-code-agent
chmod +x hooks/*.sh runtime/*.sh tests/regression.sh
```

## 第三步：配置 OpenClaw 通知默认值

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
cd ~/.openclaw/workspace/skills/claude-code-agent
bash tests/regression.sh
```

预期：输出 `All regression tests passed.`

## 第五步：做一次托管 smoke test

### 方式 A：本地托管会话

```bash
mkdir -p /tmp/claude-code-agent-test
bash runtime/start_local_claude.sh /tmp/claude-code-agent-test --permission-mode plan
```

在 Claude 里输入一条简单消息，例如：

```text
Reply with exactly: HANDOFF_READY
```

退出 attach 后，另开终端：

```bash
bash runtime/list_sessions.sh
bash runtime/session_status.sh claude-claude-code-agent-test
```

你应当看到：

- `controller=local`
- `notify_mode=off`
- `oc_session=claude-code-agent-...`

### 方式 B：接管同一会话

```bash
bash runtime/takeover.sh claude-claude-code-agent-test
bash runtime/session_status.sh claude-claude-code-agent-test
```

你应当看到：

- `controller=openclaw`
- `notify_mode=attention`
- `oc_session` 保持稳定

### 方式 C：归还本地

```bash
bash runtime/reclaim.sh claude-claude-code-agent-test
```

## 现在不再是必需项的旧步骤

### 1. 全局修改 `~/.claude/settings.json`

对于本项目的托管会话，这已经不是必须步骤。

原因：

- wrappers 会自动通过 `--settings` 注入托管 hooks
- 这样不会污染用户所有 Claude 会话

如果你**想**让裸跑 `claude` 也带上这些 hooks，可以参考 `hooks/hooks_config.json` 手工合并，但这已经属于可选方案。

### 2. 强制关闭 OpenClaw session reset

旧版安装建议要求几乎关闭 OpenClaw 的 session reset。

升级后不再把它当成硬性前提，原因是：

- 每个托管 Claude 会话现在都有独立 `openclaw session-id`
- 不再共享 agent `main` 对话上下文

如果你有超长生命周期的审阅流，仍然可以根据自己习惯调整 OpenClaw 的 session policy，但这不应再被视作“安装阻塞项”。

## 常用使用方式

### 让 OpenClaw 直接新建托管会话

你可以对 OpenClaw 说：

- “用 Claude Code 帮我在 `/path/to/project` 做 XX”
- “用 Claude Code 帮我分析这段日志”
- “用 Claude Code 帮我实现并验证一个功能”

### 手工启动托管会话

```bash
bash hooks/start_claude.sh claude-demo /path/to/project --permission-mode acceptEdits
tmux attach -t claude-demo
```

### 一次性执行

```bash
bash hooks/run_claude.sh /path/to/project -p --model sonnet "Analyze the repo and summarize the architecture."
```

## 排障

### `claude auth status` 正常，但真实请求卡住

优先直接验证：

```bash
claude -p --model haiku --max-turns 1 "Reply with exactly: OK"
```

如果这里都不通，优先修 Claude 自身环境，不要先怀疑本项目。

### 看托管会话状态

```bash
bash runtime/list_sessions.sh
bash runtime/session_status.sh <selector>
```

### 看是不是被路由到了独立 OpenClaw session

`runtime/session_status.sh` 里应能看到：

```text
oc_session: claude-code-agent-...
```

### hooks 没反应

先确认你是不是通过 wrapper 启动的托管会话，而不是手工裸跑 `claude`。

再检查：

```bash
claude --version
bash runtime/session_status.sh <selector>
```
