//
//  AppPathResolver.swift
//  Agent Island
//
//  Centralized paths for diagnostics, support files, and the shared hook bridge.
//

import Foundation

enum AppPathResolver {
    nonisolated static var legacyRuntimeRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agent-island", isDirectory: true)
    }

    nonisolated static var applicationSupportDirectory: URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = base.appendingPathComponent("AgentIsland", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    nonisolated static var runtimeRoot: URL {
        let directory = applicationSupportDirectory.appendingPathComponent("Runtime", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    nonisolated static var logsDirectory: URL {
        let directory = applicationSupportDirectory.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    nonisolated static var hooksDirectory: URL {
        let directory = legacyRuntimeRoot.appendingPathComponent("hooks", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    nonisolated static var bridgeProfilesDirectory: URL {
        let directory = runtimeRoot.appendingPathComponent("bridge-profiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    nonisolated static var approvalPoliciesFileURL: URL {
        applicationSupportDirectory.appendingPathComponent("approval-policies.json")
    }

    nonisolated static var bridgeLogFileURL: URL {
        logsDirectory.appendingPathComponent("bridge.log")
    }

    nonisolated static var appLogFileURL: URL {
        logsDirectory.appendingPathComponent("app.log")
    }

    nonisolated static func migrateLegacyRuntimeIfNeeded(fileManager: FileManager = .default) throws {
        let legacyRoot = legacyRuntimeRoot
        guard fileManager.fileExists(atPath: legacyRoot.path) else {
            return
        }

        let migrations: [(from: URL, to: URL)] = [
            (
                legacyRoot.appendingPathComponent("bridge-profiles", isDirectory: true),
                bridgeProfilesDirectory
            ),
            (
                legacyRoot.appendingPathComponent("approval-policies.json"),
                approvalPoliciesFileURL
            ),
            (
                legacyRoot.appendingPathComponent("bridge-debug.log"),
                bridgeLogFileURL
            ),
            (
                legacyRoot.appendingPathComponent("app-debug.log"),
                appLogFileURL
            )
        ]

        for migration in migrations {
            try migrateItemIfNeeded(fileManager: fileManager, from: migration.from, to: migration.to)
        }
    }

    nonisolated private static func migrateItemIfNeeded(fileManager: FileManager, from sourceURL: URL, to destinationURL: URL) throws {
        guard fileManager.fileExists(atPath: sourceURL.path),
              !fileManager.fileExists(atPath: destinationURL.path) else {
            return
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            guard !fileManager.fileExists(atPath: destinationURL.path) else {
                return
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }
}
