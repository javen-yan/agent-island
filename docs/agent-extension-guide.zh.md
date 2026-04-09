# Agent 扩展指南

这份文档说明如何给 AgentIsland 接入一个新的 provider，而不让 UI 再理解一套新的原始协议。

相关文档：

- [文档索引](./README.zh.md)
- [统一 Agent 协议 v1](./unified-agent-protocol.zh.md)
- [多 Agent 架构](./multi-agent-architecture.zh.md)
- [Agent 接入 Checklist](./agent-integration-checklist.zh.md)

## 核心原则

新增 provider 必须沿用同一套分层模型：

1. 官方 provider runtime
2. provider-specific adapter
3. 统一事件和动作映射
4. 共享 Swift runtime 和 UI

不要让新增 provider 直接把原始官方事件名带进 UI，除非确实没有合理的统一映射方式。

## 哪些东西必须稳定

UI 和状态机应继续依赖：

- 语义事件 kind
- 语义动作 payload
- 显式 provider capabilities

如果拿不准某个字段该不该进入稳定协议，优先把它留在 provider-specific payload metadata 里，等确认它具备跨 provider 的通用价值后再升级。

## 接入清单

如果你要直接按步骤执行，请优先使用：

- [Agent 接入 Checklist](./agent-integration-checklist.zh.md)

### 1. 添加 Rust 适配器

在下面目录新增一个适配器：

```text
bridge-rs/src/adapter/
```

仓库里现在也保留了一份 adapter 模板：

```text
bridge-rs/src/adapter/provider_template.rs.example
```

建议职责：

- 解析官方 payload
- 翻译成统一事件 kind
- 计算共享 runtime status
- 组装 provider payload metadata
- 生成官方权限响应 JSON

然后在下面位置注册：

- `bridge-rs/src/adapter/mod.rs`
- `bridge-rs/src/protocol.rs`

### 2. 把官方事件映射到统一事件

新增 provider 应尽量映射到统一语义事件：

- `session.started`
- `session.ended`
- `turn.input_submitted`
- `turn.completed`
- `tool.pending`
- `tool.started`
- `tool.completed`
- `tool.failed`
- `permission.requested`
- `notification`

如果该 provider 存在审批流，它的 capability descriptor 也要显式声明 approval model。

### 3. 定义审批行为

你需要明确三件事：

- 哪个官方事件触发审批
- 审批模式是 native、terminal-backed 还是 unsupported
- 如何把 allow / deny 转成该 provider 官方要求的响应 JSON

注意：响应格式仍然必须是 provider 专属的。共享的是 unified action，而不是官方回包格式。

### 4. 添加安装和修复逻辑

更新：

```text
AgentIsland/Services/Hooks/AgentHookPlugin.swift
```

需要处理：

- 新插件的注册
- 官方 hook 事件配置
- install / repair / uninstall
- capability 元数据

### 5. 接入 Swift runtime

必要时更新智能体枚举和能力定义，但 Swift 业务逻辑仍应优先围绕统一协议。

重点文件：

- `AgentIsland/Models/AgentPlatform.swift`
- `AgentIsland/Services/Hooks/AgentPermissionAdapter.swift`
- `AgentIsland/Services/Hooks/HookSocketServer.swift`
- `AgentIsland/Models/UnifiedAgentProtocol.swift`

### 6. 正确使用 provider payload

provider payload 是 provider 专属信息的透传位。

适合放进去的内容：

- 官方事件元数据
- matcher 名称
- 命令文本
- 升权提示
- provider 专属调试字段

不应该放进去的内容：

- 规范化后的业务语义
- 统一审批状态
- 已经属于稳定字段的核心信息

### 7. 添加测试

至少补两类测试：

#### 事件映射测试

在 `bridge-rs` 中验证：

- 原始官方事件名被保留
- unified event kind 正确
- capability 相关 approval metadata 正确
- 关键 provider payload 字段存在

#### 权限响应测试

验证：

- allow 回包格式
- deny 回包格式
- 如果该 provider 允许“无回包”路径，也要覆盖

### 8. 更新文档

接入新增 provider 后，至少同步更新：

- `README.md`
- `README.zh.md`
- `docs/README.md`
- `docs/README.zh.md`
- `docs/agent-extension-guide.zh.md`

建议至少写清楚：

- 官方 hook 入口
- 审批入口
- unified 事件映射
- 当前验证状态

## 推荐顺序

1. 新增 Rust adapter
2. 补 dispatch 测试
3. 补 permission response 测试
4. 添加 installer 支持
5. 接通 Swift runtime
6. 验证构建
7. 更新文档
