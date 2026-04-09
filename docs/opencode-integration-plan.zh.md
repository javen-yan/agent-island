# OpenCode 集成计划

这份文档定义 AgentIsland 接入 OpenCode 的设计与实施计划。

相关文档：

- [文档索引](./README.zh.md)
- [统一 Agent 协议 v1](./unified-agent-protocol.zh.md)
- [Agent 扩展指南](./agent-extension-guide.zh.md)

## 为什么接 OpenCode

根据 OpenCode 官方文档，它是一个运行在终端、IDE 和桌面端的开源 coding agent，并且具备：

- 多会话
- provider 灵活配置
- MCP 支持
- config 驱动

这和 AgentIsland 的 provider translation 架构是匹配的。

## 官方文档关键信号

从官方文档可以确认：

- OpenCode 以终端、桌面和 IDE 编码代理形态对外提供
- provider 通过 `opencode.json` 配置
- 凭证通过 `/connect` 命令录入
- MCP server 通过 OpenCode 的命令和配置接入
- 它更偏向 config-driven runtime，而不一定复用 Claude/Codex/Gemini 那种完全相同的 hooks 形态

本计划参考的官方来源：

- [OpenCode 官网](https://opencode.ai/)
- [Providers](https://opencode.ai/docs/providers)
- [CLI](https://opencode.ai/docs/cli/)
- [MCP servers](https://dev.opencode.ai/docs/mcp-servers/)
- [Config](https://opencode.ai/docs/ja/config/)

## 集成假设

OpenCode 应作为一个 provider adapter 接入，而不是产品里的特殊模式。

也就是：

`OpenCode runtime -> OpenCode ingress adapter -> Unified Agent Event -> AgentIsland core`

## 需要适配的内容

### 1. 会话身份

需要稳定提取：

- session id
- cwd
- transcript 或 conversation 路径
- pid / tty

### 2. 工具生命周期

需要识别：

- tool pending
- tool started
- tool completed
- tool failed

### 3. 权限与审批模型

需要确认 OpenCode 是否暴露：

- pre-tool approval hooks
- config 级 allowlist / denylist
- terminal-only confirmation
- model 或 agent 级干预点

### 4. 消息与历史记录

需要确认：

- 是否支持直接请求历史
- 是否存在 transcript 文件
- 是否支持消息注入

### 5. 能力面

需要先建立 capability baseline：

- permissions
- transcript history
- runtime observation
- messaging
- MCP tool visibility

## 建议的适配策略

### 优先路径

如果 OpenCode 暴露结构化 runtime event 或 hook-like callback，就直接新增原生 Rust adapter：

```text
bridge-rs/src/adapter/opencode.rs
```

### 兜底路径

如果 OpenCode 更偏 transcript/config 驱动，那就分两阶段接：

1. 先接 runtime observation + transcript
2. 再接 interactive approvals

这样依然符合统一协议里的 partial-capability provider 模型。

## 初始能力目标

初始 capability 预估：

- `interactiveApproval`
  未确认
- `toolLevelApproval`
  未确认
- `transcriptHistory`
  大概率支持
- `runtimeObservation`
  大概率支持
- `mcpVisibility`
  大概率支持
- `messageInjection`
  未确认

在官方文档进一步确认前，OpenCode 应按“部分能力 provider”处理。

## 实施 Checklist

- [ ] 确认官方 runtime event 或 hook 入口
- [ ] 确认 config 文件发现方式和项目级优先级
- [ ] 确认 transcript/history 来源与格式
- [ ] 确认 approval 机制与可能的 response payload
- [ ] 确认 MCP server / tool metadata 是否能映射到 UI
- [ ] 新增 `AgentPlatform.opencode`
- [ ] 新增 provider capability baseline
- [ ] 新增 Rust adapter skeleton
- [ ] 如果支持可安装 hooks，则补 installer/bootstrap
- [ ] 如果没有 hooks，则补 history/runtime adapter
- [ ] 新增 UI 图标和 accent color
- [ ] 补 dispatch tests 和 permission response tests

## 推荐实施顺序

1. 文档与 capability 假设
2. Runtime observation
3. Transcript/history
4. Permission/approval
5. MCP metadata visibility
6. UI 打磨与诊断

## 风险

- OpenCode 可能没有 Claude/Codex/Gemini 那种同等深度的 approval callback。
- 它可能更依赖 config 和 transcript，而不是 hook 语义。
- MCP 支持可能会暴露比当前 UI 更丰富的工具元数据。

## 产品结论

OpenCode 应该被看成：

- 一等 provider
- 在能力未确认前的 partial-capability provider
- 由 adapter 层负责适配，而不是让 UI 长出一套特例
