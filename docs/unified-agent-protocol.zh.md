# 统一 Agent 协议 v1

这份文档定义 AgentIsland 面向产品内核的当前内部协议。

目标是让 Claude、Codex、Gemini 和未来的新 agent 都通过 provider 转换层接入，而不是把各家的 hook 细节泄漏进核心运行时。

相关文档：

- [文档索引](./README.zh.md)
- [多 Agent 架构](./multi-agent-architecture.zh.md)
- [运行时可观测性](./runtime-observability.zh.md)
- [Agent 扩展指南（中文）](./agent-extension-guide.zh.md)

## 目标

AgentIsland 应该把外部智能体看作 provider，而不是产品里的三套独立模式。

产品核心只消费三类东西：

- 稳定的语义事件
- 稳定的响应动作
- 显式的能力声明

产品核心不应该直接依赖：

- 官方原始事件名
- 某家 provider 的权限术语
- 某家 provider 的响应 JSON 结构

## 非目标

- 不是要抹平所有 provider 差异
- 不是要把所有 provider 字段都升格为核心字段
- 不是要假装所有 provider 都支持同样的控制能力

provider 差异必须通过 capability 和 `provider_payload` 被保留下来。

## 设计原则

- 统一产品语义，不统一厂商术语。
- provider 特有的解析留在 ingress adapter。
- provider 特有的响应编码留在 egress adapter。
- 优先用 capability 建模，而不是 `if provider == ...`。
- provider 做不到时允许优雅降级。
- 保留原始 provider 载荷，用于诊断和回放。

## 运行时形态

运行时链路：

`Provider Input -> Provider Ingress Adapter -> Unified Agent Event -> Core Engine -> Unified Agent Action -> Provider Response Adapter`

核心引擎只理解：

- 统一事件
- 统一动作
- capability 描述

## 协议分层

### 1. Provider Input

原始 provider 数据，例如：

- Claude hook JSON
- Codex hook JSON
- Gemini hook JSON
- transcript 元数据
- 进程元数据

### 2. Unified Agent Event

产品逻辑消费的稳定事件。

### 3. Unified Agent Action

产品逻辑或策略引擎产出的稳定响应动作。

### 4. Provider Response

回写给 provider 运行时的官方原生响应。

## 统一事件包络

所有规范化事件都使用同一个 envelope。

```json
{
  "version": "1.0",
  "event_id": "evt_123",
  "timestamp": "2026-04-08T12:34:56Z",
  "provider": "codex",
  "session_id": "session_123",
  "turn_id": "turn_456",
  "kind": "permission.requested",
  "payload": {},
  "capability_hints": {},
  "provider_payload": {}
}
```

## 稳定包络字段

- `version`
  协议版本。
- `event_id`
  内部唯一事件 ID。
- `timestamp`
  ISO-8601 时间戳。
- `provider`
  来源 provider，例如 `claude`、`codex`、`gemini`。
- `session_id`
  稳定的会话或线程 ID。
- `turn_id`
  provider 暴露时才存在的 turn 标识。
- `kind`
  稳定的语义事件名。
- `payload`
  稳定的语义载荷。
- `capability_hints`
  事件级的能力提示，可选。
- `provider_payload`
  保留下来的 provider 原始字段，用于调试、回放和后续迁移。

## 事件类型

核心协议应保持小而语义化。

### Session

- `session.started`
- `session.ended`
- `session.compaction_requested`
- `session.compacted`
- `session.cwd_changed`
- `session.config_changed`

### Turn

- `turn.input_submitted`
- `turn.started`
- `turn.completed`
- `turn.failed`

### Permission

- `permission.requested`
- `permission.resolved`
- `permission.denied_by_provider`

### Tool

- `tool.pending`
- `tool.started`
- `tool.completed`
- `tool.failed`

### Agent

- `agent.subtask_started`
- `agent.subtask_completed`
- `agent.idle`

### Model

- `model.request_prepared`
- `model.response_chunk`
- `model.response_completed`

### Notification

- `notification`

### Interaction

- `interaction.elicitation_requested`
- `interaction.elicitation_resolved`

这些命名故意不直接绑定 `PreToolUse`、`BeforeTool`、`PermissionRequest` 这类官方事件名。

## 通用载荷片段

每个事件类型的 payload 可以不同，但建议复用一些公共片段。

### Session Reference

```json
{
  "cwd": "/workspace/project",
  "transcript_path": "/path/to/transcript.jsonl",
  "pid": 12345,
  "tty": "/dev/ttys001"
}
```

### Tool Reference

```json
{
  "call_id": "tool_123",
  "tool_name": "Bash",
  "arguments": {
    "command": "git status"
  }
}
```

### Risk Summary

```json
{
  "destructive": false,
  "filesystem_write": false,
  "network": false,
  "sandbox_escalation": false,
  "secrets_access": false,
  "open_world": false
}
```

### Capability Hint

```json
{
  "supports_allow": true,
  "supports_deny": true,
  "supports_ask": false,
  "supports_argument_patch": false,
  "supports_additional_context": true,
  "supports_stop_turn": false
}
```

## 事件载荷建议

### `permission.requested`

所有审批面都用这个统一语义事件，即使各家官方事件名不同。

```json
{
  "request_id": "perm_123",
  "source_kind": "tool_call",
  "session": {
    "cwd": "/workspace/project",
    "transcript_path": "/tmp/transcript.jsonl",
    "pid": 12345,
    "tty": "/dev/ttys001"
  },
  "tool": {
    "call_id": "tool_123",
    "tool_name": "Bash",
    "arguments": {
      "command": "rm -rf build"
    }
  },
  "risk": {
    "destructive": true,
    "filesystem_write": true,
    "network": false,
    "sandbox_escalation": false,
    "secrets_access": false,
    "open_world": false
  },
  "provider_source": {
    "event": "PreToolUse"
  }
}
```

### `tool.started`

```json
{
  "tool": {
    "call_id": "tool_123",
    "tool_name": "run_shell_command",
    "arguments": {
      "command": "npm test"
    }
  }
}
```

### `tool.completed`

```json
{
  "tool": {
    "call_id": "tool_123",
    "tool_name": "run_shell_command",
    "arguments": {
      "command": "npm test"
    }
  },
  "result": {
    "status": "success",
    "output_text": "Tests passed",
    "structured_output": null
  }
}
```

### `model.request_prepared`

```json
{
  "request": {
    "model": "gemini-2.5-pro",
    "messages": [],
    "config": {}
  }
}
```

只有 provider 暴露 model 层 hooks 时，才需要这类事件。

## 统一动作包络

所有产品侧响应都使用一个统一 action 对象。

```json
{
  "version": "1.0",
  "action_id": "act_123",
  "target_event_id": "evt_123",
  "decision": "allow",
  "message": "Approved by AgentIsland",
  "continue": true,
  "stop_reason": null,
  "patch": {},
  "metadata": {}
}
```

## 稳定动作字段

- `version`
- `action_id`
- `target_event_id`
- `decision`
  取值建议为 `allow`、`deny`、`ask`、`noop`。
- `message`
  给用户或 provider 的说明文本。
- `continue`
  provider 支持时，表示是否继续 turn 或 agent loop。
- `stop_reason`
  停止时的原因。
- `patch`
  结构化修改请求。
- `metadata`
  内部记账信息，不作为语义控制字段。

## Patch 对象

`patch` 是统一协议比现在 `decision/reason` 更强的关键。

```json
{
  "tool_arguments": {},
  "tool_result": {},
  "model_request": {},
  "model_response": {},
  "additional_context": "optional text",
  "tail_call": {
    "name": "tool_name",
    "args": {}
  }
}
```

provider response adapter 可以：

- 完整应用 patch
- 部分应用 patch
- 忽略不支持的 patch 字段

不支持的字段不应导致整个链路失败。

## Capability 描述

每个 provider adapter 都必须声明能力矩阵。

推荐顶层结构：

```json
{
  "provider": "codex",
  "permissions": {},
  "tool_control": {},
  "model_control": {},
  "session_control": {},
  "agent_control": {},
  "history": {}
}
```

### Permission Capabilities

```json
{
  "interactive_approval": true,
  "tool_level_approval": true,
  "sandbox_escalation_approval": true,
  "app_tool_approval": false,
  "provider_managed_permissions_visible": true
}
```

### Tool Control Capabilities

```json
{
  "allow": true,
  "deny": true,
  "rewrite_args": false,
  "replace_result": false,
  "tail_call": false
}
```

### Model Control Capabilities

```json
{
  "rewrite_request": false,
  "replace_response": false,
  "stream_intercept": false,
  "tool_selection_control": false
}
```

### Session Control Capabilities

```json
{
  "inject_start_context": true,
  "notification_message": true,
  "stop_turn": true,
  "compaction_hooks": false
}
```

### Agent Control Capabilities

```json
{
  "subagent_events": true,
  "subagent_retry_control": false,
  "elicitation": false
}
```

## Provider 转换规则

provider adapter 应拆成两个职责。

### Ingress Adapter

职责：

1. 解析 provider 原始输入
2. 确定语义 `kind`
3. 归一化稳定 payload
4. 在需要时附加 capability hints
5. 保留原始字段到 `provider_payload`

### Egress Adapter

职责：

1. 接收统一 action
2. 编码成最接近的 provider 原生响应
3. 安全丢弃不支持的控制字段
4. 记录降级决策，方便诊断

## 降级规则

统一协议必须支持有意识的降级。

例如：

- 产品侧要求 `patch.tool_arguments`，但 provider 不支持参数改写，则忽略该 patch，保留原始执行路径
- 产品侧要求 `ask`，但 provider 只支持 `allow/deny`，则映射为 `noop`
- 产品侧要求 `tail_call`，但 provider 不支持 tail call，则丢弃并记诊断日志

降级必须可被日志和诊断看见。

## Codex 指南

Codex 应被建模为“部分能力可用”的 provider，而不是“坏掉的 provider”。

当前实践含义：

- `PreToolUse` 适合做 Bash 运行前审批
- app/tool 级别的审批策略还存在于配置层
- 不是所有权限面都会作为 hook 事件发出来
- hook 响应深度弱于 Gemini，也弱于 Claude 的高级场景

建议建模方式：

- 把 Bash 审批映射为 `permission.requested`
- 把配置层权限视为 provider capability 或 provider policy state
- 不要假装 AgentIsland 已经控制了 Codex 全部权限
- 明确区分：
  - 运行时审批事件
  - provider 配置策略
  - 当前未覆盖的权限面

这样产品层就不会把“Codex 的 hook 审批”误认为“Codex 全权限联动”。

## Claude 指南

Claude 目前暴露的 hook 面最丰富。

建议：

- 对产品真正有价值的部分映射进统一语义事件
- 长尾细节继续留在 `provider_payload`
- 不要因为单一 Claude 特性就膨胀稳定核心字段，除非它有明显跨 provider 价值

当前落地原则：

- Claude 的长尾事件默认不直接晋升到稳定核心协议
- 只有在它们开始影响共享产品逻辑，或者已具备跨 provider 复用价值时，才考虑晋升
- 在此之前，优先保留在 `provider_payload` 和 capability 诊断层

## Gemini 指南

Gemini 在 model 层和 tool 层的变换能力比较强。

建议：

- 只有存在 Gemini 这类 model hooks 的 provider 时，才启用 `model.*`
- 参数改写、响应改写、tail call 通过 `patch` 表达
- 做不到这些能力的 provider 走显式降级

## 迁移计划

### Phase 1

- 保持当前 hook bridge 协议不变
- 平行定义 unified event 和 unified action 类型
- 新增 provider capability 描述

### Phase 2

- 在 Swift 边界把当前 `HookPayload` 转换为 unified events
- 后续新增 UI 逻辑不再直接依赖 provider 原始字段

### Phase 3

- 将响应处理从 `decision/reason` 扩展到统一 action
- 引入 provider response adapter

### Phase 4

- 将策略逻辑迁移到 capability-based decision
- 暴露降级诊断信息

### Phase 5

- 如果需要，再让 bridge 侧 adapter 直接产出 unified events

## 稳定核心字段晋升规则

只有同时满足以下条件，字段才应该进入稳定核心协议：

- 至少两个 provider 已经能表达，或者很快能表达
- 这个字段会影响产品逻辑，而不只是诊断
- 它经过 provider 转换后仍然语义稳定

否则应继续留在：

- `provider_payload`
- provider-specific capability state
- diagnostics only

## 建议的 Swift 类型

建议概念层先有这些类型：

- `UnifiedAgentEvent`
- `UnifiedAgentAction`
- `ProviderCapabilities`
- `ProviderIngressAdapter`
- `ProviderResponseAdapter`
- `ProviderPolicySnapshot`

这些名字只是建议，不是必须的 API 命名。

## 待决问题

- provider policy snapshot 应该事件驱动，还是按需拉取
- unified event 是否需要单独的 `trace_id` 做跨事件关联
- tool 风险分类应由 adapter 做、policy engine 做，还是两边都做
- 不支持的 action 字段应只进诊断，还是也反馈到 UI

## 总结

产品内核应该统一的是：

- 一套语义事件协议
- 一套语义动作协议
- 一套显式 capability 模型

不应该统一的是：

- 一个伪造的 provider 行为
- 一个伪造的全局权限系统
- 一个伪造的响应深度

这条边界，决定了多 agent 产品架构是否能长期稳定演进。
