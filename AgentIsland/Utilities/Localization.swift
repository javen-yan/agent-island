//
//  Localization.swift
//  Agent Island
//
//  Lightweight localization support for Settings-first migration.
//

import Foundation
import Combine

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published private(set) var appLanguage: AppLanguage

    private init() {
        self.appLanguage = AppSettings.appLanguage
    }

    var resolvedLanguage: SupportedLanguage {
        Self.resolveLanguage(setting: appLanguage)
    }

    func setLanguage(_ language: AppLanguage) {
        guard appLanguage != language else { return }
        appLanguage = language
        AppSettings.appLanguage = language
    }

    nonisolated static func resolveLanguage(setting: AppLanguage) -> SupportedLanguage {
        switch setting {
        case .english:
            return .english
        case .simplifiedChinese:
            return .simplifiedChinese
        case .system:
            return resolveSystemLanguage()
        }
    }

    nonisolated static func resolveSystemLanguage() -> SupportedLanguage {
        for identifier in Locale.preferredLanguages {
            let lowered = identifier.lowercased()
            if lowered.hasPrefix("zh-hans") || lowered.hasPrefix("zh-cn") || lowered == "zh" {
                return .simplifiedChinese
            }
            if lowered.hasPrefix("en") {
                return .english
            }
        }
        return .english
    }
}

enum SupportedLanguage: String {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
}

enum L10nKey: String {
    case settingsPaneGeneralTitle
    case settingsPaneGeneralSubtitle
    case settingsPaneAgentsTitle
    case settingsPaneAgentsSubtitle
    case settingsPaneDiagnosticsTitle
    case settingsPaneDiagnosticsSubtitle
    case settingsPaneApprovalRulesTitle
    case settingsPaneApprovalRulesSubtitle
    case settingsPaneAboutTitle
    case settingsPaneAboutSubtitle
    case settingsQuit
    case settingsAboutTagline
    case settingsAboutCheckForUpdates
    case settingsAboutOpenGitHub
    case settingsAboutStarOnGitHub
    case settingsUpdateChecking
    case settingsUpdateUpToDate
    case settingsUpdateAvailable
    case settingsUpdateDownloading
    case settingsUpdatePreparing
    case settingsUpdateReady
    case settingsUpdateInstalling
    case settingsGeneralPreferencesTitle
    case settingsGeneralPreferencesSubtitle
    case settingsGeneralPermissionsTitle
    case settingsGeneralPermissionsSubtitle
    case settingsGeneralIslandDisplay
    case settingsGeneralAttentionSound
    case settingsGeneralLaunchAtLogin
    case settingsGeneralAccessibility
    case settingsLanguage
    case settingsAutomatic
    case settingsAutomaticSubtitle
    case settingsScreen
    case settingsNotificationSound
    case settingsBuiltIn
    case settingsMain
    case settingsEnabled
    case settingsOpenSystemSettings
    case settingsAgentsIntegrationsTitle
    case settingsAgentsIntegrationsSubtitle
    case settingsAgentsApprovals
    case settingsAgentsHistory
    case settingsAgentsMonitoringOnly
    case settingsAgentsClaudeDescription
    case settingsAgentsCodexDescription
    case settingsAgentsGeminiDescription
    case settingsDiagnosticsLoggingTitle
    case settingsDiagnosticsLoggingSubtitle
    case settingsDiagnosticsLogFilesTitle
    case settingsDiagnosticsLogFilesSubtitle
    case settingsDiagnosticsBridgeLogging
    case settingsDiagnosticsBridgeLevel
    case settingsDiagnosticsAppLogging
    case settingsDiagnosticsAppLevel
    case settingsDiagnosticsOpenLogsFolder
    case settingsDiagnosticsRevealBridgeLog
    case settingsDiagnosticsRevealAppLog
    case settingsToastBridgeLoggingEnabled
    case settingsToastBridgeLoggingDisabled
    case settingsToastBridgeLevelSet
    case settingsToastAppLoggingEnabled
    case settingsToastAppLoggingDisabled
    case settingsToastAppLevelSet
    case settingsToastLaunchAtLoginEnabled
    case settingsToastLaunchAtLoginDisabled
    case settingsToastLaunchAtLoginFailed
    case settingsToastDisabledAgent
    case settingsToastFailedInstallAgent
    case settingsToastInstalledAgent
    case settingsToastRepairFailedAgent
    case settingsToastRepairedAgent
    case settingsToastRemovedApprovalRule
    case settingsVersionFormat
    case settingsRepairIntegration
    case settingsApprovalRulesEmptyTitle
    case settingsApprovalRulesEmptyDescription
    case settingsApprovalRulesSavedTitle
    case settingsApprovalRulesSavedSubtitle
    case settingsDelete
    case agentNameClaude
    case agentNameCodex
    case agentNameGemini
    case approvalDeny
    case approvalAllowOnce
    case approvalAllowAlways
    case approvalAutoExecute
    case approvalContinue
    case approvalOnce
    case approvalAlways
    case approvalAuto
    case exitQuit
    case exitExit
    case phaseWaitingForApproval
    case phaseWaitingForTerminalConfirmation
    case phaseReadyForInput
    case phaseProcessing
    case phaseCompacting
    case phaseIdle
    case phaseEnded
    case timeNow
    case instancesNoSessions
    case instancesRunAgentsInTerminal
    case instancesContinueInTerminal
    case instancesYou
    case instancesNeedsYourInput
    case instancesReadyToContinue
    case asksSuffix
    case chatLoadingMessages
    case chatNoMessagesYet
    case chatMessagePlaceholder
    case chatEnableMessagingPlaceholder
    case chatSubagentUsedTools
    case chatMoreToolUses
    case chatInterrupted
    case chatConfirmInTerminal
    case chatTaskToolsSummary
    case chatWaitingPrefix
    case chatRunningAgent
    case chatProcessing
    case chatWorking
    case chatWaitingForConfirmationInTerminal
    case chatTerminalUnavailable
    case chatContinueInTerminal
    case chatNeedsInputInTerminal
    case chatNeedsApprovalInTerminal
    case chatConfirmCommand
    case chatPermissionRequest
    case chatReviewCommandBeforeContinuing
    case chatActionNeedsApprovalBeforeContinuing
    case chatProviderContinueFooter
    case chatNewMessageSingular
    case chatNewMessagePlural
    case permissionSourceCodex
    case permissionSourceGeminiRichRewrite
    case permissionSourceProviderManaged
    case permissionSourceHandledByApp
    case permissionSourceLimitedControls
}

enum L10n {
    nonisolated static func text(_ key: L10nKey, _ args: CVarArg...) -> String {
        let language = LocalizationManager.resolveLanguage(setting: AppSettings.appLanguageSnapshot())
        let template = localizedStrings[key]?[language] ?? localizedStrings[key]?[.english] ?? key.rawValue
        guard !args.isEmpty else { return template }
        return String(format: template, locale: Locale(identifier: language.rawValue), arguments: args)
    }

    nonisolated private static let localizedStrings: [L10nKey: [SupportedLanguage: String]] = [
        .settingsPaneGeneralTitle: [.english: "General", .simplifiedChinese: "通用"],
        .settingsPaneGeneralSubtitle: [.english: "Display, notifications, startup, and required permissions.", .simplifiedChinese: "显示、通知、启动和必要权限。"],
        .settingsPaneAgentsTitle: [.english: "Agents", .simplifiedChinese: "Agents"],
        .settingsPaneAgentsSubtitle: [.english: "Hook setup and health for connected agents.", .simplifiedChinese: "已连接 agent 的 hook 配置与状态。"],
        .settingsPaneDiagnosticsTitle: [.english: "Diagnostics", .simplifiedChinese: "诊断"],
        .settingsPaneDiagnosticsSubtitle: [.english: "Logs and runtime troubleshooting.", .simplifiedChinese: "日志与运行时诊断。"],
        .settingsPaneApprovalRulesTitle: [.english: "Approval Rules", .simplifiedChinese: "审批规则"],
        .settingsPaneApprovalRulesSubtitle: [.english: "Saved approval decisions from supported agents.", .simplifiedChinese: "来自受支持 agent 的已保存审批结果。"],
        .settingsPaneAboutTitle: [.english: "About", .simplifiedChinese: "关于"],
        .settingsPaneAboutSubtitle: [.english: "Version, updates, and project links.", .simplifiedChinese: "版本、更新与项目链接。"],
        .settingsQuit: [.english: "Quit", .simplifiedChinese: "退出"],
        .settingsAboutTagline: [.english: "A unified island for connected agents.", .simplifiedChinese: "一个统一承载已连接 agent 的 Island。"],
        .settingsAboutCheckForUpdates: [.english: "Check for Updates", .simplifiedChinese: "检查更新"],
        .settingsAboutOpenGitHub: [.english: "Open GitHub", .simplifiedChinese: "打开 GitHub"],
        .settingsAboutStarOnGitHub: [.english: "Star on GitHub", .simplifiedChinese: "在 GitHub 点 Star"],
        .settingsUpdateChecking: [.english: "Checking for updates…", .simplifiedChinese: "正在检查更新…"],
        .settingsUpdateUpToDate: [.english: "AgentIsland is up to date.", .simplifiedChinese: "当前已是最新版本。"],
        .settingsUpdateAvailable: [.english: "Update available: %@. Use the island update flow to continue.", .simplifiedChinese: "发现新版本：%@。请通过 Island 更新流程继续。"],
        .settingsUpdateDownloading: [.english: "Downloading update… %d%%", .simplifiedChinese: "正在下载更新… %d%%"],
        .settingsUpdatePreparing: [.english: "Preparing update… %d%%", .simplifiedChinese: "正在准备更新… %d%%"],
        .settingsUpdateReady: [.english: "Update %@ is ready to install.", .simplifiedChinese: "更新 %@ 已可安装。"],
        .settingsUpdateInstalling: [.english: "Installing update…", .simplifiedChinese: "正在安装更新…"],
        .settingsGeneralPreferencesTitle: [.english: "Preferences", .simplifiedChinese: "偏好设置"],
        .settingsGeneralPreferencesSubtitle: [.english: "Common display, sound, and startup options.", .simplifiedChinese: "常用显示、声音与启动选项。"],
        .settingsGeneralPermissionsTitle: [.english: "Permissions", .simplifiedChinese: "权限"],
        .settingsGeneralPermissionsSubtitle: [.english: "Accessibility is required for direct session control.", .simplifiedChinese: "辅助功能权限用于会话直接控制。"],
        .settingsGeneralIslandDisplay: [.english: "Display", .simplifiedChinese: "显示器"],
        .settingsGeneralAttentionSound: [.english: "Attention Sound", .simplifiedChinese: "提醒声音"],
        .settingsGeneralLaunchAtLogin: [.english: "Launch at Login", .simplifiedChinese: "登录时启动"],
        .settingsGeneralAccessibility: [.english: "Accessibility", .simplifiedChinese: "辅助功能"],
        .settingsLanguage: [.english: "Language", .simplifiedChinese: "语言"],
        .settingsAutomatic: [.english: "Automatic", .simplifiedChinese: "自动"],
        .settingsAutomaticSubtitle: [.english: "Prefer the built-in display, then the main display.", .simplifiedChinese: "优先使用内建显示器，其次使用主显示器。"],
        .settingsScreen: [.english: "Screen", .simplifiedChinese: "屏幕"],
        .settingsNotificationSound: [.english: "Notification Sound", .simplifiedChinese: "通知声音"],
        .settingsBuiltIn: [.english: "Built-in", .simplifiedChinese: "内建"],
        .settingsMain: [.english: "Main", .simplifiedChinese: "主屏幕"],
        .settingsEnabled: [.english: "Enabled", .simplifiedChinese: "已启用"],
        .settingsOpenSystemSettings: [.english: "Open System Settings", .simplifiedChinese: "打开系统设置"],
        .settingsAgentsIntegrationsTitle: [.english: "Integrations", .simplifiedChinese: "集成"],
        .settingsAgentsIntegrationsSubtitle: [.english: "Enable each agent integration and review its current status.", .simplifiedChinese: "启用各个 agent 集成并查看当前状态。"],
        .settingsAgentsApprovals: [.english: "Approvals", .simplifiedChinese: "审批"],
        .settingsAgentsHistory: [.english: "History", .simplifiedChinese: "历史"],
        .settingsAgentsMonitoringOnly: [.english: "Monitoring only", .simplifiedChinese: "仅观察"],
        .settingsAgentsClaudeDescription: [.english: "Full hook integration with approvals, history, and runtime control.", .simplifiedChinese: "完整 hook 集成，包含审批、历史和运行时控制。"],
        .settingsAgentsCodexDescription: [.english: "Bash-only monitoring that expands the island after each response and keeps follow-up lightweight inside the island.", .simplifiedChinese: "仅观察 Bash，会在每轮完成后自动展开 Island，并在 Island 内保持轻量后续交互。"],
        .settingsAgentsGeminiDescription: [.english: "Hook integration with approvals and direct interaction support.", .simplifiedChinese: "支持审批与直接交互的 hook 集成。"],
        .settingsDiagnosticsLoggingTitle: [.english: "Logging", .simplifiedChinese: "日志"],
        .settingsDiagnosticsLoggingSubtitle: [.english: "Bridge and app logs help diagnose runtime issues.", .simplifiedChinese: "Bridge 和应用日志可用于诊断运行时问题。"],
        .settingsDiagnosticsLogFilesTitle: [.english: "Log Files", .simplifiedChinese: "日志文件"],
        .settingsDiagnosticsLogFilesSubtitle: [.english: "Open the logs folder or reveal individual log files.", .simplifiedChinese: "打开日志目录或定位具体日志文件。"],
        .settingsDiagnosticsBridgeLogging: [.english: "Bridge Logging", .simplifiedChinese: "Bridge 日志"],
        .settingsDiagnosticsBridgeLevel: [.english: "Bridge Level", .simplifiedChinese: "Bridge 级别"],
        .settingsDiagnosticsAppLogging: [.english: "App Logging", .simplifiedChinese: "应用日志"],
        .settingsDiagnosticsAppLevel: [.english: "App Level", .simplifiedChinese: "应用级别"],
        .settingsDiagnosticsOpenLogsFolder: [.english: "Open Logs Folder", .simplifiedChinese: "打开日志目录"],
        .settingsDiagnosticsRevealBridgeLog: [.english: "Reveal bridge.log", .simplifiedChinese: "显示 bridge.log"],
        .settingsDiagnosticsRevealAppLog: [.english: "Reveal app.log", .simplifiedChinese: "显示 app.log"],
        .settingsToastBridgeLoggingEnabled: [.english: "Enabled bridge file logging", .simplifiedChinese: "已启用 bridge 文件日志"],
        .settingsToastBridgeLoggingDisabled: [.english: "Disabled bridge file logging", .simplifiedChinese: "已关闭 bridge 文件日志"],
        .settingsToastBridgeLevelSet: [.english: "Bridge log level set to %@", .simplifiedChinese: "Bridge 日志级别已设为 %@"],
        .settingsToastAppLoggingEnabled: [.english: "Enabled app file logging", .simplifiedChinese: "已启用应用文件日志"],
        .settingsToastAppLoggingDisabled: [.english: "Disabled app file logging", .simplifiedChinese: "已关闭应用文件日志"],
        .settingsToastAppLevelSet: [.english: "App log level set to %@", .simplifiedChinese: "应用日志级别已设为 %@"],
        .settingsToastLaunchAtLoginEnabled: [.english: "Launch at login enabled", .simplifiedChinese: "已启用登录时启动"],
        .settingsToastLaunchAtLoginDisabled: [.english: "Launch at login disabled", .simplifiedChinese: "已关闭登录时启动"],
        .settingsToastLaunchAtLoginFailed: [.english: "Failed to update launch at login", .simplifiedChinese: "更新登录时启动失败"],
        .settingsToastDisabledAgent: [.english: "Disabled %@", .simplifiedChinese: "已关闭 %@"],
        .settingsToastFailedInstallAgent: [.english: "Failed to install %@: %@", .simplifiedChinese: "安装 %@ 失败：%@"],
        .settingsToastInstalledAgent: [.english: "Installed %@", .simplifiedChinese: "已安装 %@"],
        .settingsToastRepairFailedAgent: [.english: "Repair failed for %@: %@", .simplifiedChinese: "修复 %@ 失败：%@"],
        .settingsToastRepairedAgent: [.english: "Repaired %@", .simplifiedChinese: "已修复 %@"],
        .settingsToastRemovedApprovalRule: [.english: "Removed approval rule", .simplifiedChinese: "已删除审批规则"],
        .settingsVersionFormat: [.english: "Version %@ (%@)", .simplifiedChinese: "版本 %@（%@）"],
        .settingsRepairIntegration: [.english: "Repair Integration", .simplifiedChinese: "修复集成"],
        .settingsApprovalRulesEmptyTitle: [.english: "No Saved Approval Rules", .simplifiedChinese: "暂无已保存审批规则"],
        .settingsApprovalRulesEmptyDescription: [.english: "Saved approval decisions from supported agents appear here for faster future runs.", .simplifiedChinese: "受支持 agent 的已保存审批结果会显示在这里，方便后续更快执行。"],
        .settingsApprovalRulesSavedTitle: [.english: "Saved Rules", .simplifiedChinese: "已保存规则"],
        .settingsApprovalRulesSavedSubtitle: [.english: "Persistent approval decisions from supported agents appear here.", .simplifiedChinese: "受支持 agent 的持久化审批结果会显示在这里。"],
        .settingsDelete: [.english: "Delete", .simplifiedChinese: "删除"],
        .agentNameClaude: [.english: "Claude", .simplifiedChinese: "Claude"],
        .agentNameCodex: [.english: "Codex", .simplifiedChinese: "Codex"],
        .agentNameGemini: [.english: "Gemini", .simplifiedChinese: "Gemini"],
        .approvalDeny: [.english: "Deny", .simplifiedChinese: "拒绝"],
        .approvalAllowOnce: [.english: "Allow Once", .simplifiedChinese: "允许一次"],
        .approvalAllowAlways: [.english: "Allow Always", .simplifiedChinese: "始终允许"],
        .approvalAutoExecute: [.english: "Auto Execute", .simplifiedChinese: "自动执行"],
        .approvalContinue: [.english: "Continue", .simplifiedChinese: "继续"],
        .approvalOnce: [.english: "Once", .simplifiedChinese: "一次"],
        .approvalAlways: [.english: "Always", .simplifiedChinese: "始终"],
        .approvalAuto: [.english: "Auto", .simplifiedChinese: "自动"],
        .exitQuit: [.english: "Quit", .simplifiedChinese: "退出"],
        .exitExit: [.english: "Exit", .simplifiedChinese: "结束"],
        .phaseWaitingForApproval: [.english: "Waiting for approval: %@", .simplifiedChinese: "等待审批：%@"],
        .phaseWaitingForTerminalConfirmation: [.english: "Waiting in Terminal: %@", .simplifiedChinese: "等待终端确认：%@"],
        .phaseReadyForInput: [.english: "Ready for input", .simplifiedChinese: "等待输入"],
        .phaseProcessing: [.english: "Processing...", .simplifiedChinese: "处理中…"],
        .phaseCompacting: [.english: "Compacting context...", .simplifiedChinese: "正在压缩上下文…"],
        .phaseIdle: [.english: "Idle", .simplifiedChinese: "空闲"],
        .phaseEnded: [.english: "Ended", .simplifiedChinese: "已结束"],
        .timeNow: [.english: "now", .simplifiedChinese: "刚刚"],
        .instancesNoSessions: [.english: "No sessions", .simplifiedChinese: "暂无会话"],
        .instancesRunAgentsInTerminal: [.english: "Run a supported agent in terminal", .simplifiedChinese: "在终端中运行受支持的 agent"],
        .instancesContinueInTerminal: [.english: "Continue below", .simplifiedChinese: "可在下方继续"],
        .instancesReadyToContinue: [.english: "Ready to continue", .simplifiedChinese: "可继续交互"],
        .instancesYou: [.english: "You:", .simplifiedChinese: "你："],
        .instancesNeedsYourInput: [.english: "Needs your input", .simplifiedChinese: "需要你的输入"],
        .asksSuffix: [.english: "%@ asks", .simplifiedChinese: "%@ 请求输入"],
        .chatLoadingMessages: [.english: "Loading messages...", .simplifiedChinese: "正在加载消息…"],
        .chatNoMessagesYet: [.english: "No messages yet", .simplifiedChinese: "暂无消息"],
        .chatMessagePlaceholder: [.english: "Message %@...", .simplifiedChinese: "发送给 %@…"],
        .chatEnableMessagingPlaceholder: [.english: "Open %@ in tmux or cmux to enable messaging", .simplifiedChinese: "请在 tmux 或 cmux 中打开 %@ 以启用消息发送"],
        .chatSubagentUsedTools: [.english: "Subagent used %d tools:", .simplifiedChinese: "子代理使用了 %d 个工具："],
        .chatMoreToolUses: [.english: "+%d more tool uses", .simplifiedChinese: "+%d 个更多工具调用"],
        .chatInterrupted: [.english: "Interrupted", .simplifiedChinese: "已中断"],
        .chatConfirmInTerminal: [.english: "Confirm in Terminal", .simplifiedChinese: "请在终端确认"],
        .chatTaskToolsSummary: [.english: "%@ (%d tools)", .simplifiedChinese: "%@（%d 个工具）"],
        .chatWaitingPrefix: [.english: "Waiting: %@", .simplifiedChinese: "等待：%@"],
        .chatRunningAgent: [.english: "Running agent...", .simplifiedChinese: "正在运行代理…"],
        .chatProcessing: [.english: "Processing", .simplifiedChinese: "处理中"],
        .chatWorking: [.english: "Working", .simplifiedChinese: "执行中"],
        .chatWaitingForConfirmationInTerminal: [.english: "Waiting for confirmation in Terminal", .simplifiedChinese: "等待在终端确认"],
        .chatTerminalUnavailable: [.english: "Terminal unavailable", .simplifiedChinese: "终端不可用"],
        .chatContinueInTerminal: [.english: "This turn is complete. Continue below.", .simplifiedChinese: "这一轮已完成，可在下方继续。"],
        .chatNeedsInputInTerminal: [.english: "%@ needs your input in Terminal", .simplifiedChinese: "%@ 需要你在终端输入"],
        .chatNeedsApprovalInTerminal: [.english: "%@ needs approval in Terminal", .simplifiedChinese: "%@ 需要你在终端审批"],
        .chatConfirmCommand: [.english: "Confirm Command", .simplifiedChinese: "确认命令"],
        .chatPermissionRequest: [.english: "Permission Request", .simplifiedChinese: "权限请求"],
        .chatReviewCommandBeforeContinuing: [.english: "Review this command before continuing.", .simplifiedChinese: "继续前请先检查这个命令。"],
        .chatActionNeedsApprovalBeforeContinuing: [.english: "This action needs your approval before continuing.", .simplifiedChinese: "继续前需要你的批准。"],
        .chatProviderContinueFooter: [.english: "%@ Continue will let the provider run this command immediately.", .simplifiedChinese: "%@点击继续后，provider 会立即执行这个命令。"],
        .chatNewMessageSingular: [.english: "1 new message", .simplifiedChinese: "1 条新消息"],
        .chatNewMessagePlural: [.english: "%d new messages", .simplifiedChinese: "%d 条新消息"],
        .permissionSourceCodex: [.english: "Codex mixes Agent Island runtime approvals with provider-side config rules, so some commands may be auto-approved before they reach this panel.", .simplifiedChinese: "Codex 同时使用 Agent Island 运行时审批和 provider 侧配置规则，因此有些命令可能会在到达这个面板前就被自动放行。"],
        .permissionSourceGeminiRichRewrite: [.english: "Gemini supports richer tool rewriting in provider hooks, but this panel is currently using the safe allow-or-deny path.", .simplifiedChinese: "Gemini 的 provider hooks 支持更丰富的工具改写能力，但当前面板仍使用更安全的允许/拒绝路径。"],
        .permissionSourceProviderManaged: [.english: "%@ also applies provider-side approval rules. Some requests may be pre-approved before Agent Island sees them.", .simplifiedChinese: "%@ 也会应用 provider 侧审批规则。有些请求可能会在 Agent Island 看到之前就被预先批准。"],
        .permissionSourceHandledByApp: [.english: "This approval is being handled directly by Agent Island.", .simplifiedChinese: "这次审批由 Agent Island 直接处理。"],
        .permissionSourceLimitedControls: [.english: "This provider exposes limited approval controls in Agent Island.", .simplifiedChinese: "这个 provider 在 Agent Island 中仅暴露有限的审批控制。"],
    ]
}
