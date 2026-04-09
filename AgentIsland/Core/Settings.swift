//
//  Settings.swift
//  Agent Island
//
//  App settings manager using UserDefaults
//

import Foundation

/// Available notification sounds
enum NotificationSound: String, CaseIterable {
    case none = "None"
    case pop = "Pop"
    case ping = "Ping"
    case tink = "Tink"
    case glass = "Glass"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case hero = "Hero"
    case morse = "Morse"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case basso = "Basso"

    /// The system sound name to use with NSSound, or nil for no sound
    var soundName: String? {
        self == .none ? nil : rawValue
    }
}

enum AppLanguage: String, CaseIterable, Codable {
    case system
    case english
    case simplifiedChinese

    var displayName: String {
        switch self {
        case .system: return "System"
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }
}

enum TerminalBackend: String, CaseIterable {
    case tmux
    case cmux

    var displayName: String {
        rawValue
    }
}

enum BridgeLogLevel: String, Codable, CaseIterable, Sendable {
    case off
    case error
    case info
    case debug
    case trace

    var displayName: String {
        rawValue.uppercased()
    }

    nonisolated var priority: Int {
        switch self {
        case .off: return 0
        case .error: return 1
        case .info: return 2
        case .debug: return 3
        case .trace: return 4
        }
    }

    nonisolated func allows(_ incoming: BridgeLogLevel) -> Bool {
        self != .off && incoming.priority <= priority
    }
}

enum AppSettings {
    private static let defaults = UserDefaults.standard
    private static let codexDangerousPatternMetaCharacters = CharacterSet(charactersIn: #"^$.*+?()[]{}|\\"#)

    struct AppDiagnosticsSnapshot: Sendable {
        let enabled: Bool
        let level: BridgeLogLevel
    }

    // MARK: - Keys

    private enum Keys {
        static let notificationSound = "notificationSound"
        static let codexDangerousCommandPatterns = "codexDangerousCommandPatterns"
        static let bridgeLogEnabled = "bridgeLogEnabled"
        static let bridgeLogLevel = "bridgeLogLevel"
        static let appLogEnabled = "appLogEnabled"
        static let appLogLevel = "appLogLevel"
        static let appLanguage = "appLanguage"
        static let chatHistoryRetentionLimit = "chatHistoryRetentionLimit"
    }

    // MARK: - Notification Sound

    /// The sound to play when Claude finishes and is ready for input
    static var notificationSound: NotificationSound {
        get {
            guard let rawValue = defaults.string(forKey: Keys.notificationSound),
                  let sound = NotificationSound(rawValue: rawValue) else {
                return .pop // Default to Pop
            }
            return sound
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.notificationSound)
        }
    }

    // MARK: - Codex Hook Safety

    static let codexBuiltInDangerousCommands: [String] = [
        "rm",
        "sudo",
        "su",
        "dd",
        "mkfs",
        "diskutil",
        "shutdown",
        "reboot",
        "halt",
        "chmod",
        "chown"
    ]

    static var codexBuiltInDangerousCommandPatterns: [String] {
        codexBuiltInDangerousCommands.map { command in
            let escaped = NSRegularExpression.escapedPattern(for: command)
            return #"^\s*["']?"# + escaped + #"(?:\s|$)"#
        }
    }

    /// Additional regex patterns that should trigger Codex PreToolUse confirmation.
    /// These are merged with the built-in dangerous command patterns.
    static var codexDangerousCommandPatterns: [String] {
        get {
            normalizedCodexDangerousCommandPatterns(
                defaults.stringArray(forKey: Keys.codexDangerousCommandPatterns) ?? []
            )
        }
        set {
            let cleaned = normalizedCodexDangerousCommandPatterns(newValue)
            defaults.set(Array(NSOrderedSet(array: cleaned)) as? [String] ?? cleaned, forKey: Keys.codexDangerousCommandPatterns)
        }
    }

    static func codexDangerousCommandPatternIssue(for pattern: String) -> String? {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let containsRegexSyntax = trimmed.rangeOfCharacter(from: codexDangerousPatternMetaCharacters) != nil
        if !containsRegexSyntax,
           trimmed.rangeOfCharacter(from: .alphanumerics) != nil {
            return "Pattern is too broad. Use an anchored regex like (^|\\\\s)\(trimmed)(\\\\s|$)."
        }

        return nil
    }

    @discardableResult
    static func sanitizeStoredCodexDangerousCommandPatterns() -> Bool {
        let raw = defaults.stringArray(forKey: Keys.codexDangerousCommandPatterns) ?? []
        let normalized = normalizedCodexDangerousCommandPatterns(raw)
        guard raw != normalized else { return false }
        defaults.set(normalized, forKey: Keys.codexDangerousCommandPatterns)
        return true
    }

    // MARK: - Bridge Diagnostics

    static var bridgeLogEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.bridgeLogEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.bridgeLogEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.bridgeLogEnabled)
        }
    }

    static var bridgeLogLevel: BridgeLogLevel {
        get {
            guard let rawValue = defaults.string(forKey: Keys.bridgeLogLevel),
                  let level = BridgeLogLevel(rawValue: rawValue) else {
                return .info
            }
            return level
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.bridgeLogLevel)
        }
    }

    static var appLogEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.appLogEnabled) == nil {
                return false
            }
            return defaults.bool(forKey: Keys.appLogEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.appLogEnabled)
        }
    }

    static var appLogLevel: BridgeLogLevel {
        get {
            guard let rawValue = defaults.string(forKey: Keys.appLogLevel),
                  let level = BridgeLogLevel(rawValue: rawValue) else {
                return .info
            }
            return level
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.appLogLevel)
        }
    }

    static var appLanguage: AppLanguage {
        get {
            guard let rawValue = defaults.string(forKey: Keys.appLanguage),
                  let language = AppLanguage(rawValue: rawValue) else {
                return .system
            }
            return language
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.appLanguage)
        }
    }

    static var chatHistoryRetentionLimit: Int {
        get {
            let storedValue = defaults.integer(forKey: Keys.chatHistoryRetentionLimit)
            if storedValue == 0 && defaults.object(forKey: Keys.chatHistoryRetentionLimit) == nil {
                return 50
            }
            return normalizedChatHistoryRetentionLimit(storedValue)
        }
        set {
            defaults.set(normalizedChatHistoryRetentionLimit(newValue), forKey: Keys.chatHistoryRetentionLimit)
        }
    }

    nonisolated static func appLanguageSnapshot() -> AppLanguage {
        let defaults = UserDefaults.standard
        guard let rawValue = defaults.string(forKey: "appLanguage"),
              let language = AppLanguage(rawValue: rawValue) else {
            return .system
        }
        return language
    }

    nonisolated static func appDiagnosticsSnapshot() -> AppDiagnosticsSnapshot {
        let defaults = UserDefaults.standard
        let enabledKey = "appLogEnabled"
        let levelKey = "appLogLevel"
        let enabled: Bool
        if defaults.object(forKey: enabledKey) == nil {
            enabled = false
        } else {
            enabled = defaults.bool(forKey: enabledKey)
        }

        let level: BridgeLogLevel
        if let rawValue = defaults.string(forKey: levelKey),
           let parsedLevel = BridgeLogLevel(rawValue: rawValue) {
            level = parsedLevel
        } else {
            level = .info
        }

        return AppDiagnosticsSnapshot(
            enabled: enabled,
            level: level
        )
    }

    nonisolated static func chatHistoryRetentionLimitSnapshot() -> Int {
        let defaults = UserDefaults.standard
        let key = "chatHistoryRetentionLimit"
        let storedValue = defaults.integer(forKey: key)
        if storedValue == 0 && defaults.object(forKey: key) == nil {
            return 50
        }
        return min(max(storedValue, 10), 500)
    }

    private static func normalizedCodexDangerousCommandPatterns(_ patterns: [String]) -> [String] {
        let cleaned = patterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { codexDangerousCommandPatternIssue(for: $0) == nil }

        return Array(NSOrderedSet(array: cleaned)) as? [String] ?? cleaned
    }

    private static func normalizedChatHistoryRetentionLimit(_ value: Int) -> Int {
        min(max(value, 10), 500)
    }
}
