//
//  LandState.swift
//  PetAgent
//
//  F3 · owner: Haeyoung Park
//  Land state's StateHandler implementation
//
//  TODO(P3): a brief landing pose, then transition to Idle.

final class LandState: StateHandler {
    let name = "Land"
    let clipKey = "land"
    let loopsClip = false
}
