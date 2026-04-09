//
//  SessionPhaseHelpers.swift
//  Agent Island
//
//  Helper functions for session phase display
//

import SwiftUI

struct SessionPhaseHelpers {
    /// Get color for session phase
    static func phaseColor(for phase: SessionPhase) -> Color {
        switch phase {
        case .waitingForApproval:
            return TerminalColors.amber
        case .waitingForInput:
            return TerminalColors.green
        case .processing:
            return TerminalColors.cyan
        case .compacting:
            return TerminalColors.magenta
        case .idle, .ended:
            return TerminalColors.dim
        }
    }

    /// Get description for session phase
    static func phaseDescription(for phase: SessionPhase) -> String {
        switch phase {
        case .waitingForApproval(let ctx):
            if ctx.mode == .terminal {
                return L10n.text(.phaseWaitingForTerminalConfirmation, ctx.toolName)
            }
            return L10n.text(.phaseWaitingForApproval, ctx.toolName)
        case .waitingForInput:
            return L10n.text(.phaseReadyForInput)
        case .processing:
            return L10n.text(.phaseProcessing)
        case .compacting:
            return L10n.text(.phaseCompacting)
        case .idle:
            return L10n.text(.phaseIdle)
        case .ended:
            return L10n.text(.phaseEnded)
        }
    }

    /// Format time ago string
    static func timeAgo(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 5 { return L10n.text(.timeNow) }
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }
}
