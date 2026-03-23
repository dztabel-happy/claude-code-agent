# 提示词设计指南

> OpenClaw 在构造 Claude Code 提示词时参考本文件。
> 这些模式是**示例和框架**，不是死模板。OpenClaw 应该根据实际任务灵活构造提示词。

## 核心理念

OpenClaw 使用 Claude Code 的方式应该**超越人类用户**：

1. **人类懒得写好提示词**——OpenClaw 每次都构造结构化、上下文完整的提示词
2. **人类不了解所有 flags**——OpenClaw 知道每个 flag 的最佳使用场景
3. **人类不会灵活选模型**——OpenClaw 根据任务复杂度自动选择最合适的模型
4. **人类不会充分利用工具链**——OpenClaw 主动利用 MCP、子代理、worktree、Chrome 等
5. **人类不擅长拆分任务**——OpenClaw 评估任务后合理拆分、并行、分阶段执行
6. **人类不做系统化质量检查**——OpenClaw 每次都验证输出质量

## 提示词构造原则

无论什么任务，好的提示词都遵循这些原则：

1. **明确目标**：做什么、达到什么效果
2. **提供上下文**：相关文件/路径、已有约束、背景信息
3. **指定边界**：做什么、不做什么
4. **定义完成条件**：什么算"做完了"
5. **利用工具链**：显式指定可用的 MCP、子代理等
6. **分步骤**（复杂任务）：按逻辑拆分步骤，每步有明确产出

补充原则：

7. **不要让模型自己猜 skill 路径**：涉及本 skill 内脚本时，用 `{baseDir}` 或 runtime metadata 的真实路径
8. **不要把托管 hooks 作为提示词内容交给 Claude 记忆**：托管行为应由 wrapper 的 `--settings` overlay 负责

## 任务模式库

### 编程开发类

#### 功能实现

```
在 {workdir} 项目中，实现以下功能：

目标：{description}
技术栈：{stack}
相关文件：{files}

要求：
1. {requirement_1}
2. {requirement_2}
3. 完成后运行 {test_command} 确认通过

约束：
- 不要修改 {protected_files}
- 遵循现有代码风格
```

#### Bug 修复

```
修复以下 bug：

问题描述：{bug_description}
复现步骤：{steps}
期望行为：{expected}
实际行为：{actual}
相关文件：{files}

请先分析根本原因，然后修复，最后验证。
```

#### 代码审查

```
审查 {scope} 的代码变更：

关注点：代码质量、潜在 bug、性能、安全
输出格式：按严重程度分类（Critical / Warning / Info）
```

#### 重构

```
重构 {target} 模块：

目标：{refactor_goal}
要求：保持所有现有功能不变，每步重构后运行测试
```

### 研究分析类

#### 技术调研

```
调研 {topic}：

需要了解：
1. {aspect_1}
2. {aspect_2}
3. {aspect_3}

输出：结构化的调研报告，包含对比、推荐、依据
可用工具：WebSearch、WebFetch（如需查阅在线文档）
```

#### 代码库分析

```
分析 {project} 的代码库：

需要了解：
1. 整体架构
2. 核心模块及其依赖关系
3. 技术栈和关键设计决策
4. {specific_question}

输出：结构化的分析报告
```

#### 日志/数据分析

```
分析 {data_source}：

目标：{analysis_goal}
数据位置：{path_or_command}
关注：{metrics_or_patterns}

输出：分析结论 + 关键发现 + 建议行动
```

### 写作文档类

#### 文档生成

```
为 {target} 生成文档：

范围：{scope}
格式：{format}（Markdown / 其他）
受众：{audience}

要求：
1. 自动分析代码/内容结构
2. 包含使用示例
3. 保持与实际代码同步
```

#### 报告撰写

```
撰写关于 {topic} 的报告：

目的：{purpose}
受众：{audience}
包含：{sections}
参考材料：{references}

要求：
1. 结构清晰
2. 数据/事实准确
3. 有可操作的结论
```

### 系统运维类

#### 环境搭建

```
搭建 {environment}：

目标：{goal}
当前状态：{current_state}
约束：{constraints}

步骤要求：每步验证成功后再继续下一步
```

#### 自动化脚本

```
编写自动化脚本：

功能：{description}
触发条件：{trigger}
输入：{input}
输出：{output}

要求：
1. 错误处理完善
2. 有日志输出
3. 可幂等执行
```

### 文件处理类

#### 批量文件操作

```
处理 {directory} 中的文件：

操作：{operation}（重命名/转换/整理/提取等）
规则：{rules}
排除：{exclusions}

先列出计划，确认后再执行。
```

#### 数据转换

```
将 {source} 转换为 {target_format}：

输入：{input_path}
输出：{output_path}
转换规则：{rules}

验证：转换后检查数据完整性
```

### 多智能体协作类

#### Agent Teams — 并行调研

```
Create an agent team to research {topic}. Spawn {N} teammates:
- {role_1}: {focus_1}
- {role_2}: {focus_2}
- {role_3}: {focus_3}

Have them each investigate independently, then share and challenge each other's findings.
```

#### Agent Teams — 并行开发

```
Create an agent team to implement {feature}. Spawn teammates:
- {role_1}: {scope_1} (owns {dir_1})
- {role_2}: {scope_2} (owns {dir_2})
- {role_3}: {scope_3} (owns {dir_3})

Each teammate owns their directory exclusively — no cross-editing.
Require plan approval before making changes.
```

#### Agent Teams — 竞争假设

```
{problem_description}

Spawn {N} agent teammates to investigate different hypotheses.
Have them talk to each other to try to disprove each other's theories.
Update findings with whatever consensus emerges.
```

## CLI Flag 组合策略

OpenClaw 应该根据任务特点选择最佳 flag 组合，而不是只用默认配置。

### 按任务类型

| 任务类型 | 推荐组合 |
|---------|---------|
| 简单单次任务 | `claude -p "prompt"` |
| 需受控自动化 | `claude -p --permission-mode acceptEdits "prompt"` |
| 复杂任务 | `claude --model opus --effort high "prompt"` |
| 预算敏感 | `claude -p --max-budget-usd N --max-turns N "prompt"` |
| 需要上网 | `claude -p --chrome "prompt"` 或 利用 WebSearch/WebFetch |
| 结构化输出 | `claude -p --json-schema '{...}' "prompt"` |
| 追加规则 | `claude --append-system-prompt "规则" "prompt"` |
| 并行任务 | `claude -w worktree-name "prompt"` |
| 继续任务 | `claude -c -p "后续指令"` |
| 团队协作 | `hooks/start_claude.sh ... --agent-teams` |

### 提示词增强清单

构建提示词前检查是否可以利用：

- [ ] `--model` 根据任务复杂度选择模型
- [ ] `--add-dir` 添加额外目录供 Claude 访问
- [ ] `--append-system-prompt` 添加任务特定规则
- [ ] `--chrome` 如需浏览器
- [ ] `--agents` 定义任务专用子代理
- [ ] `--allowed-tools` 预授权常用工具减少审批
- [ ] `--effort` 根据任务复杂度调节推理强度
- [ ] `--max-turns` / `--max-budget-usd` 控制资源使用
- [ ] `-c` 如果是在之前任务的基础上继续
- [ ] `-w` 如果需要隔离环境
- [ ] CLAUDE.md 是否有项目级规范可以利用
