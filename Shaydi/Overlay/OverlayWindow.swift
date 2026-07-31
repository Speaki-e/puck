//
//  OverlayWindow.swift
//  Shaydi
//
//  F1 · owner: Sangwoo Kang
//  NSWindow subclass: borderless, transparent, click-through by default, level .floating
//

import AppKit

/// Transparent, borderless window hosting one display's PetARView.
/// plan/02_pet-app.md F1. `canBecomeKey`/`canBecomeMain` are false so this
/// never steals focus from whatever app the user is actually working in —
/// F6's text-input bubble is a separate window that's the deliberate
/// exception to that rule.
final class OverlayWindow: NSWindow {
    convenience init(screenFrame: CGRect) {
        self.init(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
