//
//  AgentSettingsFacade.swift
//  Agent Island
//
//  Centralizes settings-side service, system, and persistence actions so UI can
//  consume a single facade instead of reaching into multiple layers directly.
//

import AppKit
import ApplicationServices
import Foundation
import ServiceManagement

struct AgentSettingsScreenOption: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?

    static let automatic = AgentSettingsScreenOption(
        id: "automatic",
        title: L10n.text(.settingsAutomatic),
        subtitle: L10n.text(.settingsAutomaticSubtitle)
    )

    static func id(for screen: NSScreen) -> String {
        let identifier = ScreenIdentifier(screen: screen)
        let displayID = identifier.displayID.map(String.init) ?? "unknown"
        return "\(displayID)::\(identifier.localizedName)"
    }
}

struct AgentSettingsSnapshot {
    let launchAtLogin: Bool
    let pluginSummaries: [AgentHookPluginSummary]
    let approvalRules: [ApprovalRule]
    let codexBuiltInDangerousCommandPatterns: [String]
    let codexDangerousCommandPatterns: [String]
    let bridgeLogEnabled: Bool
    let bridgeLogLevel: BridgeLogLevel
    let appLogEnabled: Bool
    let appLogLevel: BridgeLogLevel
    let selectedSound: NotificationSound
    let selectedLanguage: AppLanguage
    let chatHistoryRetentionLimit: Int
    let selectedScreenOptionID: String
    let screenOptions: [AgentSettingsScreenOption]
}

enum AgentSettingsActionResult {
    case none
    case success(String)
    case failure(String)
}

@MainActor
final class AgentSettingsFacade {
    static let shared = AgentSettingsFacade()
    nonisolated static let approvalRulesDidChangeNotification = ApprovalPolicyStore.rulesDidChangeNotification

    let updateManager: UpdateManager

    private let pluginManager: AgentHookPluginManager
    private let screenSelector: ScreenSelector
    private let workspace: NSWorkspace
    private let fileManager: FileManager
    private let approvalPolicyStore: ApprovalPolicyStore

    init(
        updateManager: UpdateManager? = nil,
        pluginManager: AgentHookPluginManager? = nil,
        screenSelector: ScreenSelector? = nil,
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default,
        approvalPolicyStore: ApprovalPolicyStore = .shared
    ) {
        self.updateManager = updateManager ?? .shared
        self.pluginManager = pluginManager ?? .shared
        self.screenSelector = screenSelector ?? .shared
        self.workspace = workspace
        self.fileManager = fileManager
        self.approvalPolicyStore = approvalPolicyStore
    }

    func loadSnapshot() async -> AgentSettingsSnapshot {
        pluginManager.refreshBridgeProfilesFromApprovalRules()

        screenSelector.refreshScreens()
        let selectedScreenOptionID: String
        if screenSelector.selectionMode == .automatic {
            selectedScreenOptionID = AgentSettingsScreenOption.automatic.id
        } else if let selectedScreen = screenSelector.selectedScreen {
            selectedScreenOptionID = AgentSettingsScreenOption.id(for: selectedScreen)
        } else {
            selectedScreenOptionID = AgentSettingsScreenOption.automatic.id
        }

        return AgentSettingsSnapshot(
            launchAtLogin: SMAppService.mainApp.status == .enabled,
            pluginSummaries: pluginManager.pluginSummaries(),
            approvalRules: await approvalPolicyStore.allRules(),
            codexBuiltInDangerousCommandPatterns: AppSettings.codexBuiltInDangerousCommandPatterns,
            codexDangerousCommandPatterns: AppSettings.codexDangerousCommandPatterns,
            bridgeLogEnabled: AppSettings.bridgeLogEnabled,
            bridgeLogLevel: AppSettings.bridgeLogLevel,
            appLogEnabled: AppSettings.appLogEnabled,
            appLogLevel: AppSettings.appLogLevel,
            selectedSound: AppSettings.notificationSound,
            selectedLanguage: AppSettings.appLanguage,
            chatHistoryRetentionLimit: AppSettings.chatHistoryRetentionLimit,
            selectedScreenOptionID: selectedScreenOptionID,
            screenOptions: resolvedScreenOptions(),
        )
    }

    func loadApprovalRules() async -> [ApprovalRule] {
        await approvalPolicyStore.allRules()
    }

    func setLaunchAtLogin(_ enabled: Bool) -> AgentSettingsActionResult {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                return .success(L10n.text(.settingsToastLaunchAtLoginEnabled))
            } else {
                try SMAppService.mainApp.unregister()
                return .success(L10n.text(.settingsToastLaunchAtLoginDisabled))
            }
        } catch {
            return .failure(L10n.text(.settingsToastLaunchAtLoginFailed))
        }
    }

    func selectScreenOption(_ id: String) {
        if id == AgentSettingsScreenOption.automatic.id {
            screenSelector.selectAutomatic()
        } else if let screen = screenSelector.availableScreens.first(where: {
            AgentSettingsScreenOption.id(for: $0) == id
        }) {
            screenSelector.selectScreen(screen)
        }

        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func setNotificationSound(_ sound: NotificationSound) {
        AppSettings.notificationSound = sound
        if let soundName = sound.soundName {
            NSSound(named: soundName)?.play()
        }
    }

    func setAppLanguage(_ language: AppLanguage) {
        LocalizationManager.shared.setLanguage(language)
    }

    func setChatHistoryRetentionLimit(_ limit: Int) {
        AppSettings.chatHistoryRetentionLimit = limit
        Task {
            await SessionStore.shared.applyChatHistoryRetentionToAllSessions()
        }
    }

    func setCodexDangerousCommandPatterns(_ patterns: [String]) -> AgentSettingsActionResult {
        AppSettings.codexDangerousCommandPatterns = patterns
        pluginManager.refreshBridgeProfilesFromApprovalRules()
        return .success(L10n.text(.settingsToastCodexPatternsSaved))
    }

    func togglePlugin(_ summary: AgentHookPluginSummary) -> AgentSettingsActionResult {
        guard summary.isAvailable else { return .none }

        if summary.isEnabled {
            pluginManager.uninstall(agentType: summary.agentType)
            return .success(L10n.text(.settingsToastDisabledAgent, summary.agentType.displayName))
        } else if let error = pluginManager.install(agentType: summary.agentType) {
            return .failure(L10n.text(.settingsToastFailedInstallAgent, summary.agentType.displayName, error.localizedDescription))
        } else {
            return .success(L10n.text(.settingsToastInstalledAgent, summary.agentType.displayName))
        }
    }

    func repairPlugin(_ summary: AgentHookPluginSummary) -> AgentSettingsActionResult {
        guard summary.isAvailable else { return .none }

        if let error = pluginManager.repair(agentType: summary.agentType) {
            return .failure(L10n.text(.settingsToastRepairFailedAgent, summary.agentType.displayName, error.localizedDescription))
        } else {
            return .success(L10n.text(.settingsToastRepairedAgent, summary.agentType.displayName))
        }
    }

    func removeApprovalRule(_ rule: ApprovalRule) async -> AgentSettingsActionResult {
        await approvalPolicyStore.removeRule(id: rule.id)
        return .success(L10n.text(.settingsToastRemovedApprovalRule))
    }

    func setBridgeLogEnabled(_ enabled: Bool) -> AgentSettingsActionResult {
        AppSettings.bridgeLogEnabled = enabled
        pluginManager.refreshBridgeProfilesFromApprovalRules()
        return .success(enabled ? L10n.text(.settingsToastBridgeLoggingEnabled) : L10n.text(.settingsToastBridgeLoggingDisabled))
    }

    func setBridgeLogLevel(_ level: BridgeLogLevel) -> AgentSettingsActionResult {
        AppSettings.bridgeLogLevel = level
        pluginManager.refreshBridgeProfilesFromApprovalRules()
        return .success(L10n.text(.settingsToastBridgeLevelSet, level.displayName))
    }

    func setAppLogEnabled(_ enabled: Bool) -> AgentSettingsActionResult {
        AppSettings.appLogEnabled = enabled
        return .success(enabled ? L10n.text(.settingsToastAppLoggingEnabled) : L10n.text(.settingsToastAppLoggingDisabled))
    }

    func setAppLogLevel(_ level: BridgeLogLevel) -> AgentSettingsActionResult {
        AppSettings.appLogLevel = level
        return .success(L10n.text(.settingsToastAppLevelSet, level.displayName))
    }

    func openLogsFolder() {
        workspace.open(AppPathResolver.logsDirectory)
    }

    func revealBridgeLog() {
        revealLogFile(at: AppPathResolver.bridgeLogFileURL)
    }

    func revealAppLog() {
        revealLogFile(at: AppPathResolver.appLogFileURL)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        workspace.open(url)
    }

    func checkForUpdates() {
        updateManager.checkForUpdates()
    }

    func openProjectRepository() {
        guard let url = URL(string: "https://github.com/javen-yan/agent-island") else {
            return
        }
        workspace.open(url)
    }

    func openProjectStarPage() {
        openProjectRepository()
    }

    private func resolvedScreenOptions() -> [AgentSettingsScreenOption] {
        [AgentSettingsScreenOption.automatic] + screenSelector.availableScreens.map { screen in
            AgentSettingsScreenOption(
                id: AgentSettingsScreenOption.id(for: screen),
                title: screen.localizedName,
                subtitle: screenSubtitle(for: screen)
            )
        }
    }

    private func revealLogFile(at url: URL) {
        if !fileManager.fileExists(atPath: url.path) {
            if !fileManager.fileExists(atPath: AppPathResolver.logsDirectory.path) {
                try? fileManager.createDirectory(at: AppPathResolver.logsDirectory, withIntermediateDirectories: true)
            }
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        workspace.activateFileViewerSelecting([url])
    }

    private func screenSubtitle(for screen: NSScreen) -> String? {
        var parts: [String] = []
        if screen.isBuiltinDisplay {
            parts.append(L10n.text(.settingsBuiltIn))
        }
        if screen == NSScreen.main {
            parts.append(L10n.text(.settingsMain))
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
