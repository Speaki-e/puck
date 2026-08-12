//
//  ScreenManager.swift
//  Puck
//
//  F1 · owner: Sangwoo Kang
//  Tracks NSScreen list, responds to didChangeScreenParametersNotification
//

import AppKit

/// Keeps the current GlobalScreenSpace up to date as displays are
/// connected/disconnected/rearranged. Per GlobalScreenSpace.current()'s own
/// contract, a momentarily-empty screen list (e.g. mid-sleep) is ignored —
/// `current` keeps its last-known value rather than going stale/undefined.
final class ScreenManager {
    private(set) var current: GlobalScreenSpace
    private var observer: NSObjectProtocol?

    /// Called with the new GlobalScreenSpace whenever the display
    /// configuration actually changes (not called for the initial value).
    var onChange: ((GlobalScreenSpace) -> Void)?

    init?() {
        guard let space = GlobalScreenSpace.current() else { return nil }
        current = space
    }

    func startObserving() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopObserving() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }

    private func refresh() {
        guard let space = GlobalScreenSpace.current() else { return }
        current = space
        onChange?(space)
    }
}
