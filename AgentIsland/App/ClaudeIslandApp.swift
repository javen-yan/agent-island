//
//  AgentIslandApp.swift
//  Agent Island
//
//  Dynamic Island for monitoring supported agent sessions
//

import SwiftUI

@main
struct AgentIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            AgentIslandSettingsSceneView()
        }
    }
}
