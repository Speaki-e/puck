//
//  SpinState.swift
//  PetAgent
//
//  F3 · owner: 박해영 (Haeyoung Park)
//  The happy flips the pet does after being petted (byeolki: "쓰담쓰담 끝나면
//  일정 시간동안 빙글 빙글 돌기" → "회전이 아니라 뒤집는거를 원함",
//  2026-07-29). It turns about its own vertical axis, like a sheet of paper
//  being turned over repeatedly -- not an in-plane rotation, which tips the
//  pet sideways and reads as falling over.
//
//  Purely a rendering effect -- the pet stays exactly where it is -- so this
//  state owns only the timing, and the flipping itself comes from
//  BouncePreset.spin driven by the elapsed time CharacterController already
//  feeds the avatar every frame. No new per-frame plumbing.
//
//  Has its own clip key rather than reusing "pet": BouncePreset is looked up
//  BY clip key, so sharing one would mean sharing the wiggle too. The
//  manifest points "spin" at the same artwork as "pet" -- the blissed-out
//  face from being stroked is what should be whirling around.
//

import Foundation

final class SpinState: StateHandler {
    let name = "Spin"
    let clipKey = "spin"
    let loopsClip = true
    /// Petting the pet again mid-spin restarts the flipping rather than being
    /// swallowed, same reasoning as the other reaction states.
    let restartsOnReentry = true

    /// Long enough for the full turns BouncePreset.spin plays, and short
    /// enough that the pet gets back to roaming promptly.
    static let duration: TimeInterval = 2.0

    private var elapsed: TimeInterval = 0
    private var hasRequestedIdle = false

    func enter() {
        elapsed = 0
        hasRequestedIdle = false
    }

    func update(dt: TimeInterval, context: StateContext) {
        guard !hasRequestedIdle else { return }
        elapsed += dt
        guard elapsed >= Self.duration else { return }
        hasRequestedIdle = true
        context.requestTransition(.idle)
    }
}
