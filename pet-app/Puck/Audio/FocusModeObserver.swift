//
//  FocusModeObserver.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang)
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
    static let distributedNotificationName = Notification.Name("com.apple.notificationcenterui.dndStatusChanged")

    private(set) var isFocusActive = false
    /// Called with the new value whenever a status-change notification arrives.
    var onChange: ((Bool) -> Void)?

    /// DistributedNotificationCenter in the app; injectable so tests can
    /// exercise this wiring over a private, in-process NotificationCenter.
    /// The distributed centre is a cross-process daemon (distnoted) shared
    /// with the whole machine: delivery latency is unbounded, and the name
    /// above is one macOS itself posts, so a test that posts through it is
    /// racing both the daemon and anything else on the Mac that toggles
    /// Focus while it runs.
    private let center: NotificationCenter

    private var observerToken: NSObjectProtocol?

    init(center: NotificationCenter = DistributedNotificationCenter.default()) {
        self.center = center
    }

    func startObserving() {
        observerToken = center.addObserver(
            forName: Self.distributedNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleNotification(notification)
        }
    }

    func stopObserving() {
        if let observerToken {
            center.removeObserver(observerToken)
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
