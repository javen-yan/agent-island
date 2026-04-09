//
//  CodexInterruptWatcher.swift
//  Agent Island
//
//  Watches Codex transcript files for turn-abort markers written when the user
//  interrupts a running turn with Esc.
//

import Foundation
import os.log

private let codexInterruptLogger = Logger(subsystem: "com.agentisland", category: "CodexInterrupt")

protocol CodexInterruptWatcherDelegate: AnyObject {
    func didDetectInterrupt(sessionId: String)
}

final class CodexInterruptWatcher {
    private let sessionId: String
    private let filePath: String
    private let queue = DispatchQueue(label: "com.agentisland.codexinterruptwatcher", qos: .userInteractive)

    private var fileHandle: FileHandle?
    private var source: DispatchSourceFileSystemObject?
    private var lastOffset: UInt64 = 0

    weak var delegate: CodexInterruptWatcherDelegate?

    init?(sessionId: String, transcriptPath: String?) {
        self.sessionId = sessionId

        if let transcriptPath,
           FileManager.default.fileExists(atPath: transcriptPath) {
            self.filePath = transcriptPath
        } else if let resolvedPath = Self.resolveTranscriptPath(sessionId: sessionId) {
            self.filePath = resolvedPath
        } else {
            return nil
        }
    }

    func start() {
        queue.async { [weak self] in
            self?.startWatching()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopInternal()
        }
    }

    private func startWatching() {
        stopInternal()

        guard FileManager.default.fileExists(atPath: filePath),
              let handle = FileHandle(forReadingAtPath: filePath) else {
            codexInterruptLogger.warning("Failed to open Codex transcript: \(self.filePath, privacy: .public)")
            AppDiagnosticsLogger.log(.error, category: .session, "Failed to open Codex transcript path=\(self.filePath)")
            return
        }

        fileHandle = handle

        do {
            lastOffset = try handle.seekToEnd()
        } catch {
            codexInterruptLogger.error("Failed to seek Codex transcript: \(error.localizedDescription, privacy: .public)")
            AppDiagnosticsLogger.log(.error, category: .session, "Failed to seek Codex transcript path=\(self.filePath) error=\(error.localizedDescription)")
            return
        }

        let fd = handle.fileDescriptor
        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: queue
        )

        newSource.setEventHandler { [weak self] in
            self?.checkForInterrupt()
        }

        newSource.setCancelHandler { [weak self] in
            try? self?.fileHandle?.close()
            self?.fileHandle = nil
        }

        source = newSource
        newSource.resume()

        codexInterruptLogger.debug("Started watching Codex transcript: \(self.sessionId.prefix(8), privacy: .public)...")
        AppDiagnosticsLogger.log(.debug, category: .session, "Started Codex interrupt watcher session=\(self.sessionId)")
    }

    private func checkForInterrupt() {
        guard let handle = fileHandle else { return }

        let currentSize: UInt64
        do {
            currentSize = try handle.seekToEnd()
        } catch {
            return
        }

        guard currentSize > lastOffset else { return }

        do {
            try handle.seek(toOffset: lastOffset)
        } catch {
            return
        }

        guard let newData = try? handle.readToEnd(),
              let newContent = String(data: newData, encoding: .utf8) else {
            return
        }

        lastOffset = currentSize

        let lines = newContent.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            if isInterruptLine(line) {
                codexInterruptLogger.info("Detected Codex interrupt in session: \(self.sessionId.prefix(8), privacy: .public)")
                AppDiagnosticsLogger.log(.info, category: .session, "Detected Codex interrupt session=\(self.sessionId)")
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.didDetectInterrupt(sessionId: self.sessionId)
                }
                return
            }
        }
    }

    private func isInterruptLine(_ line: String) -> Bool {
        guard let lineData = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
            return line.contains("<turn_aborted>")
        }

        if let topLevelType = json["type"] as? String {
            if topLevelType == "event_msg",
               let payload = json["payload"] as? [String: Any],
               payload["type"] as? String == "turn_aborted" {
                return true
            }

            if topLevelType == "response_item",
               let payload = json["payload"] as? [String: Any],
               payload["type"] as? String == "message",
               let role = payload["role"] as? String,
               role == "user",
               let content = payload["content"] as? [[String: Any]] {
                return content.contains { item in
                    (item["text"] as? String)?.contains("<turn_aborted>") == true
                }
            }
        }

        return false
    }

    private func stopInternal() {
        if source != nil {
            codexInterruptLogger.debug("Stopped watching Codex transcript: \(self.sessionId.prefix(8), privacy: .public)...")
            AppDiagnosticsLogger.log(.debug, category: .session, "Stopped Codex interrupt watcher session=\(self.sessionId)")
        }
        source?.cancel()
        source = nil
    }

    private static func resolveTranscriptPath(sessionId: String) -> String? {
        let sessionsRoot = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/sessions")
        guard let enumerator = FileManager.default.enumerator(atPath: sessionsRoot) else {
            return nil
        }

        while let relativePath = enumerator.nextObject() as? String {
            guard relativePath.hasSuffix(".jsonl"),
                  relativePath.contains(sessionId) else {
                continue
            }

            let fullPath = (sessionsRoot as NSString).appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: fullPath) {
                return fullPath
            }
        }

        return nil
    }

    deinit {
        source?.cancel()
    }
}

@MainActor
final class CodexInterruptWatcherManager {
    static let shared = CodexInterruptWatcherManager()

    private var watchers: [String: CodexInterruptWatcher] = [:]
    weak var delegate: CodexInterruptWatcherDelegate?

    private init() {}

    func startWatching(sessionId: String, transcriptPath: String?) {
        guard watchers[sessionId] == nil,
              let watcher = CodexInterruptWatcher(sessionId: sessionId, transcriptPath: transcriptPath) else {
            return
        }

        watcher.delegate = delegate
        watcher.start()
        watchers[sessionId] = watcher
    }

    func stopWatching(sessionId: String) {
        watchers[sessionId]?.stop()
        watchers.removeValue(forKey: sessionId)
    }

    func stopAll() {
        for (_, watcher) in watchers {
            watcher.stop()
        }
        watchers.removeAll()
    }
}
