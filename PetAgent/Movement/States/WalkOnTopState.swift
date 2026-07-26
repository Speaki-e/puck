//
//  WalkOnTopState.swift
//  PetAgent
//
//  F3 · owner: 박해영 (Haeyoung Park)
//  WalkOnTop state's StateHandler implementation.
//
//  Reuses "walk" since the manifest has no dedicated clip (walking on top of
//  a window still looks like the walk animation).
//  TODO(P3): detect the supporting window disappearing/minimizing ->
//  transition to Fall. Needs the F4 window list.

final class WalkOnTopState: StateHandler {
    let name = "WalkOnTop"
    let clipKey = "walk"
    let loopsClip = true
}
