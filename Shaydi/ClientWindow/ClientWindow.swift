//
//  ClientWindow.swift
//  Shaydi
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  A regular titled/resizable window (unlike OverlayWindow/TextInputBubbleWindow,
//  this one is a real app window, not a floating/borderless overlay) -- it's
//  the persistent "Claude Desktop"-style client, not a transient popup.
//

import AppKit

final class ClientWindow: NSWindow {
    /// Fired when the user closes the window -- AppDelegate un-pins the
    /// character (F3 Pinned state) from here.
    var onWillClose: (() -> Void)?

    convenience init(contentRect: CGRect) {
        self.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = AppIdentity.displayName
        isReleasedWhenClosed = false
        applyGlassChrome()
        delegate = self
    }

    func showAndActivate() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension ClientWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        onWillClose?()
    }
}

extension NSWindow {
    /// The house window chrome (client window, settings window): content runs
    /// up under a transparent titlebar so the view's own vibrant background
    /// reaches the traffic lights, instead of a separate gray titlebar strip
    /// -- the plain-titlebar look was part of what read as "default macOS
    /// settings pane" (byeolki: "맥 기본 설정창처럼 생겼네").
    ///
    /// `isOpaque`/`backgroundColor` are load-bearing here, not decoration --
    /// byeolki, 2026-08-02: "신호등만 색이 다르게 보임 ... 신호등 부분만
    /// 다른 부분 같음". `titlebarAppearsTransparent` alone hides the gray
    /// titlebar *bar*, but the window's own default opaque background
    /// (`NSColor.windowBackgroundColor`, a light system gray) still shows
    /// through in the sliver right around the traffic lights unless the
    /// window itself is non-opaque with a clear background -- every other
    /// custom window in this app (OverlayWindow, NotchWindow,
    /// TextInputBubbleWindow) already sets these two for the same reason,
    /// this one just hadn't needed to draw all the way to its own corners
    /// until now.
    func applyGlassChrome() {
        styleMask.insert(.fullSizeContentView)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isOpaque = false
        backgroundColor = .clear
    }
}
