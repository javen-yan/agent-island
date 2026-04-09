//
//  AgentIcon.swift
//  Agent Island
//
//  Centralized icon wrapper for UI brand redesign.
//  Provide custom asset names first, then fall back to SF Symbols.
//

import AppKit
import SwiftUI

enum AgentIconRegistry {
    private static let fallbackIconNames: [String: String] = [
        "brain.head.profile": "agenticon-brain",
        "provider.claude": "provider-claude",
        "provider.codex": "provider-codex",
        "provider.gemini": "provider-gemini",
        "terminal": "agenticon-terminal",
        "sparkles": "agenticon-sparkles",
        "xmark": "agenticon-close",
        "line.3.horizontal": "agenticon-menu",
        "gear": "agenticon-gear",
        "checkmark": "agenticon-check",
        "hand.raised": "agenticon-permission",
        "exclamationmark.circle.fill": "agenticon-warning",
        "trash": "agenticon-trash",
        "bubble.left.fill": "agenticon-bubble-fill",
        "bubble.left.and.bubble.right": "agenticon-chat",
        "arrow.up.circle.fill": "agenticon-arrow-up",
        "chevron.left": "agenticon-chevron-left",
        "chevron.right": "agenticon-chevron-right",
        "chevron.down": "agenticon-chevron-down",
        "chevron.up": "agenticon-chevron-up",
        "speaker.wave.2": "agenticon-speaker",
        "display": "agenticon-display",
        "clock.arrow.circlepath": "agenticon-clock",
        "arrow.turn.down.right": "agenticon-arrow-down-right",
        "xmark.circle": "agenticon-close-circle",
        "doc.text": "agenticon-document-text",
        "doc": "agenticon-document",
        "puzzlepiece": "agenticon-plugin",
        "circle": "agenticon-circle",
        "circle.lefthalf.filled": "agenticon-circle-progress",
        "checkmark.circle.fill": "agenticon-check-circle-fill"
    ]

    static func imageName(for systemName: String) -> String? {
        fallbackIconNames[systemName]
    }
}

extension Image {
    init(agentIcon systemName: String) {
        if let imageName = AgentIconRegistry.imageName(for: systemName),
           NSImage(named: NSImage.Name(imageName)) != nil {
            self.init(imageName)
            return
        }

        self.init(systemName: systemName)
    }
}
