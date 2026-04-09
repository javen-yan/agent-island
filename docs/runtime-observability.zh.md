# 运行时可观测性

这份文档定义 AgentIsland 当前的诊断与日志模型。

相关文档：

- [文档索引](./README.zh.md)
- [统一 Agent 协议 v1](./unified-agent-protocol.zh.md)
- [多 Agent 架构](./multi-agent-architecture.zh.md)

## 目标

诊断能力需要尽快回答三个问题：

- 哪个事件进入了应用
- 运行时如何解释这个事件
- 为什么某个 provider 的动作被允许、拒绝或降级

日志模型应该默认低噪声，同时支持明确配置。

## 当前来源

AgentIsland 目前有两层诊断来源：

- Swift Runtime 通过 `os.Logger`
- Rust bridge 通过内置的 `agent-island-bridge`

关键 Swift runtime 路径现在也可以镜像到单独的日志文件。
当前 app-side 文件日志已经覆盖：

- hook socket 接入与响应
- capability dispatch
- session 状态推进
- debounced transcript sync 调度
- Claude 和 Codex interrupt watcher
- subagent agent-file watcher

## 日志策略

### 默认行为

- 默认开启 bridge 文件日志
- 默认 bridge 文件日志级别为 `info`
- 默认关闭 app 文件日志
- 应用侧运行时日志仍然通过 `os.Logger`

### 用户可配置项

设置菜单中暴露：

- `Bridge File Logging`
- `Bridge Log Level`
- `App File Logging`
- `App Log Level`

支持的 bridge 日志级别：

- `off`
- `error`
- `info`
- `debug`
- `trace`

当 bridge logging 关闭时，Rust bridge 不再向 `bridge.log` 追加内容。
当 app logging 关闭时，AgentIsland 不再向 `app.log` 追加内容。

## Bridge 日志路径

bridge 日志文件默认写入：

```text
~/Library/Application Support/AgentIsland/Logs/bridge.log
```

虽然仍可通过 bridge 启动环境覆盖路径，但标准路径和级别现在由应用设置统一管理。

应用侧诊断文件默认写入：

```text
~/Library/Application Support/AgentIsland/Logs/app.log
```

## 运行时支持目录

运行时支持文件现在统一收口到：

```text
~/Library/Application Support/AgentIsland/Runtime/
```

关键运行时路径：

- `Runtime/bridge-profiles`
- `approval-policies.json`

共享 hook bridge 二进制仍然保留在：

```text
~/.agent-island/hooks/agent-island-bridge
```

bridge 启动时现在会显式传入新的 profile 路径。
旧的 `~/.agent-island` 路径现在只作为一次性迁移来源。
AgentIsland 启动时会把旧运行时文件迁移到 `Application Support/AgentIsland`，但共享 hook bridge 二进制仍保留在 `~/.agent-island/hooks`。

## Bridge 日志语义

Rust bridge 会输出结构化单行日志，例如：

- 进程启动
- 进程退出
- 进程错误
- 收到 hook payload
- 发出权限响应
- adapter 降级说明

日志会按级别过滤：

- `error`
  进程和分发失败
- `info`
  生命周期与正常权限响应
- `debug`
  更丰富的事件元数据
- `trace`
  更详细的请求摘要和 bridge 细节

## 设计规则

- 日志配置属于产品设置层，不应写死在 provider 逻辑里。
- bridge 应该先判断是否需要输出，再决定是否打开文件。
- provider adapter 可以写降级诊断，但不能绕过级别过滤。
- UI 只暴露稳定的产品术语，不直接暴露环境变量名字。

## 后续工作

- 增加最近诊断的应用内导出
- 将 app-side 文件日志覆盖范围从当前 hook / dispatcher / session 热路径继续扩展
- provider 更多后，再增加更细的诊断过滤
