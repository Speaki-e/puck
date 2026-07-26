//
//  PointState.swift
//  PetAgent
//
//  F3 · owner: Haeyoung Park
//  Point state's StateHandler implementation
//
//  TODO(P8): loop the point clip + point SFX; release after ~8s or once a
//  click on the target is detected (F10 PointingController).

final class PointState: StateHandler {
    let name = "Point"
    let clipKey = "point"
    let loopsClip = true
}
