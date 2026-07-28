//
//  CharacterBody.swift
//  PetAgent
//
//  F3 · owner: 박해영 (Haeyoung Park)
//  The pet's position and facing, and the one place that pushes them onto the
//  avatar.
//
//  States previously received only `dt` and had no handle on the character at
//  all, so no amount of frame ticking could have moved anything. They now act
//  on this; it forwards to AvatarPlayable so no state ever talks to the
//  renderer directly (F2's rule that the FSM must not know the avatar type).
//
//  Coordinates are GlobalScreenSpace pixels: top-left origin, Y down.
//

import CoreGraphics
import Foundation

final class CharacterBody {
    /// pet-app's own default bounce intensity when manifest.bounce_intensity
    /// is absent (2026-07-29 2D switch, 02_pet-app.md F2).
    static let defaultBounceIntensity = 0.6

    private let avatar: AvatarPlayable
    private let bounceIntensity: Double

    var position: CGPoint {
        didSet { avatar.setScreenPosition(position) }
    }

    /// Writing the same facing is a no-op — the FSM sets this every frame
    /// while walking, and re-applying the transform 60 times a second is
    /// pointless work.
    var facing: AvatarFacing {
        didSet {
            guard facing != oldValue else { return }
            avatar.setFacing(facing)
        }
    }

    /// F3 ceiling-crawling (2026-07-29): true while CeilingState/ClimbToCeilingState
    /// own the character. Same no-op-on-unchanged guard as facing.
    var isUpsideDown: Bool = false {
        didSet {
            guard isUpsideDown != oldValue else { return }
            avatar.setUpsideDown(isUpsideDown)
        }
    }

    func play(clip: String, loop: Bool) {
        avatar.play(clip: clip, loop: loop)
    }

    func stop() {
        avatar.stop()
    }

    func updateBounce(clip: String, elapsed: TimeInterval) {
        avatar.updateBounce(clip: clip, elapsed: elapsed, intensity: bounceIntensity)
    }

    init(avatar: AvatarPlayable, position: CGPoint, facing: AvatarFacing = .right, bounceIntensity: Double = CharacterBody.defaultBounceIntensity) {
        self.avatar = avatar
        self.position = position
        self.facing = facing
        self.bounceIntensity = bounceIntensity
        avatar.setScreenPosition(position)
    }
}
