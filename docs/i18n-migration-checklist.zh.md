# I18N 迁移 Checklist

## 目标

增加一套本地化能力，满足：

- 默认跟随系统语言
- 支持用户手动指定语言
- 没有匹配语言时自动回退到 English

## 范围

第一阶段先覆盖 Settings 窗口，先把架构跑通，再迁移 Island、聊天和其它长尾界面。

## 计划

- [x] 盘点现有文案入口，确认目前没有 strings catalog
- [x] 明确目标行为：`system`、`english`、`simplified chinese`
- [ ] 增加轻量级本地化管理器，负责语言解析
- [ ] 增加持久化语言设置
- [ ] 在 Settings 中增加语言选择器
- [ ] 为 Settings 窗口补本地化资源
- [ ] 将 `SettingsWindowView.swift` 迁移到本地化读取
- [ ] 验证系统语言自动识别
- [ ] 验证手动切换到 English
- [ ] 验证手动切换到 Simplified Chinese
- [ ] 验证不支持的系统语言自动回退到 English

## 说明

- English 作为基础文案和回退语言。
- 第一阶段只覆盖 Settings；Island、chat、tool results、diagnostics 文案后续分批迁移。
- key 需要保持语义稳定，不要直接用整句英文当 key。
