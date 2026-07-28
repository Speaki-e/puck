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
    let spriteLayer = CALayer()
    private var loadedImages: [String: CGImage] = [:]
    private var facing: AvatarFacing = .right
    private var currentBounce = BounceTransform.identity

    init(avatarDirectory: URL, loadResult: AvatarLoadResult, parent: CALayer) {
        self.avatarDirectory = avatarDirectory
        self.loadResult = loadResult

        let hitbox = loadResult.manifest.hitbox
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
        spriteLayer.position = CGPoint(x: position.x, y: position.y - spriteLayer.bounds.height / 2)
    }

    func setFacing(_ facing: AvatarFacing) {
        guard facing != self.facing else { return }
        self.facing = facing
        applyTransform()
    }

    func updateBounce(clip: String, elapsed: TimeInterval, intensity: Double) {
        currentBounce = BouncePreset.preset(for: clip).transform(elapsed: elapsed, intensity: intensity)
        applyTransform()
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
        spriteLayer.setAffineTransform(
            CGAffineTransform(scaleX: CGFloat(currentBounce.scaleX) * flipX, y: CGFloat(currentBounce.scaleY))
        )
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
