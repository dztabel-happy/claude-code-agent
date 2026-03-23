# 标准任务流程

## 总流程

```text
用户下任务
    ↓
先判断：这是新任务还是会话控制
    ↓
如果是会话控制，优先 runtime/control_session.sh
    ↓
如果是新任务：理解需求与验收标准
    ↓
读取 capabilities / features / prompting patterns
    ↓
判断任务模式（分析 / 修复 / review / 调研 / 文档）
    ↓
选择模型、effort、会话模式、权限模式
    ↓
设计提示词
    ↓
定义验证动作与输出要求
    ↓
启动托管 Claude 会话
    ↓
Claude 工作，hooks 更新状态并唤醒 OpenClaw
    ↓
OpenClaw 复核结果、继续推进或汇报
```

## 决策顺序

1. 这是一次性任务，还是多轮任务？
2. 这是分析、修复、review、调研还是会话控制？
3. 是否需要隔离 worktree？
4. 是否需要浏览器？
5. 是否真的值得开启 Agent Teams？
6. 需要多高的 effort？
7. 权限模式是否应保守？

## 默认值与升级

- 默认值是为了减少日常复杂度，不是为了限制 OpenClaw 能力
- 只要理由充分，OpenClaw 可以升级模型、effort、会话模式、Chrome、worktree 或 Agent Teams
- 只有安全边界、会话隔离和显式路由属于硬约束

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

### 会话控制

- 优先 `runtime/control_session.sh`
- 能自动唯一匹配时不要求用户再给 selector
- 有歧义时再追问，不要猜

### 并行任务

- 只有在任务天然可拆分时才显式启用 `--agent-teams`
- 不把 Agent Teams 当默认值

## 监督原则

- OpenClaw 是项目经理，不是原话转发器
- Claude 返回内容后，先看是否达到任务卡要求
- 验收不通过时继续推进，不要过早向用户宣布完成

- 先查 runtime registry，再等 hook 唤醒
- 只处理托管会话
- 不干预 `controller=local` 的会话
- 会话匹配歧义时必须先确认，不猜

## 托管架构原则

- 每个 Claude 托管会话都应有独立 `openclaw session-id`
- 不要把多个 Claude 会话都路由到 OpenClaw agent 的同一条 `main` 对话上下文
- 不要要求用户为了托管会话去全局改 `~/.claude/settings.json`
- 不要把 Agent Teams 和危险权限当作默认流程

## 汇报前检查

- [ ] 任务目标已完成
- [ ] 交付物真实存在
- [ ] 测试或验证已执行
- [ ] 若有会话接管，确认使用的是正确 session
- [ ] 若用户已 reclaim，本次没有继续干预
- [ ] 是否还有阻塞项、风险或后续建议
