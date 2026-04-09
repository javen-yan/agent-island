# Agent 接入 Checklist

接入一个新的 agent/provider 时，建议按这份 checklist 走。目标是把接入工作变成固定步骤，而不是继续在 UI 里堆 provider 特判。

## 核心原则

新增 agent 应该只需要补四层：

1. `AgentPlatform` 产品 profile
2. Rust bridge adapter
3. Swift runtime 支持
4. 验证与文档

如果某个问题落不到这四层之一，通常意味着架构还需要先收口，再继续扩 provider。

## Phase 1. 产品 Profile

- [ ] 在 [/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Models/AgentPlatform.swift](/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Models/AgentPlatform.swift) 新增一个 `case`
- [ ] 填一份 `AgentBehaviorProfile`
- [ ] 明确：
  - 显示名 key
  - accent color
  - icon symbol
  - terminal control profile
  - `autoRevealOnTurnCompletion`
  - `supportsPostTurnFollowUpInIsland`
  - `showsLastReplyInCompletionSummary`
- [ ] 只给产品拥有的文案加 i18n，不要把 provider 原始输出也塞进来

验收：

- 不改 UI `if provider == ...` 分支，也能把这个 agent 正常显示出来。

## Phase 2. Rust Adapter

- [ ] 新增 `bridge-rs/src/adapter/<provider>.rs`
- [ ] 在 [/Users/javen/Documents/Workspace/private/helper/claude-island/bridge-rs/src/adapter/mod.rs](/Users/javen/Documents/Workspace/private/helper/claude-island/bridge-rs/src/adapter/mod.rs) 注册
- [ ] 解析：
  - hook event name
  - session id
  - cwd
  - transcript path
  - tool name
  - tool use id
  - message
  - command text
  - escalation hints
- [ ] 实现：
  - `should_emit_event`
  - `status_for_event`
  - `process_info`
  - `requires_approval`
  - `internal_event`
  - `permission_mode`
  - `extra_payload`
  - `permission_response`

验收：

- 官方输入可以稳定映射成统一 runtime event。

## Phase 3. Hook 安装层

- [ ] 在 [/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Services/Hooks/AgentHookPlugin.swift](/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Services/Hooks/AgentHookPlugin.swift) 增加安装/修复/卸载逻辑
- [ ] 定义：
  - 官方配置路径
  - hook 注册内容
  - availability 检测
  - install 前置条件
  - bridge profile 生成
- [ ] 把 provider 专属文件改写逻辑留在 plugin 层，不要往 UI 扩散

验收：

- 新 agent 可以独立 install / repair / refresh。

## Phase 4. Swift Runtime

- [ ] 如果有历史文件，在 [/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Services/Session/SessionTranscriptProvider.swift](/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Services/Session/SessionTranscriptProvider.swift) 接 transcript
- [ ] 如果有实时信号，在 [/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Services/Session/AgentRuntimeObserver.swift](/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Services/Session/AgentRuntimeObserver.swift) 接 runtime observer
- [ ] 在 [/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Models/UnifiedAgentProtocol.swift](/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Models/UnifiedAgentProtocol.swift) 补 baseline capabilities
- [ ] 只有真的需要时，才在 [/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Services/Hooks/AgentPermissionAdapter.swift](/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Services/Hooks/AgentPermissionAdapter.swift) 增加 provider 特殊等待策略

验收：

- 新 agent 可以复用现有统一运行时，而不是单独走一条 UI 支线。

## Phase 5. UI 验证

- [ ] 确认以下页面都能正常工作：
  - settings
  - Island 列表
  - chat
  - approval bar
  - diagnostics
- [ ] 能用行为位替代的 provider 名称判断，尽量替代掉
- [ ] provider 专属文案留在 localization 和 capability 层，不要写死在 view 里

验收：

- UI 是 capability 驱动，不是 provider 名称驱动。

## Phase 6. 测试

- [ ] 在 [/Users/javen/Documents/Workspace/private/helper/claude-island/bridge-rs/src/dispatcher.rs](/Users/javen/Documents/Workspace/private/helper/claude-island/bridge-rs/src/dispatcher.rs) 增加 bridge dispatch 测试
- [ ] 在 `bridge-rs` 增加 permission response 测试
- [ ] 如果新增 provider 改变了语义 phase，在 [/Users/javen/Documents/Workspace/private/helper/claude-island/UnifiedRuntimePackage/Tests/UnifiedRuntimeKitTests/UnifiedRuntimeKitTests.swift](/Users/javen/Documents/Workspace/private/helper/claude-island/UnifiedRuntimePackage/Tests/UnifiedRuntimeKitTests/UnifiedRuntimeKitTests.swift) 补 unified runtime 测试
- [ ] 构建 app target

验收：

- `cargo test`
- `swift test`
- `xcodebuild -quiet -project AgentIsland.xcodeproj -scheme AgentIsland`

全部通过。

## Phase 7. 文档

- [ ] 更新 [/Users/javen/Documents/Workspace/private/helper/claude-island/docs/agent-extension-guide.md](/Users/javen/Documents/Workspace/private/helper/claude-island/docs/agent-extension-guide.md)
- [ ] 更新 [/Users/javen/Documents/Workspace/private/helper/claude-island/docs/agent-extension-guide.zh.md](/Users/javen/Documents/Workspace/private/helper/claude-island/docs/agent-extension-guide.zh.md)
- [ ] 如果文档入口有变化，更新 [/Users/javen/Documents/Workspace/private/helper/claude-island/docs/README.md](/Users/javen/Documents/Workspace/private/helper/claude-island/docs/README.md)
- [ ] 至少写清楚：
  - 官方 hook 边界
  - transcript 支持
  - runtime observation 支持
  - continuation 模型
  - 当前限制

## 推荐顺序

1. 产品 profile
2. Rust adapter
3. hook 安装层
4. Swift runtime
5. 测试
6. UI polish
7. 文档
