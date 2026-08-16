//
//  AppDelegate+Wander.swift
//  Puck
//
//  F3 · owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Picks wander destinations for IdleState's scheduler -- roam points,
//  climbable windows, and toy interest.
//

import AppKit
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
                let windows = overlayLocalWindows(excluding: nil)
                return WindowSupport.nearestClimbTarget(
                    from: body.position,
                    in: windows,
                    roamableTop: controller.roamableArea.minY,
                    avatarHeight: avatarHitboxSize.height,
                    excluding: unclimbableWindowIDs(in: windows)
                )
            } ?? Self.randomRoamPoint(in: controller.roamableArea)
            controller.transition(to: .walk)
        case .climbToCeiling:
            // ClimbToCeilingState falls back to .fall on its own if there's no
            // wall underfoot, but that costs one visible frame of the climb
            // clip flashing before it drops -- climbing should only ever
            // happen against an actual on-screen wall, never arbitrary
            // terrain. Checking here avoids ever entering the state
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

    /// Settings' "포커스된 창 위로는 올라가지 않기" toggle, resolved against the
    /// window list the pet is currently walking through. Empty while the
    /// toggle is off, so the pet climbs whatever it reaches.
    ///
    /// The reader the setting never had: `avoidClimbingFocusedWindow` was
    /// written by the Settings panel and consulted by nothing, so the toggle
    /// changed nothing at all. Same shape as `autoMuteOnFocus`'s reader in
    /// AppDelegate+OverlayAvatar -- read fresh at the moment the decision is
    /// made rather than cached, since the panel writes it while the pet runs.
    func unclimbableWindowIDs(in windows: [WindowInfo]) -> Set<CGWindowID> {
        guard settingsStore.avoidClimbingFocusedWindow else { return [] }
        let focusedPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let focused = WindowSupport.focusedWindow(ownedBy: focusedPID, in: windows) else { return [] }
        return [focused.windowID]
    }

    /// How much of each side of the screen wander targets stay out of, as a
    /// fraction of its width. Targeting the literal edges meant a good share
    /// of wanders ended with the pet pressed into a corner, where it then sat
    /// until the next timer -- and screen-edge containment holds it there
    /// exactly, so it reads as being stuck rather than as having wandered.
    /// It can still be *carried* or thrown into a corner; it just won't
    /// choose one.
    static let roamEdgeMargin: CGFloat = 0.08

    private static func randomRoamPoint(in area: CGRect) -> CGPoint {
        guard area.width > 0 else { return .zero }
        let margin = area.width * roamEdgeMargin
        return CGPoint(x: CGFloat.random(in: (area.minX + margin)...(area.maxX - margin)), y: area.maxY)
    }
}
