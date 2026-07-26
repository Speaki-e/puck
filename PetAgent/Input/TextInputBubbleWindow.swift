//
//  TextInputBubbleWindow.swift
//  PetAgent
//
//  F6 · owner: Haeyoung Park
//  canBecomeKey borderless bubble window, restores frontmost app on close
//
//  The one deliberate exception to OverlayWindow's "never take focus" rule
//  (plan/02_pet-app.md F1/F6) — this window hosts the text-input bubble and
//  must become key so the user can actually type into it.

import AppKit

final class TextInputBubbleWindow: NSWindow {
    private var previouslyFrontmostApp: NSRunningApplication?

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
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    /// Remembers whichever app is frontmost right now, then takes focus.
    func showAndActivate() {
        previouslyFrontmostApp = NSWorkspace.shared.frontmostApplication
        makeKeyAndOrderFront(nil)
    }

    /// Hides the bubble and restores focus to whatever was frontmost before `showAndActivate()`.
    func closeAndRestoreFocus() {
        orderOut(nil)
        previouslyFrontmostApp?.activate()
        previouslyFrontmostApp = nil
    }
}
