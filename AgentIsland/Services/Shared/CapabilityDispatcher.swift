//
//  CapabilityDispatcher.swift
//  Agent Island
//
//  Dispatches normalized ingress events into the shared session engine.
//

import Foundation

actor DefaultCapabilityDispatcher {
    nonisolated static let shared = DefaultCapabilityDispatcher()

    func handle(_ event: AgentIngressEvent) async {
        await MainActor.run {
            AgentEventBus.shared.publishIngress(event)
        }

        switch event {
        case .hookReceived(let hookEvent):
            let unifiedEvent = hookEvent.unifiedEvent
            AppDiagnosticsLogger.log(
                .debug,
                category: .dispatcher,
                "Dispatching unified event kind=\(unifiedEvent.kind.rawValue) session=\(hookEvent.sessionId) provider=\(hookEvent.agentType.rawValue)"
            )
            await SessionStore.shared.process(.unifiedEventReceived(unifiedEvent))
            _ = await ApprovalPolicyExecutor.shared.applyAutomaticPolicyIfNeeded(for: unifiedEvent)

            if unifiedEvent.shouldStartRuntimeObservation {
                await MainActor.run {
                    AgentInteractionRegistry.shared.startObservingIfSupported(
                        sessionId: hookEvent.sessionId,
                        agentType: hookEvent.agentType,
                        cwd: hookEvent.cwd,
                        transcriptPath: hookEvent.transcriptPath
                    )
                }
            }

            if unifiedEvent.shouldStopRuntimeObservation {
                await MainActor.run {
                    AgentInteractionRegistry.shared.stopObservingIfSupported(
                        sessionId: hookEvent.sessionId,
                        agentType: hookEvent.agentType
                    )
                }
            }

            if unifiedEvent.shouldCancelPendingPermissions {
                await HookSocketServer.shared.cancelPendingPermissions(sessionId: hookEvent.sessionId)
            }

            if let toolUseId = unifiedEvent.completedToolCallId {
                await HookSocketServer.shared.cancelPendingPermission(toolUseId: toolUseId)
            }

        case .permissionSocketFailed(let sessionId, let toolUseId):
            AppDiagnosticsLogger.log(
                .error,
                category: .dispatcher,
                "Permission socket failure session=\(sessionId) tool=\(toolUseId)"
            )
            await SessionStore.shared.process(
                .permissionSocketFailed(sessionId: sessionId, toolUseId: toolUseId)
            )

        case .historyLoadRequested(let sessionId, let cwd):
            AppDiagnosticsLogger.log(.debug, category: .dispatcher, "History load requested session=\(sessionId) cwd=\(cwd)")
            await SessionStore.shared.process(.loadHistory(sessionId: sessionId, cwd: cwd))

        case .fileSyncReceived(let payload):
            AppDiagnosticsLogger.log(.trace, category: .dispatcher, "File sync payload session=\(payload.sessionId)")
            await SessionStore.shared.process(.fileUpdated(payload))

        case .interruptDetected(let sessionId):
            AppDiagnosticsLogger.log(.info, category: .dispatcher, "Interrupt detected session=\(sessionId)")
            await SessionStore.shared.process(.interruptDetected(sessionId: sessionId))
        }
    }
}
