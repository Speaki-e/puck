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
    private(set) var previouslyFrontmostApp: NSRunningApplication?
    /// Injectable for tests -- real NSWorkspace frontmost-app state can't be
    /// relied on to change inside a test runner the way it does in a live app.
    var frontmostAppProvider: () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication }

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
    /// Skips recapturing while already visible: this window itself would be
    /// frontmost at that point (a re-triggered hotkey while the bubble is
    /// still open), so recapturing would clobber the real target app with
    /// PetAgent -- closeAndRestoreFocus() would then "restore" focus to
    /// PetAgent instead of the app the user actually invoked this from.
    func showAndActivate() {
        guard !isVisible else {
            makeKeyAndOrderFront(nil)
            return
        }
        previouslyFrontmostApp = frontmostAppProvider()
        makeKeyAndOrderFront(nil)
    }

    /// Hides the bubble and restores focus to whatever was frontmost before `showAndActivate()`.
    func closeAndRestoreFocus() {
        orderOut(nil)
        previouslyFrontmostApp?.activate()
        previouslyFrontmostApp = nil
    }
}
