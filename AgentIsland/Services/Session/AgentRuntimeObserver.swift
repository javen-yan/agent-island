//
//  AgentRuntimeObserver.swift
//  Agent Island
//
//  Agent-specific runtime observers for live session signals such as interrupts.
//

import Foundation

protocol AgentRuntimeObserverDelegate: AnyObject {
    func didDetectInterrupt(sessionId: String)
}

protocol AgentInteractionAdapter: Sendable {
    var agentType: AgentPlatform { get }
    nonisolated var supportsMessaging: Bool { get }
    nonisolated var supportsSessionControl: Bool { get }
    nonisolated func canSendMessages(in session: SessionState) -> Bool
    func sendMessage(_ message: String, in session: SessionState) async -> Bool
    nonisolated func canInterruptTurn(in session: SessionState) -> Bool
    func interruptTurn(in session: SessionState) async -> Bool
    nonisolated func canTerminateSession(in session: SessionState) -> Bool
    func terminateSession(in session: SessionState) async -> Bool
}

@MainActor
protocol AgentRuntimeObserver: AnyObject {
    var agentType: AgentPlatform { get }
    var delegate: AgentRuntimeObserverDelegate? { get set }
    func startObserving(sessionId: String, cwd: String, transcriptPath: String?)
    func stopObserving(sessionId: String)
    func stopAll()
}

@MainActor
final class AgentRuntimeObserverRegistry {
    static let shared = AgentRuntimeObserverRegistry()

    private let observers: [AgentPlatform: AgentRuntimeObserver]

    private init() {
        let claudeObserver = ClaudeRuntimeObserver()
        let codexObserver = CodexRuntimeObserver()
        self.observers = [
            .claude: claudeObserver,
            .codex: codexObserver
        ]
    }

    func observer(for agentType: AgentPlatform) -> AgentRuntimeObserver? {
        observers[agentType]
    }

    nonisolated func supportsObservation(for agentType: AgentPlatform) -> Bool {
        switch agentType {
        case .claude, .codex:
            return true
        default:
            return false
        }
    }

    func setDelegate(_ delegate: AgentRuntimeObserverDelegate) {
        for observer in observers.values {
            observer.delegate = delegate
        }
    }
}

@MainActor
private final class ClaudeRuntimeObserver: NSObject, AgentRuntimeObserver {
    let agentType: AgentPlatform = .claude

    weak var delegate: AgentRuntimeObserverDelegate? {
        didSet {
            InterruptWatcherManager.shared.delegate = self
        }
    }

    func startObserving(sessionId: String, cwd: String, transcriptPath: String?) {
        InterruptWatcherManager.shared.startWatching(sessionId: sessionId, cwd: cwd)
    }

    func stopObserving(sessionId: String) {
        InterruptWatcherManager.shared.stopWatching(sessionId: sessionId)
    }

    func stopAll() {
        InterruptWatcherManager.shared.stopAll()
    }
}

extension ClaudeRuntimeObserver: JSONLInterruptWatcherDelegate {
    nonisolated func didDetectInterrupt(sessionId: String) {
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didDetectInterrupt(sessionId: sessionId)
        }
    }
}

@MainActor
private final class CodexRuntimeObserver: NSObject, AgentRuntimeObserver {
    let agentType: AgentPlatform = .codex

    weak var delegate: AgentRuntimeObserverDelegate? {
        didSet {
            CodexInterruptWatcherManager.shared.delegate = self
        }
    }

    func startObserving(sessionId: String, cwd: String, transcriptPath: String?) {
        CodexInterruptWatcherManager.shared.startWatching(
            sessionId: sessionId,
            transcriptPath: transcriptPath
        )
    }

    func stopObserving(sessionId: String) {
        CodexInterruptWatcherManager.shared.stopWatching(sessionId: sessionId)
    }

    func stopAll() {
        CodexInterruptWatcherManager.shared.stopAll()
    }
}

extension CodexRuntimeObserver: CodexInterruptWatcherDelegate {
    nonisolated func didDetectInterrupt(sessionId: String) {
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didDetectInterrupt(sessionId: sessionId)
        }
    }
}

struct AgentInteractionRegistry {
    nonisolated static let shared = AgentInteractionRegistry()

    struct Capabilities: Sendable {
        let supportsConversationHistory: Bool
        let supportsRuntimeObservation: Bool
        let supportsMessaging: Bool
        let supportsSessionControl: Bool
    }

    private let runtimeObservationAgents: Set<AgentPlatform> = [.claude, .codex]

    private let adapters: [AgentPlatform: any AgentInteractionAdapter] = [
        .claude: TmuxAgentInteractionAdapter(agentType: .claude, supportsMessaging: true),
        .codex: TmuxAgentInteractionAdapter(agentType: .codex, supportsMessaging: true),
        .gemini: TmuxAgentInteractionAdapter(agentType: .gemini, supportsMessaging: true)
    ]

    nonisolated func capabilities(for agentType: AgentPlatform) -> Capabilities {
        Capabilities(
            supportsConversationHistory: SessionTranscriptProviderRegistry.shared.supportsHistory(for: agentType),
            supportsRuntimeObservation: runtimeObservationAgents.contains(agentType),
            supportsMessaging: adapter(for: agentType)?.supportsMessaging ?? false,
            supportsSessionControl: adapter(for: agentType)?.supportsSessionControl ?? false
        )
    }

    nonisolated func supportsConversationHistory(for agentType: AgentPlatform) -> Bool {
        capabilities(for: agentType).supportsConversationHistory
    }

    @MainActor
    func startObservingIfSupported(sessionId: String, agentType: AgentPlatform, cwd: String, transcriptPath: String?) {
        guard capabilities(for: agentType).supportsRuntimeObservation else { return }

        AgentRuntimeObserverRegistry.shared
            .observer(for: agentType)?
            .startObserving(sessionId: sessionId, cwd: cwd, transcriptPath: transcriptPath)
    }

    @MainActor
    func stopObservingIfSupported(sessionId: String, agentType: AgentPlatform) {
        guard capabilities(for: agentType).supportsRuntimeObservation else { return }

        AgentRuntimeObserverRegistry.shared
            .observer(for: agentType)?
            .stopObserving(sessionId: sessionId)
    }

    nonisolated func canSendMessages(for session: SessionState) -> Bool {
        adapter(for: session.agentType)?.canSendMessages(in: session) ?? false
    }

    func sendMessage(_ message: String, for session: SessionState) async -> Bool {
        guard let adapter = adapter(for: session.agentType) else {
            return false
        }

        return await adapter.sendMessage(message, in: session)
    }

    nonisolated func canInterruptTurn(for session: SessionState) -> Bool {
        adapter(for: session.agentType)?.canInterruptTurn(in: session) ?? false
    }

    func interruptTurn(for session: SessionState) async -> Bool {
        guard let adapter = adapter(for: session.agentType) else {
            return false
        }

        return await adapter.interruptTurn(in: session)
    }

    nonisolated func canTerminateSession(for session: SessionState) -> Bool {
        adapter(for: session.agentType)?.canTerminateSession(in: session) ?? false
    }

    func terminateSession(for session: SessionState) async -> Bool {
        guard let adapter = adapter(for: session.agentType) else {
            return false
        }

        return await adapter.terminateSession(in: session)
    }

    private nonisolated func adapter(for agentType: AgentPlatform) -> (any AgentInteractionAdapter)? {
        adapters[agentType]
    }
}

private struct TmuxAgentInteractionAdapter: AgentInteractionAdapter {
    let agentType: AgentPlatform
    let supportsMessaging: Bool
    let supportsSessionControl = true

    private func resolvedBackend(for session: SessionState) async -> TerminalBackend {
        await TerminalMultiplexerRegistry.shared.resolvedOrFallbackBackend(
            pid: session.pid,
            tty: session.tty
        )
    }

    private func backendAdapter(for session: SessionState) async -> any TerminalMultiplexerAdapter {
        let backend = await resolvedBackend(for: session)
        return await TerminalMultiplexerRegistry.shared.adapter(for: backend)
    }

    nonisolated func canSendMessages(in session: SessionState) -> Bool {
        guard supportsMessaging, session.isInTerminalMultiplexer, session.tty != nil else {
            return false
        }

        if agentType == .codex {
            return session.phase == .waitingForInput
        }

        return true
    }

    func sendMessage(_ message: String, in session: SessionState) async -> Bool {
        guard let tty = session.tty else {
            return false
        }

        return await backendAdapter(for: session).sendMessage(message, tty: tty, agentPid: session.pid)
    }

    nonisolated func canInterruptTurn(in session: SessionState) -> Bool {
        agentType.terminalControlProfile.supportsInterrupt && session.isInTerminalMultiplexer && session.tty != nil
    }

    func interruptTurn(in session: SessionState) async -> Bool {
        guard canInterruptTurn(in: session),
              let tty = session.tty else {
            return false
        }

        return await backendAdapter(for: session).sendSpecialKey(.escape, tty: tty, agentPid: session.pid)
    }

    nonisolated func canTerminateSession(in session: SessionState) -> Bool {
        agentType.terminalControlProfile.exitCommand != nil && session.isInTerminalMultiplexer && session.tty != nil
    }

    func terminateSession(in session: SessionState) async -> Bool {
        guard canTerminateSession(in: session),
              let exitCommand = agentType.terminalControlProfile.exitCommand,
              let tty = session.tty else {
            return false
        }

        if session.phase.isActive || session.phase.isWaitingForApproval {
            _ = await backendAdapter(for: session).sendSpecialKey(.escape, tty: tty, agentPid: session.pid)
            try? await Task.sleep(for: .milliseconds(120))
        }

        return await backendAdapter(for: session).sendMessage(exitCommand.text, tty: tty, agentPid: session.pid)
    }
}

private struct UnsupportedAgentInteractionAdapter: AgentInteractionAdapter {
    let agentType: AgentPlatform
    let supportsMessaging = false
    let supportsSessionControl = false

    nonisolated func canSendMessages(in session: SessionState) -> Bool {
        false
    }

    func sendMessage(_ message: String, in session: SessionState) async -> Bool {
        false
    }

    nonisolated func canInterruptTurn(in session: SessionState) -> Bool {
        false
    }

    func interruptTurn(in session: SessionState) async -> Bool {
        false
    }

    nonisolated func canTerminateSession(in session: SessionState) -> Bool {
        false
    }

    func terminateSession(in session: SessionState) async -> Bool {
        false
    }
}
