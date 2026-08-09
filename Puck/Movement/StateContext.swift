//
//  StateContext.swift
//  Puck
//
//  F3 · owner: 박해영 (Haeyoung Park)
//  What a state can see and do during one frame.
//
//  States used to receive nothing but `dt`, so they could neither move the
//  character nor hand control to another state — the transition table in
//  plan/02_pet-app.md section 3 had no way to express itself in code. This
//  passes the character and the world it moves through, plus the one way a
//  state asks to be replaced.
//
//  All coordinates are GlobalScreenSpace pixels: top-left origin, Y down.
//

import CoreGraphics

struct StateContext {
    /// Position and facing, already wired to the avatar.
    let body: CharacterBody

    /// The area the pet may roam, normally the union of every display.
    let roamableArea: CGRect

    /// The rendered avatar's current height (manifest hitbox * scale). F3
    /// ceiling-crawling (2026-07-29): ClimbToCeilingState needs this to climb
    /// to where the character's HEAD reaches the ceiling, not its feet --
    /// climbing feet-to-roamableArea.minY while still right-side-up (body
    /// extending upward from the feet) pushes the head off the top of the
    /// screen before "arrival," since there is no room above the literal
    /// screen edge the way there is above a window's top edge.
    let avatarHeight: CGFloat

    /// The pet's visible outline relative to its ground point (see
    /// AvatarPlayable.visualBounds). States clamp and bounce against this
    /// rather than the bare position, so the pet stops when its artwork meets
    /// a screen edge instead of when its centre does — byeolki: "이 펫 에셋의
    /// 태두리를 사각형으로 정확히 잡고 그 태두리 기반으로 화면경계에서 튕기게"
    /// (2026-07-29).
    let visualBounds: CGRect

    /// px/sec for Walk/Climb/WalkOnTop/MoveTo/Ceiling -- MovementSolver.walkSpeed
    /// scaled by Settings' movement-speed slider (byeolki's request, 2026-07-29).
    let walkSpeed: CGFloat

    /// Layer-0 windows in front-to-back Z order, already converted into the
    /// pet's coordinate space (F4 reports global Quartz frames; AppDelegate
    /// rebases them onto the overlay window before they get here).
    let windows: [WindowInfo]

    /// The surface the pet would land on if it fell straight down from `point`
    /// — a window top edge (F4) or the bottom of the screen. Injected as a
    /// closure so states stay independent of WindowListWatcher.
    let landingY: (CGPoint) -> CGFloat

    /// Asks the FSM to enter another state after this frame. Deferred rather
    /// than immediate so a state never mutates the controller mid-update.
    let requestTransition: (StateKind) -> Void
}
