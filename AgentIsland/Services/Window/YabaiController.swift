//
//  YabaiController.swift
//  Agent Island
//
//  Legacy yabai window management retained for future re-integration.
//  The current product flow does not call into this file.
//

import Foundation

/// Controller for yabai window management.
actor YabaiController {
    static let shared = YabaiController()

    private init() {}

    func focusWindow(
        forAgentPid agentPid: Int,
        terminalBackend: TerminalBackend = TerminalMultiplexerRegistry.fallbackBackend
    ) async -> Bool {
        guard await WindowFinder.shared.isYabaiAvailable() else {
            return false
        }

        switch terminalBackend {
        case .tmux:
            let windows = await WindowFinder.shared.getAllWindows()
            let tree = ProcessTreeBuilder.shared.buildTree()
            guard let target = await TmuxController.shared.findTmuxTarget(forAgentPid: agentPid) else {
                return false
            }

            _ = await TmuxController.shared.switchToPane(target: target)
            if let terminalPid = await findTerminalPidForTmuxSession(target.session, tree: tree, windows: windows) {
                return await WindowFocuser.shared.focusTmuxWindow(terminalPid: terminalPid, windows: windows)
            }
            return false

        case .cmux:
            guard let target = await CmuxController.shared.findTarget(forAgentPid: agentPid) else {
                return false
            }
            return await CmuxController.shared.switchToTarget(target)
        }
    }

    func focusWindow(
        forWorkingDirectory workingDirectory: String,
        terminalBackend: TerminalBackend = TerminalMultiplexerRegistry.fallbackBackend
    ) async -> Bool {
        guard await WindowFinder.shared.isYabaiAvailable() else { return false }

        switch terminalBackend {
        case .tmux:
            let windows = await WindowFinder.shared.getAllWindows()
            let tree = ProcessTreeBuilder.shared.buildTree()
            guard let target = await TmuxController.shared.findTmuxTarget(forWorkingDirectory: workingDirectory) else {
                return false
            }

            _ = await TmuxController.shared.switchToPane(target: target)
            if let terminalPid = await findTerminalPidForTmuxSession(target.session, tree: tree, windows: windows) {
                return await WindowFocuser.shared.focusTmuxWindow(terminalPid: terminalPid, windows: windows)
            }
            return false

        case .cmux:
            guard let target = await CmuxController.shared.findTarget(forWorkingDirectory: workingDirectory) else {
                return false
            }
            return await CmuxController.shared.switchToTarget(target)
        }
    }

    private func findTerminalPidForTmuxSession(
        _ session: String,
        tree: [Int: ProcessInfo],
        windows: [YabaiWindow]
    ) async -> Int? {
        guard let tmuxPath = await TmuxPathFinder.shared.getTmuxPath() else { return nil }

        do {
            let output = try await ProcessExecutor.shared.run(tmuxPath, arguments: [
                "list-clients", "-t", session, "-F", "#{client_pid}"
            ])

            let clientPids = output.components(separatedBy: "\n")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

            let windowPids = Set(windows.map(\.pid))
            for clientPid in clientPids {
                var currentPid = clientPid
                while currentPid > 1 {
                    guard let info = tree[currentPid] else { break }
                    if isTerminalProcess(info.command) && windowPids.contains(currentPid) {
                        return currentPid
                    }
                    currentPid = info.ppid
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    private nonisolated func isTerminalProcess(_ command: String) -> Bool {
        let terminalCommands = ["Terminal", "iTerm", "iTerm2", "Alacritty", "kitty", "WezTerm", "wezterm-gui", "Hyper"]
        return terminalCommands.contains { command.contains($0) }
    }
}
