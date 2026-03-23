# 知识库更新流程

## 触发条件

1. `claude --version` 与 `state/version.txt` 不一致
2. 超过 7 天未更新
3. 用户要求“按最新官方文档核对”
4. OpenClaw 路由 / skills / session 行为发生变化
5. 本项目默认策略发生变化

## 更新步骤

### 1. 版本检查

```bash
claude --version
npm view @anthropic-ai/claude-code version
openclaw --version
npm view openclaw version
cat state/version.txt
cat state/last_updated.txt
```

### 2. CLI 自省

```bash
claude --help
claude agents
claude mcp list
openclaw agent --help
openclaw skills list --json
```

### 3. 官方文档复核

- Claude Code:
  - `https://code.claude.com/docs/en/cli-reference`
  - `https://docs.anthropic.com/en/docs/claude-code/hooks`
  - `https://docs.anthropic.com/en/docs/claude-code/settings`
  - `https://code.claude.com/docs/en/permissions`
  - `https://code.claude.com/docs/en/agent-teams`
- OpenClaw:
  - `https://docs.openclaw.ai/cli/agent`
  - `https://docs.openclaw.ai/skills`

### 4. 核对实现文件

```bash
sed -n '1,260p' hooks/start_claude.sh
sed -n '1,260p' hooks/run_claude.sh
sed -n '1,260p' hooks/hook_common.sh
sed -n '1,320p' runtime/session_store.sh
sed -n '1,220p' hooks/hooks_config.json
sed -n '1,220p' SKILL.md
sed -n '1,220p' INSTALL.md
```

### 5. 更新知识与文档

- `knowledge/features.md`
- `knowledge/capabilities.md`
- `knowledge/config_schema.md`
- `knowledge/changelog.md`
- `references/claude-code-reference.md`
- `README.md`
- `README_ZH.md`
- `INSTALL.md`

### 6. 更新状态文件

```bash
claude --version | head -1 > state/version.txt
date '+%Y-%m-%d' > state/last_updated.txt
```

### 7. 回归测试

```bash
bash tests/regression.sh
```

### 8. 汇报

向用户明确说明：

1. Claude Code 版本差异
2. OpenClaw skills / 路由是否变化
3. 本项目哪些默认策略被调整
4. 是否仍有待验证的灰度能力
