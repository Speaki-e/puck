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
        // false, not true -- byeolki, 2026-08-01, after cloning boring.notch
        // to fix the notch's look: an NSWindow-level shadow draws a
        // rectangular penumbra behind NotchShape's flare, which reads as a
        // pill floating in front of the menu bar instead of an extension of
        // it. boring.notch's own BoringNotchWindow sets this false too and
        // draws its own conditional SwiftUI-level shadow only while
        // expanded (see NotchView) -- flush when collapsed, lifted when open.
        hasShadow = false
        // .statusBar, not .floating -- byeolki, 2026-08-01: "맥북 노치가
        // 메뉴막대 쪽에 있는데, 너가 만든거 위치는 걍 메뉴막대를 제외한 화면
        // 맨 위임 조정하고". This is the same level NSStatusItem/menu extras
        // use, so the pill actually draws at the menu bar's own stripe
        // instead of merely floating above ordinary app windows below it.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
