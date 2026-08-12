//
//  AppDelegate+Wander.swift
//  Puck
//
//  F3 · owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Picks wander destinations for IdleState's scheduler -- roam points,
//  climbable windows, and toy interest.
//

import CoreGraphics
import Foundation

extension AppDelegate {
    // MARK: - Wander (F3)

    /// IdleState computes a wander outcome and previously had nowhere to send
    /// it — `wanderDelegate` was never assigned, so the scheduler fired into
    /// the void. Picking the destination needs the roamable area (and, later,
    /// the window list), which is bootstrap knowledge, not state knowledge.
    func idleStateDidRequestWander(_ outcome: WanderScheduler.Outcome) {
        guard let controller = characterController else { return }
        switch outcome {
        case .walkToRandomPoint:
            walkState.target = Self.randomRoamPoint(in: controller.roamableArea)
            controller.transition(to: .walk)
        case .climbNearestWindow:
            // Walk to the nearest climbable window's side; WalkState's own
            // blockingWindow check takes it from there and hands off to Climb.
            // Falls back to roaming when there's nothing to climb, rather
            // than standing still.
            walkState.target = characterBody.flatMap { body in
                WindowSupport.nearestClimbTarget(
                    from: body.position,
                    in: overlayLocalWindows(excluding: nil),
                    roamableTop: controller.roamableArea.minY,
                    avatarHeight: avatarHitboxSize.height
                )
            } ?? Self.randomRoamPoint(in: controller.roamableArea)
            controller.transition(to: .walk)
        case .climbToCeiling:
            // ClimbToCeilingState falls back to .fall on its own if there's no
            // wall underfoot, but that costs one visible frame of the climb
            // clip flashing before it drops -- byeolki: "이거 화면에 있는
            // 벽? 통해서만 올라갈 수 있게 해줘 그냥 아무 지형에서
            // 올라가버리냐". Checking here avoids ever entering the state
            // without a wall to begin with.
            guard let body = characterBody,
                  WindowSupport.windowBeingClimbed(at: body.position, in: overlayLocalWindows(excluding: nil)) != nil else {
                walkState.target = Self.randomRoamPoint(in: controller.roamableArea)
                controller.transition(to: .walk)
                return
            }
            controller.transition(to: .climbToCeiling)
        case .playWithToy:
            // Before this draw, play could only ever start at the moment a toy
            // LANDED -- so a toy the pet had kicked away and walked off from
            // was abandoned for good. Falls back to roaming when nothing is
            // out or nothing has settled yet, same as the climbs do.
            guard !isRestingFromToys,
                  let box = toyBox,
                  let name = ToyInterestPolicy.next(
                      from: box.candidates,
                      lastPlayed: box.lastPlayedName,
                      petPosition: characterBody?.position ?? .zero
                  )
            else {
                walkState.target = Self.randomRoamPoint(in: controller.roamableArea)
                controller.transition(to: .walk)
                return
            }
            startPlaying(with: ToyCatalogue.toy(named: name))
        case .stay:
            break
        }
    }

    /// How much of each side of the screen wander targets stay out of, as a
    /// fraction of its width. Targeting the literal edges meant a good share
    /// of wanders ended with the pet pressed into a corner, where it then sat
    /// until the next timer -- and screen-edge containment holds it there
    /// exactly, so it reads as being stuck rather than as having wandered
    /// (byeolki: "펫이 너무 구석이 박히고"). It can still be *carried* or
    /// thrown into a corner; it just won't choose one.
    static let roamEdgeMargin: CGFloat = 0.08

    private static func randomRoamPoint(in area: CGRect) -> CGPoint {
        guard area.width > 0 else { return .zero }
        let margin = area.width * roamEdgeMargin
        return CGPoint(x: CGFloat.random(in: (area.minX + margin)...(area.maxX - margin)), y: area.maxY)
    }
}
