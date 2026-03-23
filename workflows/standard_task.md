# 标准任务流程

## 总流程

```text
用户下任务
    ↓
理解需求与验收标准
    ↓
读取 capabilities / features / prompting patterns
    ↓
选择模型、effort、会话模式、权限模式
    ↓
设计提示词
    ↓
启动托管 Claude 会话
    ↓
Claude 工作，hooks 更新状态并唤醒 OpenClaw
    ↓
OpenClaw 复核结果、继续推进或汇报
```

## 决策顺序

1. 这是一次性任务，还是多轮任务？
2. 是否需要隔离 worktree？
3. 是否需要浏览器？
4. 是否需要 Agent Teams？
5. 需要多高的 effort？
6. 权限模式是否应保守？

## 启动原则

### 一次性任务

- 用 `hooks/run_claude.sh`
- Claude 以 `-p/--print` 运行
- wrapper 自动注入 managed settings overlay

### 多轮任务

- 用 `hooks/start_claude.sh`
- Claude 运行在 tmux 中
- wrapper 自动注入 managed settings overlay

### 本地起步、之后 handoff

- 用 `runtime/start_local_claude.sh`
- 离开时 `runtime/takeover.sh`
- 回来时 `runtime/reclaim.sh`

## 监督原则

- 先查 runtime registry，再等 hook 唤醒
- 只处理托管会话
- 不干预 `controller=local` 的会话
- 会话匹配歧义时必须先确认，不猜

## 托管架构原则

- 每个 Claude 托管会话都应有独立 `openclaw session-id`
- 不要把多个 Claude 会话都路由到 OpenClaw agent 的同一条 `main` 对话上下文
- 不要要求用户为了托管会话去全局改 `~/.claude/settings.json`

## 汇报前检查

- [ ] 任务目标已完成
- [ ] 交付物真实存在
- [ ] 测试或验证已执行
- [ ] 若有会话接管，确认使用的是正确 session
- [ ] 若用户已 reclaim，本次没有继续干预
- [ ] 是否还有阻塞项、风险或后续建议
