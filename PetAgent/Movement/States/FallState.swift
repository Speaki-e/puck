//
//  FallState.swift
//  PetAgent
//
//  F3 · owner: 박해영 (Haeyoung Park)
//  Fall state's StateHandler implementation.
//
//  TODO(P3): apply fall acceleration + detect a landing surface (F4
//  LandingSurfaceResolver) -> transition to Land.

final class FallState: StateHandler {
    let name = "Fall"
    let clipKey = "fall"
    let loopsClip = false
}
