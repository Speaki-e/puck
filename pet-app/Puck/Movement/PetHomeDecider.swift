//
//  PetHomeDecider.swift
//  Puck
//
//  Whether the pet is in its tank or out on the desktop.
//
//  One place decides this, and it is here rather than in the client: the
//  client knows about its own window, but only pet-app knows whether the pet
//  is hidden, and a decision split across a socket is a decision that can
//  disagree with itself.
//

import Foundation

final class PetHomeDecider {
    enum Move: Equatable {
        case home
        case desktop
    }

    /// How long a state has to hold before the pet acts on it. Alt-tabbing
    /// past the window would otherwise teleport the pet there and back.
    static let holdSeconds: TimeInterval = 0.7

    /// The menu bar's Hide toggle. Outranks everything: a hidden pet is not
    /// somewhere, it is nowhere.
    var isPetHidden = false {
        didSet { if isPetHidden != oldValue { pending = nil; elapsed = 0 } }
    }

    private var current: Move = .desktop
    private var pending: Move?
    private var elapsed: TimeInterval = 0

    /// The client's latest word on its tank. `hasTank` is false when there is
    /// no usable rect at all (window closed, or too small for a pet).
    func report(hasTank: Bool, visible: Bool, pinned: Bool) {
        let wanted: Move
        if !hasTank {
            wanted = .desktop
        } else if pinned {
            wanted = .home
        } else {
            wanted = visible ? .home : .desktop
        }
        guard wanted != pending else { return }
        pending = wanted
        elapsed = 0
    }

    /// - Returns: the move to make, once and only once, when a reported state
    ///   has held long enough and differs from where the pet already is.
    func tick(dt: TimeInterval) -> Move? {
        guard !isPetHidden, let pending else { return nil }
        elapsed += dt
        guard elapsed >= Self.holdSeconds else { return nil }
        self.pending = nil
        elapsed = 0
        guard pending != current else { return nil }
        current = pending
        return pending
    }
}
