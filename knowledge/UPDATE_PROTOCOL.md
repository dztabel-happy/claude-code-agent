# 知识库更新协议

> 目标：让本 skill 的知识库持续跟上 Claude Code、OpenClaw 和本 repo 自身的真实行为。

## 何时必须更新

1. `claude --version` 与 `state/version.txt` 不一致
2. `state/last_updated.txt` 距今超过 7 天
3. 用户明确要求核对最新能力
4. OpenClaw 路由 / skills / session 行为发生变化
5. 本项目默认策略发生变化，例如 Agent Teams、权限策略、安装路径

## 先看哪些数据源

### 一手优先级

| 优先级 | 数据源 | 用途 |
|--------|------|------|
| 1 | 本机 CLI 自省 | 当前真实可用能力 |
| 2 | 官方文档 | 标准行为、灰度能力、配置语义 |
| 3 | 官方包 / 版本源 | npm / releases |
| 4 | 本机 smoke test | 校验 wrapper / hooks / 会话路由 |

### 具体来源

- Claude Code CLI：`claude --help`
- Claude Code agents：`claude agents`
- Claude Code MCP：`claude mcp list`
- OpenClaw 路由：`openclaw agent --help`
- OpenClaw skills：`openclaw skills list --json`
- Claude Code 官方文档：
  - `https://code.claude.com/docs/en/cli-reference`
  - `https://docs.anthropic.com/en/docs/claude-code/hooks`
  - `https://docs.anthropic.com/en/docs/claude-code/settings`
  - `https://code.claude.com/docs/en/permissions`
  - `https://code.claude.com/docs/en/agent-teams`
- OpenClaw 官方文档：
  - `https://docs.openclaw.ai/cli/agent`
  - `https://docs.openclaw.ai/skills`
- 设计参考：
  - `https://developers.openai.com/codex/skills`
  - `https://developers.openai.com/codex/guides/agents-md`

## 标准更新步骤

### Step 1：版本核对

```bash
claude --version
npm view @anthropic-ai/claude-code version
openclaw --version
npm view openclaw version
cat state/version.txt
cat state/last_updated.txt
```

### Step 2：本机 CLI 自省

```bash
claude --help
claude agents
claude mcp list
openclaw agent --help
openclaw skills list --json
```

### Step 3：官方文档复核

重点核对：

- 新增 / 移除 flags
- permission modes 是否变化
- hooks 事件是否变化
- settings overlay / setting sources 语义
- OpenClaw agent routing / session-id 语义
- OpenClaw skills metadata / 目录约束是否变化

### Step 4：本项目实现差异检查

重点看这些文件：

- `hooks/start_claude.sh`
- `hooks/run_claude.sh`
- `hooks/hook_common.sh`
- `runtime/takeover.sh`
- `runtime/session_store.sh`
- `hooks/hooks_config.json`
- `SKILL.md`
- `INSTALL.md`

### Step 5：更新知识文件

| 文件 | 更新重点 |
|------|---------|
| `knowledge/features.md` | CLI 能力、hooks、permission modes |
| `knowledge/capabilities.md` | 本机 MCP / agents / 版本 |
| `knowledge/config_schema.md` | settings overlay 与托管边界 |
| `knowledge/changelog.md` | 实测发现和差异 |
| `references/claude-code-reference.md` | 快查命令 / flags |
| `README.md` / `README_ZH.md` | 默认工作流与安装入口 |
| `INSTALL.md` | 路径假设与可选步骤 |

### Step 6：更新状态文件

```bash
claude --version | head -1 > state/version.txt
date '+%Y-%m-%d' > state/last_updated.txt
```

### Step 7：回归验证

```bash
bash tests/regression.sh
```

## 更新原则

1. 以本机真实能力为第一准绳，不盲信旧知识
2. 以官方文档为第二准绳，不把猜测写成事实
3. 对灰度能力明确标注“待验证”或“显式 opt-in”
4. 对托管架构相关结论，至少做一次本地 smoke test
5. 默认策略优先追求简单、稳定，而不是功能更多
