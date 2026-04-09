//
//  NotchChromeFacade.swift
//  Agent Island
//
//  Lightweight facade for notch chrome state that should remain decoupled from
//  concrete service singletons such as the update manager.
//

import Combine
import Foundation

@MainActor
final class NotchChromeFacade: ObservableObject {
    static let shared = NotchChromeFacade()

    @Published private(set) var hasUnseenUpdate = false

    private var cancellables = Set<AnyCancellable>()

    init(updateManager: UpdateManager? = nil) {
        let updateManager = updateManager ?? .shared
        updateManager.$hasUnseenUpdate
            .receive(on: DispatchQueue.main)
            .assign(to: &$hasUnseenUpdate)
    }
}
