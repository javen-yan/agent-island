//
//  UnifiedAgentProtocol.swift
//  Agent Island
//
//  Target product-facing protocol models for multi-provider normalization.
//

import Foundation

private typealias SessionPermissionContext = PermissionContext

struct UnifiedAgentEvent: Identifiable, Codable, Equatable, Sendable {
    nonisolated static let currentVersion = "1.0"

    let version: String
    let eventId: String
    let timestamp: Date
    let provider: AgentPlatform
    let sessionId: String
    let turnId: String?
    let kind: Kind
    let payload: Payload
    let capabilityHints: CapabilityHints?
    let providerPayload: ProviderPayload

    nonisolated init(
        version: String = UnifiedAgentEvent.currentVersion,
        eventId: String = UUID().uuidString,
        timestamp: Date = Date(),
        provider: AgentPlatform,
        sessionId: String,
        turnId: String? = nil,
        kind: Kind,
        payload: Payload,
        capabilityHints: CapabilityHints? = nil,
        providerPayload: ProviderPayload = .empty
    ) {
        self.version = version
        self.eventId = eventId
        self.timestamp = timestamp
        self.provider = provider
        self.sessionId = sessionId
        self.turnId = turnId
        self.kind = kind
        self.payload = payload
        self.capabilityHints = capabilityHints
        self.providerPayload = providerPayload
    }

    nonisolated var id: String { eventId }

    enum Kind: String, Codable, CaseIterable, Sendable {
        case sessionStarted = "session.started"
        case sessionEnded = "session.ended"
        case sessionCompactionRequested = "session.compaction_requested"
        case sessionCompacted = "session.compacted"
        case sessionCwdChanged = "session.cwd_changed"
        case sessionConfigChanged = "session.config_changed"
        case turnInputSubmitted = "turn.input_submitted"
        case turnStarted = "turn.started"
        case turnCompleted = "turn.completed"
        case turnFailed = "turn.failed"
        case permissionRequested = "permission.requested"
        case permissionResolved = "permission.resolved"
        case permissionDeniedByProvider = "permission.denied_by_provider"
        case toolPending = "tool.pending"
        case toolStarted = "tool.started"
        case toolCompleted = "tool.completed"
        case toolFailed = "tool.failed"
        case agentSubtaskStarted = "agent.subtask_started"
        case agentSubtaskCompleted = "agent.subtask_completed"
        case agentIdle = "agent.idle"
        case modelRequestPrepared = "model.request_prepared"
        case modelResponseChunk = "model.response_chunk"
        case modelResponseCompleted = "model.response_completed"
        case notification = "notification"
        case interactionElicitationRequested = "interaction.elicitation_requested"
        case interactionElicitationResolved = "interaction.elicitation_resolved"
    }
}

struct UnifiedAgentAction: Identifiable, Codable, Equatable, Sendable {
    nonisolated static let currentVersion = "1.0"

    let version: String
    let actionId: String
    let targetEventId: String
    let decision: Decision
    let message: String?
    let shouldContinue: Bool?
    let stopReason: String?
    let patch: Patch
    let metadata: [String: String]

    nonisolated init(
        version: String = UnifiedAgentAction.currentVersion,
        actionId: String = UUID().uuidString,
        targetEventId: String,
        decision: Decision,
        message: String? = nil,
        shouldContinue: Bool? = nil,
        stopReason: String? = nil,
        patch: Patch = .empty,
        metadata: [String: String] = [:]
    ) {
        self.version = version
        self.actionId = actionId
        self.targetEventId = targetEventId
        self.decision = decision
        self.message = message
        self.shouldContinue = shouldContinue
        self.stopReason = stopReason
        self.patch = patch
        self.metadata = metadata
    }

    nonisolated var id: String { actionId }

    enum Decision: String, Codable, CaseIterable, Sendable {
        case allow
        case deny
        case ask
        case noop
    }
}

struct ProviderCapabilities: Codable, Equatable, Sendable {
    let provider: AgentPlatform
    let permissions: PermissionCapabilities
    let toolControl: ToolControlCapabilities
    let modelControl: ModelControlCapabilities
    let sessionControl: SessionControlCapabilities
    let agentControl: AgentControlCapabilities
    let history: HistoryCapabilities

    struct PermissionCapabilities: Codable, Equatable, Sendable {
        let interactiveApproval: Bool
        let toolLevelApproval: Bool
        let sandboxEscalationApproval: Bool
        let appToolApproval: Bool
        let providerManagedPermissionsVisible: Bool
    }

    struct ToolControlCapabilities: Codable, Equatable, Sendable {
        let allow: Bool
        let deny: Bool
        let rewriteArgs: Bool
        let replaceResult: Bool
        let tailCall: Bool
    }

    struct ModelControlCapabilities: Codable, Equatable, Sendable {
        let rewriteRequest: Bool
        let replaceResponse: Bool
        let streamIntercept: Bool
        let toolSelectionControl: Bool
    }

    struct SessionControlCapabilities: Codable, Equatable, Sendable {
        let injectStartContext: Bool
        let notificationMessage: Bool
        let stopTurn: Bool
        let compactionHooks: Bool
    }

    struct AgentControlCapabilities: Codable, Equatable, Sendable {
        let subagentEvents: Bool
        let subagentRetryControl: Bool
        let elicitation: Bool
    }

    struct HistoryCapabilities: Codable, Equatable, Sendable {
        let transcriptHistory: Bool
        let structuredToolResults: Bool
    }
}

struct ProviderPolicySnapshot: Codable, Equatable, Sendable {
    let provider: AgentPlatform
    let capturedAt: Date
    let summary: String?
    let toolPolicies: [String: ProviderToolPolicy]
    let extra: [String: String]

    struct ProviderToolPolicy: Codable, Equatable, Sendable {
        let toolName: String
        let approvalMode: String?
        let source: String?
        let notes: String?
    }
}

extension UnifiedAgentEvent {
    struct Payload: Codable, Equatable, Sendable {
        let session: SessionContext?
        let tool: ToolContext?
        let permission: PermissionContext?
        let result: ResultContext?
        let message: String?
        let notification: NotificationContext?
        let metadata: [String: String]

        nonisolated init(
            session: SessionContext? = nil,
            tool: ToolContext? = nil,
            permission: PermissionContext? = nil,
            result: ResultContext? = nil,
            message: String? = nil,
            notification: NotificationContext? = nil,
            metadata: [String: String] = [:]
        ) {
            self.session = session
            self.tool = tool
            self.permission = permission
            self.result = result
            self.message = message
            self.notification = notification
            self.metadata = metadata
        }
    }

    struct CapabilityHints: Codable, Equatable, Sendable {
        let supportsAllow: Bool
        let supportsDeny: Bool
        let supportsAsk: Bool
        let supportsArgumentPatch: Bool
        let supportsAdditionalContext: Bool
        let supportsStopTurn: Bool
    }

    struct ProviderPayload: Codable, Equatable, Sendable {
        let event: String?
        let fields: [String: String]

        nonisolated static let empty = ProviderPayload(event: nil, fields: [:])
    }

    struct SessionContext: Codable, Equatable, Sendable {
        let cwd: String?
        let transcriptPath: String?
        let pid: Int?
        let tty: String?
    }

    struct ToolContext: Codable, Equatable, Sendable {
        let callId: String?
        let toolName: String
        let arguments: [String: String]
        let risk: RiskSummary?
    }

    struct PermissionContext: Codable, Equatable, Sendable {
        let requestId: String
        let sourceKind: String
        let providerEvent: String?
    }

    struct ResultContext: Codable, Equatable, Sendable {
        let status: String
        let outputText: String?
    }

    struct NotificationContext: Codable, Equatable, Sendable {
        let type: String?
        let title: String?
    }

    struct RiskSummary: Codable, Equatable, Sendable {
        let destructive: Bool
        let filesystemWrite: Bool
        let network: Bool
        let sandboxEscalation: Bool
        let secretsAccess: Bool
        let openWorld: Bool
    }
}

extension UnifiedAgentAction {
    struct Patch: Codable, Equatable, Sendable {
        let toolArguments: [String: String]
        let toolResult: [String: String]
        let modelRequest: [String: String]
        let modelResponse: [String: String]
        let additionalContext: String?
        let tailCall: TailCall?

        nonisolated static let empty = Patch(
            toolArguments: [:],
            toolResult: [:],
            modelRequest: [:],
            modelResponse: [:],
            additionalContext: nil,
            tailCall: nil
        )
    }

    struct TailCall: Codable, Equatable, Sendable {
        let name: String
        let arguments: [String: String]
    }
}

extension ProviderCapabilities {
    nonisolated static func baseline(for provider: AgentPlatform) -> ProviderCapabilities {
        switch provider {
        case .claude:
            return ProviderCapabilities(
                provider: .claude,
                permissions: .init(
                    interactiveApproval: true,
                    toolLevelApproval: true,
                    sandboxEscalationApproval: true,
                    appToolApproval: false,
                    providerManagedPermissionsVisible: false
                ),
                toolControl: .init(
                    allow: true,
                    deny: true,
                    rewriteArgs: false,
                    replaceResult: false,
                    tailCall: false
                ),
                modelControl: .init(
                    rewriteRequest: false,
                    replaceResponse: false,
                    streamIntercept: false,
                    toolSelectionControl: false
                ),
                sessionControl: .init(
                    injectStartContext: false,
                    notificationMessage: true,
                    stopTurn: true,
                    compactionHooks: true
                ),
                agentControl: .init(
                    subagentEvents: true,
                    subagentRetryControl: false,
                    elicitation: false
                ),
                history: .init(
                    transcriptHistory: true,
                    structuredToolResults: true
                )
            )

        case .codex:
            return ProviderCapabilities(
                provider: .codex,
                permissions: .init(
                    interactiveApproval: true,
                    toolLevelApproval: true,
                    sandboxEscalationApproval: true,
                    appToolApproval: false,
                    providerManagedPermissionsVisible: true
                ),
                toolControl: .init(
                    allow: true,
                    deny: true,
                    rewriteArgs: false,
                    replaceResult: false,
                    tailCall: false
                ),
                modelControl: .init(
                    rewriteRequest: false,
                    replaceResponse: false,
                    streamIntercept: false,
                    toolSelectionControl: false
                ),
                sessionControl: .init(
                    injectStartContext: false,
                    notificationMessage: false,
                    stopTurn: false,
                    compactionHooks: false
                ),
                agentControl: .init(
                    subagentEvents: false,
                    subagentRetryControl: false,
                    elicitation: false
                ),
                history: .init(
                    transcriptHistory: true,
                    structuredToolResults: false
                )
            )

        case .gemini:
            return ProviderCapabilities(
                provider: .gemini,
                permissions: .init(
                    interactiveApproval: true,
                    toolLevelApproval: true,
                    sandboxEscalationApproval: false,
                    appToolApproval: false,
                    providerManagedPermissionsVisible: false
                ),
                toolControl: .init(
                    allow: true,
                    deny: true,
                    rewriteArgs: true,
                    replaceResult: false,
                    tailCall: true
                ),
                modelControl: .init(
                    rewriteRequest: true,
                    replaceResponse: true,
                    streamIntercept: false,
                    toolSelectionControl: true
                ),
                sessionControl: .init(
                    injectStartContext: true,
                    notificationMessage: true,
                    stopTurn: false,
                    compactionHooks: true
                ),
                agentControl: .init(
                    subagentEvents: false,
                    subagentRetryControl: false,
                    elicitation: false
                ),
                history: .init(
                    transcriptHistory: false,
                    structuredToolResults: false
                )
            )
        }
    }

    nonisolated func approvalCapability(
        approvalMode: ApprovalMode? = nil
    ) -> ApprovalCapability {
        if approvalMode == .terminal {
            return ApprovalCapability(
                kind: .terminalOnly,
                supportedPolicies: [.deny],
                supportedActions: []
            )
        }

        guard permissions.interactiveApproval else {
            return ApprovalCapability(
                kind: .unsupported,
                supportedPolicies: [],
                supportedActions: []
            )
        }

        var policies: [ApprovalPolicy] = []
        var actions: [ApprovalAction] = []

        if toolControl.deny {
            policies.append(.deny)
            actions.append(.deny)
        }

        if toolControl.allow {
            policies.append(.allowOnce)
            actions.append(.allowOnce)
        }

        if permissions.toolLevelApproval && toolControl.allow {
            policies.append(.allowAlways)
            policies.append(.autoExecute)
            actions.append(.allowAlways)
            actions.append(.autoExecute)
        }

        if actions.isEmpty {
            return ApprovalCapability(
                kind: .unsupported,
                supportedPolicies: [],
                supportedActions: []
            )
        }

        return ApprovalCapability(
            kind: .nativeInteractive,
            supportedPolicies: policies,
            supportedActions: actions
        )
    }

    nonisolated var supportsAskApproval: Bool {
        provider == .claude
    }

    nonisolated func permissionSourceDescription(provider: AgentPlatform) -> String {
        if provider == .codex {
            return "Codex mixes Agent Island runtime approvals with provider-side config rules, so some commands may be auto-approved before they reach this panel."
        }

        if provider == .gemini && toolControl.rewriteArgs {
            return "Gemini supports richer tool rewriting in provider hooks, but this panel is currently using the safe allow-or-deny path."
        }

        if permissions.providerManagedPermissionsVisible {
            return "\(provider.rawValue.capitalized) also applies provider-side approval rules. Some requests may be pre-approved before Agent Island sees them."
        }

        if permissions.interactiveApproval {
            return "This approval is being handled directly by Agent Island."
        }

        return "This provider exposes limited approval controls in Agent Island."
    }
}

extension UnifiedAgentEvent {
    nonisolated var shouldStartRuntimeObservation: Bool {
        switch kind {
        case .toolStarted,
             .turnStarted,
             .turnInputSubmitted,
             .toolCompleted,
             .turnCompleted,
             .turnFailed,
             .sessionCompactionRequested:
            return true
        default:
            return false
        }
    }

    nonisolated var shouldStopRuntimeObservation: Bool {
        kind == .sessionEnded
    }

    nonisolated var shouldCancelPendingPermissions: Bool {
        kind == .turnCompleted || kind == .sessionEnded
    }

    nonisolated var shouldSyncTranscript: Bool {
        switch kind {
        case .turnInputSubmitted, .toolStarted, .toolCompleted, .turnCompleted, .turnFailed:
            return true
        default:
            return false
        }
    }

    nonisolated var shouldResetSubagentState: Bool {
        kind == .turnCompleted || kind == .turnFailed || kind == .sessionEnded
    }

    nonisolated var completedToolCallId: String? {
        guard kind == .toolCompleted else { return nil }
        return payload.tool?.callId
    }

    nonisolated var approvalMode: ApprovalMode? {
        switch payload.metadata["approvalMode"] {
        case ApprovalMode.terminal.rawValue:
            return .terminal
        case ApprovalMode.nativeApp.rawValue:
            return .nativeApp
        default:
            return nil
        }
    }

    nonisolated var providerCapabilitiesBaseline: ProviderCapabilities {
        ProviderCapabilities.baseline(for: provider)
    }

    nonisolated func mappedSessionPhase(currentPhase: SessionPhase) -> SessionPhase? {
        switch kind {
        case .sessionStarted:
            return .waitingForInput
        case .permissionRequested:
            let tool = payload.tool
            let permission = payload.permission
            return .waitingForApproval(SessionPermissionContext(
                toolUseId: tool?.callId ?? permission?.requestId ?? "",
                toolName: tool?.toolName ?? "unknown",
                toolInput: anyCodableArguments(from: tool?.arguments ?? [:]),
                mode: approvalMode ?? .nativeApp,
                receivedAt: timestamp
            ))
        case .turnInputSubmitted, .toolStarted, .turnStarted:
            return .processing
        case .toolCompleted, .toolFailed:
            if provider == .codex {
                return .waitingForInput
            }
            return .processing
        case .turnCompleted, .turnFailed:
            if case .waitingForApproval = currentPhase {
                return .idle
            }
            return .waitingForInput
        case .sessionCompactionRequested, .sessionCompacted:
            return .compacting
        case .notification:
            if payload.notification?.type == HookEvent.NotificationType.idlePrompt.rawValue {
                return .waitingForInput
            }
            return nil
        case .agentIdle:
            if case .waitingForApproval = currentPhase {
                return currentPhase
            }
            return .waitingForInput
        case .sessionEnded:
            return .ended
        default:
            return nil
        }
    }

    private nonisolated func anyCodableArguments(from input: [String: String]) -> [String: AnyCodable]? {
        guard !input.isEmpty else { return nil }
        var result: [String: AnyCodable] = [:]
        for (key, value) in input {
            result[key] = AnyCodable(value)
        }
        return result
    }
}
