//
//  WalkState.swift
//  PetAgent
//
//  F3 · owner: 박해영 (Haeyoung Park)
//  Walk state's StateHandler implementation.
//
//  TODO(P2): constant-velocity on-screen movement + detect touching a window's
//  left/right edge -> transition to Climb. Needs the F4 window list.

final class WalkState: StateHandler {
    let name = "Walk"
    let clipKey = "walk"
    let loopsClip = true
}
