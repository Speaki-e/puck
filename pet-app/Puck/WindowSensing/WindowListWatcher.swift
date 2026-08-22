//
//  WindowListWatcher.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  CGWindowListCopyWindowInfo polling (10/15Hz) + NSWorkspace notification handling
//

import AppKit
import CoreGraphics

/// Polls the on-screen window list and keeps `windows` (front-to-back Z order,
/// already filtered to layer-0 app windows) up to date. Polls at `idlePollHz`
/// by default; an NSWorkspace app-activate/launch/terminate notification
/// triggers an immediate refresh plus `burstDuration` seconds at `burstPollHz`.
final class WindowListWatcher {
    static let idlePollHz: Double = 10
    static let burstPollHz: Double = 15
    static let burstDuration: TimeInterval = 3

    private(set) var windows: [WindowInfo] = []

    private let selfPID: pid_t
    private let minimumSize: CGSize
    private var pollTimer: Timer?
    /// Monotonic (ProcessInfo.systemUptime), not Date() — a wall-clock jump from
    /// NTP sync or waking from sleep must not affect when the burst window ends.
    private var burstEndUptime: TimeInterval?
    private var observerTokens: [NSObjectProtocol] = []

    init(
        selfPID: pid_t = ProcessInfo.processInfo.processIdentifier,
        minimumSize: CGSize = CGSize(width: 40, height: 40)
    ) {
        self.selfPID = selfPID
        self.minimumSize = minimumSize
    }

    func start() {
        refresh()
        scheduleTimer(hz: Self.idlePollHz)

        let center = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        observerTokens = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.triggerBurst()
            }
        }
    }

    /// A watcher that is simply dropped leaves its timer on the run loop and
    /// its observers on the workspace centre -- both of which the run loop
    /// and the centre keep alive, so "nobody refers to it any more" is not
    /// the same as "it stopped".
    deinit {
        stop()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        let center = NSWorkspace.shared.notificationCenter
        observerTokens.forEach { center.removeObserver($0) }
        observerTokens.removeAll()
    }

    private func triggerBurst() {
        burstEndUptime = ProcessInfo.processInfo.systemUptime + Self.burstDuration
        scheduleTimer(hz: Self.burstPollHz)
        refresh()
    }

    private func scheduleTimer(hz: Double) {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / hz, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common (not the default add(timer:forMode:) mode) so polling doesn't
        // pause while the user has a menu open or a modal/tracking loop is active.
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func tick() {
        refresh()
        if let end = burstEndUptime, ProcessInfo.processInfo.systemUptime >= end {
            burstEndUptime = nil
            scheduleTimer(hz: Self.idlePollHz)
        }
    }

    private func refresh() {
        windows = Self.filter(Self.fetchRawWindowList(), excludingPID: selfPID, minimumSize: minimumSize)
    }

    /// Pure filtering step, independently testable from the live window list:
    /// keeps only normal app windows (layer 0), excludes this process's own
    /// windows, and drops anything smaller than `minimumSize`. Z-order
    /// (input array order) is preserved.
    static func filter(_ windows: [WindowInfo], excludingPID selfPID: pid_t, minimumSize: CGSize) -> [WindowInfo] {
        windows.filter { window in
            window.layer == 0
                && window.ownerPID != selfPID
                && window.frame.width >= minimumSize.width
                && window.frame.height >= minimumSize.height
        }
    }

    /// Live CGWindowListCopyWindowInfo fetch, parsed into WindowInfo, already in
    /// front-to-back Z order. Not unit tested — it depends on real on-screen
    /// windows; keep this a thin, trusted parsing layer and put logic in `filter`.
    private static func fetchRawWindowList() -> [WindowInfo] {
        guard
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: AnyObject]]
        else {
            return []
        }

        return list.compactMap { entry in
            guard
                let windowID = entry[kCGWindowNumber as String] as? CGWindowID,
                let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                let layer = entry[kCGWindowLayer as String] as? Int,
                let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                let frame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else {
                return nil
            }

            return WindowInfo(
                windowID: windowID,
                ownerPID: ownerPID,
                ownerName: entry[kCGWindowOwnerName as String] as? String,
                title: entry[kCGWindowName as String] as? String,
                layer: layer,
                frame: frame
            )
        }
    }
}
