import Foundation

struct TerminalMultiplexerRegistry {
    nonisolated static let shared = TerminalMultiplexerRegistry()
    nonisolated static let fallbackBackend: TerminalBackend = .tmux

    private init() {}

    func adapter(for backend: TerminalBackend) async -> any TerminalMultiplexerAdapter {
        switch backend {
        case .tmux:
            return TmuxTerminalMultiplexerAdapter.shared
        case .cmux:
            return CmuxTerminalMultiplexerAdapter.shared
        }
    }

    nonisolated func detectedBackend(pid: Int, tree: [Int: ProcessInfo]) -> TerminalBackend? {
        let orderedBackends = TerminalBackend.allCases
        for backend in orderedBackends {
            if ProcessTreeBuilder.shared.isInTerminalMultiplexer(pid: pid, tree: tree, backend: backend) {
                return backend
            }
        }
        return nil
    }

    nonisolated func resolvedBackend(
        pid: Int?,
        tty: String?,
        preferred fallback: TerminalBackend,
        tree: [Int: ProcessInfo]? = nil
    ) async -> TerminalBackend? {
        if let pid {
            let resolvedTree = tree ?? ProcessTreeBuilder.shared.buildTree()
            if let detected = detectedBackend(pid: pid, tree: resolvedTree) {
                return detected
            }
        }

        guard let tty, !tty.isEmpty else {
            return nil
        }

        let orderedBackends = [fallback] + TerminalBackend.allCases.filter { $0 != fallback }
        for backend in orderedBackends {
            let adapter = await adapter(for: backend)
            if await adapter.hasTarget(forTTY: tty) {
                return backend
            }
        }

        return nil
    }

    nonisolated func resolvedOrFallbackBackend(
        pid: Int?,
        tty: String?,
        tree: [Int: ProcessInfo]? = nil
    ) async -> TerminalBackend {
        await resolvedBackend(
            pid: pid,
            tty: tty,
            preferred: Self.fallbackBackend,
            tree: tree
        ) ?? Self.fallbackBackend
    }
}
