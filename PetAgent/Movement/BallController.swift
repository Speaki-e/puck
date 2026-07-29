//
//  BallController.swift
//  PetAgent
//
//  F12 · owner: 박해영 (Haeyoung Park)
//  Glue between BallPhysics (pure math) and the CALayer it's drawn on
//  (02_pet-app.md F12, optional ball-toy interaction).
//
//  The toy is a pet-app-bundled decoration, not a user-customizable avatar
//  asset (plan/02_pet-app.md F12). It started as a plain drawn circle so no
//  art was needed; it is now byeolki's pumpkin (2026-07-29, "호박 이미지
//  추가함 저거 가지고 놀게"), which ships in the app bundle rather than in an
//  avatar package for exactly that reason -- swapping avatars must not take
//  the toy away.
//
//  Falls back to the old drawn circle if the image is missing, so a broken
//  or absent resource costs the toy its looks and not its behaviour.

import AppKit
import CoreGraphics
import ImageIO
import Foundation
import QuartzCore

final class BallController {
    /// Fired once when the ball transitions from falling to resting. The
    /// Idle/Walk-only gate on actually chasing it (F3's priority rule) is the
    /// caller's decision, not this controller's.
    var onLanded: ((CGPoint) -> Void)?

    let layer = CALayer()
    private(set) var state: BallState?

    /// Where the toy's visible pixels sit relative to its physics position
    /// (the middle of its layer). Measured from the artwork's alpha, because
    /// the drawn pumpkin doesn't fill its square box: resting the *centre* on
    /// a surface buries half the toy in the floor, and resting the layer's
    /// bottom edge leaves it floating on the transparent margin below the
    /// artwork (byeolki: "호박 테두리 실제 이미지 border", 2026-07-29).
    private(set) var visualBounds: CGRect = .zero
    /// The artwork's opaque box and pixel size, kept so a size change can
    /// recompute `visualBounds` without scanning the image's alpha again.
    private var measurement: (opaquePixels: CGRect, imagePixelSize: CGSize)?
    /// The radius the toy would have at scale 1, so repeated slider changes
    /// recompute from this rather than compounding -- the same trap
    /// SpriteAvatar.updateScale documents for the pet.
    private let baseRadius: CGFloat

    var isActive: Bool { state != nil }

    /// Big enough to read as a pumpkin rather than a dot, small enough that
    /// the pet can still be seen behind it while kicking it about.
    static let defaultRadius: CGFloat = 22

    init(parent: CALayer, radius: CGFloat = BallController.defaultRadius, scale: Double = 1) {
        baseRadius = radius
        let scaled = radius * CGFloat(scale)
        layer.bounds = CGRect(x: 0, y: 0, width: scaled * 2, height: scaled * 2)
        if let image = Self.loadToyImage() {
            layer.contents = image
            // The artwork isn't square; fit it rather than stretching it into
            // the layer's box.
            layer.contentsGravity = .resizeAspect
            layer.contentsScale = parent.contentsScale
            measurement = Self.measure(image)
            visualBounds = Self.visualBounds(for: measurement, layerSize: layer.bounds.size)
        } else {
            // The original drawn circle, kept as the fallback.
            layer.cornerRadius = radius
            layer.backgroundColor = NSColor.white.cgColor
            layer.borderColor = NSColor.black.cgColor
            layer.borderWidth = 1.5
            // A drawn circle fills its box exactly.
            visualBounds = CGRect(x: -scaled, y: -scaled, width: scaled * 2, height: scaled * 2)
        }
        layer.isHidden = true
        // Ticked every frame like the pet is, so the same rule applies: no
        // implicit animation between the frames we compute.
        layer.disableImplicitAnimations()
        parent.addSublayer(layer)
    }

    func spawn(at position: CGPoint) {
        state = BallState(position: position, phase: .falling)
        layer.position = position
        layer.isHidden = false
    }

    /// Call every frame while a ball exists (falling, resting, or kicked).
    /// `landingY` is the surface the toy comes to rest *on*, so it is the
    /// artwork's bottom edge that has to meet it -- the physics works in
    /// centres, so the surface is raised by however far the visible bottom
    /// sits below the centre.
    func tick(dt: TimeInterval, landingY: CGFloat, roamableArea: CGRect) {
        guard let current = state else { return }
        let wasFalling = current.phase == .falling

        let next = BallPhysics.step(
            current,
            dt: dt,
            landingY: landingY - visualBounds.maxY,
            roamableArea: roamableArea,
            visualBounds: visualBounds
        )
        state = next
        layer.position = next.position

        if wasFalling, next.phase == .resting {
            onLanded?(next.position)
        }
        if next.phase == .gone {
            layer.isHidden = true
            state = nil
        }
    }

    /// True while the cursor has hold of the toy.
    var isHeld: Bool { state?.phase == .held }

    /// Picks the toy up: physics stops until it is let go.
    func grab() {
        guard var current = state else { return }
        current.phase = .held
        current.verticalVelocity = 0
        current.horizontalVelocity = 0
        state = current
    }

    /// Carries the toy. Assigned outright, with no easing -- the same
    /// "the toy IS the cursor while held" model the pet's drag uses.
    func move(to position: CGPoint) {
        guard var current = state, current.phase == .held else { return }
        current.position = position
        state = current
        layer.position = position
    }

    /// Lets go: the toy falls from wherever it was dropped and lands normally.
    func release() {
        guard var current = state, current.phase == .held else { return }
        current.phase = .falling
        state = current
    }

    /// Lifts the toy up over the pet's head and lets it drop back onto it --
    /// the start of the heading loop (byeolki: "펫의 머리 위로 든 다음에
    /// 머리 위에서 계속 튕기게", 2026-07-29).
    ///
    /// The toy is placed rather than thrown: it is beside the pet when this
    /// runs (ChaseBall stops it there), and arcing it onto a head from the
    /// side is a projectile-targeting problem for a gesture the pet is
    /// supposed to be doing deliberately.
    /// Upward speed of a throw, px/sec. What matters is the height it buys:
    /// peak = speed^2 / (2 * gravity), so at the app's gravity of 2400 this
    /// sends the toy about 117pt up -- most of the pet's own height above its
    /// head, and about 0.6s in the air (byeolki: "던지는 높이 좀 더 높이",
    /// 2026-07-29; it was 420, which only cleared the head by ~37pt).
    static let throwSpeed: CGFloat = 750

    func lift(overX x: CGFloat, headTop: CGFloat, liftSpeed: CGFloat = BallController.throwSpeed) {
        guard var current = state, current.phase != .held else { return }
        current.position = CGPoint(x: x, y: headTop - visualBounds.maxY)
        current.horizontalVelocity = 0
        current.verticalVelocity = -liftSpeed
        current.phase = .falling
        state = current
        layer.position = current.position
    }

    /// Launches a resting ball away in `direction` -- a no-op if it's still
    /// falling or already kicked, so a stray call can't relaunch it mid-flight.
    func kick(direction: AvatarFacing) {
        guard let current = state, current.phase == .resting else { return }
        state = BallPhysics.kick(current, direction: direction)
    }

    /// Pops a resting ball straight up -- a no-op if it's still falling or
    /// already kicked, same guard as kick(direction:). Used for the
    /// juggle-before-kick variety (2026-07-29).
    func juggle() {
        guard let current = state, current.phase == .resting else { return }
        state = BallPhysics.juggle(current)
    }

    /// OverlayWindowController tears down and recreates every window+SpriteLayerView
    /// on a real display change -- mirrors SpriteAvatar.reparent's precedent.
    func reparent(to newParent: CALayer) {
        layer.removeFromSuperlayer()
        // Same reason SpriteAvatar does this: reparenting is exactly when the
        // toy can cross between a 1x and a 2x display, and a stale
        // contentsScale renders it at half resolution.
        layer.contentsScale = newParent.contentsScale
        newParent.addSublayer(layer)
    }

    /// Live-applies a new size (Settings' toy-size slider). Recomputed from
    /// `baseRadius` every time so repeated slider drags don't compound, and
    /// the outline follows -- everything that keeps the toy out of the floor
    /// and off the walls is measured from it.
    func updateScale(_ scale: Double) {
        let scaled = baseRadius * CGFloat(scale)
        layer.bounds = CGRect(x: 0, y: 0, width: scaled * 2, height: scaled * 2)
        if measurement != nil {
            visualBounds = Self.visualBounds(for: measurement, layerSize: layer.bounds.size)
        } else {
            visualBounds = CGRect(x: -scaled, y: -scaled, width: scaled * 2, height: scaled * 2)
        }
        // A resized toy resting on a surface would otherwise be left half
        // buried in it (or hovering) until something moved it again.
        if let current = state, current.phase == .resting {
            state?.phase = .falling
        }
    }

    private static func measure(_ image: CGImage) -> (opaquePixels: CGRect, imagePixelSize: CGSize)? {
        guard let opaque = OpaquePixelBounds.of(image) else { return nil }
        return (opaque, CGSize(width: image.width, height: image.height))
    }

    private static func visualBounds(
        for measurement: (opaquePixels: CGRect, imagePixelSize: CGSize)?,
        layerSize: CGSize
    ) -> CGRect {
        guard let measurement else {
            return CGRect(origin: CGPoint(x: -layerSize.width / 2, y: -layerSize.height / 2), size: layerSize)
        }
        return SpriteVisualBounds.relativeToCenter(
            opaquePixels: measurement.opaquePixels,
            imagePixelSize: measurement.imagePixelSize,
            layerSize: layerSize
        )
    }

    /// The bundled toy artwork, or nil if it isn't there.
    private static func loadToyImage() -> CGImage? {
        guard
            let url = Bundle.main.url(forResource: "pumpkin", withExtension: "png", subdirectory: "Toys")
                ?? Bundle.main.url(forResource: "pumpkin", withExtension: "png"),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            AppLogger.shared.log(.error, "Ball toy artwork missing; falling back to a drawn circle")
            return nil
        }
        return image
    }
}
