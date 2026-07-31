//
//  NotchWindowController.swift
//  Shaydi
//
//  Notch · owner: 박해영 (Haeyoung Park)
//  Owns the single NotchWindow, keeping it pinned to the top-center of the
//  main screen and swapping its size between collapsed/expanded via
//  NotchLayout.
//

import AppKit

final class NotchWindowController {
    /// The resting pill, no bigger than it needs to be to read as a notch.
    static let collapsedSize = CGSize(width: 160, height: 24)
    /// Sized to fit ToyCatalogue's toy-button row once expanded.
    static let expandedSize = CGSize(width: 260, height: 140)

    private(set) var window: NotchWindow?
    private(set) var isExpanded = false

    /// Injectable for tests -- a real NSScreen's frame can't be relied on to
    /// have a known value inside a test runner (same reasoning as
    /// TextInputBubbleWindow's frontmostAppProvider).
    var screenVisibleFrameProvider: () -> CGRect? = { NSScreen.main?.visibleFrame }

    private var screenChangeObserver: NSObjectProtocol?

    func start(contentView: NSView) {
        guard let screenFrame = screenVisibleFrameProvider() else { return }

        let window = NotchWindow(contentRect: NotchLayout.frame(
            screenMidX: screenFrame.midX, topY: screenFrame.maxY, size: Self.collapsedSize
        ))
        window.contentView = contentView
        window.orderFrontRegardless()
        self.window = window

        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.reposition() }
    }

    func stop() {
        window?.orderOut(nil)
        window = nil
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
        screenChangeObserver = nil
    }

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        reposition()
    }

    private func reposition() {
        guard let window, let screenFrame = screenVisibleFrameProvider() else { return }
        let size = isExpanded ? Self.expandedSize : Self.collapsedSize
        let frame = NotchLayout.frame(screenMidX: screenFrame.midX, topY: screenFrame.maxY, size: size)
        // Not animated: the SwiftUI content already animates its own
        // corner-radius/opacity change, and animating the NSWindow frame
        // itself on top would need to be pumped by a live run loop to
        // observe synchronously, which a plain unit test can't do.
        window.setFrame(frame, display: true, animate: false)
    }
}
