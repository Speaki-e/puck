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

    func test_tick_hidesTheLayerAndDeactivates_onceGone() {
        let controller = BallController(parent: CALayer())
        controller.spawn(at: CGPoint(x: 200, y: 495))
        controller.tick(dt: 0.1, landingY: 500, roamableArea: roamableArea) // resting
        controller.kick(direction: .right)

        for _ in 0..<20 { // long enough to exceed BallPhysics.kickedLifetime
            controller.tick(dt: 0.1, landingY: 500, roamableArea: roamableArea)
        }

        XCTAssertTrue(controller.layer.isHidden)
        XCTAssertFalse(controller.isActive)
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
