//
//  ClaudeInstancesView.swift
//  Agent Island
//
//  Minimal instances list matching Dynamic Island aesthetic
//

import Combine
import SwiftUI

private struct InstancesContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct AgentInstancesView: View {
    @ObservedObject var sessionMonitor: AgentSessionMonitor
    @ObservedObject var viewModel: NotchViewModel
    @State private var pendingContentHeight: CGFloat = 0

    var body: some View {
        Group {
            if sessionMonitor.instances.isEmpty {
                emptyState
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: InstancesContentHeightKey.self, value: proxy.size.height)
                        }
                    )
            } else {
                instancesList
            }
        }
        .onPreferenceChange(InstancesContentHeightKey.self) { height in
            guard height > 0 else { return }
            let clampedHeight = max(72, ceil(height))
            guard abs(clampedHeight - pendingContentHeight) > 1 else { return }
            pendingContentHeight = clampedHeight

            DispatchQueue.main.async {
                viewModel.updateInstancesContentHeight(clampedHeight)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(L10n.text(.instancesNoSessions))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))

            Text(L10n.text(.instancesRunAgentsInTerminal))
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Instances List

    /// Priority: active (approval/processing/compacting) > waitingForInput > idle
    /// Secondary sort: by last user message date (stable - doesn't change when agent responds)
    /// Note: approval requests stay in their date-based position to avoid layout shift
    private var sortedInstances: [SessionListState] {
        sessionMonitor.instances.sorted { a, b in
            let priorityA = phasePriority(a.phase)
            let priorityB = phasePriority(b.phase)
            if priorityA != priorityB {
                return priorityA < priorityB
            }
            // Sort by last user message date (more recent first)
            // Fall back to lastActivity if no user messages yet
            let dateA = a.lastUserMessageDate ?? a.lastActivity
            let dateB = b.lastUserMessageDate ?? b.lastActivity
            return dateA > dateB
        }
    }

    /// Lower number = higher priority
    /// Approval requests share priority with processing to maintain stable ordering
    private func phasePriority(_ phase: SessionPhase) -> Int {
        switch SessionListState(
            sessionId: "",
            agentType: .claude,
            cwd: "",
            transcriptPath: nil,
            projectName: "",
            pid: nil,
            tty: nil,
            isInTerminalMultiplexer: false,
            detectedTerminalBackend: nil,
            phase: phase,
            conversationInfo: ConversationInfo(
                summary: nil,
                lastMessage: nil,
                lastMessageRole: nil,
                lastToolName: nil,
                firstUserMessage: nil,
                lastUserMessageDate: nil
            ),
            lastActivity: .distantPast,
            createdAt: .distantPast
        ).unifiedViewKind {
        case .permissionRequested, .toolStarted, .sessionCompactionRequested:
            return 0
        case .agentIdle:
            return phase == .waitingForInput ? 1 : 2
        case .sessionEnded:
            return 2
        default:
            return 2
        }
    }

    private var instancesList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(sortedInstances) { session in
                    InstanceRow(
                        session: session,
                        onChat: { openChat(session) },
                        onArchive: { archiveSession(session) },
                        onPolicy: { policy in executeApprovalPolicy(session, policy: policy) }
                    )
                    .id(session.stableId)
                }
            }
            .padding(.vertical, 4)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: InstancesContentHeightKey.self, value: proxy.size.height + 8)
                }
            )
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Actions

    private func openChat(_ session: SessionListState) {
        Task {
            guard let detail = await sessionMonitor.sessionDetail(sessionId: session.sessionId) else { return }
            await MainActor.run {
                viewModel.showChat(for: detail)
            }
        }
    }

    private func executeApprovalPolicy(_ session: SessionListState, policy: ApprovalPolicy) {
        sessionMonitor.executeApprovalPolicy(sessionId: session.sessionId, policy: policy)
        viewModel.notchClose()
    }

    private func archiveSession(_ session: SessionListState) {
        sessionMonitor.archiveSession(sessionId: session.sessionId)
    }
}

// MARK: - Instance Row

struct InstanceRow: View {
    let session: SessionListState
    let onChat: () -> Void
    let onArchive: () -> Void
    let onPolicy: (ApprovalPolicy) -> Void

    @State private var isHovered = false
    @State private var spinnerPhase = 0

    private let spinnerSymbols = ["·", "✢", "✳", "∗", "✻", "✽"]
    private let spinnerTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    /// Whether we're showing the approval UI
    private var isWaitingForApproval: Bool {
        session.phase.isWaitingForApproval
    }

    /// Codex approvals must be completed in the terminal
    private var usesTerminalApprovalUI: Bool {
        isWaitingForApproval && session.approvalCapability.kind == .terminalOnly
    }

    private var supportsPostTurnFollowUpInIsland: Bool {
        session.agentType.supportsPostTurnFollowUpInIsland
    }

    /// Whether the pending tool requires interactive input (not just approve/deny)
    private var isInteractiveTool: Bool {
        guard let toolName = session.pendingToolName else { return false }
        return toolName == "AskUserQuestion"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                stateIndicator
                    .frame(width: 14)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(session.displayTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        AgentBadge(agentType: session.agentType)
                    }

                    if showsCompletionState {
                        if session.agentType.showsLastReplyInCompletionSummary,
                           let lastMsg = session.lastMessage,
                           !lastMsg.isEmpty {
                            Text(lastMsg)
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        if supportsPostTurnFollowUpInIsland {
                            Text(L10n.text(.instancesContinueInTerminal))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(TerminalColors.green)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else {
                            Text(L10n.text(.instancesReadyToContinue))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(TerminalColors.green)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    } else if !showsTransientContentCard, let toolName = session.pendingToolName {
                        compactSubtitleForPendingTool(toolName: toolName)
                    } else if let role = session.lastMessageRole {
                        switch role {
                        case "tool":
                            HStack(spacing: 4) {
                                if let toolName = session.lastToolName {
                                    Text(MCPToolFormatter.formatToolName(toolName))
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                if let input = session.lastMessage {
                                    Text(input)
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.4))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                        case "user":
                            HStack(spacing: 4) {
                                Text(L10n.text(.instancesYou))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.5))
                                if let msg = session.lastMessage {
                                    Text(msg)
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.4))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                        default:
                            if let msg = session.lastMessage {
                                Text(msg)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.4))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    } else if let lastMsg = session.lastMessage {
                        Text(lastMsg)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 0)

                persistentActionsRow
            }

            if showsTransientContentCard {
                HStack(spacing: 8) {
                    Spacer()
                        .frame(width: 24)

                    transientContentCard

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onChat()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isWaitingForApproval)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
        )
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var persistentActionsRow: some View {
        HStack(spacing: 8) {
            IconButton(icon: "bubble.left") {
                onChat()
            }

            if session.phase == .idle || session.phase == .waitingForInput {
                IconButton(icon: "archivebox") {
                    onArchive()
                }
            }
        }
    }

    private var showsTransientContentCard: Bool {
        isWaitingForApproval
    }

    private var showsCompletionState: Bool {
        session.unifiedViewKind == .agentIdle
            && session.phase == .waitingForInput
            && session.isInTerminalMultiplexer
            && !isWaitingForApproval
    }

    @ViewBuilder
    private func compactSubtitleForPendingTool(toolName: String) -> some View {
        HStack(spacing: 4) {
            Text(MCPToolFormatter.formatToolName(toolName))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(TerminalColors.amber.opacity(0.9))
            if isInteractiveTool {
                Text(L10n.text(.instancesNeedsYourInput))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            } else if usesTerminalApprovalUI {
                Text(session.pendingToolInput ?? L10n.text(.chatWaitingForConfirmationInTerminal))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            } else if let input = session.pendingToolInput {
                Text(input)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var transientContentCard: some View {
        if isWaitingForApproval && (isInteractiveTool || usesTerminalApprovalUI) {
            if isInteractiveTool {
                ListAskBar(
                    agentName: session.agentType.displayName,
                    isEnabled: session.isInTerminalMultiplexer
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                ListTerminalApprovalBar(
                    tool: session.pendingToolName ?? "exec_command",
                    toolInput: session.pendingToolInput,
                    isEnabled: session.isInTerminalMultiplexer
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        } else if isWaitingForApproval {
            ListApprovalBar(
                tool: session.pendingToolName ?? "tool",
                toolInput: session.pendingToolInput,
                agentType: session.agentType,
                supportedActions: session.approvalCapability.supportedActions,
                isTerminalEnabled: session.isInTerminalMultiplexer,
                permissionSourceDescription: session.permissionSourceDescription,
                onAction: handleApprovalAction
            )
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    private func handleApprovalAction(_ action: ApprovalAction) {
        switch action {
        case .deny:
            onPolicy(.deny)
        case .allowOnce:
            onPolicy(.allowOnce)
        case .allowAlways:
            onPolicy(.allowAlways)
        case .autoExecute:
            onPolicy(.autoExecute)
        }
    }

    private var actionBarBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(isHovered ? 0.08 : 0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(isHovered ? 0.08 : 0.04), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch session.unifiedStatusColor {
        case "processing":
            Text(spinnerSymbols[spinnerPhase % spinnerSymbols.count])
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(session.agentType.accentColor)
                .onReceive(spinnerTimer) { _ in
                    spinnerPhase = (spinnerPhase + 1) % spinnerSymbols.count
                }
        case "approval":
            Text(spinnerSymbols[spinnerPhase % spinnerSymbols.count])
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(TerminalColors.amber)
                .onReceive(spinnerTimer) { _ in
                    spinnerPhase = (spinnerPhase + 1) % spinnerSymbols.count
                }
        case "ready":
            Circle()
                .fill(TerminalColors.green)
                .frame(width: 6, height: 6)
        default:
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 6, height: 6)
        }
    }

}

struct AgentBadge: View {
    let agentType: AgentPlatform

    var body: some View {
        HStack(spacing: 4) {
            Image(agentIcon: agentType.iconSymbol)
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 11, height: 11)
            Text(agentType.displayName)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundColor(agentType.accentColor.opacity(0.95))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(agentType.accentColor.opacity(0.14))
        .clipShape(Capsule())
    }
}

// MARK: - List Action Bars

struct ListApprovalBar: View {
    let tool: String
    let toolInput: String?
    let agentType: AgentPlatform
    let supportedActions: [ApprovalAction]
    let isTerminalEnabled: Bool
    let permissionSourceDescription: String
    let onAction: (ApprovalAction) -> Void

    private var providerCapabilities: ProviderCapabilities {
        ProviderCapabilities.baseline(for: agentType)
    }

    private var approvalTitle: String {
        providerCapabilities.permissions.providerManagedPermissionsVisible
            ? L10n.text(.chatConfirmCommand)
            : L10n.text(.chatPermissionRequest)
    }

    private var approvalFooterText: String? {
        providerCapabilities.permissions.providerManagedPermissionsVisible
            ? L10n.text(.chatProviderContinueFooter, permissionSourceDescription)
            : permissionSourceDescription
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(TerminalColors.amber)
                    .frame(width: 7, height: 7)
                Text(approvalTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
            }

            HStack(spacing: 6) {
                Text(MCPToolFormatter.formatToolName(tool))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(TerminalColors.amber)

                if let toolInput {
                    Text(toolInput)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let approvalFooterText {
                Text(approvalFooterText)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.38))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                ForEach(supportedActions, id: \.self) { action in
                    let isEnabled = true
                    Button {
                        if isEnabled {
                            onAction(action)
                        }
                    } label: {
                        label(for: action)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(foregroundColor(for: action, isEnabled: isEnabled))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(backgroundColor(for: action, isEnabled: isEnabled))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(actionBarContainer)
    }

    @ViewBuilder
    private func label(for action: ApprovalAction) -> some View {
        Text(compactLabel(for: action))
    }

    private func compactLabel(for action: ApprovalAction) -> String {
        action.displayLabel(provider: agentType, compact: true)
    }

    private func foregroundColor(for action: ApprovalAction, isEnabled: Bool) -> Color {
        guard isEnabled else { return .white.opacity(0.35) }
        switch action {
        case .deny: return .white.opacity(0.8)
        case .allowOnce, .allowAlways, .autoExecute: return .black
        }
    }

    private func backgroundColor(for action: ApprovalAction, isEnabled: Bool) -> Color {
        guard isEnabled else { return Color.white.opacity(0.08) }
        switch action {
        case .deny:
            return Color.white.opacity(0.12)
        case .allowOnce:
            return Color.white.opacity(0.92)
        case .allowAlways:
            return Color(red: 0.95, green: 0.62, blue: 0.18)
        case .autoExecute:
            return Color(red: 0.76, green: 0.22, blue: 0.18)
        }
    }
}

struct ListTerminalApprovalBar: View {
    let tool: String
    let toolInput: String?
    let isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(TerminalColors.amber)
                    .frame(width: 7, height: 7)
                Text(L10n.text(.chatWaitingForConfirmationInTerminal))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(MCPToolFormatter.formatToolName(tool))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(TerminalColors.amber)
                    Text(toolInput ?? (isEnabled ? L10n.text(.chatWaitingForConfirmationInTerminal) : L10n.text(.chatTerminalUnavailable)))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(actionBarContainer)
    }
}

struct ListAskBar: View {
    let agentName: String
    let isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(agentIcon: "bubble.left.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.cyan)
                    Text(L10n.text(.asksSuffix, agentName))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.cyan)
                }

                Text(isEnabled ? L10n.text(.chatNeedsInputInTerminal, agentName) : L10n.text(.chatTerminalUnavailable))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.cyan.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.cyan.opacity(0.16), lineWidth: 1)
                )
        )
    }
}

private var actionBarContainer: some View {
    RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
}

// MARK: - Inline Approval Buttons

/// Compact inline approval buttons with staggered animation
struct InlineApprovalButtons: View {
    let supportedActions: [ApprovalAction]
    let isTerminalEnabled: Bool
    let onAction: (ApprovalAction) -> Void

    @State private var showPolicyButtons = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(supportedActions, id: \.self) { action in
                let isEnabled = true
                Button {
                    if isEnabled {
                        onAction(action)
                    }
                } label: {
                    label(for: action)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(foregroundColor(for: action, isEnabled: isEnabled))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(backgroundColor(for: action, isEnabled: isEnabled))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
            }
        }
        .opacity(showPolicyButtons ? 1 : 0)
        .scaleEffect(showPolicyButtons ? 1 : 0.8)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) {
                showPolicyButtons = true
            }
        }
    }

    @ViewBuilder
    private func label(for action: ApprovalAction) -> some View {
        Text(compactLabel(for: action))
    }

    private func compactLabel(for action: ApprovalAction) -> String {
        switch action {
        case .deny: return L10n.text(.approvalDeny)
        case .allowOnce: return L10n.text(.approvalOnce)
        case .allowAlways: return L10n.text(.approvalAlways)
        case .autoExecute: return L10n.text(.approvalAuto)
        }
    }

    private func foregroundColor(for action: ApprovalAction, isEnabled: Bool) -> Color {
        guard isEnabled else { return .white.opacity(0.35) }
        switch action {
        case .deny: return .white.opacity(0.7)
        case .allowOnce, .allowAlways, .autoExecute: return .black
        }
    }

    private func backgroundColor(for action: ApprovalAction, isEnabled: Bool) -> Color {
        guard isEnabled else { return Color.white.opacity(0.08) }
        switch action {
        case .deny:
            return Color.white.opacity(0.1)
        case .allowOnce:
            return Color.white.opacity(0.92)
        case .allowAlways:
            return Color(red: 0.95, green: 0.60, blue: 0.18)
        case .autoExecute:
            return Color(red: 0.74, green: 0.20, blue: 0.18)
        }
    }
}

// MARK: - Icon Button

struct IconButton: View {
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            action()
        } label: {
            Image(agentIcon: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isHovered ? .white.opacity(0.8) : .white.opacity(0.4))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.white.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Compact Terminal Button (inline in description)
