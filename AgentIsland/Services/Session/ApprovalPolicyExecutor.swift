//
//  ApprovalPolicyExecutor.swift
//  Agent Island
//
//  Unified approval policy execution entry point.
//

import Foundation

enum ApprovalExecutionResult: Sendable {
    case executed
    case requiresTerminal
    case unsupported
    case unavailable
}

actor ApprovalPolicyExecutor {
    static let shared = ApprovalPolicyExecutor()

    private init() {}

    func execute(policy: ApprovalPolicy, sessionId: String) async -> ApprovalExecutionResult {
        guard let session = await SessionStore.shared.session(for: sessionId),
              let permission = session.activePermission else {
            return .unavailable
        }

        switch session.approvalCapability.kind {
        case .nativeInteractive:
            guard session.approvalCapability.supportedPolicies.contains(policy) else {
                return .unsupported
            }
            return await executeNativeInteractive(
                policy: policy,
                sessionId: sessionId,
                permission: permission
            )
        case .terminalOnly:
            return .requiresTerminal
        case .unsupported:
            return .unsupported
        }
    }

    private func executeNativeInteractive(
        policy: ApprovalPolicy,
        sessionId: String,
        permission: PermissionContext
    ) async -> ApprovalExecutionResult {
        switch policy {
        case .deny:
            await HookSocketServer.shared.respondToPermission(
                sessionId: sessionId,
                toolUseId: permission.toolUseId,
                action: UnifiedAgentAction(
                    targetEventId: permission.toolUseId,
                    decision: .deny
                )
            )
            await SessionStore.shared.process(
                .permissionDenied(sessionId: sessionId, toolUseId: permission.toolUseId, reason: nil)
            )
            return .executed

        case .allowOnce:
            return await approve(sessionId: sessionId, permission: permission)

        case .allowAlways, .autoExecute:
            guard let session = await SessionStore.shared.session(for: sessionId) else {
                return .unavailable
            }
            await ApprovalPolicyStore.shared.persistRule(for: session, permission: permission, policy: policy)
            return await approve(sessionId: sessionId, permission: permission)
        }
    }

    func applyAutomaticPolicyIfNeeded(for event: UnifiedAgentEvent) async -> ApprovalExecutionResult {
        guard event.kind == .permissionRequested,
              event.providerCapabilitiesBaseline.approvalCapability(
                approvalMode: event.approvalMode
              ).supportedPolicies.contains(.allowAlways),
              let policy = await ApprovalPolicyStore.shared.matchingPolicy(for: event),
              policy == .allowAlways || policy == .autoExecute else {
            return .unavailable
        }

        return await execute(policy: policy == .autoExecute ? .autoExecute : .allowOnce, sessionId: event.sessionId)
    }

    private func approve(sessionId: String, permission: PermissionContext) async -> ApprovalExecutionResult {
        await HookSocketServer.shared.respondToPermission(
            sessionId: sessionId,
            toolUseId: permission.toolUseId,
            action: UnifiedAgentAction(
                targetEventId: permission.toolUseId,
                decision: .allow
            )
        )
        await SessionStore.shared.process(
            .permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId)
        )
        return .executed
    }
}
