//
//  ClaudeSessionMonitor.swift
//  Agent Island
//
//  MainActor wrapper around SessionStore for UI binding.
//  Publishes SessionState arrays for SwiftUI observation.
//

import AppKit
import Combine
import Foundation

@MainActor
class AgentSessionMonitor: ObservableObject {
    @Published var instances: [SessionListState] = []
    @Published var pendingInstances: [SessionListState] = []

    private let dispatcher = DefaultCapabilityDispatcher.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        SessionStore.shared.sessionSummariesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.updateFromSessions(sessions)
            }
            .store(in: &cancellables)
        AgentRuntimeObserverRegistry.shared.setDelegate(self)
    }

    // MARK: - Monitoring Lifecycle

    func startMonitoring() {
        HookSocketServer.shared.start(
            onEvent: { event in
                Task {
                    await self.dispatcher.handle(.hookReceived(event))
                }
            },
            onPermissionFailure: { sessionId, toolUseId in
                Task {
                    await self.dispatcher.handle(.permissionSocketFailed(sessionId: sessionId, toolUseId: toolUseId))
                }
            }
        )
    }

    func stopMonitoring() {
        HookSocketServer.shared.stop()
    }

    // MARK: - Permission Handling

    func approvePermission(sessionId: String) {
        Task {
            _ = await ApprovalPolicyExecutor.shared.execute(policy: .allowOnce, sessionId: sessionId)
        }
    }

    func denyPermission(sessionId: String, reason: String?) {
        Task {
            if reason == nil {
                _ = await ApprovalPolicyExecutor.shared.execute(policy: .deny, sessionId: sessionId)
                return
            }

            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            HookSocketServer.shared.respondToPermission(
                toolUseId: permission.toolUseId,
                action: UnifiedAgentAction(
                    targetEventId: permission.toolUseId,
                    decision: .deny,
                    message: reason
                )
            )

            await SessionStore.shared.process(
                .permissionDenied(sessionId: sessionId, toolUseId: permission.toolUseId, reason: reason)
            )
        }
    }

    func executeApprovalPolicy(sessionId: String, policy: ApprovalPolicy) {
        Task {
            _ = await ApprovalPolicyExecutor.shared.execute(policy: policy, sessionId: sessionId)
        }
    }

    /// Archive (remove) a session from the instances list
    func archiveSession(sessionId: String) {
        Task {
            await SessionStore.shared.process(.sessionEnded(sessionId: sessionId))
        }
    }

    // MARK: - State Update

    private func updateFromSessions(_ sessions: [SessionListState]) {
        instances = sessions
        pendingInstances = sessions.filter { $0.needsAttention }
    }

    func sessionDetail(sessionId: String) async -> SessionState? {
        await SessionStore.shared.session(for: sessionId)
    }

    // MARK: - History Loading (for UI)

    /// Request history load for a session
    func loadHistory(sessionId: String, cwd: String) {
        Task {
            await dispatcher.handle(.historyLoadRequested(sessionId: sessionId, cwd: cwd))
        }
    }
}

// MARK: - Runtime Observer Delegate

extension AgentSessionMonitor: AgentRuntimeObserverDelegate {
    nonisolated func didDetectInterrupt(sessionId: String) {
        Task {
            await DefaultCapabilityDispatcher.shared.handle(.interruptDetected(sessionId: sessionId))
        }

        Task { @MainActor in
            if let session = await SessionStore.shared.session(for: sessionId) {
                AgentInteractionRegistry.shared.stopObservingIfSupported(
                    sessionId: sessionId,
                    agentType: session.agentType
                )
            }
        }
    }
}
