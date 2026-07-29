//
//  BallControllerTests.swift
//  PetAgent
//
//  F12 test · owner: 박해영 (Haeyoung Park)
//  Glue between BallPhysics and its CALayer -- spawn/tick/kick/reparent.
//

import XCTest
import QuartzCore
@testable import PetAgent

final class BallControllerTests: XCTestCase {
    private let roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 600)

    func test_spawn_showsTheLayerAtTheGivenPosition() {
        let parent = CALayer()
        let controller = BallController(parent: parent)

        controller.spawn(at: CGPoint(x: 200, y: 0))

        XCTAssertFalse(controller.layer.isHidden)
        XCTAssertEqual(controller.layer.position, CGPoint(x: 200, y: 0))
        XCTAssertTrue(controller.isActive)
    }

    func test_beforeSpawn_isNotActive() {
        let controller = BallController(parent: CALayer())
        XCTAssertFalse(controller.isActive)
    }

    func test_tick_movesTheLayerAsTheBallFalls() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 0))

        controller.tick(dt: 0.1, landingY: 500, roamableArea: roamableArea)

        XCTAssertGreaterThan(controller.layer.position.y, 0)
    }

    func test_tick_firesOnLanded_exactlyOnceWhenItReachesTheGround() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 495))
        var landedPositions: [CGPoint] = []
        controller.onLanded = { landedPositions.append($0) }

        controller.tick(dt: 0.1, landingY: 500, roamableArea: roamableArea) // lands this frame
        controller.tick(dt: 0.1, landingY: 500, roamableArea: roamableArea) // resting, must not refire

        XCTAssertEqual(landedPositions.count, 1)
    }

    func test_kick_whileResting_launchesIt() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 495))
        controller.tick(dt: 0.1, landingY: 500, roamableArea: roamableArea) // now resting

        controller.kick(direction: .right)
        controller.tick(dt: 0.1, landingY: 500, roamableArea: roamableArea)

        XCTAssertGreaterThan(controller.layer.position.x, 200, "kicked right should move it right")
    }

    func test_kick_whileNotYetResting_isANoOp() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 0)) // still falling

        controller.kick(direction: .right)

        XCTAssertTrue(controller.isActive) // unaffected -- no crash, no state change
    }

    // MARK: - juggle() (F12 juggle-before-kick variety, 2026-07-29)

    func test_juggle_whileResting_popsItUpward() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 495))
        controller.tick(dt: 0.1, landingY: 500, roamableArea: roamableArea) // now resting
        let restingY = controller.layer.position.y

        controller.juggle()
        controller.tick(dt: 0.05, landingY: 500, roamableArea: roamableArea)

        XCTAssertLessThan(controller.layer.position.y, restingY, "should have popped upward")
    }

    func test_juggle_thenFallsBackAndRests() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 495))
        controller.tick(dt: 0.1, landingY: 500, roamableArea: roamableArea) // now resting

        controller.juggle()
        for _ in 0..<30 { // enough time for a small pop to arc back down
            controller.tick(dt: 0.05, landingY: 500, roamableArea: roamableArea)
        }

        // Back on the surface -- measured to the artwork's bottom edge, not to
        // the layer's centre, which would bury the toy in the floor.
        XCTAssertEqual(controller.layer.position.y + controller.visualBounds.maxY, 500, accuracy: 0.5)
    }

    /// Nothing expires the toy any more, so the only route to `.gone` is
    /// having no surface at all beneath it.
    func test_tick_hidesTheLayerAndDeactivates_onceGone() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 495))
        controller.tick(dt: 0.1, landingY: 500, roamableArea: roamableArea) // resting
        controller.kick(direction: .right)

        for _ in 0..<40 {
            // No landing surface anywhere below: the toy falls away and is
            // eventually cleaned up.
            controller.tick(dt: 0.1, landingY: 99_999, roamableArea: roamableArea)
        }

        XCTAssertTrue(controller.layer.isHidden)
        XCTAssertFalse(controller.isActive)
    }

    /// The toy is permanent (byeolki: "던지고 사라지지 않게 계속 남아있게") --
    /// a kick has to end with it back in play, not gone.
    func test_aKickedToyStaysOnScreenAndComesBackToRest() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 495))
        controller.tick(dt: 0.1, landingY: 500, roamableArea: roamableArea)
        controller.kick(direction: .right)

        for _ in 0..<600 {
            controller.tick(dt: 1.0 / 60, landingY: 500, roamableArea: roamableArea)
        }

        XCTAssertTrue(controller.isActive, "the toy disappeared")
        XCTAssertEqual(controller.state?.phase, .resting)
    }

    /// Throwing again moves the toy instead of doing nothing -- otherwise the
    /// menu item is dead forever after the first throw.
    func test_spawn_whileAlreadyInPlay_movesTheToy() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 100))
        controller.tick(dt: 0.5, landingY: 500, roamableArea: roamableArea)

        controller.spawn(at: CGPoint(x: 800, y: 50))

        XCTAssertEqual(controller.state?.position, CGPoint(x: 800, y: 50))
        XCTAssertEqual(controller.state?.phase, .falling, "dropped again from the new spot")
    }

    func test_reparent_movesTheLayerToTheNewParent() {
        let oldParent = CALayer()
        let controller = BallController(parent: oldParent)
        XCTAssertTrue(oldParent.sublayers?.contains(controller.layer) ?? false)

        let newParent = CALayer()
        controller.reparent(to: newParent)

        XCTAssertFalse(oldParent.sublayers?.contains(controller.layer) ?? false)
        XCTAssertTrue(newParent.sublayers?.contains(controller.layer) ?? false)
    }
}

/// The toy's artwork (byeolki's pumpkin, 2026-07-29). It ships in the app
/// bundle rather than in an avatar package, so switching avatars can't take
/// the toy away.
///
/// Bundle lookup itself can't be asserted from here -- these tests have no
/// host application, so `Bundle.main` is the xctest runner and never contains
/// app resources. What is worth guarding is that the file is still in the
/// repo, still decodable, and still shaped like the artwork the layer expects
/// -- a rename or a corrupt commit silently drops the pet back to the plain
/// drawn circle, with nothing failing anywhere.
final class BallToyArtworkTests: XCTestCase {
    private var artworkURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Movement
            .deletingLastPathComponent() // PetAgentTests
            .deletingLastPathComponent() // pet-app
            .appendingPathComponent("PetAgent/Resources/Toys/pumpkin.png")
    }

    func test_theToyArtworkIsInTheRepo() {
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: artworkURL.path),
            "the toy art is gone; BallController falls back to a drawn circle"
        )
    }

    func test_theToyArtworkDecodes() throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(artworkURL as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))

        XCTAssertGreaterThan(image.width, 0)
        XCTAssertGreaterThan(image.height, 0)
    }

    /// The layer draws it with .resizeAspect into a square box, so wildly
    /// non-square art would letterbox into something much smaller than the
    /// radius suggests.
    func test_theToyArtworkIsRoughlySquare() throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(artworkURL as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))

        let aspect = Double(image.width) / Double(image.height)
        XCTAssertEqual(aspect, 1, accuracy: 0.3, "the toy would letterbox badly in its square layer")
    }

    /// Without artwork the toy still has to behave -- the fallback is a
    /// cosmetic downgrade, not a broken toy.
    func test_theToyStillWorksWithoutArtwork() {
        let parent = CALayer()
        let controller = BallController(parent: parent)

        controller.spawn(at: CGPoint(x: 100, y: 0))
        XCTAssertTrue(controller.isActive)

        controller.tick(dt: 1, landingY: 100, roamableArea: CGRect(x: 0, y: 0, width: 500, height: 500))
        XCTAssertEqual(controller.state?.phase, .resting)
    }
}

/// Resting the toy on a surface by its artwork rather than by its layer
/// (byeolki: "호박 테두리 실제 이미지 border", 2026-07-29).
final class BallToyVisualBoundsTests: XCTestCase {
    private func makeController() -> BallController {
        BallController(parent: CALayer())
    }

    /// Without artwork the fallback is a drawn circle, which fills its box.
    func test_theDrawnCircleFallbackFillsItsBox() {
        let controller = makeController()

        // Whichever path ran, the bounds must be centred on the position and
        // no larger than the layer.
        XCTAssertEqual(controller.visualBounds.midX, 0, accuracy: 3, "not centred horizontally")
        XCTAssertLessThanOrEqual(controller.visualBounds.width, BallController.defaultRadius * 2 + 0.01)
        XCTAssertLessThanOrEqual(controller.visualBounds.height, BallController.defaultRadius * 2 + 0.01)
    }

    /// The artwork's bottom edge is what has to meet the surface. Resting the
    /// layer's centre there buries half the toy; resting its bottom edge
    /// leaves it hovering on the transparent margin.
    func test_theToyRestsOnItsArtworkNotItsCentre() {
        let controller = makeController()
        let floor: CGFloat = 400

        controller.spawn(at: CGPoint(x: 100, y: 0))
        // Long enough to have certainly landed.
        for _ in 0..<300 {
            controller.tick(dt: 1.0 / 60, landingY: floor, roamableArea: CGRect(x: 0, y: 0, width: 800, height: 800))
        }

        let position = try? XCTUnwrap(controller.state?.position)
        let restingY = try? XCTUnwrap(position?.y)
        XCTAssertEqual(controller.state?.phase, .resting)

        // Bottom of the artwork == the surface.
        XCTAssertEqual((restingY ?? 0) + controller.visualBounds.maxY, floor, accuracy: 0.01)
        XCTAssertLessThan(restingY ?? 0, floor, "the toy's centre must sit above the surface it rests on")
    }

    /// A regression guard on the specific mistake: the centre landing exactly
    /// on the surface, which is what happens if visualBounds is ignored.
    func test_theToyDoesNotSinkIntoTheSurface() {
        let controller = makeController()
        let floor: CGFloat = 400
        controller.spawn(at: CGPoint(x: 100, y: 0))
        for _ in 0..<300 {
            controller.tick(dt: 1.0 / 60, landingY: floor, roamableArea: CGRect(x: 0, y: 0, width: 800, height: 800))
        }

        let sunk = (controller.state?.position.y ?? 0) - floor
        XCTAssertLessThanOrEqual(sunk, 0, "the toy is \(sunk)pt into the floor")
    }
}

/// Picking the toy up with the cursor (byeolki: "호박도 펫처럼 커서로 집을 수
/// 있게", 2026-07-29).
final class BallToyGrabTests: XCTestCase {
    private let roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 600)

    private func restingToy() -> BallController {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 100))
        controller.tick(dt: 1, landingY: 500, roamableArea: roamableArea)
        XCTAssertEqual(controller.state?.phase, .resting)
        return controller
    }

    func test_grabbingSuspendsPhysics() {
        let controller = restingToy()
        controller.grab()
        let held = controller.state?.position

        // Plenty of frames with a surface far below: gravity must not act.
        for _ in 0..<120 {
            controller.tick(dt: 1.0 / 60, landingY: 5000, roamableArea: roamableArea)
        }

        XCTAssertTrue(controller.isHeld)
        XCTAssertEqual(controller.state?.position, held, "the toy moved while it was being held")
    }

    func test_movingCarriesTheToyAndItsLayer() {
        let controller = restingToy()
        controller.grab()

        controller.move(to: CGPoint(x: 700, y: 120))

        XCTAssertEqual(controller.state?.position, CGPoint(x: 700, y: 120))
        XCTAssertEqual(controller.layer.position, CGPoint(x: 700, y: 120), "the drawing has to follow too")
    }

    /// Only a held toy may be carried -- otherwise a stray call could
    /// teleport one mid-flight.
    func test_movingAToyThatIsNotHeldDoesNothing() {
        let controller = restingToy()
        let before = controller.state?.position

        controller.move(to: CGPoint(x: 700, y: 120))

        XCTAssertEqual(controller.state?.position, before)
    }

    func test_releasingDropsItFromWhereItWasLetGo() {
        let controller = restingToy()
        controller.grab()
        controller.move(to: CGPoint(x: 700, y: 50))

        controller.release()
        XCTAssertEqual(controller.state?.phase, .falling)
        XCTAssertFalse(controller.isHeld)

        for _ in 0..<600 where controller.state?.phase == .falling {
            controller.tick(dt: 1.0 / 60, landingY: 500, roamableArea: roamableArea)
        }

        XCTAssertEqual(controller.state?.phase, .resting, "it should land again")
        XCTAssertEqual(
            (controller.state?.position.y ?? 0) + controller.visualBounds.maxY,
            500,
            accuracy: 0.01,
            "resting on the surface by its artwork, same as any other landing"
        )
    }

    /// Being carried must not leave it stuck in mid-air if it's never
    /// released -- but equally, holding it over the floor and letting go has
    /// to land it rather than leaving it floating.
    func test_aHeldToyIsNotAffectedByScreenBounds() {
        let controller = restingToy()
        controller.grab()

        // Carried well outside the roamable area, as a cursor can do.
        controller.move(to: CGPoint(x: -300, y: -200))
        controller.tick(dt: 1.0 / 60, landingY: 500, roamableArea: roamableArea)

        XCTAssertEqual(controller.state?.position, CGPoint(x: -300, y: -200), "the hand outranks the walls")
    }
}

/// Lifting the toy onto the pet's head to start the heading loop.
final class BallToyLiftTests: XCTestCase {
    private let roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 600)

    private func restingToy() -> BallController {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 100))
        controller.tick(dt: 1, landingY: 500, roamableArea: roamableArea)
        return controller
    }

    func test_liftPlacesTheToyOnTheHeadAndSendsItUp() {
        let controller = restingToy()
        let headTop: CGFloat = 300

        controller.lift(overX: 640, headTop: headTop)

        XCTAssertEqual(controller.state?.position.x, 640, "directly over the pet")
        XCTAssertEqual(
            (controller.state?.position.y ?? 0) + controller.visualBounds.maxY,
            headTop,
            accuracy: 0.01,
            "sitting on the head by its artwork, like any other surface"
        )
        XCTAssertLessThan(controller.state?.verticalVelocity ?? 0, 0, "travelling upward")
        XCTAssertEqual(controller.state?.horizontalVelocity, 0, "straight up, so it comes back down on the head")
        XCTAssertEqual(controller.state?.phase, .falling)
    }

    /// It arcs up and comes back to where it started -- that return is what
    /// the head-collision path then turns into the next bounce.
    func test_aLiftedToyComesBackDownToTheHead() {
        let controller = restingToy()
        let headTop: CGFloat = 300
        controller.lift(overX: 640, headTop: headTop)

        var rose = false
        for _ in 0..<600 {
            controller.tick(dt: 1.0 / 60, landingY: headTop, roamableArea: roamableArea)
            if (controller.state?.verticalVelocity ?? 0) < 0 { rose = true }
            if controller.state?.phase == .resting { break }
        }

        XCTAssertTrue(rose, "never went up")
        XCTAssertEqual(controller.state?.phase, .resting, "never came back down onto the head")
        XCTAssertEqual(controller.state?.position.x, 640, "drifted sideways off the head")
    }

    /// A toy in the user's hand must not be yanked onto the pet's head.
    func test_liftIgnoresAHeldToy() {
        let controller = restingToy()
        controller.grab()
        let held = controller.state?.position

        controller.lift(overX: 640, headTop: 300)

        XCTAssertEqual(controller.state?.position, held)
        XCTAssertTrue(controller.isHeld)
    }
}

extension BallToyLiftTests {
    /// The throw has to clear the pet's head by a visible margin, not just
    /// hop off it (byeolki: "던지는 높이 좀 더 높이").
    func test_theThrowGoesWellAboveTheHead() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 100))
        controller.tick(dt: 1, landingY: 500, roamableArea: CGRect(x: 0, y: 0, width: 1000, height: 600))

        let headTop: CGFloat = 400
        controller.lift(overX: 500, headTop: headTop)

        var highest = CGFloat.greatestFiniteMagnitude
        for _ in 0..<600 {
            // No ceiling in the way, so the arc is the arc.
            controller.tick(dt: 1.0 / 60, landingY: headTop, roamableArea: CGRect(x: 0, y: 0, width: 1000, height: 10_000))
            highest = min(highest, (controller.state?.position.y ?? 0) + controller.visualBounds.maxY)
            if controller.state?.phase == .resting { break }
        }

        let clearance = headTop - highest
        XCTAssertGreaterThan(clearance, 100, "only cleared the head by \(clearance)pt")
        XCTAssertEqual(controller.state?.phase, .resting, "and it still comes back down")
    }
}

/// Resizing the toy (byeolki: "호박 크기도 조절 가능 하게", 2026-07-29).
final class BallToyScaleTests: XCTestCase {
    private let roamableArea = CGRect(x: 0, y: 0, width: 1000, height: 600)

    func test_scalingResizesTheLayer() {
        let controller = BallController(parent: CALayer())
        let base = controller.layer.bounds.width

        controller.updateScale(2)

        XCTAssertEqual(controller.layer.bounds.width, base * 2, accuracy: 0.01)
    }

    /// Repeated slider drags must recompute from the built-in size, not
    /// multiply the current one -- the trap the pet's own scaling documents.
    func test_scalingIsNotCumulative() {
        let controller = BallController(parent: CALayer())
        let base = controller.layer.bounds.width

        controller.updateScale(2)
        controller.updateScale(2)
        controller.updateScale(1.5)

        XCTAssertEqual(controller.layer.bounds.width, base * 1.5, accuracy: 0.01)
    }

    /// Everything that keeps the toy out of the floor and off the walls is
    /// measured from its outline, so that has to follow the size.
    func test_theOutlineFollowsTheSize() {
        let controller = BallController(parent: CALayer())
        let base = controller.visualBounds

        controller.updateScale(2)

        XCTAssertEqual(controller.visualBounds.width, base.width * 2, accuracy: 0.01)
        XCTAssertEqual(controller.visualBounds.maxY, base.maxY * 2, accuracy: 0.01)
    }

    func test_scalingCanBeSetAtConstruction() {
        let big = BallController(parent: CALayer(), scale: 2)
        let normal = BallController(parent: CALayer())

        XCTAssertEqual(big.layer.bounds.width, normal.layer.bounds.width * 2, accuracy: 0.01)
    }

    /// A toy resting on the floor when it's resized would be left buried in
    /// it (grown) or hovering above it (shrunk), so it drops again.
    func test_resizingARestingToyLetsItSettleAgain() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 100))
        controller.tick(dt: 1, landingY: 500, roamableArea: roamableArea)
        XCTAssertEqual(controller.state?.phase, .resting)

        controller.updateScale(2)
        XCTAssertEqual(controller.state?.phase, .falling, "should re-settle at its new size")

        for _ in 0..<600 where controller.state?.phase == .falling {
            controller.tick(dt: 1.0 / 60, landingY: 500, roamableArea: roamableArea)
        }

        XCTAssertEqual(
            (controller.state?.position.y ?? 0) + controller.visualBounds.maxY,
            500,
            accuracy: 0.01,
            "the bigger toy must still rest ON the floor"
        )
    }
}
