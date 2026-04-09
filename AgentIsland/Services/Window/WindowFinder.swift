//
//  WindowFinder.swift
//  Agent Island
//
//  Legacy yabai window lookup helpers retained for future re-integration.
//  The current product flow does not call into this file.
//

import Foundation

/// Information about a yabai window.
struct YabaiWindow: Sendable {
    let id: Int
    let pid: Int
    let title: String
    let space: Int
    let isVisible: Bool
    let hasFocus: Bool

    nonisolated init?(from dict: [String: Any]) {
        guard let id = dict["id"] as? Int,
              let pid = dict["pid"] as? Int else { return nil }

        self.id = id
        self.pid = pid
        self.title = dict["title"] as? String ?? ""
        self.space = dict["space"] as? Int ?? 0
        self.isVisible = dict["is-visible"] as? Bool ?? false
        self.hasFocus = dict["has-focus"] as? Bool ?? false
    }
}

/// Finds windows using yabai.
actor WindowFinder {
    static let shared = WindowFinder()

    private var yabaiPath: String?
    private var isAvailableCache: Bool?

    private init() {}

    /// Check if yabai is available (cached).
    func isYabaiAvailable() -> Bool {
        if let cached = isAvailableCache { return cached }

        let paths = ["/opt/homebrew/bin/yabai", "/usr/local/bin/yabai"]
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                yabaiPath = path
                isAvailableCache = true
                return true
            }
        }

        isAvailableCache = false
        return false
    }

    /// Get the yabai path if available.
    func getYabaiPath() -> String? {
        _ = isYabaiAvailable()
        return yabaiPath
    }

    /// Get all windows from yabai.
    func getAllWindows() async -> [YabaiWindow] {
        guard isYabaiAvailable(), let path = yabaiPath else { return [] }

        do {
            let output = try await ProcessExecutor.shared.run(path, arguments: ["-m", "query", "--windows"])
            guard let data = output.data(using: .utf8),
                  let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return []
            }
            return jsonArray.compactMap { YabaiWindow(from: $0) }
        } catch {
            return []
        }
    }

    nonisolated func getCurrentSpace(windows: [YabaiWindow]) -> Int? {
        windows.first(where: { $0.hasFocus })?.space
    }

    nonisolated func findWindows(forTerminalPid pid: Int, windows: [YabaiWindow]) -> [YabaiWindow] {
        windows.filter { $0.pid == pid }
    }

    nonisolated func findTmuxWindow(forTerminalPid pid: Int, windows: [YabaiWindow]) -> YabaiWindow? {
        windows.first { $0.pid == pid && $0.title.lowercased().contains("tmux") }
    }

    nonisolated func findPrimaryTerminalWindow(forTerminalPid pid: Int, windows: [YabaiWindow]) -> YabaiWindow? {
        windows.first { $0.pid == pid && !$0.title.contains("✳") }
    }
}
