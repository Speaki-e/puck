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
    /// Accumulated spin, radians. Reset whenever the toy stops being carried
    /// so it never comes back to physics lying on its side.
    private var spinAngle: CGFloat = 0
    /// The toy's unscaled on-screen size, so repeated slider changes
    /// recompute from this rather than compounding -- the same trap
    /// SpriteAvatar.updateScale documents for the pet.
    private let baseSize: CGSize
    /// Which toy this is. Exposed so callers can tell whether a rebuild is
    /// needed when the setting changes.
    let toy: Toy

    var isActive: Bool { state != nil }

    /// Big enough to read as a pumpkin rather than a dot, small enough that
    /// the pet can still be seen behind it while kicking it about.
    /// Size of the drawn-circle fallback, which has no artwork to take
    /// proportions from.
    static let fallbackSize = CGSize(width: 44, height: 44)

    init(parent: CALayer, toy: Toy = ToyCatalogue.default, scale: Double = 1) {
        self.toy = toy

        if let image = Self.loadArtwork(for: toy) {
            // The layer takes the ARTWORK's proportions, so nothing is
            // letterboxed and the drawn toy fills its own box exactly.
            let aspect = CGFloat(image.width) / CGFloat(image.height)
            baseSize = CGSize(width: toy.height * aspect, height: toy.height)
            layer.bounds = CGRect(origin: .zero, size: Self.scaled(baseSize, by: scale))
            layer.contents = image
            layer.contentsGravity = .resizeAspect
            layer.contentsScale = parent.contentsScale
            measurement = Self.measure(image)
            visualBounds = Self.visualBounds(for: measurement, layerSize: layer.bounds.size)
        } else {
            // The original drawn circle, kept as the fallback.
            baseSize = Self.fallbackSize
            let size = Self.scaled(baseSize, by: scale)
            layer.bounds = CGRect(origin: .zero, size: size)
            layer.cornerRadius = size.width / 2
            layer.backgroundColor = NSColor.white.cgColor
            layer.borderColor = NSColor.black.cgColor
            layer.borderWidth = 1.5
            // A drawn circle fills its box exactly.
            visualBounds = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        }
        layer.isHidden = true
        // Ticked every frame like the pet is, so the same rule applies: no
        // implicit animation between the frames we compute.
        layer.disableImplicitAnimations()
        parent.addSublayer(layer)
    }

    func spawn(at position: CGPoint) {
        spinAngle = 0
        layer.setAffineTransform(.identity)
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
        applyInFlightSpin(for: next.phase, dt: dt)

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
        spinAngle = 0
        layer.setAffineTransform(.identity)
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

    /// Carries the toy above the pet's head, spinning it. Called every frame
    /// while the pet is playing with a spin-style toy: the position follows
    /// the pet (it can still be nudged around by anything that moves the pet)
    /// and the angle accumulates, so the spin rate doesn't depend on the
    /// frame rate.
    func carry(to position: CGPoint, dt: TimeInterval) {
        guard var current = state, current.phase != .held else { return }
        current.phase = .carried
        current.position = position
        current.horizontalVelocity = 0
        current.verticalVelocity = 0
        state = current

        spinAngle += Self.spinRate * CGFloat(dt)
        layer.position = position
        layer.setAffineTransform(CGAffineTransform(rotationAngle: spinAngle))
    }

    /// Hands the toy back to physics, upright again.
    func stopCarrying() {
        spinAngle = 0
        layer.setAffineTransform(.identity)
        guard var current = state, current.phase == .carried else { return }
        current.phase = .falling
        state = current
    }

    /// A toy that twirls overhead also twirls while it's in the air -- a
    /// spinning wand that goes rigid the moment it's thrown looks broken.
    /// It settles upright when it lands, so it never comes to rest on its
    /// side (byeolki: "지팡이도 다른 장난감처럼 던져지고 막 그렇게 되게",
    /// 2026-07-29).
    private func applyInFlightSpin(for phase: BallPhase, dt: TimeInterval) {
        guard toy.play == .spinOverhead else { return }

        switch phase {
        case .kicked, .falling:
            spinAngle += Self.spinRate * CGFloat(dt)
            layer.setAffineTransform(CGAffineTransform(rotationAngle: spinAngle))
        case .resting, .gone:
            guard spinAngle != 0 else { return }
            spinAngle = 0
            layer.setAffineTransform(.identity)
        case .held, .carried:
            break // whoever is holding it owns the angle
        }
    }

    /// Turns per second, as radians. Brisk enough to read as twirling rather
    /// than drifting, slow enough that the artwork doesn't blur into a smear.
    static let spinRate: CGFloat = 2 * .pi * 1.2

    /// Lets go. With a `velocity` the toy is thrown and flies with it
    /// (byeolki: "호박도 펫처럼 잡아 던질 수 있게", 2026-07-29); at rest it
    /// just drops. Thrown, it uses the same `.kicked` motion a kick does, so
    /// it bounces off the walls, ceiling and floor and settles -- there is no
    /// separate "thrown by the user" physics to keep in step.
    func release(velocity: CGPoint = .zero) {
        guard var current = state, current.phase == .held else { return }
        let thrown = MovementSolver.cappedThrow(velocity)
        current.horizontalVelocity = thrown.x
        current.verticalVelocity = thrown.y
        // Falling is the vertical-only path; a throw needs the sideways one.
        current.phase = thrown == .zero ? .falling : .kicked
        current.kickedElapsed = 0
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
        let size = Self.scaled(baseSize, by: scale)
        layer.bounds = CGRect(origin: .zero, size: size)
        if measurement != nil {
            visualBounds = Self.visualBounds(for: measurement, layerSize: size)
        } else {
            layer.cornerRadius = size.width / 2
            visualBounds = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
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

    private static func scaled(_ size: CGSize, by scale: Double) -> CGSize {
        CGSize(width: size.width * CGFloat(scale), height: size.height * CGFloat(scale))
    }

    /// A toy's bundled artwork, or nil if it isn't there.
    private static func loadArtwork(for toy: Toy) -> CGImage? {
        guard
            let url = Bundle.main.url(
                forResource: toy.name,
                withExtension: "png",
                subdirectory: "Toys/\(toy.name)"
            ),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            AppLogger.shared.log(.error, "Artwork for toy \(toy.name) missing; falling back to a drawn circle")
            return nil
        }
        return image
    }
}
