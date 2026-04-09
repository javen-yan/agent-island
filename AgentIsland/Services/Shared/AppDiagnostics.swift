//
//  AppDiagnostics.swift
//  Agent Island
//
//  Lightweight app-side file diagnostics sink for key runtime paths.
//

import Foundation

actor AppDiagnostics {
    static let shared = AppDiagnostics()

    enum Category: String, Sendable {
        case hooks = "hooks"
        case dispatcher = "dispatcher"
        case session = "session"
        case plugins = "plugins"
    }

    private let fileManager = FileManager.default
    private lazy var logPath: String = AppPathResolver.appLogFileURL.path
    private let formatter = ISO8601DateFormatter()
    private var fileHandle: FileHandle?

    func log(
        _ level: BridgeLogLevel,
        category: Category,
        message: @autoclosure () -> String
    ) {
        let settings = AppSettings.appDiagnosticsSnapshot()

        guard settings.enabled,
              settings.level.allows(level) else {
            return
        }

        let line = "ts=\(formatter.string(from: Date())) level=\(level.rawValue) category=\(category.rawValue) message=\(message())\n"

        guard let data = line.data(using: .utf8) else { return }

        if fileHandle == nil {
            if !fileManager.fileExists(atPath: logPath) {
                fileManager.createFile(atPath: logPath, contents: nil)
            }

            fileHandle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
        }

        guard let handle = fileHandle else {
            return
        }

        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            try? handle.close()
            fileHandle = nil
        }
    }
}

enum AppDiagnosticsLogger {
    nonisolated static func log(
        _ level: BridgeLogLevel,
        category: AppDiagnostics.Category,
        _ message: @autoclosure @escaping () -> String
    ) {
        let settings = AppSettings.appDiagnosticsSnapshot()
        guard settings.enabled,
              settings.level.allows(level) else {
            return
        }

        Task.detached(priority: .utility) {
            await AppDiagnostics.shared.log(level, category: category, message: message())
        }
    }
}
