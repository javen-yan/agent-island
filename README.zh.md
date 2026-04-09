<div align="center">
  <img src="AgentIsland/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Logo" width="100" height="100">
  <h1 align="center">AgentIsland</h1>
  <p align="center">
    面向 Claude、Codex 和 Gemini 会话的 macOS 菜单栏助手。
    <br>
    将运行态可见性、审批状态和会话历史统一到一个入口。
  </p>
  <p align="center">
    <a href="https://github.com/javen-yan/agent-island/releases/latest" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/github/v/release/javen-yan/agent-island?style=rounded&color=white&labelColor=000000&label=release" alt="最新版本">
    </a>
    <a href="https://javen-yan.github.io/agent-island/appcast.xml" target="_blank" rel="noopener noreferrer">
      <img alt="Sparkle Appcast" src="https://img.shields.io/badge/appcast-Sparkle-white?style=rounded&labelColor=000000">
    </a>
  </p>
</div>

[English README](./README.md)

更多文档入口见：[文档索引](./docs/README.zh.md)

## 它是什么

AgentIsland 是一个面向终端 AI agent 的 macOS 菜单栏应用。它把会话状态、工具执行、审批状态和最近对话历史收拢到一个统一界面里，减少你在多个终端窗口之间来回切换的成本。

当前支持：

- Claude
- Codex
- Gemini

## 当前产品设计

现在的 AgentIsland 已经围绕一套共享运行时组织起来：

- 各家 agent 的 hooks 和 transcript 先经过 provider adapter 接入。
- Rust bridge 会把 provider 事件规整成稳定的内部载荷。
- Swift 运行时以 `SessionStore`、`SessionTranscriptProvider` 和统一事件处理为中心。
- UI 不再按 agent 分裂成几套独立产品流，而是渲染同一个共享 session 模型。

几个当前已经落地的重要行为：

- Claude 走应用内审批，并使用 transcript 回填历史。
- Codex 的终端确认会在应用里显示等待状态，但实际确认仍在终端里完成。
- Codex 危险命令确认支持“内建规则 + 用户自定义 regex 扩展”。
- 超长 tool 输出默认只在内存里保留 preview，需要时再从 transcript 懒加载完整内容。

## 当前能力

- 菜单栏 / Notch 入口
- 多会话展示
- 工具执行时间线
- 统一审批状态
- transcript 驱动的历史视图
- 大 tool 输出懒加载详情
- Hook 安装、修复与 bridge 重新分发
- bridge 与 app 的诊断日志控制
- Sparkle 发布与 appcast 发布链路

## 当前支持矩阵

| Agent | 接入方式 | 审批方式 | 历史方式 | 状态 |
| --- | --- | --- | --- | --- |
| Claude | 官方 hooks + JSONL transcript 解析 | 应用内审批 | transcript 回填 | 已验证 |
| Codex | 官方 hooks + transcript 解析 | 终端确认，应用只展示状态 | transcript 回填 | 已验证 |
| Gemini | 官方 hooks + bridge adapter | provider 驱动审批 | 运行时集成 | 已接入 |

## 架构概览

当前 AgentIsland 可以按四层来理解：

1. Provider 层
   Claude、Codex、Gemini 各自保留官方 hook 语义。

2. Bridge 层
   `bridge-rs` 负责把 provider 原生事件映射成稳定运行时载荷。

3. Runtime 层
   Swift 服务负责 session、transcript 同步、审批、工具状态和有内存边界的历史管理。

4. UI 层
   Notch、聊天视图、会话列表和设置页都消费共享运行时状态。

建议先看这些文档：

- [当前产品总览](./docs/current-product-overview.zh.md)
- [统一 Agent 协议 v1](./docs/unified-agent-protocol.zh.md)
- [多 Agent 架构](./docs/multi-agent-architecture.zh.md)
- [运行时可观测性](./docs/runtime-observability.zh.md)

## 快速开始

### 依赖

- macOS 15.6+
- Xcode 17+
- Rust toolchain
- Claude Code CLI
- 可选：Codex CLI、Gemini CLI

### 本地构建

```bash
./scripts/build.sh
```

本地跳过签名：

```bash
AGENT_ISLAND_NO_SIGN=1 ./scripts/build.sh
```

### 本地发布构建

```bash
./scripts/create-release.sh
```

这会打包 app、准备 Sparkle 产物，并让本地发布行为和 CI 保持一致。

## 发布流程

现在 tag 发布会通过 GitHub Actions 自动产出发布内容，并保留 appcast 历史，而不是每次只覆盖成单条记录。

当前发布链路包含：

- 构建 app 和 bundled bridge
- 打包 dmg / zip
- 发布 GitHub Release 资产
- 重新生成并合并 Sparkle `appcast.xml`
- 部署 appcast 到 GitHub Pages

相关地址：

- [GitHub appcast](https://javen-yan.github.io/agent-island/appcast.xml)

## 调试与排查

查看 app 日志：

```bash
log stream --level debug --predicate 'subsystem == "com.agentisland"'
```

只看 hooks：

```bash
log stream --level debug --predicate 'subsystem == "com.agentisland" AND category == "Hooks"'
```

常见排查点：

- 如果 Codex 审批看起来卡住，先确认 CLI 是否还在等待终端确认。
- 如果某个 session 明显吃内存，先看是不是包含很多超长 tool 输出，再确认懒加载是否按预期工作。
- 如果 app 状态和 provider 行为不一致，先看 bridge 日志，再往 UI 层排查。
- 如果发布元数据不对，连同 tag 版本、Xcode 版本号和生成出的 appcast 一起核对。

## 仓库结构

- `AgentIsland/`: macOS app
- `bridge-rs/`: Rust bridge runtime
- `docs/`: 架构、运行时与集成文档
- `scripts/`: 构建、打包、发布脚本

## 致谢

本项目基于 [farouqaldori/claude-island](https://github.com/farouqaldori/claude-island) 演化而来，并在其桥接与通知思路上扩展成更通用的多 agent 运行时。

## License

Apache 2.0
