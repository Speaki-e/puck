//
//  ClickThroughController.swift
//  PetAgent
//
//  F1 · owner: Sangwoo Kang
//  Toggles ignoresMouseEvents based on the manifest hitbox AABB
//
//  Precise alpha-pixel hit testing is a later-priority improvement
//  (plan/02_pet-app.md F1) — this is the AABB version.

import AppKit
import CoreGraphics

/// Keeps a window's `ignoresMouseEvents` in sync with whether the cursor is
/// over the character's hitbox: click-through everywhere else, clickable
/// over the character so clicks/drags reach the app instead of passing
/// through to whatever's behind it.
final class ClickThroughController {
    private weak var window: NSWindow?
    private var monitor: Any?
    private var characterScreenPosition: CGPoint = .zero
    private var hitboxSize: CGSize = .zero

    init(window: NSWindow) {
        self.window = window
        window.ignoresMouseEvents = true
    }

    /// Called whenever the character moves or its avatar (and thus hitbox) changes.
    func updateCharacter(screenPosition: CGPoint, hitboxSize: CGSize) {
        characterScreenPosition = screenPosition
        self.hitboxSize = hitboxSize
    }

    func startMonitoring() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.handleMouseMoved()
        }
    }

    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handleMouseMoved() {
        let allow = Self.shouldAllowClicks(
            cursorPosition: NSEvent.mouseLocation,
            characterScreenPosition: characterScreenPosition,
            hitboxSize: hitboxSize
        )
        window?.ignoresMouseEvents = !allow
    }

    /// Pure hit test. Both points must already be in the same coordinate
    /// space (the caller is responsible for that consistency).
    static func shouldAllowClicks(cursorPosition: CGPoint, characterScreenPosition: CGPoint, hitboxSize: CGSize) -> Bool {
        let rect = CGRect(
            x: characterScreenPosition.x - hitboxSize.width / 2,
            y: characterScreenPosition.y - hitboxSize.height / 2,
            width: hitboxSize.width,
            height: hitboxSize.height
        )
        return rect.contains(cursorPosition)
    }
}
