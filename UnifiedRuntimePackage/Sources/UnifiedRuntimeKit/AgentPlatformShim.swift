import Foundation

enum ApprovalPolicy: String, Codable, CaseIterable, Sendable {
    case deny
    case allowOnce
    case allowAlways
    case autoExecute
}

enum ApprovalAction: String, CaseIterable, Sendable {
    case deny
    case allowOnce
    case allowAlways
    case autoExecute
    case terminal
}

enum ApprovalCapabilityKind: String, Codable, Sendable {
    case nativeInteractive
    case terminalOnly
    case unsupported
}

struct ApprovalCapability: Sendable, Equatable {
    let kind: ApprovalCapabilityKind
    let supportedPolicies: [ApprovalPolicy]
    let supportedActions: [ApprovalAction]
}

enum AgentPlatform: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case gemini
}
