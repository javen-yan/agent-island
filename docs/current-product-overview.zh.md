# 当前产品总览

这份文档描述的是 AgentIsland 当前已经实现的设计，而不是理想化的未来架构。

相关文档：

- [文档索引](./README.zh.md)
- [统一 Agent 协议 v1](./unified-agent-protocol.zh.md)
- [多 Agent 架构](./multi-agent-architecture.zh.md)
- [运行时可观测性](./runtime-observability.zh.md)

## 产品目标

AgentIsland 是一个面向 macOS 终端 AI agent 的菜单栏伴随应用。

它当前主要提供五类统一能力：

- 会话可见性
- 审批状态
- 工具执行状态
- transcript 驱动的历史视图
- 运行时诊断

产品已经明确收敛到“共享运行时”，而不是为 Claude、Codex、Gemini 分别维护三套产品模式。

## 当前运行时主路径

当前主路径可以概括为：

`Provider hooks / transcripts -> Rust bridge -> Swift runtime services -> shared session state -> UI`

具体来说：

1. provider 发出 hooks 事件和 transcript 更新。
2. `bridge-rs` 把官方 provider 载荷规整成稳定的内部载荷。
3. Swift 服务把这些事件和 transcript 历史做统一对账。
4. `SessionStore` 持有 app 使用的共享 session 状态。
5. Notch、聊天视图、会话列表和设置页都消费这套共享状态。

## 当前各 Provider 行为

### Claude

- hook 事件负责驱动审批和运行时状态迁移。
- JSONL transcript 负责提供历史和 tool result 恢复。
- Claude 仍然是目前最完整的应用内管理集成。

### Codex

- bridge 主要观察 `Bash` 相关 hook 行为和 transcript 状态。
- 终端确认会在 app 里被展示为等待状态。
- 真正的允许或拒绝仍然发生在终端里，而不是 AgentIsland 内。
- 危险命令确认规则现在由“内建规则 + 用户自定义 regex 扩展”共同决定。

### Gemini

- Gemini 也通过相同的 bridge / runtime 模型接入。
- provider 自己的审批特性会被保留，而不是被强行改造成 Claude 式控制。

## 当前 Session 模型

产品目前围绕一套共享 session 状态展开，里面主要包括：

- provider 身份
- 运行阶段
- 工具时间线
- 审批状态
- transcript 回填的对话元数据
- UI 使用的 chat items

关键点在于：UI 消费的是 session state，而不是 provider 原始事件名。

## Tool Results 与内存模型

超长 tool 输出现在不再在常规内存历史里始终保留完整文本。

当前行为是：

- 内存里默认只保存 preview
- 长 tool 输出在进入稳定 chat 数据前会先被截断
- 用户需要完整内容时，再从 transcript 懒加载详情

这样既能保住交互记录，又能降低长会话场景下的常驻内存压力。

## 审批模型

现在 AgentIsland 已经把“审批展示”和“审批控制”明确区分开了。

例如：

- Claude 审批可以由 app 接管。
- Codex 终端确认由 app 展示状态，但仍在终端里完成。
- provider 差异通过 capability 和 adapter 逻辑体现，而不是硬压成一个伪统一控制模型。

## 设置与诊断

当前设置页已经收口这些内容：

- provider 集成安装 / 修复
- bridge 日志控制
- app 日志控制
- Codex 自定义危险命令 regex
- chat history retention limit

诊断能力主要分成三层：

- Swift runtime 日志
- Rust bridge 日志
- transcript 驱动的状态回填与对账

## 发布与更新模型

当前发布链路已经包含：

- 本地构建和打包脚本
- CI tag 构建
- GitHub Release 资产发布
- Sparkle appcast 生成与合并
- GitHub Pages 托管 appcast

appcast 现在按保留历史版本来设计，不再每次只覆盖成最新一条。

## 代码入口

- 运行时状态：`AgentIsland/Services/State/SessionStore.swift`
- Transcript providers：`AgentIsland/Services/Session/SessionTranscriptProvider.swift`
- Transcript 解析：`AgentIsland/Services/Session/ConversationParser.swift`
- Hook 与 bridge profile 生成：`AgentIsland/Services/Hooks/AgentHookPlugin.swift`
- 共享 session 模型：`AgentIsland/Models/SessionState.swift`
- Tool result 渲染：`AgentIsland/UI/Views/ToolResultViews.swift`
- Bridge adapters：`bridge-rs/src/adapter`

## 总结

理解当前设计，最重要的是记住这几点：

- 一套共享运行时
- 多个 provider adapter
- transcript 驱动恢复与对账
- capability 感知的审批模型
- 有内存边界的历史 + 懒加载详情

后续继续演进产品时，文档应当以这套现实基线为准。
