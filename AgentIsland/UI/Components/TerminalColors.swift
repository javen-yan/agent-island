//
//  TerminalColors.swift
//  Agent Island
//
//  Color palette for terminal-style UI
//

import SwiftUI

struct TerminalColors {
    nonisolated static let claude = Color(red: 0.18, green: 0.73, blue: 0.99)
    nonisolated static let green = Color(red: 0.4, green: 0.75, blue: 0.45)
    nonisolated static let amber = Color(red: 1.0, green: 0.7, blue: 0.0)
    nonisolated static let red = Color(red: 1.0, green: 0.3, blue: 0.3)
    nonisolated static let cyan = Color(red: 0.0, green: 0.8, blue: 0.8)
    nonisolated static let blue = Color(red: 0.4, green: 0.6, blue: 1.0)
    nonisolated static let magenta = Color(red: 0.8, green: 0.4, blue: 0.8)
    nonisolated static let dim = Color.white.opacity(0.4)
    nonisolated static let dimmer = Color.white.opacity(0.2)
    nonisolated static let prompt = Color(red: 0.85, green: 0.47, blue: 0.34)  // #d97857
    nonisolated static let background = Color.white.opacity(0.05)
    nonisolated static let backgroundHover = Color.white.opacity(0.1)
}
