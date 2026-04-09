//
//  AgentChatFacade.swift
//  Agent Island
//
//  Consolidates chat-side session streaming and interaction actions so the chat
//  view does not directly depend on state and runtime service singletons.
//

import Combine
import Foundation

@MainActor
final class AgentChatFacade {
    static let shared = AgentChatFacade()

    private let sessionStore: SessionStore
    private let interactionRegistry: AgentInteractionRegistry

    init(
        sessionStore: SessionStore = .shared,
        interactionRegistry: AgentInteractionRegistry = .shared
    ) {
        self.sessionStore = sessionStore
        self.interactionRegistry = interactionRegistry
    }

    var sessionsPublisher: AnyPublisher<[SessionState], Never> {
        sessionStore.sessionsPublisher
    }

    func canSendMessages(for session: SessionState) -> Bool {
        interactionRegistry.canSendMessages(for: session)
    }

    func canInterruptTurn(for session: SessionState) -> Bool {
        interactionRegistry.canInterruptTurn(for: session)
    }

    func canTerminateSession(for session: SessionState) -> Bool {
        interactionRegistry.canTerminateSession(for: session)
    }

    func sendMessage(_ message: String, for session: SessionState) async -> Bool {
        await interactionRegistry.sendMessage(message, for: session)
    }

    func interruptTurn(for session: SessionState) async -> Bool {
        let interrupted = await interactionRegistry.interruptTurn(for: session)
        if interrupted {
            await sessionStore.process(.interruptDetected(sessionId: session.sessionId))
        }
        return interrupted
    }

    func terminateSession(for session: SessionState) async -> Bool {
        await interactionRegistry.terminateSession(for: session)
    }
}
