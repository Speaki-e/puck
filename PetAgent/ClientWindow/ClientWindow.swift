//
//  ClientWindow.swift
//  PetAgent
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
        title = "PetAgent"
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
    func applyGlassChrome() {
        styleMask.insert(.fullSizeContentView)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
    }
}
