//
//  SettingsWindowView.swift
//  Agent Island
//
//  Native macOS settings window built with SwiftUI and AppKit.
//

import AppKit
import ApplicationServices
import Combine
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case agents
    case diagnostics
    case approvalRules
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return L10n.text(.settingsPaneGeneralTitle)
        case .agents: return L10n.text(.settingsPaneAgentsTitle)
        case .diagnostics: return L10n.text(.settingsPaneDiagnosticsTitle)
        case .approvalRules: return L10n.text(.settingsPaneApprovalRulesTitle)
        case .about: return L10n.text(.settingsPaneAboutTitle)
        }
    }

    var subtitle: String {
        switch self {
        case .general: return L10n.text(.settingsPaneGeneralSubtitle)
        case .agents: return L10n.text(.settingsPaneAgentsSubtitle)
        case .diagnostics: return L10n.text(.settingsPaneDiagnosticsSubtitle)
        case .approvalRules: return L10n.text(.settingsPaneApprovalRulesSubtitle)
        case .about: return L10n.text(.settingsPaneAboutSubtitle)
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .agents: return "person.2.fill"
        case .diagnostics: return "waveform.path.ecg"
        case .approvalRules: return "checkmark.shield"
        case .about: return "info.circle"
        }
    }

    var accent: Color {
        switch self {
        case .general: return .blue
        case .agents: return .gray
        case .diagnostics: return .orange
        case .approvalRules: return .green
        case .about: return .secondary
        }
    }
}

private enum SettingsDetailRoute: Hashable {
    case generalPreferences
    case generalPermissions
    case agentIntegrations
    case diagnosticsLogging
    case diagnosticsLogFiles
    case approvalSavedRules
    case aboutUpdates
    case aboutProject
}

private extension NSWindow.FrameAutosaveName {
    static let agentIslandSettings = Self("com.agentisland.settings-window")
}

@MainActor
final class AgentIslandSettingsWindowControllerProvider {
    static let shared = AgentIslandSettingsWindowControllerProvider()

    private let viewModel = AgentIslandSettingsViewModel()
    private var approvalRulesObserver: NSObjectProtocol?
    private var hostingController: NSHostingController<AgentIslandSettingsRootView>?
    private var windowController: NSWindowController?

    private init() {
        approvalRulesObserver = NotificationCenter.default.addObserver(
            forName: AgentSettingsFacade.approvalRulesDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.viewModel.refreshApprovalRules()
            }
        }
    }

    deinit {
        if let approvalRulesObserver {
            NotificationCenter.default.removeObserver(approvalRulesObserver)
        }
    }

    func show(pane: SettingsPane = .general) {
        viewModel.refresh()
        let controller = makeWindowControllerIfNeeded(initialPane: pane)
        hostingController?.rootView = AgentIslandSettingsRootView(viewModel: viewModel, selection: pane)

        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindowControllerIfNeeded(initialPane: SettingsPane) -> NSWindowController {
        if let windowController {
            return windowController
        }

        let rootView = AgentIslandSettingsRootView(viewModel: viewModel, selection: initialPane)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.contentViewController = hostingController
        window.title = "AgentIsland Settings"
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName(.agentIslandSettings)
        window.setFrameUsingName(.agentIslandSettings)
        window.minSize = NSSize(width: 1040, height: 700)
        window.backgroundColor = .clear

        let controller = NSWindowController(window: window)
        self.hostingController = hostingController
        self.windowController = controller
        return controller
    }
}

@MainActor
final class AgentIslandSettingsViewModel: ObservableObject {
    private let facade: AgentSettingsFacade

    @Published var launchAtLogin = false
    @Published var pluginSummaries: [AgentHookPluginSummary] = []
    @Published var approvalRules: [ApprovalRule] = []
    @Published var codexBuiltInDangerousCommandPatterns: [String] = AppSettings.codexBuiltInDangerousCommandPatterns
    @Published var codexDangerousCommandPatterns: [String] = AppSettings.codexDangerousCommandPatterns
    @Published var codexDangerousCommandPatternsDraft: String = AppSettings.codexDangerousCommandPatterns.joined(separator: "\n")
    @Published var codexDangerousCommandPatternValidationMessage: String?
    @Published var codexDangerousCommandPatternStatusMessage: String?
    @Published var codexDangerousCommandPatternStatusIsError = false
    @Published var bridgeLogEnabled: Bool = AppSettings.bridgeLogEnabled
    @Published var bridgeLogLevel: BridgeLogLevel = AppSettings.bridgeLogLevel
    @Published var appLogEnabled: Bool = AppSettings.appLogEnabled
    @Published var appLogLevel: BridgeLogLevel = AppSettings.appLogLevel
    @Published var selectedSound: NotificationSound = AppSettings.notificationSound
    @Published var selectedLanguage: AppLanguage = AppSettings.appLanguage
    @Published var chatHistoryRetentionLimit: Int = AppSettings.chatHistoryRetentionLimit
    @Published var selectedScreenOptionID: String = AgentSettingsScreenOption.automatic.id
    @Published var screenOptions: [AgentSettingsScreenOption] = [.automatic]

    let updateManager: UpdateManager

    init(facade: AgentSettingsFacade? = nil) {
        let facade = facade ?? .shared
        self.facade = facade
        self.updateManager = facade.updateManager
    }

    func refresh() {
        Task {
            let snapshot = await facade.loadSnapshot()
            await MainActor.run {
                apply(snapshot)
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        switch facade.setLaunchAtLogin(enabled) {
        case .none:
            return
        case .success:
            launchAtLogin = enabled
        case .failure:
            refresh()
        }
    }

    func selectScreenOption(_ id: String) {
        facade.selectScreenOption(id)
        selectedScreenOptionID = id
    }

    func setNotificationSound(_ sound: NotificationSound) {
        facade.setNotificationSound(sound)
        selectedSound = sound
    }

    func setAppLanguage(_ language: AppLanguage) {
        facade.setAppLanguage(language)
        selectedLanguage = language
    }

    func setChatHistoryRetentionLimit(_ limit: Int) {
        facade.setChatHistoryRetentionLimit(limit)
        chatHistoryRetentionLimit = AppSettings.chatHistoryRetentionLimit
    }

    func saveCodexDangerousCommandPatternsDraft() {
        let patterns = codexDangerousCommandPatternsDraft
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let issues = patterns.compactMap { pattern -> String? in
            guard let issue = AppSettings.codexDangerousCommandPatternIssue(for: pattern) else {
                return nil
            }
            return "`\(pattern)` - \(issue)"
        }

        guard issues.isEmpty else {
            codexDangerousCommandPatternValidationMessage = issues.joined(separator: "\n")
            codexDangerousCommandPatternStatusMessage = nil
            codexDangerousCommandPatternStatusIsError = true
            return
        }

        switch facade.setCodexDangerousCommandPatterns(patterns) {
        case .success(let message):
            codexDangerousCommandPatternStatusMessage = message
            codexDangerousCommandPatternStatusIsError = false
        case .failure(let message):
            codexDangerousCommandPatternStatusMessage = message
            codexDangerousCommandPatternStatusIsError = true
        case .none:
            codexDangerousCommandPatternStatusMessage = nil
            codexDangerousCommandPatternStatusIsError = false
        }
        codexDangerousCommandPatterns = AppSettings.codexDangerousCommandPatterns
        codexDangerousCommandPatternsDraft = codexDangerousCommandPatterns.joined(separator: "\n")
        codexDangerousCommandPatternValidationMessage = nil
    }

    func resetCodexDangerousCommandPatternsDraft() {
        codexDangerousCommandPatternsDraft = codexDangerousCommandPatterns.joined(separator: "\n")
        codexDangerousCommandPatternValidationMessage = nil
        codexDangerousCommandPatternStatusMessage = nil
        codexDangerousCommandPatternStatusIsError = false
    }

    func togglePlugin(_ summary: AgentHookPluginSummary) {
        switch facade.togglePlugin(summary) {
        case .none:
            return
        case .success, .failure:
            refresh()
        }
    }

    func repairPlugin(_ summary: AgentHookPluginSummary) {
        switch facade.repairPlugin(summary) {
        case .none:
            return
        case .success, .failure:
            refresh()
        }
    }

    func removeApprovalRule(_ rule: ApprovalRule) {
        Task {
            _ = await facade.removeApprovalRule(rule)
            await MainActor.run {
                refreshApprovalRules()
            }
        }
    }

    func refreshApprovalRules() {
        Task {
            let rules = await facade.loadApprovalRules()
            await MainActor.run {
                approvalRules = rules
            }
        }
    }

    func setBridgeLogEnabled(_ enabled: Bool) {
        bridgeLogEnabled = enabled
        _ = facade.setBridgeLogEnabled(enabled)
    }

    func setBridgeLogLevel(_ level: BridgeLogLevel) {
        guard bridgeLogLevel != level else { return }
        bridgeLogLevel = level
        _ = facade.setBridgeLogLevel(level)
    }

    func setAppLogEnabled(_ enabled: Bool) {
        appLogEnabled = enabled
        _ = facade.setAppLogEnabled(enabled)
    }

    func setAppLogLevel(_ level: BridgeLogLevel) {
        guard appLogLevel != level else { return }
        appLogLevel = level
        _ = facade.setAppLogLevel(level)
    }

    func openLogsFolder() {
        facade.openLogsFolder()
    }

    func revealBridgeLog() {
        facade.revealBridgeLog()
    }

    func revealAppLog() {
        facade.revealAppLog()
    }

    func openAccessibilitySettings() {
        facade.openAccessibilitySettings()
    }

    func checkForUpdates() {
        facade.checkForUpdates()
    }

    func openGitHubRepository() {
        facade.openProjectRepository()
    }

    func openGitHubStarPage() {
        facade.openProjectStarPage()
    }

    private func apply(_ snapshot: AgentSettingsSnapshot) {
        launchAtLogin = snapshot.launchAtLogin
        pluginSummaries = snapshot.pluginSummaries
        approvalRules = snapshot.approvalRules
        codexBuiltInDangerousCommandPatterns = snapshot.codexBuiltInDangerousCommandPatterns
        codexDangerousCommandPatterns = snapshot.codexDangerousCommandPatterns
        codexDangerousCommandPatternsDraft = snapshot.codexDangerousCommandPatterns.joined(separator: "\n")
        codexDangerousCommandPatternValidationMessage = nil
        codexDangerousCommandPatternStatusMessage = nil
        codexDangerousCommandPatternStatusIsError = false
        bridgeLogEnabled = snapshot.bridgeLogEnabled
        bridgeLogLevel = snapshot.bridgeLogLevel
        appLogEnabled = snapshot.appLogEnabled
        appLogLevel = snapshot.appLogLevel
        selectedSound = snapshot.selectedSound
        selectedLanguage = snapshot.selectedLanguage
        chatHistoryRetentionLimit = snapshot.chatHistoryRetentionLimit
        selectedScreenOptionID = snapshot.selectedScreenOptionID
        screenOptions = snapshot.screenOptions
    }
}

struct AgentIslandSettingsSceneView: View {
    @StateObject private var viewModel = AgentIslandSettingsViewModel()

    var body: some View {
        AgentIslandSettingsRootView(viewModel: viewModel, selection: .general)
            .task {
                viewModel.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: AgentSettingsFacade.approvalRulesDidChangeNotification)) { _ in
                viewModel.refreshApprovalRules()
            }
    }
}

private struct AgentIslandSettingsRootView: View {
    @ObservedObject var viewModel: AgentIslandSettingsViewModel
    @State var selection: SettingsPane
    @State private var searchText = ""

    init(viewModel: AgentIslandSettingsViewModel, selection: SettingsPane) {
        self.viewModel = viewModel
        _selection = State(initialValue: selection)
    }

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: $selection, searchText: $searchText)
                .navigationSplitViewColumnWidth(min: 204, ideal: 228, max: 244)
        } detail: {
            SettingsDetailPane(selection: selection, viewModel: viewModel)
        }
        .background(SettingsSceneWindowAccessor(title: selection.title))
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 780, minHeight: 520)
    }
}

private struct SettingsSceneWindowAccessor: NSViewRepresentable {
    let title: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window, title: title)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.window, title: title)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject {
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var notchWasVisible = true
        private var pendingNotchHideWorkItem: DispatchWorkItem?

        func attach(to window: NSWindow?, title: String) {
            guard let window else { return }

            if self.window === window {
                updateTitle(title, for: window)
                return
            }

            detach()
            self.window = window
            configure(window, title: title)
            installObservers(for: window)
            setNotchSuppressed(window.isKeyWindow)
        }

        func detach() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            pendingNotchHideWorkItem?.cancel()
            pendingNotchHideWorkItem = nil
            setNotchSuppressed(false)
            window = nil
        }

        private func configure(_ window: NSWindow, title: String) {
            updateTitle(title, for: window)
            window.toolbarStyle = .unified
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.minSize = NSSize(width: 780, height: 520)

            if window.frame.width < 780 || window.frame.height < 520 ||
                window.frame.width > 980 || window.frame.height > 720 {
                window.setContentSize(NSSize(width: 820, height: 560))
                window.center()
            }
        }

        private func updateTitle(_ title: String, for window: NSWindow) {
            window.title = title
        }

        private func installObservers(for window: NSWindow) {
            let center = NotificationCenter.default
            observers = [
                center.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.setNotchSuppressed(true)
                },
                center.addObserver(
                    forName: NSWindow.didResignKeyNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.setNotchSuppressed(false)
                },
                center.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.setNotchSuppressed(false)
                }
            ]
        }

        private func setNotchSuppressed(_ suppressed: Bool) {
            guard let notchController = AppDelegate.shared?.windowController,
                  let notchWindow = notchController.window else { return }

            pendingNotchHideWorkItem?.cancel()
            pendingNotchHideWorkItem = nil

            if suppressed {
                notchWasVisible = notchWindow.isVisible
                notchController.viewModel.notchClose()

                let hideWorkItem = DispatchWorkItem { [weak notchWindow] in
                    guard let notchWindow else { return }

                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.18
                        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        notchWindow.animator().alphaValue = 0
                    } completionHandler: {
                        notchWindow.orderOut(nil)
                    }
                }

                pendingNotchHideWorkItem = hideWorkItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: hideWorkItem)
            } else if notchWasVisible {
                notchWindow.alphaValue = 0
                notchWindow.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    notchWindow.animator().alphaValue = 1
                }
            }
        }
    }
}

private struct SettingsSidebarContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(.thinMaterial)
    }
}

private struct SettingsDetailContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SettingsSymbolBadge: View {
    let systemName: String
    let color: Color

    private var usesProviderIcon: Bool {
        systemName.hasPrefix("provider.")
    }

    var body: some View {
        Group {
            if usesProviderIcon {
                Image(agentIcon: systemName)
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: 36, height: 36)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.92), color.opacity(0.68)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 34, height: 34)

                    Image(agentIcon: systemName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsPane
    @Binding var searchText: String

    private var filteredPanes: [SettingsPane] {
        guard !searchText.isEmpty else { return SettingsPane.allCases }
        return SettingsPane.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.subtitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        SettingsSidebarContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("AgentIsland")
                            .font(.headline.weight(.semibold))
                        Text("App Settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.black.opacity(0.06), in: Capsule())
                .padding(.horizontal, 16)

                List(selection: $selection) {
                    Section {
                        ForEach(filteredPanes) { pane in
                            SettingsSidebarRow(pane: pane, isSelected: selection == pane)
                                .tag(pane)
                                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(maxHeight: .infinity)
            }
        }
    }
}

private struct SettingsSidebarRow: View {
    let pane: SettingsPane
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: pane.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(width: 18, height: 18)

            Text(pane.title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct SettingsDetailPane: View {
    let selection: SettingsPane
    @ObservedObject var viewModel: AgentIslandSettingsViewModel

    var body: some View {
        SettingsDetailContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    rootContent
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return L10n.text(.settingsVersionFormat, version, build)
    }

    @ViewBuilder
    private var rootContent: some View {
        switch selection {
        case .general:
            GeneralSettingsPane(viewModel: viewModel)
        case .agents:
            AgentHooksSettingsPane(viewModel: viewModel)
        case .diagnostics:
            DiagnosticsSettingsPane(viewModel: viewModel)
        case .approvalRules:
            ApprovalRulesSettingsPane(viewModel: viewModel)
        case .about:
            AboutSettingsPane(
                updateManager: viewModel.updateManager,
                appVersionText: appVersionText,
                onCheckForUpdates: viewModel.checkForUpdates,
                onOpenGitHub: viewModel.openGitHubRepository,
                onStarGitHub: viewModel.openGitHubStarPage,
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        }
    }
}

private struct SettingsSubpageHeader: View {
    let route: SettingsDetailRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title.weight(.semibold))
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var title: String {
        switch route {
        case .generalPreferences: return L10n.text(.settingsGeneralPreferencesTitle)
        case .generalPermissions: return L10n.text(.settingsGeneralPermissionsTitle)
        case .agentIntegrations: return L10n.text(.settingsAgentsIntegrationsTitle)
        case .diagnosticsLogging: return L10n.text(.settingsDiagnosticsLoggingTitle)
        case .diagnosticsLogFiles: return L10n.text(.settingsDiagnosticsLogFilesTitle)
        case .approvalSavedRules: return L10n.text(.settingsApprovalRulesSavedTitle)
        case .aboutUpdates: return L10n.text(.settingsAboutCheckForUpdates)
        case .aboutProject: return L10n.text(.settingsPaneAboutTitle)
        }
    }

    private var subtitle: String {
        switch route {
        case .generalPreferences: return L10n.text(.settingsGeneralPreferencesSubtitle)
        case .generalPermissions: return L10n.text(.settingsGeneralPermissionsSubtitle)
        case .agentIntegrations: return L10n.text(.settingsAgentsIntegrationsSubtitle)
        case .diagnosticsLogging: return L10n.text(.settingsDiagnosticsLoggingSubtitle)
        case .diagnosticsLogFiles: return L10n.text(.settingsDiagnosticsLogFilesSubtitle)
        case .approvalSavedRules: return L10n.text(.settingsApprovalRulesSavedSubtitle)
        case .aboutUpdates: return L10n.text(.settingsPaneAboutSubtitle)
        case .aboutProject: return L10n.text(.settingsAboutTagline)
        }
    }
}

private struct SettingsEntryListCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let route: SettingsDetailRoute

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 16) {
                SettingsSymbolBadge(systemName: icon, color: color)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct GeneralSettingsOverview: View {
    var body: some View {
        SettingsSectionBlock(title: L10n.text(.settingsPaneGeneralTitle), subtitle: L10n.text(.settingsPaneGeneralSubtitle)) {
            SettingsEntryListCard(
                title: L10n.text(.settingsGeneralPreferencesTitle),
                subtitle: L10n.text(.settingsGeneralPreferencesSubtitle),
                icon: "gearshape",
                color: .blue,
                route: .generalPreferences
            )

            SettingsDivider()

            SettingsEntryListCard(
                title: L10n.text(.settingsGeneralPermissionsTitle),
                subtitle: L10n.text(.settingsGeneralPermissionsSubtitle),
                icon: "figure.wave",
                color: .green,
                route: .generalPermissions
            )
        }
    }
}

private struct DiagnosticsSettingsOverview: View {
    var body: some View {
        SettingsSectionBlock(title: L10n.text(.settingsPaneDiagnosticsTitle), subtitle: L10n.text(.settingsPaneDiagnosticsSubtitle)) {
            SettingsEntryListCard(
                title: L10n.text(.settingsDiagnosticsLoggingTitle),
                subtitle: L10n.text(.settingsDiagnosticsLoggingSubtitle),
                icon: "waveform.path.ecg",
                color: .orange,
                route: .diagnosticsLogging
            )

            SettingsDivider()

            SettingsEntryListCard(
                title: L10n.text(.settingsDiagnosticsLogFilesTitle),
                subtitle: L10n.text(.settingsDiagnosticsLogFilesSubtitle),
                icon: "folder",
                color: .blue,
                route: .diagnosticsLogFiles
            )
        }
    }
}

private struct AgentsSettingsOverview: View {
    var body: some View {
        SettingsSectionBlock(title: L10n.text(.settingsPaneAgentsTitle), subtitle: L10n.text(.settingsPaneAgentsSubtitle)) {
            SettingsEntryListCard(
                title: L10n.text(.settingsAgentsIntegrationsTitle),
                subtitle: L10n.text(.settingsAgentsIntegrationsSubtitle),
                icon: "terminal",
                color: .gray,
                route: .agentIntegrations
            )
        }
    }
}

private struct ApprovalRulesOverview: View {
    var body: some View {
        SettingsSectionBlock(title: L10n.text(.settingsPaneApprovalRulesTitle), subtitle: L10n.text(.settingsPaneApprovalRulesSubtitle)) {
            SettingsEntryListCard(
                title: L10n.text(.settingsApprovalRulesSavedTitle),
                subtitle: L10n.text(.settingsApprovalRulesSavedSubtitle),
                icon: "checkmark.shield",
                color: .green,
                route: .approvalSavedRules
            )
        }
    }
}

private struct AboutSettingsOverview: View {
    let appVersionText: String

    var body: some View {
        SettingsSectionBlock(title: "AgentIsland", subtitle: appVersionText) {
            SettingsEntryListCard(
                title: L10n.text(.settingsAboutCheckForUpdates),
                subtitle: L10n.text(.settingsPaneAboutSubtitle),
                icon: "arrow.triangle.2.circlepath",
                color: .blue,
                route: .aboutUpdates
            )

            SettingsDivider()

            SettingsEntryListCard(
                title: L10n.text(.settingsPaneAboutTitle),
                subtitle: L10n.text(.settingsAboutTagline),
                icon: "info.circle",
                color: .indigo,
                route: .aboutProject
            )
        }
    }
}

private struct SettingsHeroHeader: View {
    let pane: SettingsPane

    var body: some View {
        EmptyView()
    }
}

private enum SettingsSectionChromeStyle {
    case card
    case plain
}

private let settingsPickerWidth: CGFloat = 220

private struct SettingsSectionBlock<Content: View>: View {

    let title: String
    let subtitle: String?
    var chromeStyle: SettingsSectionChromeStyle = .card
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 0) {
                content()
            }
            .modifier(SettingsSectionChrome(style: chromeStyle))
        }
    }
}

private struct SettingsCardBlock<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .modifier(SettingsSectionChrome(style: .card))
    }
}

private struct SettingsSectionChrome: ViewModifier {
    let style: SettingsSectionChromeStyle

    func body(content: Content) -> some View {
        switch style {
        case .card:
            content
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.04), lineWidth: 1)
                )
        case .plain:
            content
        }
    }
}

private struct SettingsRow<Content: View>: View {
    let icon: String?
    let iconColor: Color
    let title: String
    let description: String?
    @ViewBuilder let trailing: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let icon {
                SettingsSymbolBadge(systemName: icon, color: iconColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                if let description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            trailing()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 16)
    }
}

private struct SettingsPillStatus: View {
    let text: String
    let color: Color
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.callout.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct GeneralSettingsPane: View {
    @ObservedObject var viewModel: AgentIslandSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSectionBlock(
                title: L10n.text(.settingsGeneralPreferencesTitle),
                subtitle: L10n.text(.settingsGeneralPreferencesSubtitle)
            ) {
                SettingsRow(icon: "globe", iconColor: .blue, title: L10n.text(.settingsLanguage), description: nil) {
                    Picker("", selection: $viewModel.selectedLanguage) {
                        ForEach(AppLanguage.allCases, id: \.rawValue) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: settingsPickerWidth, alignment: .trailing)
                    .onChange(of: viewModel.selectedLanguage) { _, newValue in
                        viewModel.setAppLanguage(newValue)
                    }
                }

                SettingsDivider()

                SettingsRow(icon: "display.2", iconColor: .indigo, title: L10n.text(.settingsGeneralIslandDisplay), description: nil) {
                    Picker("", selection: $viewModel.selectedScreenOptionID) {
                        ForEach(viewModel.screenOptions) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: settingsPickerWidth, alignment: .trailing)
                    .onChange(of: viewModel.selectedScreenOptionID) { _, newValue in
                        viewModel.selectScreenOption(newValue)
                    }
                }

                SettingsDivider()

                SettingsRow(icon: "speaker.wave.2.fill", iconColor: .orange, title: L10n.text(.settingsGeneralAttentionSound), description: nil) {
                    Picker("", selection: $viewModel.selectedSound) {
                        ForEach(NotificationSound.allCases, id: \.self) { sound in
                            Text(sound.rawValue).tag(sound)
                        }
                    }
                    .labelsHidden()
                    .frame(width: settingsPickerWidth, alignment: .trailing)
                    .onChange(of: viewModel.selectedSound) { _, newValue in
                        viewModel.setNotificationSound(newValue)
                    }
                }

                SettingsDivider()

                SettingsRow(icon: "text.bubble", iconColor: .teal, title: L10n.text(.settingsGeneralChatHistoryRetention), description: L10n.text(.settingsGeneralChatHistoryRetentionSubtitle)) {
                    Picker("", selection: $viewModel.chatHistoryRetentionLimit) {
                        ForEach([25, 50, 100, 200, 500], id: \.self) { limit in
                            Text("\(limit)").tag(limit)
                        }
                    }
                    .labelsHidden()
                    .frame(width: settingsPickerWidth, alignment: .trailing)
                    .onChange(of: viewModel.chatHistoryRetentionLimit) { _, newValue in
                        viewModel.setChatHistoryRetentionLimit(newValue)
                    }
                }

                SettingsDivider()

                SettingsRow(icon: "power", iconColor: .green, title: L10n.text(.settingsGeneralLaunchAtLogin), description: nil) {
                    Toggle("", isOn: Binding(
                        get: { viewModel.launchAtLogin },
                        set: { viewModel.setLaunchAtLogin($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }

            SettingsSectionBlock(
                title: L10n.text(.settingsGeneralPermissionsTitle),
                subtitle: L10n.text(.settingsGeneralPermissionsSubtitle)
            ) {
                SettingsRow(icon: "figure.wave", iconColor: .blue, title: L10n.text(.settingsGeneralAccessibility), description: nil) {
                    if AXIsProcessTrusted() {
                        SettingsPillStatus(
                            text: L10n.text(.settingsEnabled),
                            color: .green,
                            systemImage: "checkmark.circle.fill"
                        )
                    } else {
                        Button(L10n.text(.settingsOpenSystemSettings)) {
                            viewModel.openAccessibilitySettings()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }
}

private typealias GeneralPreferencesDetail = GeneralSettingsPane

private struct GeneralPermissionsDetail: View {
    @ObservedObject var viewModel: AgentIslandSettingsViewModel

    var body: some View {
        SettingsSectionBlock(
            title: L10n.text(.settingsGeneralPermissionsTitle),
            subtitle: L10n.text(.settingsGeneralPermissionsSubtitle)
        ) {
            SettingsRow(icon: "figure.wave", iconColor: .blue, title: L10n.text(.settingsGeneralAccessibility), description: nil) {
                if AXIsProcessTrusted() {
                    SettingsPillStatus(
                        text: L10n.text(.settingsEnabled),
                        color: .green,
                        systemImage: "checkmark.circle.fill"
                    )
                } else {
                    Button(L10n.text(.settingsOpenSystemSettings)) {
                        viewModel.openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

private struct AgentHooksSettingsPane: View {
    @ObservedObject var viewModel: AgentIslandSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSectionBlock(
                title: L10n.text(.settingsAgentsIntegrationsTitle),
                subtitle: L10n.text(.settingsAgentsIntegrationsSubtitle),
                chromeStyle: .plain
            ) {
                ForEach(Array(viewModel.pluginSummaries.enumerated()), id: \.element.agentType.rawValue) { index, summary in
                    SettingsRow(
                        icon: summary.agentType.iconSymbol,
                        iconColor: summary.agentType.accentColor,
                        title: summary.agentType.displayName,
                        description: agentDetail(for: summary)
                    ) {
                        HStack(spacing: 12) {
                            if summary.diagnostic.health == .needsRepair {
                                Button(L10n.text(.settingsRepairIntegration)) {
                                    viewModel.repairPlugin(summary)
                                }
                                .buttonStyle(.bordered)
                            }

                            Toggle("", isOn: Binding(
                                get: { summary.isEnabled },
                                set: { _ in viewModel.togglePlugin(summary) }
                            ))
                            .labelsHidden()
                            .disabled(!summary.isAvailable)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    if index < viewModel.pluginSummaries.count - 1 {
                        SettingsDivider()
                    }
                }
            }

            SettingsSectionBlock(
                title: L10n.text(.settingsAgentsCodexSafetyTitle),
                subtitle: L10n.text(.settingsAgentsCodexSafetySubtitle),
                chromeStyle: .plain
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text(.settingsAgentsCodexBuiltInPatterns))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)

                        Text(L10n.text(.settingsAgentsCodexBuiltInPatternsSubtitle))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        ReadOnlyPatternList(patterns: viewModel.codexBuiltInDangerousCommandPatterns)
                    }

                    SettingsDivider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text(.settingsAgentsCodexCustomPatterns))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)

                        Text(L10n.text(.settingsAgentsCodexCustomPatternsSubtitle))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        TextEditor(text: $viewModel.codexDangerousCommandPatternsDraft)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 110)
                            .padding(8)
                            .background(Color(NSColor.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )

                        if let validation = viewModel.codexDangerousCommandPatternValidationMessage,
                           !validation.isEmpty {
                            Text(validation)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.red)
                        }

                        HStack(spacing: 10) {
                            Button(L10n.text(.settingsAgentsCodexApplyPatterns)) {
                                viewModel.saveCodexDangerousCommandPatternsDraft()
                            }
                            .buttonStyle(.borderedProminent)

                            Button(L10n.text(.settingsAgentsCodexResetPatterns)) {
                                viewModel.resetCodexDangerousCommandPatternsDraft()
                            }
                            .buttonStyle(.bordered)
                        }

                        if let status = viewModel.codexDangerousCommandPatternStatusMessage,
                           !status.isEmpty {
                            Text(status)
                                .font(.system(size: 11))
                                .foregroundColor(viewModel.codexDangerousCommandPatternStatusIsError ? .red : .green)
                        }
                    }
                }
            }
        }
    }

    private func agentCapabilitiesText(for summary: AgentHookPluginSummary) -> String {
        var parts: [String] = []
        if summary.capabilities.supportsPermissionDecisions {
            parts.append(L10n.text(.settingsAgentsApprovals))
        }
        if summary.capabilities.supportsConversationHistory {
            parts.append(L10n.text(.settingsAgentsHistory))
        }
        if let responseMode = summary.capabilities.responseMode {
            parts.append(responseMode.capitalized)
        }
        return parts.isEmpty ? L10n.text(.settingsAgentsMonitoringOnly) : parts.joined(separator: " · ")
    }

    private func agentDescription(for summary: AgentHookPluginSummary) -> String {
        switch summary.agentType {
        case .claude:
            return L10n.text(.settingsAgentsClaudeDescription)
        case .codex:
            return L10n.text(.settingsAgentsCodexDescription)
        case .gemini:
            return L10n.text(.settingsAgentsGeminiDescription)
        }
    }

    private func agentDetail(for summary: AgentHookPluginSummary) -> String {
        var parts = [agentDescription(for: summary), agentCapabilitiesText(for: summary)]
        if let detail = summary.diagnostic.detail, !detail.isEmpty {
            parts.append(detail)
        }
        return parts.joined(separator: " · ")
    }
}

private struct ReadOnlyPatternList: View {
    let patterns: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(patterns, id: \.self) { pattern in
                    Text(pattern)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.82))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
        }
        .frame(minHeight: 92, maxHeight: 140)
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct DiagnosticsSettingsPane: View {
    @ObservedObject var viewModel: AgentIslandSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSectionBlock(
                title: L10n.text(.settingsDiagnosticsLoggingTitle),
                subtitle: L10n.text(.settingsDiagnosticsLoggingSubtitle)
            ) {
                SettingsRow(icon: "doc.text", iconColor: .orange, title: L10n.text(.settingsDiagnosticsBridgeLogging), description: nil) {
                    Toggle("", isOn: Binding(
                        get: { viewModel.bridgeLogEnabled },
                        set: { viewModel.setBridgeLogEnabled($0) }
                    ))
                    .labelsHidden()
                }

                SettingsDivider()

                SettingsRow(icon: "slider.horizontal.3", iconColor: .orange, title: L10n.text(.settingsDiagnosticsBridgeLevel), description: nil) {
                    Picker("", selection: $viewModel.bridgeLogLevel) {
                        ForEach(BridgeLogLevel.allCases, id: \.rawValue) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .labelsHidden()
                    .frame(width: settingsPickerWidth, alignment: .trailing)
                    .onChange(of: viewModel.bridgeLogLevel) { _, newValue in
                        viewModel.setBridgeLogLevel(newValue)
                    }
                }

                SettingsDivider()

                SettingsRow(icon: "app.badge", iconColor: .blue, title: L10n.text(.settingsDiagnosticsAppLogging), description: nil) {
                    Toggle("", isOn: Binding(
                        get: { viewModel.appLogEnabled },
                        set: { viewModel.setAppLogEnabled($0) }
                    ))
                    .labelsHidden()
                }

                SettingsDivider()

                SettingsRow(icon: "dial.medium", iconColor: .blue, title: L10n.text(.settingsDiagnosticsAppLevel), description: nil) {
                    Picker("", selection: $viewModel.appLogLevel) {
                        ForEach(BridgeLogLevel.allCases, id: \.rawValue) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .labelsHidden()
                    .frame(width: settingsPickerWidth, alignment: .trailing)
                    .onChange(of: viewModel.appLogLevel) { _, newValue in
                        viewModel.setAppLogLevel(newValue)
                    }
                }
            }

            SettingsSectionBlock(
                title: L10n.text(.settingsDiagnosticsLogFilesTitle),
                subtitle: L10n.text(.settingsDiagnosticsLogFilesSubtitle)
            ) {
                SettingsRow(icon: "folder", iconColor: .yellow, title: L10n.text(.settingsDiagnosticsOpenLogsFolder), description: nil) {
                    Button(L10n.text(.settingsDiagnosticsOpenLogsFolder)) {
                        viewModel.openLogsFolder()
                    }
                }

                SettingsDivider()

                SettingsRow(icon: "doc.text.magnifyingglass", iconColor: .indigo, title: L10n.text(.settingsDiagnosticsRevealBridgeLog), description: nil) {
                    Button(L10n.text(.settingsDiagnosticsRevealBridgeLog)) {
                        viewModel.revealBridgeLog()
                    }
                }

                SettingsDivider()

                SettingsRow(icon: "doc.text.magnifyingglass", iconColor: .purple, title: L10n.text(.settingsDiagnosticsRevealAppLog), description: nil) {
                    Button(L10n.text(.settingsDiagnosticsRevealAppLog)) {
                        viewModel.revealAppLog()
                    }
                }
            }
        }
    }
}

private struct DiagnosticsLoggingDetail: View {
    @ObservedObject var viewModel: AgentIslandSettingsViewModel

    var body: some View {
        SettingsSectionBlock(
            title: L10n.text(.settingsDiagnosticsLoggingTitle),
            subtitle: L10n.text(.settingsDiagnosticsLoggingSubtitle)
        ) {
            SettingsRow(icon: "doc.text", iconColor: .orange, title: L10n.text(.settingsDiagnosticsBridgeLogging), description: nil) {
                Toggle("", isOn: Binding(
                    get: { viewModel.bridgeLogEnabled },
                    set: { viewModel.setBridgeLogEnabled($0) }
                ))
                .labelsHidden()
            }

            SettingsDivider()

            SettingsRow(icon: "slider.horizontal.3", iconColor: .orange, title: L10n.text(.settingsDiagnosticsBridgeLevel), description: nil) {
                Picker("", selection: $viewModel.bridgeLogLevel) {
                    ForEach(BridgeLogLevel.allCases, id: \.rawValue) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .labelsHidden()
                .frame(width: settingsPickerWidth, alignment: .trailing)
                .onChange(of: viewModel.bridgeLogLevel) { _, newValue in
                    viewModel.setBridgeLogLevel(newValue)
                }
            }

            SettingsDivider()

            SettingsRow(icon: "app.badge", iconColor: .blue, title: L10n.text(.settingsDiagnosticsAppLogging), description: nil) {
                Toggle("", isOn: Binding(
                    get: { viewModel.appLogEnabled },
                    set: { viewModel.setAppLogEnabled($0) }
                ))
                .labelsHidden()
            }

            SettingsDivider()

            SettingsRow(icon: "dial.medium", iconColor: .blue, title: L10n.text(.settingsDiagnosticsAppLevel), description: nil) {
                Picker("", selection: $viewModel.appLogLevel) {
                    ForEach(BridgeLogLevel.allCases, id: \.rawValue) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .labelsHidden()
                .frame(width: settingsPickerWidth, alignment: .trailing)
                .onChange(of: viewModel.appLogLevel) { _, newValue in
                    viewModel.setAppLogLevel(newValue)
                }
            }
        }
    }
}

private struct DiagnosticsLogFilesDetail: View {
    @ObservedObject var viewModel: AgentIslandSettingsViewModel

    var body: some View {
        SettingsSectionBlock(
            title: L10n.text(.settingsDiagnosticsLogFilesTitle),
            subtitle: L10n.text(.settingsDiagnosticsLogFilesSubtitle)
        ) {
            SettingsRow(icon: "folder", iconColor: .yellow, title: L10n.text(.settingsDiagnosticsOpenLogsFolder), description: nil) {
                Button(L10n.text(.settingsDiagnosticsOpenLogsFolder)) {
                    viewModel.openLogsFolder()
                }
            }

            SettingsDivider()

            SettingsRow(icon: "doc.text.magnifyingglass", iconColor: .indigo, title: L10n.text(.settingsDiagnosticsRevealBridgeLog), description: nil) {
                Button(L10n.text(.settingsDiagnosticsRevealBridgeLog)) {
                    viewModel.revealBridgeLog()
                }
            }

            SettingsDivider()

            SettingsRow(icon: "doc.text.magnifyingglass", iconColor: .purple, title: L10n.text(.settingsDiagnosticsRevealAppLog), description: nil) {
                Button(L10n.text(.settingsDiagnosticsRevealAppLog)) {
                    viewModel.revealAppLog()
                }
            }
        }
    }
}

private struct ApprovalRulesSettingsPane: View {
    @ObservedObject var viewModel: AgentIslandSettingsViewModel

    private var groupedRules: [(agent: AgentPlatform, rules: [ApprovalRule])] {
        let grouped = Dictionary(grouping: viewModel.approvalRules, by: \.agentType)
        let ordering = viewModel.approvalRules.map(\.agentType)
        let uniqueOrdering = ordering.reduce(into: [AgentPlatform]()) { result, agent in
            if !result.contains(agent) {
                result.append(agent)
            }
        }

        return uniqueOrdering.compactMap { agent in
            guard let rules = grouped[agent], !rules.isEmpty else { return nil }
            return (agent, rules)
        }
    }

    var body: some View {
        Group {
            if groupedRules.isEmpty {
                VStack {
                    Spacer()
                    ContentUnavailableView(
                        L10n.text(.settingsApprovalRulesEmptyTitle),
                        systemImage: "checkmark.shield",
                        description: Text(L10n.text(.settingsApprovalRulesEmptyDescription))
                    )
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 420)
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(groupedRules.enumerated()), id: \.offset) { _, group in
                        SettingsSectionBlock(title: group.agent.displayName, subtitle: "\(group.rules.count)") {
                            ForEach(Array(group.rules.enumerated()), id: \.element.id) { index, rule in
                                SettingsRow(
                                    icon: "checkmark.shield",
                                    iconColor: policyColor(for: rule.policy),
                                    title: rule.toolName,
                                    description: rule.createdAt.formatted(date: .abbreviated, time: .shortened)
                                ) {
                                    VStack(alignment: .trailing, spacing: 10) {
                                        SettingsPillStatus(
                                            text: rule.policy.displayName,
                                            color: policyColor(for: rule.policy),
                                            systemImage: policyIcon(for: rule.policy)
                                        )

                                        Button(L10n.text(.settingsDelete), role: .destructive) {
                                            viewModel.removeApprovalRule(rule)
                                        }
                                    }
                                }

                                if index < group.rules.count - 1 {
                                    SettingsDivider()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func policyColor(for policy: ApprovalPolicy) -> Color {
        switch policy {
        case .deny:
            return .secondary
        case .allowOnce:
            return .green
        case .allowAlways:
            return .orange
        case .autoExecute:
            return .red
        }
    }

    private func policyIcon(for policy: ApprovalPolicy) -> String {
        switch policy {
        case .deny:
            return "xmark.circle"
        case .allowOnce:
            return "checkmark.circle"
        case .allowAlways:
            return "checkmark.seal"
        case .autoExecute:
            return "bolt.circle"
        }
    }
}

private struct AboutSettingsPane: View {
    @ObservedObject var updateManager: UpdateManager
    let appVersionText: String
    let onCheckForUpdates: () -> Void
    let onOpenGitHub: () -> Void
    let onStarGitHub: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSectionBlock(title: "AgentIsland", subtitle: nil) {
                SettingsRow(icon: "arrow.triangle.2.circlepath", iconColor: .blue, title: L10n.text(.settingsAboutCheckForUpdates), description: updateSummaryText) {
                    Button(L10n.text(.settingsAboutCheckForUpdates)) {
                        onCheckForUpdates()
                    }
                    .disabled(updateManager.state.isActive)
                }

                SettingsDivider()

                SettingsRow(icon: "link", iconColor: .indigo, title: L10n.text(.settingsAboutOpenGitHub), description: nil) {
                    Button(L10n.text(.settingsAboutOpenGitHub)) {
                        onOpenGitHub()
                    }
                }

                SettingsDivider()

                SettingsRow(icon: "star.fill", iconColor: .orange, title: L10n.text(.settingsAboutStarOnGitHub), description: nil) {
                    Button(L10n.text(.settingsAboutStarOnGitHub)) {
                        onStarGitHub()
                    }
                }
            }

            SettingsCardBlock {
                SettingsRow(icon: "power.circle.fill", iconColor: .red, title: L10n.text(.settingsQuit), description: nil) {
                    Button(L10n.text(.settingsQuit), role: .destructive) {
                        onQuit()
                    }
                }
            }
        }
    }

    private var updateStatusMessage: String? {
        switch updateManager.state {
        case .idle:
            return nil
        case .checking:
            return L10n.text(.settingsUpdateChecking)
        case .upToDate:
            return L10n.text(.settingsUpdateUpToDate)
        case .found(let version, _):
            return L10n.text(.settingsUpdateAvailable, version)
        case .downloading(let progress):
            return L10n.text(.settingsUpdateDownloading, Int(progress * 100))
        case .extracting(let progress):
            return L10n.text(.settingsUpdatePreparing, Int(progress * 100))
        case .readyToInstall(let version):
            return L10n.text(.settingsUpdateReady, version)
        case .installing:
            return L10n.text(.settingsUpdateInstalling)
        case .error(let message):
            return message
        }
    }

    private var updateSummaryText: String {
        if let updateStatusMessage, !updateStatusMessage.isEmpty {
            return "\(appVersionText) · \(updateStatusMessage)"
        }
        return appVersionText
    }
}

private struct AboutUpdatesDetail: View {
    @ObservedObject var updateManager: UpdateManager
    let appVersionText: String
    let onCheckForUpdates: () -> Void

    var body: some View {
        SettingsSectionBlock(title: "AgentIsland", subtitle: nil) {
            SettingsRow(icon: "arrow.triangle.2.circlepath", iconColor: .blue, title: L10n.text(.settingsAboutCheckForUpdates), description: updateSummaryText) {
                Button(L10n.text(.settingsAboutCheckForUpdates)) {
                    onCheckForUpdates()
                }
                .disabled(updateManager.state.isActive)
            }
        }
    }

    private var updateStatusMessage: String? {
        switch updateManager.state {
        case .idle:
            return nil
        case .checking:
            return L10n.text(.settingsUpdateChecking)
        case .upToDate:
            return L10n.text(.settingsUpdateUpToDate)
        case .found(let version, _):
            return L10n.text(.settingsUpdateAvailable, version)
        case .downloading(let progress):
            return L10n.text(.settingsUpdateDownloading, Int(progress * 100))
        case .extracting(let progress):
            return L10n.text(.settingsUpdatePreparing, Int(progress * 100))
        case .readyToInstall(let version):
            return L10n.text(.settingsUpdateReady, version)
        case .installing:
            return L10n.text(.settingsUpdateInstalling)
        case .error(let message):
            return message
        }
    }

    private var updateSummaryText: String {
        if let updateStatusMessage, !updateStatusMessage.isEmpty {
            return "\(appVersionText) · \(updateStatusMessage)"
        }
        return appVersionText
    }
}

private struct AboutProjectDetail: View {
    let onOpenGitHub: () -> Void
    let onStarGitHub: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsSectionBlock(title: L10n.text(.settingsPaneAboutTitle), subtitle: L10n.text(.settingsAboutTagline)) {
                SettingsRow(icon: "link", iconColor: .indigo, title: L10n.text(.settingsAboutOpenGitHub), description: nil) {
                    Button(L10n.text(.settingsAboutOpenGitHub)) {
                        onOpenGitHub()
                    }
                }

                SettingsDivider()

                SettingsRow(icon: "star.fill", iconColor: .orange, title: L10n.text(.settingsAboutStarOnGitHub), description: nil) {
                    Button(L10n.text(.settingsAboutStarOnGitHub)) {
                        onStarGitHub()
                    }
                }
            }

            SettingsCardBlock {
                SettingsRow(icon: "power.circle.fill", iconColor: .red, title: L10n.text(.settingsQuit), description: nil) {
                    Button(L10n.text(.settingsQuit), role: .destructive) {
                        onQuit()
                    }
                }
            }
        }
    }
}
