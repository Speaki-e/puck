//
//  FocusModeObserver.swift
//  Puck
//
//  F5 · owner: Sangwoo Kang
//  Detects macOS Focus (Do Not Disturb) -> optional auto-mute
//
//  macOS has no public, documented API for third-party apps to query Focus
//  status. This listens for the long-observed (but unofficial, undocumented,
//  version-dependent) distributed notification some menu-bar utilities rely
//  on for the older Do Not Disturb feature; there is no reliable way to
//  query the *current* status at startup, so `isFocusActive` starts at
//  false and only updates from notifications seen after `startObserving()`.
//  Whether this notification still fires at all after macOS 12's Focus
//  overhaul hasn't been verified against a real device with Focus toggled —
//  that verification needs a human actually testing it. This is exactly why
//  F5's spec calls auto-mute-on-Focus an *option*, not a requirement; it
//  defaults to off and should stay off until someone confirms detection
//  actually works on the target macOS version.

import Foundation

final class FocusModeObserver {
    private static let distributedNotificationName = Notification.Name("com.apple.notificationcenterui.dndStatusChanged")

    private(set) var isFocusActive = false
    /// Called with the new value whenever a status-change notification arrives.
    var onChange: ((Bool) -> Void)?

    private var observerToken: NSObjectProtocol?

    func startObserving() {
        observerToken = DistributedNotificationCenter.default().addObserver(
            forName: Self.distributedNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleNotification(notification)
        }
    }

    func stopObserving() {
        if let observerToken {
            DistributedNotificationCenter.default().removeObserver(observerToken)
        }
        observerToken = nil
    }

    private func handleNotification(_ notification: Notification) {
        // The legacy notification's userInfo doesn't reliably carry the new
        // status across macOS versions, so this just flips state on each
        // notification rather than trusting an unstable payload shape.
        isFocusActive.toggle()
        onChange?(isFocusActive)
    }
}
