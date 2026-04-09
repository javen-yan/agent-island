//
//  WindowFocuser.swift
//  Agent Island
//
//  Legacy yabai focus helpers retained for future re-integration.
//  The current product flow does not call into this file.
//

import Foundation

/// Focuses windows using yabai.
actor WindowFocuser {
    static let shared = WindowFocuser()

    private init() {}

    func focusWindow(id: Int) async -> Bool {
        guard let yabaiPath = await WindowFinder.shared.getYabaiPath() else { return false }

        do {
            _ = try await ProcessExecutor.shared.run(yabaiPath, arguments: [
                "-m", "window", "--focus", String(id)
            ])
            return true
        } catch {
            return false
        }
    }

    func focusTmuxWindow(terminalPid: Int, windows: [YabaiWindow]) async -> Bool {
        if let tmuxWindow = WindowFinder.shared.findTmuxWindow(forTerminalPid: terminalPid, windows: windows) {
            return await focusWindow(id: tmuxWindow.id)
        }

        if let window = WindowFinder.shared.findPrimaryTerminalWindow(forTerminalPid: terminalPid, windows: windows) {
            return await focusWindow(id: window.id)
        }

        return false
    }
}
