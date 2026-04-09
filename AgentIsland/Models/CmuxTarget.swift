//
//  CmuxTarget.swift
//  Agent Island
//
//  Data model for cmux workspace/surface targeting
//

import Foundation

struct CmuxTarget: Sendable {
    let workspaceId: String
    let surfaceId: String

    nonisolated init(workspaceId: String, surfaceId: String) {
        self.workspaceId = workspaceId
        self.surfaceId = surfaceId
    }
}
