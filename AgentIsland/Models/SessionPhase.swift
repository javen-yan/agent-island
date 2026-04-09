//
//  SessionPhase.swift
//  Agent Island
//
//  Explicit state machine for Claude session lifecycle.
//  All state transitions are validated before being applied.
//

import Foundation

enum ApprovalMode: String, Sendable {
    case nativeApp
    case terminal
}

/// Permission context for tools waiting for approval
struct PermissionContext: Sendable {
    let toolUseId: String
    let toolName: String
    let toolInput: [String: AnyCodable]?
    let mode: ApprovalMode
    let receivedAt: Date

    /// Format tool input for display
    var formattedInput: String? {
        guard let input = toolInput else { return nil }
        var parts: [String] = []
        for (key, value) in input {
            let valueStr: String
            switch value.value {
            case let str as String:
                valueStr = str.count > 100 ? String(str.prefix(100)) + "..." : str
            case let num as Int:
                valueStr = String(num)
            case let num as Double:
                valueStr = String(num)
            case let bool as Bool:
                valueStr = bool ? "true" : "false"
            default:
                valueStr = "..."
            }
            parts.append("\(key): \(valueStr)")
        }
        return parts.joined(separator: "\n")
    }
}

extension PermissionContext: Equatable {
    nonisolated static func == (lhs: PermissionContext, rhs: PermissionContext) -> Bool {
        // Compare by identity fields only (AnyCodable doesn't conform to Equatable)
        lhs.toolUseId == rhs.toolUseId &&
        lhs.toolName == rhs.toolName &&
        lhs.mode == rhs.mode &&
        lhs.receivedAt == rhs.receivedAt
    }
}

enum SessionPhaseSource: Sendable {
    case transcript
    case runtime
}

/// Explicit session phases - the state machine
enum SessionPhase: Sendable {
    /// Session is idle, waiting for user input or new activity
    case idle

    /// Claude is actively processing (running tools, generating response)
    case processing

    /// Claude has finished and is waiting for user input
    case waitingForInput

    /// A tool is waiting for user permission approval
    case waitingForApproval(PermissionContext)

    /// Context is being compacted (auto or manual)
    case compacting

    /// Session has ended
    case ended

    // MARK: - State Machine Transitions

    /// Check if a transition to the target phase is valid
    nonisolated func canTransition(to next: SessionPhase) -> Bool {
        switch (self, next) {
        // Terminal state - no transitions out
        case (.ended, _):
            return false

        // Any state can transition to ended
        case (_, .ended):
            return true

        // Idle transitions
        case (.idle, .processing):
            return true
        case (.idle, .waitingForApproval):
            return true  // Direct permission request on idle session
        case (.idle, .compacting):
            return true

        // Processing transitions
        case (.processing, .waitingForInput):
            return true
        case (.processing, .waitingForApproval):
            return true
        case (.processing, .compacting):
            return true
        case (.processing, .idle):
            return true  // Interrupt or quick completion

        // WaitingForInput transitions
        case (.waitingForInput, .processing):
            return true
        case (.waitingForInput, .idle):
            return true  // Can become idle
        case (.waitingForInput, .compacting):
            return true

        // WaitingForApproval transitions
        case (.waitingForApproval, .processing):
            return true  // Approved - tool will run
        case (.waitingForApproval, .idle):
            return true  // Denied or cancelled
        case (.waitingForApproval, .waitingForInput):
            return true  // Denied and Claude stopped
        case (.waitingForApproval, .waitingForApproval):
            return true  // Another tool needs approval (multiple pending permissions)

        // Compacting transitions
        case (.compacting, .processing):
            return true
        case (.compacting, .idle):
            return true
        case (.compacting, .waitingForInput):
            return true

        // Allow staying in same state (no-op transitions)
        default:
            return self == next
        }
    }

    /// Attempt to transition to a new phase, returns the new phase if valid
    nonisolated func transition(to next: SessionPhase) -> SessionPhase? {
        canTransition(to: next) ? next : nil
    }

    /// Whether this phase indicates the session needs user attention
    var needsAttention: Bool {
        switch self {
        case .waitingForApproval, .waitingForInput:
            return true
        default:
            return false
        }
    }

    /// Whether this phase indicates active processing
    var isActive: Bool {
        switch self {
        case .processing, .compacting:
            return true
        default:
            return false
        }
    }

    /// Whether this is a waitingForApproval phase
    var isWaitingForApproval: Bool {
        if case .waitingForApproval = self {
            return true
        }
        return false
    }

    /// Extract tool name if waiting for approval
    var approvalToolName: String? {
        if case .waitingForApproval(let ctx) = self {
            return ctx.toolName
        }
        return nil
    }

    nonisolated var approvalMode: ApprovalMode? {
        if case .waitingForApproval(let ctx) = self {
            return ctx.mode
        }
        return nil
    }
}

struct SessionPhaseSources: Equatable, Sendable {
    var transcript: SessionPhase?
    var runtime: SessionPhase?

    nonisolated mutating func set(_ phase: SessionPhase?, for source: SessionPhaseSource) {
        switch source {
        case .transcript:
            transcript = phase
        case .runtime:
            runtime = phase
        }
    }

    nonisolated func resolved(fallback: SessionPhase) -> SessionPhase {
        let candidates: [(SessionPhaseSource, SessionPhase)] = [
            (.runtime, runtime),
            (.transcript, transcript)
        ].compactMap { source, phase in
            guard let phase else { return nil }
            return (source, phase)
        }

        guard !candidates.isEmpty else { return fallback }

        return candidates.max { lhs, rhs in
            compare(lhs, rhs) == .orderedAscending
        }?.1 ?? fallback
    }

    private nonisolated func compare(
        _ lhs: (SessionPhaseSource, SessionPhase),
        _ rhs: (SessionPhaseSource, SessionPhase)
    ) -> ComparisonResult {
        let lhsScore = score(for: lhs.1)
        let rhsScore = score(for: rhs.1)
        if lhsScore != rhsScore {
            return lhsScore < rhsScore ? .orderedAscending : .orderedDescending
        }

        let lhsPriority = priority(for: lhs.0)
        let rhsPriority = priority(for: rhs.0)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority ? .orderedAscending : .orderedDescending
        }

        return .orderedSame
    }

    private nonisolated func score(for phase: SessionPhase) -> Int {
        switch phase {
        case .ended:
            return 1000
        case .waitingForApproval:
            return 900
        case .compacting:
            return 800
        case .processing:
            return 700
        case .waitingForInput:
            return 600
        case .idle:
            return 100
        }
    }

    private nonisolated func priority(for source: SessionPhaseSource) -> Int {
        switch source {
        case .runtime:
            return 2
        case .transcript:
            return 1
        }
    }
}

// MARK: - Equatable

extension SessionPhase: Equatable {
    nonisolated static func == (lhs: SessionPhase, rhs: SessionPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.processing, .processing): return true
        case (.waitingForInput, .waitingForInput): return true
        case (.waitingForApproval(let ctx1), .waitingForApproval(let ctx2)):
            return ctx1 == ctx2
        case (.compacting, .compacting): return true
        case (.ended, .ended): return true
        default: return false
        }
    }
}

// MARK: - Debug Description

extension SessionPhase: CustomStringConvertible {
    nonisolated var description: String {
        switch self {
        case .idle:
            return "idle"
        case .processing:
            return "processing"
        case .waitingForInput:
            return "waitingForInput"
        case .waitingForApproval(let ctx):
            return "waitingForApproval(\(ctx.toolName))"
        case .compacting:
            return "compacting"
        case .ended:
            return "ended"
        }
    }
}
