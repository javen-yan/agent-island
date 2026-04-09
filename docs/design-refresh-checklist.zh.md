# 设计刷新 Checklist

这份清单用于跟踪统一运行时落地之后的文档收口和产品打磨工作。

## 1. 文档刷新

- [x] 以统一运行时架构为中心重写文档索引
- [x] 新增运行时可观测性文档
- [x] 新增 OpenCode 集成计划
- [x] 重写扩展指南，改为面向统一协议和 capability-based adapter
- [x] 删除过时的内部 Hook 协议文档
- [x] 删除过时的终端交互文档

## 2. 日志控制

- [x] 新增 bridge 文件日志开关设置
- [x] 新增 bridge 日志级别设置
- [x] 扩展 bridge profile，写入日志配置
- [x] 将日志配置透传到 bridge 启动命令
- [x] Rust bridge 按开关和级别控制日志写入
- [x] 在设置菜单中暴露日志控制

## 3. Provider 品牌图标

- [x] 新增 Claude 官方风格图标资源
- [x] 新增 Codex 官方风格图标资源
- [x] 新增 Gemini 官方风格图标资源
- [x] 通过共享 icon registry 接入 provider 图标

## 4. OpenCode 规划

- [x] 查阅官方 OpenCode 文档
- [x] 文档化集成策略
- [x] 文档化 capability 假设与实施清单

## 5. 验证

- [x] `swift test` in `UnifiedRuntimePackage`
- [x] `cargo test` in `bridge-rs`
- [x] `xcodebuild -quiet -project AgentIsland.xcodeproj -scheme AgentIsland`
