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

final class CharacterBody {
    private let avatar: AvatarPlayable

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

    func play(clip: String, loop: Bool) {
        avatar.play(clip: clip, loop: loop)
    }

    func stop() {
        avatar.stop()
    }

    init(avatar: AvatarPlayable, position: CGPoint, facing: AvatarFacing = .right) {
        self.avatar = avatar
        self.position = position
        self.facing = facing
        avatar.setScreenPosition(position)
    }
}
