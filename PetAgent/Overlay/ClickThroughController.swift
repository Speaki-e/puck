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
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var characterScreenPosition: CGPoint = .zero
    private var hitboxSize: CGSize = .zero
    private var gestureRecognizer = PetGestureRecognizer()

    /// Emitted when the user clicks or drags the character itself. Cursor
    /// positions are AppKit global screen coordinates — the same space
    /// `updateCharacter(screenPosition:)` is given.
    var onGesture: ((PetGesture) -> Void)?

    init(window: NSWindow) {
        self.window = window
        window.ignoresMouseEvents = true
    }

    /// Called whenever the character moves or its avatar (and thus hitbox) changes.
    func updateCharacter(screenPosition: CGPoint, hitboxSize: CGSize) {
        characterScreenPosition = screenPosition
        self.hitboxSize = hitboxSize
    }

    /// A *global* monitor only delivers events sent to OTHER apps -- the
    /// instant handleMouseMoved() sets ignoresMouseEvents = false, our own
    /// window starts receiving mouseMoved itself, and the global monitor goes
    /// silent for it. Without a local monitor too, clicks stayed enabled
    /// permanently after the cursor's first hitbox entry.
    func startMonitoring() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.handleMouseMoved()
        }
        // Mouse-down/drag/up only reach the *local* monitor, because the
        // window stops ignoring mouse events precisely when the cursor is over
        // the character — so those events are delivered to us, not to the app
        // behind. The global monitor would never see them.
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stopMonitoring() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        let cursor = NSEvent.mouseLocation
        let gesture: PetGesture?
        switch event.type {
        case .leftMouseDown:
            // Only a press that actually landed on the character counts —
            // ignoresMouseEvents may not have caught up with a fast cursor.
            guard Self.shouldAllowClicks(
                cursorPosition: cursor,
                characterScreenPosition: characterScreenPosition,
                hitboxSize: hitboxSize
            ) else { return }
            gesture = gestureRecognizer.mouseDown(at: cursor)
        case .leftMouseDragged:
            gesture = gestureRecognizer.mouseDragged(to: cursor)
        case .leftMouseUp:
            gesture = gestureRecognizer.mouseUp(at: cursor)
        default:
            handleMouseMoved()
            return
        }
        if let gesture {
            onGesture?(gesture)
        }
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
