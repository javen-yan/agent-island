//
//  SessionListState.swift
//  Agent Island
//
//  Lightweight projection for session list and notch-level UI.
//

import Foundation

struct SessionListState: Equatable, Identifiable, Sendable {
    let sessionId: String
    let agentType: AgentPlatform
    let cwd: String
    let transcriptPath: String?
    let projectName: String
    let pid: Int?
    let tty: String?
    let isInTerminalMultiplexer: Bool
    let detectedTerminalBackend: TerminalBackend?
    let phase: SessionPhase
    let conversationInfo: ConversationInfo
    let lastActivity: Date
    let createdAt: Date

    var id: String { sessionId }

    var stableId: String {
        if let pid {
            return "\(pid)-\(sessionId)"
        }
        return sessionId
    }

    var needsAttention: Bool {
        phase.needsAttention
    }

    nonisolated var activePermission: PermissionContext? {
        if case .waitingForApproval(let ctx) = phase {
            return ctx
        }
        return nil
    }

    nonisolated var approvalMode: ApprovalMode? {
        phase.approvalMode
    }

    nonisolated var usesTerminalApproval: Bool {
        approvalMode == .terminal
    }

    nonisolated var providerCapabilities: ProviderCapabilities {
        ProviderCapabilities.baseline(for: agentType)
    }

    nonisolated var approvalCapability: ApprovalCapability {
        providerCapabilities.approvalCapability(approvalMode: approvalMode)
    }

    nonisolated var permissionSourceDescription: String {
        providerCapabilities.permissionSourceDescription(provider: agentType)
    }

    var unifiedViewKind: UnifiedAgentEvent.Kind {
        switch phase {
        case .waitingForApproval:
            return .permissionRequested
        case .processing:
            return .toolStarted
        case .compacting:
            return .sessionCompactionRequested
        case .waitingForInput, .idle:
            return .agentIdle
        case .ended:
            return .sessionEnded
        }
    }

    var unifiedStatusColor: String {
        switch unifiedViewKind {
        case .permissionRequested:
            return "approval"
        case .toolStarted, .sessionCompactionRequested:
            return "processing"
        case .agentIdle:
            return phase == .waitingForInput ? "ready" : "idle"
        case .sessionEnded:
            return "idle"
        default:
            return "idle"
        }
    }

    var unifiedPendingApprovalEvent: UnifiedAgentEvent? {
        guard let permission = activePermission else { return nil }

        return UnifiedAgentEvent(
            provider: agentType,
            sessionId: sessionId,
            kind: .permissionRequested,
            payload: .init(
                session: .init(
                    cwd: cwd,
                    transcriptPath: transcriptPath,
                    pid: pid,
                    tty: tty
                ),
                tool: .init(
                    callId: permission.toolUseId,
                    toolName: permission.toolName,
                    arguments: permission.formattedInput.map { ["display": $0] } ?? [:],
                    risk: nil
                ),
                permission: .init(
                    requestId: permission.toolUseId,
                    sourceKind: "tool_call",
                    providerEvent: nil
                ),
                metadata: [
                    "approvalMode": permission.mode.rawValue,
                    "permissionSource": permissionSourceDescription
                ]
            ),
            capabilityHints: .init(
                supportsAllow: providerCapabilities.toolControl.allow,
                supportsDeny: providerCapabilities.toolControl.deny,
                supportsAsk: providerCapabilities.supportsAskApproval,
                supportsArgumentPatch: providerCapabilities.toolControl.rewriteArgs,
                supportsAdditionalContext: providerCapabilities.sessionControl.injectStartContext,
                supportsStopTurn: providerCapabilities.sessionControl.stopTurn
            )
        )
    }

    var displayTitle: String {
        cleanedDisplayTitle(conversationInfo.summary)
            ?? cleanedDisplayTitle(conversationInfo.firstUserMessage)
            ?? projectName
    }

    var pendingToolName: String? {
        activePermission?.toolName
    }

    var pendingToolInput: String? {
        activePermission?.formattedInput
    }

    var lastMessage: String? {
        conversationInfo.lastMessage
    }

    var lastMessageRole: String? {
        conversationInfo.lastMessageRole
    }

    var lastToolName: String? {
        conversationInfo.lastToolName
    }

    var summary: String? {
        conversationInfo.summary
    }

    var firstUserMessage: String? {
        conversationInfo.firstUserMessage
    }

    var lastUserMessageDate: Date? {
        conversationInfo.lastUserMessageDate
    }
}
