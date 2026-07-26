//
//  ClimbState.swift
//  PetAgent
//
//  F3 · owner: 박해영 (Haeyoung Park)
//  Climb state's StateHandler implementation.
//
//  TODO(P3): detect reaching the window's top edge -> transition to
//  WalkOnTop. Needs the F4 window list.

final class ClimbState: StateHandler {
    let name = "Climb"
    let clipKey = "climb"
    let loopsClip = true
}
