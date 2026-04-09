# Agent 扩展指南

这份文档说明如何沿用当前共享运行时设计，为 AgentIsland 新增一个 agent 集成。

相关文档：

- [文档索引](./README.zh.md)
- [当前产品总览](./current-product-overview.zh.md)
- [多 Agent 架构](./multi-agent-architecture.zh.md)
- [统一 Agent 协议 v1](./unified-agent-protocol.zh.md)

## 目标

新增的 agent 应该表现为“共享运行时上的另一个 integration”，而不是一套新的产品模式。

这意味着：

- provider 专属协议处理留在 adapter 边界
- 共享 session state 尽量保持 provider 无关
- UI 继续渲染同一套公共模型
- 不支持的能力要显式表达，而不是藏在特判里

## 当前扩展分层

新增 provider 时，建议按这几个层次推进：

1. Provider runtime 与 hook 模型
2. Rust bridge adapter
3. Swift hook plugin 与 capability 声明
4. Transcript / history 集成
5. Runtime state 对账
6. UI 验证与文档更新

## 1. 先确认 Provider 合同

开始编码前先明确：

- 官方有哪些 hook 或事件入口
- 是否有 transcript 或历史数据源
- 审批是应用内接管、终端内确认、provider 自己管理，还是根本没有
- provider 是否能提供足够稳定的 session 标识和工具元数据

不要先从 UI 需求倒推。先从 provider 的真实运行时合同出发。

## 2. 添加 Bridge Adapter

在下面目录新增一个 adapter：

```text
bridge-rs/src/adapter/
```

当前参考实现：

- `bridge-rs/src/adapter/claude.rs`
- `bridge-rs/src/adapter/codex.rs`
- `bridge-rs/src/adapter/gemini.rs`

adapter 负责：

- 解析官方 provider 载荷
- 规整 tool name、tool id、session id、cwd、message 等公共字段
- 把 provider 原生事件映射成稳定的内部运行时语义
- 通过 `extra` 保留 provider 专属元数据
- 如果支持审批，生成 provider 原生权限响应

注册位置通常包括：

- `bridge-rs/src/adapter/mod.rs`

如果需要协议层补充，也同步更新：

- `bridge-rs/src/protocol.rs`
- `bridge-rs/src/dispatcher.rs`

## 3. 明确审批模型

这是最重要的扩展决策之一。

你必须真实选择以下其中一种：

- 应用内审批
- 终端确认，应用只展示状态
- provider 自己管理审批，应用只做有限展示
- 没有审批面

不要把终端确认硬伪装成原生 app 审批。

当前参考：

- Codex 是“终端内确认，应用展示等待状态”
- Claude 是“应用内审批”

## 4. 添加 Hook Plugin 与 Capabilities

更新：

```text
AgentIsland/Services/Hooks/AgentHookPlugin.swift
```

需要定义：

- availability detection
- install / repair / uninstall 行为
- derived bridge profile 行为
- supported events
- approval source
- 是否支持 transcript history
- 是否支持 permission decisions

目标是让 provider 通过 capability 把行为说清楚，而不是让产品层大量写死 provider 名字。

## 5. 扩展 Agent 模型

只在确有必要时更新这些共享模型入口：

- `AgentIsland/Models/AgentPlatform.swift`
- `AgentIsland/Services/Hooks/AgentPermissionAdapter.swift`
- `AgentIsland/Models/UnifiedAgentProtocol.swift`

这些改动要尽量克制。

如果某个字段只对单一 provider 有意义，先放在 adapter metadata 里，不要过早升格成全局模型字段。

## 6. 接入 Transcript 支持

如果 provider 有持久 transcript 或事件日志，就通过下面入口接入：

```text
AgentIsland/Services/Session/SessionTranscriptProvider.swift
```

必要时再扩展：

```text
AgentIsland/Services/Session/ConversationParser.swift
```

Transcript 支持最好覆盖：

- 初始历史加载
- 增量同步
- 会话元数据
- tool result 恢复
- 大 tool 输出的懒加载详情

如果 provider 没有 transcript，就把这个限制显式保留，不要伪造历史能力。

## 7. 接通 Runtime State 对账

共享运行时最终都会流进：

```text
AgentIsland/Services/State/SessionStore.swift
```

新 provider 至少要能和现有 session 模型配合完成：

- tool start / complete
- approval waiting state
- interrupted session
- transcript backfill
- session summaries
- 有内存边界的 chat history

尽量让 provider 适配现有 runtime，而不是把 provider 特例塞进核心状态机。

## 8. 校验 Tool Result 行为

当前产品默认只在内存里保留 preview 大小的 tool 输出，完整内容需要时再从 transcript 懒加载。

新 provider 如果有 transcript，最好保持同样行为。

需要检查：

- preview 截断是否正常
- lazy detail loading 是否可用
- 超长 tool 输出不会把 chat view 撑爆
- transcript 缺失时能否优雅降级

## 9. 添加测试

至少补这两类：

### Bridge 测试

验证：

- 事件映射
- approval state 映射
- permission mode 映射
- provider 专属 metadata 保留
- permission response 编码

常见位置：

```text
bridge-rs/src/dispatcher.rs
```

### Runtime 测试或验证路径

验证：

- plugin install / repair 路径
- history load 路径
- approval 状态渲染
- 如果支持 transcript，详情懒加载路径

## 10. 更新用户文档

当这个 provider 已经具备可交付形态后，至少更新：

- `README.md`
- `README.zh.md`
- `docs/README.md`
- `docs/README.zh.md`
- 当前这份扩展指南
- 如果需要，再更新架构类文档中的 provider 示例

至少写清楚：

- 接入方式
- 审批方式
- 历史方式
- 当前验证状态

## 实际推荐顺序

建议按这个顺序推进：

1. 先确认 provider 官方行为。
2. 新增 Rust adapter。
3. 补 bridge tests。
4. 添加 hook plugin 与 capabilities。
5. 如果可行，再接 transcript。
6. 验证 runtime 对账。
7. 验证大 tool 输出行为。
8. 更新文档。

## 总结

新增集成时，记住四条原则：

- provider 专属逻辑尽量留在 adapter 附近
- 运行时语义尽量共享
- 审批行为必须真实
- 大历史内容必须有边界

只要新 provider 能守住这四点，就能比较自然地融入 AgentIsland 当前设计。
