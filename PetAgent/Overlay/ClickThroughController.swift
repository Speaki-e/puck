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
    private var isUpsideDown = false
    private var gestureRecognizer = PetGestureRecognizer()

    /// Emitted when the user clicks or drags the character itself. Cursor
    /// positions are AppKit global screen coordinates — the same space
    /// `updateCharacter(screenPosition:)` is given.
    var onGesture: ((PetGesture) -> Void)?

    /// Every cursor sample over the overlay, with whether it landed on the
    /// pet's head. Petting is recognised from plain movement rather than
    /// clicks, so it can't come through `onGesture` -- and the recognising
    /// itself lives outside this type, which only knows about hit testing.
    var onCursorMoved: ((CGPoint, Bool) -> Void)?

    init(window: NSWindow) {
        self.window = window
        window.ignoresMouseEvents = true
    }

    /// Called whenever the character moves or its avatar (and thus hitbox) changes.
    func updateCharacter(screenPosition: CGPoint, hitboxSize: CGSize, isUpsideDown: Bool = false) {
        characterScreenPosition = screenPosition
        self.hitboxSize = hitboxSize
        self.isUpsideDown = isUpsideDown
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
        let cursor = NSEvent.mouseLocation
        let allow = Self.shouldAllowClicks(
            cursorPosition: cursor,
            characterScreenPosition: characterScreenPosition,
            hitboxSize: hitboxSize,
            isUpsideDown: isUpsideDown
        )
        window?.ignoresMouseEvents = !allow

        let head = Self.headRect(
            characterScreenPosition: characterScreenPosition,
            hitboxSize: hitboxSize,
            isUpsideDown: isUpsideDown
        )
        onCursorMoved?(cursor, head.contains(cursor))
    }

    /// Pure hit test. Both points must already be in the same coordinate
    /// space (the caller is responsible for that consistency).
    ///
    /// `characterScreenPosition` is the character's ground/feet point (the
    /// same convention CharacterBody.position uses everywhere), in AppKit
    /// global space (bottom-left origin, Y increases upward) -- so the
    /// hitbox extends *upward* from it, not symmetrically around it. Building
    /// it symmetric around the feet left the character's upper half outside
    /// its own hitbox.
    ///
    /// F3 ceiling-crawling (2026-07-29): hanging from the ceiling, the body
    /// extends *downward* from the attachment point instead -- the same
    /// SpriteAvatar.setScreenPosition flip this mirrors on the click-test
    /// side. Missing this made a visibly-hanging pet unclickable.
    ///
    /// Extra margin added on every side beyond the manifest hitbox (2026-07-29,
    /// byeolki: "히트박스가 너무 작아서 잘 안 잡힘") -- the dummy avatar
    /// renders at ~130x133px, and requiring pixel-perfect precision on a
    /// sprite that small made grabbing it feel unreliable. A zero-size
    /// hitbox is still never clickable -- that's an unconfigured/loading
    /// avatar, not a small one, and padding shouldn't manufacture a
    /// clickable area out of nothing.
    ///
    /// Trimmed down slightly (2026-07-29, byeolki: "히트박스 넘모 큰데 아주
    /// 살짝만 줄여볼까") -- 40 read as too generous once the full expression
    /// set was in daily use; still forgiving, just less so.
    static let hitTestPadding: CGFloat = 28

    /// The character's full, unpadded body rect: the ground point plus
    /// hitboxSize, flipped by isUpsideDown. `shouldAllowClicks` pads this on
    /// every side; `headRect` slices a fraction off its "head" edge --
    /// previously each rebuilt this same vertical-slice-anchored-at-the-
    /// ground-point math independently (found via review).
    private static func bodyRect(characterScreenPosition: CGPoint, hitboxSize: CGSize, isUpsideDown: Bool) -> CGRect {
        let originY = isUpsideDown
            ? characterScreenPosition.y - hitboxSize.height
            : characterScreenPosition.y
        return CGRect(
            x: characterScreenPosition.x - hitboxSize.width / 2,
            y: originY,
            width: hitboxSize.width,
            height: hitboxSize.height
        )
    }

    static func shouldAllowClicks(
        cursorPosition: CGPoint,
        characterScreenPosition: CGPoint,
        hitboxSize: CGSize,
        isUpsideDown: Bool = false
    ) -> Bool {
        guard hitboxSize != .zero else { return false }
        let body = bodyRect(characterScreenPosition: characterScreenPosition, hitboxSize: hitboxSize, isUpsideDown: isUpsideDown)
        let rect = body.insetBy(dx: -hitTestPadding, dy: -hitTestPadding)
        return rect.contains(cursorPosition)
    }

    /// Fraction of the character's height, measured down from the top, that
    /// counts as its head for petting. The art is a chibi with a very large
    /// head, so this is generous — but it stops short of the body, because
    /// "쓰담쓰담" on the pet's feet isn't petting.
    static let headFraction: CGFloat = 0.45

    /// The head's rectangle, in the same AppKit global space as
    /// `shouldAllowClicks`. No hit-test padding: petting should require
    /// actually being on the pet, unlike grabbing it.
    static func headRect(
        characterScreenPosition: CGPoint,
        hitboxSize: CGSize,
        isUpsideDown: Bool = false
    ) -> CGRect {
        guard hitboxSize != .zero else { return .zero }
        let body = bodyRect(characterScreenPosition: characterScreenPosition, hitboxSize: hitboxSize, isUpsideDown: isUpsideDown)
        let headHeight = hitboxSize.height * headFraction
        // Y grows upward here, and the body extends up from the feet -- so the
        // head is the TOP slice, unless the pet is hanging from the ceiling
        // and its head is the bottom one.
        let originY = isUpsideDown ? body.minY : body.maxY - headHeight
        return CGRect(x: body.minX, y: originY, width: body.width, height: headHeight)
    }
}
