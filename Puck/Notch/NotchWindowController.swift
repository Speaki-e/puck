//
//  NotchWindowController.swift
//  Puck
//
//  Notch · owner: 박해영 (Haeyoung Park)
//  Owns the single NotchWindow, keeping it pinned to the top-center of the
//  main screen and swapping its size between collapsed/expanded via
//  NotchLayout.
//

import AppKit

final class NotchWindowController {
    /// Room for boring.notch's own headline widgets (Now Playing + battery)
    /// stacked above the toy row -- byeolki, 2026-08-01: "다이내믹 아일랜드
    /// 걍 Boring Notch 클론코딩을 기반으로 하고, 거기에 toy 꺼내는 것만
    /// 얹으라는 소리였는데". This is our own content's size, not tied to
    /// the physical notch, so unlike collapsedSize it stays a constant.
    static let expandedSize = CGSize(width: 300, height: 220)

    private(set) var window: NotchWindow?
    private(set) var isExpanded = false

    /// Injectable for tests -- a real NSScreen's frame can't be relied on to
    /// have a known value inside a test runner (same reasoning as
    /// TextInputBubbleWindow's frontmostAppProvider).
    ///
    /// `.frame`, not `.visibleFrame` -- byeolki, 2026-08-01: "맥북 노치가
    /// 메뉴막대 쪽에 있는데, 너가 만든거 위치는 걍 메뉴막대를 제외한 화면
    /// 맨 위임 조정하고". The real notch sits AT the menu bar's stripe, not
    /// below it; `.visibleFrame` excludes the menu bar and would leave this
    /// pinned under it instead of overlapping the same row a real
    /// notch/menu bar occupies.
    var screenFrameProvider: () -> CGRect? = { NSScreen.main?.frame }

    /// The real notch's own dimensions, if this screen has one -- read the
    /// same NSScreen values boring.notch's getClosedNotchSize does. nil
    /// (not a zeroed struct) when there's no main screen at all, so
    /// `collapsedSize()` can tell "no data" apart from "screen has no
    /// notch" and fall back correctly in both cases.
    var screenMetricsProvider: () -> NotchScreenMetrics? = {
        guard let screen = NSScreen.main else { return nil }
        return NotchScreenMetrics(
            screenWidth: screen.frame.width,
            notchHeight: screen.safeAreaInsets.top,
            auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width,
            menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY
        )
    }

    private var screenChangeObserver: NSObjectProtocol?

    /// The resting pill's size -- the real physical notch's own
    /// width/height when this screen has one, so the pill reads as an
    /// extension of the hardware cutout instead of a floating guess.
    private func collapsedSize() -> CGSize {
        screenMetricsProvider().map(NotchGeometry.closedSize) ?? NotchGeometry.fallbackSize
    }

    func start(contentView: NSView) {
        guard let screenFrame = screenFrameProvider() else { return }

        let window = NotchWindow(contentRect: NotchLayout.frame(
            screenMidX: screenFrame.midX, topY: screenFrame.maxY, size: collapsedSize()
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
        guard let window, let screenFrame = screenFrameProvider() else { return }
        let size = isExpanded ? Self.expandedSize : collapsedSize()
        let frame = NotchLayout.frame(screenMidX: screenFrame.midX, topY: screenFrame.maxY, size: size)
        // Not animated: the SwiftUI content already animates its own
        // corner-radius/opacity change, and animating the NSWindow frame
        // itself on top would need to be pumped by a live run loop to
        // observe synchronously, which a plain unit test can't do.
        window.setFrame(frame, display: true, animate: false)
    }
}
