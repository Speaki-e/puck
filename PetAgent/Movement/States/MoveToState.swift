//
//  MoveToState.swift
//  PetAgent
//
//  F3 · owner: Haeyoung Park
//  MoveTo state's StateHandler implementation
//
//  Reuses "walk" since the manifest has no dedicated clip. Entered whenever a
//  tool/event target coordinate arrives, from any current state (transition
//  table's "any state" row).
//  TODO(P7/P8): constant-velocity movement toward a target + arrival radius,
//  then transition to Point or Idle depending on why it was triggered.

final class MoveToState: StateHandler {
    let name = "MoveTo"
    let clipKey = "walk"
    let loopsClip = true
}
