//
//  SpriteAvatar.swift
//  PetAgent
//
//  F2 · owner: 박해영 (Haeyoung Park)
//  2026-07-29 2D switch: primary AvatarPlayable implementation. Loads one PNG
//  per clip (same file-stem manifest convention usdz used) and shows it on a
//  CALayer parented into SpriteLayerView's contentLayer.
//
//  No mesh/animation to manage -- "playing a clip" is just swapping which
//  cached CGImage the layer shows. Whatever motion the pet has beyond a
//  static image comes from updateBounce (BouncePreset), not from this file.
//

import CoreGraphics
import Foundation
import QuartzCore

final class SpriteAvatar: AvatarPlayable {
    private let avatarDirectory: URL
    private let loadResult: AvatarLoadResult
    /// Unscaled manifest.hitbox -- updateScale recomputes bounds from this
    /// every time rather than the layer's current (already-scaled) bounds,
    /// so repeated Settings slider changes don't compound.
    private let hitbox: AvatarManifest.Hitbox
    let spriteLayer = CALayer()
    private var loadedImages: [String: CGImage] = [:]
    private var facing: AvatarFacing = .right
    private var currentBounce = BounceTransform.identity
    private var isUpsideDown = false
    /// Derived from the clip name passed to updateBounce, not a separate
    /// AvatarPlayable method -- see updateBounce's doc comment.
    private var isClimbing = false
    /// The last logical position passed to setScreenPosition, so
    /// setUpsideDown can immediately recompute the rendered offset for it --
    /// see setUpsideDown's doc comment.
    private var lastPosition: CGPoint = .zero

    init(avatarDirectory: URL, loadResult: AvatarLoadResult, parent: CALayer) {
        self.avatarDirectory = avatarDirectory
        self.loadResult = loadResult
        self.hitbox = loadResult.manifest.hitbox

        let scale = loadResult.manifest.scale
        spriteLayer.bounds = CGRect(x: 0, y: 0, width: hitbox.width * scale, height: hitbox.height * scale)
        spriteLayer.contentsGravity = .resizeAspect
        parent.addSublayer(spriteLayer)
    }

    func play(clip: String, loop: Bool) {
        guard let fileName = AvatarLoader.resolvedClipName(for: clip, in: loadResult) else { return }
        // A load failure (missing/corrupt file) leaves whatever was already
        // showing rather than blanking the pet -- same "don't strand the
        // caller with nothing" reasoning USDZAvatar's animation-less-file path uses.
        guard let image = loadedImage(named: fileName) else { return }
        spriteLayer.contents = image
    }

    func stop() {
        // Nothing to stop -- a static image has no playback state of its own.
    }

    func setScreenPosition(_ position: CGPoint) {
        // SpriteLayerView is isFlipped (top-left origin, Y down), the same
        // convention GlobalScreenSpace/StateContext already use -- unlike
        // USDZAvatar/ScreenSpaceMapper, no world<->screen conversion needed.
        //
        // `position` is the character's ground/feet point -- the one
        // convention every other piece of the FSM already assumes (WalkState's
        // targets sit at roamableArea.maxY, LandingSurfaceResolver returns a
        // surface's top edge, USDZAvatar's rig has its root bone at the feet).
        // CALayer's own `position` is its *center*, so without this offset the
        // sprite floats half its height above wherever the FSM thinks it's
        // standing -- visible as the pet hanging in empty space instead of
        // standing on the Dock/window edge it just "landed" on.
        //
        // CeilingState instead passes roamableArea.minY (the ceiling line) as
        // an attachment point the character hangs FROM, with its body
        // extending downward into the room, not upward off the top of the
        // screen -- and since setUpsideDown's flip renders the art's feet at
        // the layer's top edge, that attachment point is the layer's top
        // edge too. Getting this offset's sign wrong doesn't just look
        // wrong, it pushes the whole sprite off the top of the screen.
        lastPosition = position
        let verticalOffset = isUpsideDown ? spriteLayer.bounds.height / 2 : -spriteLayer.bounds.height / 2
        spriteLayer.position = CGPoint(x: position.x, y: position.y + verticalOffset)
    }

    func setFacing(_ facing: AvatarFacing) {
        guard facing != self.facing else { return }
        self.facing = facing
        applyTransform()
    }

    /// F3 wall-climbing (2026-07-29, byeolki: "벽 타는 것도 사진 돌려서
    /// 올라가게 해주고"): rotates the sprite 90deg while the "climb" clip is
    /// playing -- ClimbState (a window's side) and ClimbToCeilingState (open
    /// air, toward the ceiling) both use it, so both get the rotation for
    /// free with no per-state wiring.
    func updateBounce(clip: String, elapsed: TimeInterval, intensity: Double) {
        currentBounce = BouncePreset.preset(for: clip).transform(elapsed: elapsed, intensity: intensity)
        isClimbing = clip == "climb"
        applyTransform()
    }

    /// F3 ceiling-crawling. A Y-only flip (not a 180deg rotation) so the
    /// walking-direction/facing semantics stay correct while upside-down --
    /// a full rotation would also reverse the apparent direction of motion.
    ///
    /// Also immediately re-applies setScreenPosition's offset for the cached
    /// last position, not just the transform -- otherwise there's a one-frame
    /// window (right when CeilingState hands off to FallState, which resets
    /// isUpsideDown before its own first position update runs) where the
    /// flip is already correct but the position is still offset for the OLD
    /// orientation, a visible pop that reads as a stutter/teleport.
    func setUpsideDown(_ isUpsideDown: Bool) {
        guard isUpsideDown != self.isUpsideDown else { return }
        self.isUpsideDown = isUpsideDown
        applyTransform()
        setScreenPosition(lastPosition)
    }

    /// Settings' size slider. Recomputes from the original manifest hitbox
    /// (not the layer's current bounds) so this stays idempotent under
    /// repeated calls -- the caller is expected to re-push the character's
    /// position afterward (via CharacterBody), since the ground-point offset
    /// in setScreenPosition depends on this height.
    func updateScale(_ scale: Double) {
        spriteLayer.bounds = CGRect(x: 0, y: 0, width: hitbox.width * scale, height: hitbox.height * scale)
    }

    /// Settings' emotion mapping / EventRouter-driven mood swap. Silent
    /// no-op for an unmapped key or a missing file -- same policy as clips'
    /// idle fallback and the sounds table's "unmapped = silence."
    func showEmotion(_ emotion: String) {
        guard
            case .name(let fileName)? = loadResult.manifest.emotions?[emotion],
            let image = loadedImage(named: fileName)
        else {
            return
        }
        spriteLayer.contents = image
    }

    /// OverlayWindowController tears down and recreates every window+SpriteLayerView
    /// on a real display change (monitor plug/unplug, resolution change) --
    /// callers must re-parent to the rebuilt view's contentLayer or the
    /// sprite is left attached to an orphaned layer (mirrors USDZAvatar.reparent).
    func reparent(to newParent: CALayer) {
        spriteLayer.removeFromSuperlayer()
        newParent.addSublayer(spriteLayer)
    }

    private func applyTransform() {
        let flipX: CGFloat = facing == .left ? -1 : 1
        let flipY: CGFloat = isUpsideDown ? -1 : 1
        var transform = CGAffineTransform(scaleX: CGFloat(currentBounce.scaleX) * flipX, y: CGFloat(currentBounce.scaleY) * flipY)
        if isClimbing {
            transform = transform.rotated(by: .pi / 2)
        }
        spriteLayer.setAffineTransform(transform)
    }

    /// Only caches on a successful load -- caching a failure would make a
    /// transient error (e.g. file briefly locked during an avatar import)
    /// permanent for the rest of the process, mirroring USDZAvatar's
    /// loadedEntity(named:) precedent.
    private func loadedImage(named fileName: String) -> CGImage? {
        if let cached = loadedImages[fileName] {
            return cached
        }
        let url = avatarDirectory.appendingPathComponent("\(fileName).png")
        guard
            let dataProvider = CGDataProvider(url: url as CFURL),
            let image = CGImage(
                pngDataProviderSource: dataProvider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        else {
            AppLogger.shared.log(.error, "Failed to load avatar sprite at \(url.path)")
            return nil
        }
        loadedImages[fileName] = image
        return image
    }
}
