//
//  NotchWindow.swift
//  Shaydi
//
//  Notch · owner: 박해영 (Haeyoung Park)
//  Borderless panel pinned to the top of the screen -- a "boring.notch"
//  -style Dynamic Island, present regardless of whether the Mac actually has
//  a camera notch (byeolki, 2026-08-01: "boring notch처럼 일반적인
//  다이내믹 아일랜드를 다는데").
//
//  Unlike OverlayWindow this isn't one-per-display and it does accept mouse
//  events -- the toy buttons inside need to be clickable -- but it still
//  never becomes key or main: a borderless window's own buttons fire on
//  click without that, and this must never steal keyboard focus the way
//  TextInputBubbleWindow deliberately does.
//

import AppKit

final class NotchWindow: NSWindow {
    convenience init(contentRect: CGRect) {
        self.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
