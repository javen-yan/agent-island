//
//  AgentPlatform.swift
//  Agent Island
//
//  Supported top-level agent runtimes for session tracking and hook setup.
//

import SwiftUI

enum AgentExitCommand: Sendable {
    case quit
    case exit

    var text: String {
        switch self {
        case .quit: return "/quit"
        case .exit: return "/exit"
        }
    }

    var buttonLabel: String {
        switch self {
        case .quit: return L10n.text(.exitQuit)
        case .exit: return L10n.text(.exitExit)
        }
    }
}

struct AgentTerminalControlProfile: Sendable {
    let supportsInterrupt: Bool
    let exitCommand: AgentExitCommand?
}

struct AgentBehaviorProfile: Sendable {
    let displayNameKey: L10nKey
    let accentColor: Color
    let iconSymbol: String
    let terminalControlProfile: AgentTerminalControlProfile
    let autoRevealOnTurnCompletion: Bool
    let supportsPostTurnFollowUpInIsland: Bool
    let showsLastReplyInCompletionSummary: Bool
}

enum ApprovalPolicy: String, Codable, CaseIterable, Sendable {
    case deny
    case allowOnce
    case allowAlways
    case autoExecute

    nonisolated var displayName: String {
        switch self {
        case .deny: return L10n.text(.approvalDeny)
        case .allowOnce: return L10n.text(.approvalAllowOnce)
        case .allowAlways: return L10n.text(.approvalAllowAlways)
        case .autoExecute: return L10n.text(.approvalAutoExecute)
        }
    }
}

enum ApprovalAction: String, CaseIterable, Sendable {
    case deny
    case allowOnce
    case allowAlways
    case autoExecute

    nonisolated var label: String {
        switch self {
        case .deny: return L10n.text(.approvalDeny)
        case .allowOnce: return L10n.text(.approvalAllowOnce)
        case .allowAlways: return L10n.text(.approvalAllowAlways)
        case .autoExecute: return L10n.text(.approvalAutoExecute)
        }
    }

    nonisolated func displayLabel(
        provider: AgentPlatform,
        compact: Bool = false
    ) -> String {
        switch self {
        case .allowOnce:
            if provider == .codex {
                return L10n.text(.approvalContinue)
            }
            return compact ? L10n.text(.approvalOnce) : label
        case .allowAlways:
            return compact ? L10n.text(.approvalAlways) : label
        case .autoExecute:
            return compact ? L10n.text(.approvalAuto) : label
        case .deny:
            return label
        }
    }
}

enum ApprovalCapabilityKind: String, Codable, Sendable {
    case nativeInteractive
    case terminalOnly
    case unsupported
}

struct ApprovalCapability: Sendable {
    let kind: ApprovalCapabilityKind
    let supportedPolicies: [ApprovalPolicy]
    let supportedActions: [ApprovalAction]
}

enum AgentPlatform: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case gemini

    private nonisolated var profile: AgentBehaviorProfile {
        switch self {
        case .claude:
            return AgentBehaviorProfile(
                displayNameKey: .agentNameClaude,
                accentColor: TerminalColors.claude,
                iconSymbol: "provider.claude",
                terminalControlProfile: AgentTerminalControlProfile(
                    supportsInterrupt: true,
                    exitCommand: .exit
                ),
                autoRevealOnTurnCompletion: false,
                supportsPostTurnFollowUpInIsland: false,
                showsLastReplyInCompletionSummary: false
            )
        case .codex:
            return AgentBehaviorProfile(
                displayNameKey: .agentNameCodex,
                accentColor: Color(red: 0.06, green: 0.64, blue: 0.50),
                iconSymbol: "provider.codex",
                terminalControlProfile: AgentTerminalControlProfile(
                    supportsInterrupt: true,
                    exitCommand: .quit
                ),
                autoRevealOnTurnCompletion: true,
                supportsPostTurnFollowUpInIsland: true,
                showsLastReplyInCompletionSummary: true
            )
        case .gemini:
            return AgentBehaviorProfile(
                displayNameKey: .agentNameGemini,
                accentColor: Color(red: 0.26, green: 0.52, blue: 0.96),
                iconSymbol: "provider.gemini",
                terminalControlProfile: AgentTerminalControlProfile(
                    supportsInterrupt: true,
                    exitCommand: .quit
                ),
                autoRevealOnTurnCompletion: false,
                supportsPostTurnFollowUpInIsland: false,
                showsLastReplyInCompletionSummary: false
            )
        }
    }

    nonisolated var displayName: String {
        L10n.text(profile.displayNameKey)
    }

    var accentColor: Color {
        profile.accentColor
    }

    var iconSymbol: String {
        profile.iconSymbol
    }

    nonisolated var approvalCapability: ApprovalCapability {
        ProviderCapabilities.baseline(for: self).approvalCapability()
    }

    nonisolated var terminalControlProfile: AgentTerminalControlProfile {
        profile.terminalControlProfile
    }

    nonisolated var autoRevealOnTurnCompletion: Bool {
        profile.autoRevealOnTurnCompletion
    }

    nonisolated var supportsPostTurnFollowUpInIsland: Bool {
        profile.supportsPostTurnFollowUpInIsland
    }

    nonisolated var showsLastReplyInCompletionSummary: Bool {
        profile.showsLastReplyInCompletionSummary
    }

    static func from(rawValue: String?) -> AgentPlatform {
        guard let rawValue else { return .claude }

        switch rawValue.lowercased() {
        case "claude", "claudecode", "claude_code":
            return .claude
        case "codex":
            return .codex
        case "gemini", "geminicli", "gemini_cli":
            return .gemini
        default:
            return .claude
        }
    }

    nonisolated static func detect(fromCommand command: String) -> AgentPlatform? {
        let normalized = command.lowercased()

        if normalized.contains("claude") {
            return .claude
        }
        if normalized.contains("codex") {
            return .codex
        }
        if normalized.contains("gemini") {
            return .gemini
        }

        return nil
    }
}
