//
//  NotchUserDriver.swift
//  ClaudeIsland
//
//  Stub update manager (Sparkle removed)
//

import Combine
import Foundation

/// Update state published to UI
enum UpdateState: Equatable {
    case idle

    var isActive: Bool { false }
}

/// Stub update manager — Sparkle has been removed
@MainActor
class UpdateManager: NSObject, ObservableObject {
    static let shared = UpdateManager()

    @Published var state: UpdateState = .idle
    @Published var hasUnseenUpdate: Bool = false

    func markUpdateSeen() {
        hasUnseenUpdate = false
    }
}
