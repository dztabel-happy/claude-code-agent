# Claude Code 配置参考

> 这是给本 skill 用的高信号配置摘要，不追求覆盖所有字段。
> 最后核对：2026-03-23

## 配置来源层级

Claude Code 当前支持这些来源：

1. 用户级：`~/.claude/settings.json`
2. 项目共享：`.claude/settings.json`
3. 项目本地：`.claude/settings.local.json`
4. 运行时 overlay：`--settings <file-or-json>`
5. CLI 参数：如 `--model`、`--permission-mode`

额外控制：

- `--setting-sources user,project,local`：控制加载哪些静态来源
- `--settings`：适合 session 级 overlay

## 本项目当前推荐做法

### 对托管会话

不要默认要求用户修改全局 `~/.claude/settings.json`。

当前 wrappers 会自动：

- 通过 `--settings <generated-file>` 注入 managed hooks
- 保持托管 hooks 和会话 metadata 一致
- 只在显式启用 `--agent-teams` 时注入团队相关 env 与 hooks

### 对非托管裸会话

- 不注入本项目 hooks
- 不接管
- 不发 OpenClaw 唤醒

## 本项目关心的 settings 字段

### `env`

Agent Teams 相关 env 现在是**可选项**：

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

用途：

- 只在确实需要团队能力时启用实验开关
- 不再把 Agent Teams 视为所有托管会话的默认前提

### `hooks`

当前本项目真正需要的 hooks 分两层：

#### 默认始终注入

```json
{
  "hooks": {
    "Stop": [...],
    "Notification": [...],
    "PermissionRequest": [...]
  }
}
```

#### 只有显式启用 Agent Teams 才注入

```json
{
  "hooks": {
    "TeammateIdle": [...],
    "TaskCompleted": [...]
  }
}
```

#### 当前托管 overlay 结构

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"/abs/path/hooks/on_stop.sh\"",
            "timeout": 15
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt|idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"/abs/path/hooks/on_notification.sh\"",
            "timeout": 15
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"/abs/path/hooks/on_permission_request.sh\"",
            "timeout": 15
          }
        ]
      }
    ]
  }
}
```

如果启用了 Agent Teams，overlay 还会补上：

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "hooks": {
    "TeammateIdle": [...],
    "TaskCompleted": [...]
  }
}
```

### `permissions`

```json
{
  "permissions": {
    "allow": ["Bash(git:*)", "Read"],
    "deny": ["Read(./.env)"],
    "ask": ["Bash(git push:*)"]
  }
}
```

本项目要点：

- `allow` / `deny` / `ask` 是重要的静态策略
- wrapper 级 `--permission-mode` 仍然优先
- 托管 overlay 里的 `PermissionRequest` hook 会补一层 session 级动态审批策略
- 对托管任务，优先通过 wrapper 决定模式，不把核心行为藏进用户全局配置

## `--setting-sources` 的边界

当前 wrappers **不会强制覆写** Claude 默认的静态 sources。

这意味着：

- 用户级 / 项目级 / 本地级 settings 仍会照常参与合并
- wrapper 只负责再叠一层 managed overlay

如果你需要更强的隔离，可显式传：

```bash
--setting-sources project,local
```

或根据场景更严格地限制来源。

## 可选的全局 hooks 模板

`hooks/hooks_config.json` 现在是一个模板，不再假设固定安装目录。

使用前必须先把：

```text
__SKILL_DIR__
```

替换成真实绝对路径。

该模板默认不会自动打开 Agent Teams。

## 其他高频字段

| 字段 | 用途 |
|------|------|
| `model` | 默认模型 |
| `outputStyle` | 输出风格 |
| `disableAllHooks` | 关闭 hooks |
| `includeGitInstructions` | 是否注入 git 指令 |
| `enableAllProjectMcpServers` | 自动批准项目级 MCP |
| `autoUpdatesChannel` | `stable` / `latest` |
| `teammateMode` | 团队显示 / 运行模式 |

## 本项目与配置的边界

### 由 wrapper 管

- 托管 hooks overlay
- OpenClaw / Claude 的托管环境变量
- 每个托管会话的 `openclaw session-id`
- Agent Teams 是否启用

### 由用户 / 项目配置管

- 长期默认模型
- 常驻 MCP
- 通用权限白名单
- 团队共享的项目级 hooks / CLAUDE.md

## CLAUDE.md

Claude Code 会自动读取：

- `~/.claude/CLAUDE.md`
- `CLAUDE.md`
- `.claude/CLAUDE.md`
- `CLAUDE.local.md`

本 skill 使用原则：

- 项目规范优先放进 `CLAUDE.md`
- 托管会话策略不要放进 `CLAUDE.md`
- 托管策略应在 wrapper 和 session metadata 层维护
