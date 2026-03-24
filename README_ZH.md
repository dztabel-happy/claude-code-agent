# Claude Code Agent

**[English](README.md)** | 中文

`claude-code-agent` 是一个给 OpenClaw 用的 skill。它的核心不是“帮你包一层 Claude Code 命令”，而是让 OpenClaw 能把 Claude Code 当成一个可托管、可恢复、可远程接力的 worker。

一句话理解：

- OpenClaw 负责开会话、读进度、收通知、做决策、向你汇报
- Claude Code 负责在同一个会话里持续干活

## 核心能力

- 用 OpenClaw 启动新 Claude Code 会话，或恢复已有会话
- 会话常驻在 `tmux` 里，你离开电脑后不会断现场
- 会话状态保存在 runtime metadata 里，OpenClaw 能找到同一条会话继续推进
- `Notification`、`PermissionRequest`、`Stop` 等 hook 事件会把 OpenClaw 再唤醒
- OpenClaw 接手时会先读最近的 `tmux` 输出，再决定下一步，而不是从头猜
- 你可以随时让 OpenClaw 查看进度、继续执行、停掉会话、切回本地、再交还托管
- OpenClaw 不需要一直常驻盯着终端，它是事件驱动地回来处理，像项目经理一样推进任务
- 如果你人在电脑前，可以把会话正式切回本地，此后由你自己直接操作，OpenClaw 不再继续接收后续通知
- 当你再次离开电脑时，可以再发消息让 OpenClaw 接管；它会先读之前的上下文和 `tmux` 现场，再继续同一会话

## 这个 skill 的定位

这不是一个“主要靠终端脚本手工使用”的项目。

它的定位很明确：

- OpenClaw 是项目经理
- Claude Code 是执行者
- 这个仓库是二者之间的会话层、路由层、唤醒层

你真正日常使用的入口，应该是 OpenClaw 对话。

## 你平时怎么用

### 1. 开始一个任务

直接对 OpenClaw 说：

```text
用 claude-code-agent 分析 /path/to/project。
用 claude-code-agent 修复 /path/to/project 的 bug，跑完测试再汇报。
用 claude-code-agent 审查 /path/to/project 当前改动。
用 claude-code-agent 对 /path/to/project 做一次只读审计。
```

OpenClaw 应该做的是：

1. 选择这个 skill
2. 启动或复用一个 Claude Code 托管会话
3. 让 Claude Code 在那个会话里持续工作
4. 在收到 hook 或消息事件后，再回到同一个会话继续推进

### 2. 中途随时回来

任务做了一半，你可以随时再找 OpenClaw：

```text
用 claude-code-agent 看一下 /path/to/project 现在做到哪了。
用 claude-code-agent 继续刚才那个会话。
用 claude-code-agent 把当前进度先总结给我。
用 claude-code-agent 列出当前托管的 Claude 会话。
```

这里的关键不是“重新开一个 Claude”，而是继续同一个会话。

会话状态在 runtime 里，现场输出在 `tmux` 里。OpenClaw 回来时可以先读现场，再继续干活。

### 3. 你可以直接离开电脑

这是这个 skill 最重要的价值之一。

典型场景是：

1. 你让 OpenClaw 开始一个任务
2. Claude Code 在 `tmux` 里继续工作
3. 你离开电脑，甚至只剩手机能联系 OpenClaw
4. 中间如果出现等待输入、审批、任务完成、异常停止等事件，OpenClaw 会收到消息
5. OpenClaw 像项目经理一样决定下一步，并把情况告诉你

也就是说，OpenClaw 不用一直“挂在终端前面”。它和人操作 OpenClaw 一样，是被消息和事件驱动的。

### 4. 人在电脑前就切回本地，离开时再交还 OpenClaw

这是一个很重要的使用方式：

1. 你人在电脑前时，可以让 OpenClaw 把当前 Claude 会话切回本地控制
2. 从那一刻开始，后面的操作就完全由你自己在终端里处理
3. 因为控制权已经回到本地，OpenClaw 不会再继续接收这个会话后续的通知
4. 当你准备离开电脑时，再对 OpenClaw 说一声，让它重新接管
5. OpenClaw 接管后，会先读这个会话已有的上下文、状态记录和最近的 `tmux` 输出，然后继续推进

也就是说，你可以在“本地亲自操作”和“远程让 OpenClaw 托管”之间来回切换，而且切换的是同一条会话，不是重新开新会话。

## OpenClaw 在这里像什么

像一个真正的项目经理，而不是简单转发器。

它应该做这些事：

- 接收你的目标和约束
- 把你的话整理成更合适的 Claude Code 执行指令
- 选择继续旧会话还是开新会话
- 在被唤醒后先读 `tmux` 最近输出和会话状态
- 判断是继续推进、先汇报、请求你确认、还是切回本地
- 保持你始终知道现在发生了什么

所以这个 skill 的核心不是“帮 OpenClaw 调一次 Claude”，而是“让 OpenClaw 能长期托管 Claude Code 项目会话”。

## 它到底怎么工作的

工作链路可以压缩成 5 步：

1. OpenClaw 通过这个 skill 启动 Claude Code 托管会话
2. Claude Code 跑在 `tmux` 里，现场持续保留
3. 运行时把 `session_key`、`cwd`、`openclaw_session_id`、`permission_policy` 等状态写到本地 runtime
4. Claude hooks 在 `Notification`、`PermissionRequest`、`Stop` 等节点唤醒 OpenClaw
5. OpenClaw 回来后先读会话状态和最近 `tmux` 输出，再决定后续动作

所以它不是“OpenClaw 一直盯着 Claude”，而是“Claude 需要时再把 OpenClaw 叫回来”。

## 快速开始

### 1. 准备条件

- 已安装 OpenClaw
- 已安装并认证 Claude Code
- 已安装 `tmux`
- 已安装 `jq`

### 2. 把 skill 放到 OpenClaw 能发现的位置

OpenClaw 最新文档说明，skills 的发现优先级是：

1. `<workspace>/skills`
2. `~/.openclaw/skills`
3. OpenClaw 自带 bundled skills

推荐安装方式：

装到 workspace：

```bash
git clone https://github.com/dztabel-happy/claude-code-agent.git ~/.openclaw/workspace/skills/claude-code-agent
```

装成共享 skill：

```bash
git clone https://github.com/dztabel-happy/claude-code-agent.git ~/.openclaw/skills/claude-code-agent
```

如果你的 workspace 不是 `~/.openclaw/workspace`，就换成 `<你的 workspace>/skills/claude-code-agent`。

### 3. 需要时先跑 OpenClaw 官方初始化

```bash
openclaw onboard
```

官方文档把它作为 gateway、workspace、skills 的统一 onboarding 入口。

### 4. 新开 OpenClaw 会话后直接使用

```text
用 claude-code-agent 分析 /path/to/project。
```

这是日常主路径。不是先去终端手工跑 wrapper。

## 如何让 OpenClaw 安装这个 skill

这里要说清楚两件事。

### 官方文档层面

最新 OpenClaw 文档已经说明：

- `openclaw onboard` 是官方推荐的初始化入口
- OpenClaw 有自己的 skills 发现和安装体系
- skills 会从 workspace 和共享目录自动发现

### 这个仓库当前最稳妥的落地方式

对这个 GitHub 仓库来说，目前最稳妥的方式仍然是：

1. clone 或复制到 `<workspace>/skills/claude-code-agent` 或 `~/.openclaw/skills/claude-code-agent`
2. 新开一个 OpenClaw 会话
3. 直接让 OpenClaw 使用 `claude-code-agent`

不要默认认为 OpenClaw 只靠 skill 名就一定能直接从 GitHub 拉这个仓库，除非你当前使用的 OpenClaw 构建和 registry 发布状态明确支持这条路径。

## 什么时候你要亲自介入

日常推荐仍然是让 OpenClaw 处理：

```text
用 claude-code-agent 把当前会话切回本地控制。
用 claude-code-agent 继续接管 /path/to/project 的 Claude 会话。
用 claude-code-agent 停掉 claude-demo 这个会话。
```

如果你已经在电脑前，本地兜底工具如下。

只看现场，不改变控制权：

```bash
tmux attach -t <session-name>
```

正式控制已有托管会话：

```bash
bash runtime/control_session.sh list
bash runtime/control_session.sh status
bash runtime/control_session.sh reclaim [selector]
bash runtime/control_session.sh takeover [selector]
bash runtime/control_session.sh stop [selector]
```

记忆方式很简单：

- `tmux attach` = 看现场 / 临时插话
- `reclaim` = 正式切回本地，后续通知停止，由你自己操作
- `takeover` = 正式交还 OpenClaw，它会先读之前上下文和 `tmux` 现场再继续

## 为什么这个设计有价值

没有这层运行时，OpenClaw 更像是在“临时调一次 Claude Code”。

有了这层之后，OpenClaw 才更像是在“管理一个持续运行的项目执行会话”：

- 会话不断
- 现场可回读
- 中途可接力
- 人可以离开电脑
- OpenClaw 不必常驻
- 用户能持续知道任务状态

这才是这个 skill 的核心。

## 官方参考

- [OpenClaw Skills CLI 文档](https://docs.openclaw.ai/cli/skills)
- [OpenClaw Skills 使用文档](https://docs.openclaw.ai/tools/skills)
- [OpenClaw Onboarding CLI 文档](https://docs.openclaw.ai/cli/onboard)
- [OpenClaw onboarding 概览](https://docs.openclaw.ai/start/onboarding-overview)
