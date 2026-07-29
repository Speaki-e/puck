//
//  SpriteAvatarTests.swift
//  PetAgent
//
//  F2 test · owner: 박해영 (Haeyoung Park)
//  2026-07-29 2D switch: SpriteAvatar loads PNG clips instead of usdz.
//

import XCTest
import AppKit
import QuartzCore
@testable import PetAgent

final class SpriteAvatarTests: XCTestCase {
    private var packageDirectory: URL!

    override func setUpWithError() throws {
        packageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: packageDirectory)
    }

    /// A minimal valid 4x4 PNG, distinguishable by fill color so different
    /// clips' images are provably different files.
    private func writePNG(named name: String, color: NSColor) throws {
        let size = CGSize(width: 4, height: 4)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            return XCTFail("failed to synthesize a test PNG")
        }
        try png.write(to: packageDirectory.appendingPathComponent("\(name).png"))
    }

    private func makeLoadResult(
        clips: [String: String] = ["idle": "idle"],
        emotions: [String: String] = [:]
    ) throws -> AvatarLoadResult {
        let clipsJSON = clips.map { "\"\($0.key)\": \"\($0.value)\"" }.joined(separator: ", ")
        let emotionsJSON = emotions.map { "\"\($0.key)\": \"\($0.value)\"" }.joined(separator: ", ")
        let json = """
        {
          "schema_version": 1, "name": "test", "type": "sprites", "scale": 1.0,
          "hitbox": { "width": 120, "height": 140 },
          "clips": { \(clipsJSON) },
          "emotions": { \(emotionsJSON) },
          "sounds": {}
        }
        """
        return try AvatarLoader.load(manifestData: Data(json.utf8))
    }

    // MARK: - Retina rasterization

    /// A hand-made CALayer defaults to contentsScale 1.0 regardless of the
    /// display it ends up on -- only a view's own backing layer gets the
    /// window's scale for free. Left at 1.0 on a 2x screen the sprite is
    /// rasterized at half the physical resolution and upscaled: visibly soft,
    /// and because the bitmap is aligned to the coarser 1x pixel grid, a walk
    /// that advances ~1.5pt per frame renders as stair-stepped jitter instead
    /// of smooth motion.
    func test_spriteLayer_inheritsParentContentsScale_soItRasterizesAtRetinaResolution() throws {
        try writePNG(named: "idle", color: .red)
        let parent = CALayer()
        parent.contentsScale = 2

        let avatar = SpriteAvatar(
            avatarDirectory: packageDirectory,
            loadResult: try makeLoadResult(),
            parent: parent
        )

        XCTAssertEqual(avatar.spriteLayer.contentsScale, 2)
    }

    /// OverlayWindowController rebuilds every window/view on a display change,
    /// so reparenting is exactly when the pet can move between a 1x and a 2x
    /// screen -- the scale has to follow it there.
    func test_reparent_adoptsTheNewParentsContentsScale() throws {
        try writePNG(named: "idle", color: .red)
        let onex = CALayer()
        onex.contentsScale = 1
        let avatar = SpriteAvatar(
            avatarDirectory: packageDirectory,
            loadResult: try makeLoadResult(),
            parent: onex
        )

        let retina = CALayer()
        retina.contentsScale = 2
        avatar.reparent(to: retina)

        XCTAssertEqual(avatar.spriteLayer.contentsScale, 2)
    }

    func test_play_setsLayerContentsFromThePNGFile() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let parent = CALayer()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: parent)

        avatar.play(clip: "idle", loop: true)

        XCTAssertNotNil(avatar.spriteLayer.contents)
    }

    func test_play_missingClip_fallsBackToIdlesImage() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.play(clip: "walk", loop: true) // not in the manifest's clips -- falls back to idle
        let afterFallback = avatar.spriteLayer.contents

        avatar.play(clip: "idle", loop: true)
        let afterIdle = avatar.spriteLayer.contents

        XCTAssertNotNil(afterFallback)
        // Both should be the same cached CGImage instance (idle's), not merely non-nil.
        XCTAssertTrue((afterFallback as! CGImage) === (afterIdle as! CGImage))
    }

    func test_play_withMissingFileOnDisk_doesNotCrashAndLeavesContentsUnchanged() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult(clips: ["idle": "idle", "walk": "walk"])
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.play(clip: "idle", loop: true)
        let beforeMissingPlay = avatar.spriteLayer.contents

        avatar.play(clip: "walk", loop: true) // walk.png was never written
        XCTAssertTrue((avatar.spriteLayer.contents as! CGImage) === (beforeMissingPlay as! CGImage))
    }

    /// The FSM's `position` is the character's ground/feet point everywhere
    /// else in the codebase (WalkState's targets, LandingSurfaceResolver,
    /// USDZAvatar's root-at-feet rig convention) -- CALayer's own `position`
    /// is its *center* by default, so SpriteAvatar has to convert, or the
    /// pet floats half its height above wherever the FSM thinks it's
    /// standing (this is the bug byeolki reported: the pet hanging in empty
    /// space instead of standing on the Dock).
    func test_setScreenPosition_treatsInputAsGroundPoint_notLayerCenter() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult() // hitbox height 140, scale 1.0
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.setScreenPosition(CGPoint(x: 42, y: 99))

        // Center = ground point minus half the rendered height, so the
        // sprite's bottom edge lands exactly on the ground point.
        XCTAssertEqual(avatar.spriteLayer.position, CGPoint(x: 42, y: 99 - 70))
    }

    /// Hanging from the ceiling (F3, 2026-07-29): `position` is
    /// `roamableArea.minY`, the ceiling line. The flip (setUpsideDown)
    /// makes the art's feet render at the TOP of the layer and its head at
    /// the bottom, so the layer must extend DOWNWARD from the ceiling point
    /// -- the opposite offset from the ground-standing case. Getting this
    /// wrong doesn't just look wrong, it renders the sprite entirely off the
    /// top edge of the screen (this was the actual bug: nothing visibly hung
    /// from the ceiling because the sprite was pushed off-screen).
    func test_setScreenPosition_whenUpsideDown_hangsDownwardFromTheCeilingPoint() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult() // hitbox height 140, scale 1.0
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.setUpsideDown(true)
        avatar.setScreenPosition(CGPoint(x: 42, y: 0))

        XCTAssertEqual(avatar.spriteLayer.position, CGPoint(x: 42, y: 70))
    }

    /// setUpsideDown only used to flip the transform (scaleY), never
    /// recomputing the position offset -- that happened lazily, the next
    /// time something called setScreenPosition. For one frame right as
    /// CeilingState hands off to FallState (which resets isUpsideDown before
    /// its own first position update runs), the sprite would render
    /// right-side-up but still positioned with the hanging-downward offset:
    /// a one-frame pop that reads as a stutter/teleport.
    func test_setUpsideDown_immediatelyRecomputesTheCachedPosition() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult() // hitbox height 140, scale 1.0
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.setScreenPosition(CGPoint(x: 42, y: 0))
        avatar.setUpsideDown(true)

        XCTAssertEqual(avatar.spriteLayer.position, CGPoint(x: 42, y: 70))
    }

    func test_setFacingLeft_flipsLayerHorizontally() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.setFacing(.left)

        XCTAssertEqual(avatar.spriteLayer.affineTransform().a, -1, accuracy: 0.0001)
    }

    func test_setFacingRight_isIdentityScaleX() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.setFacing(.left)
        avatar.setFacing(.right)

        XCTAssertEqual(avatar.spriteLayer.affineTransform().a, 1, accuracy: 0.0001)
    }

    func test_updateBounce_combinesWithFacing() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.setFacing(.left)
        avatar.updateBounce(clip: "land", elapsed: 0, intensity: 1.0) // land at t=0 -> scaleX 1.3, scaleY 0.7

        let transform = avatar.spriteLayer.affineTransform()
        XCTAssertEqual(transform.a, -1.3, accuracy: 0.001) // 1.3 scale, flipped negative
        XCTAssertEqual(transform.d, 0.7, accuracy: 0.001)
    }

    // MARK: - Climbing rotation (F3 wall-climbing, 2026-07-29)

    /// byeolki: "벽 타는 것도 사진 돌려서 올라가게 해주고" -- climbing (both
    /// ClimbState and ClimbToCeilingState share the "climb" clip) rotates
    /// the sprite 90 degrees, the same way isUpsideDown flips it for the
    /// ceiling. Derived from the clip name already passed into updateBounce
    /// every frame -- no new AvatarPlayable method needed.
    func test_updateBounce_withClimbClip_rotatesTheSpriteNinetyDegrees() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.updateBounce(clip: "climb", elapsed: 0, intensity: 1.0)

        let transform = avatar.spriteLayer.affineTransform()
        XCTAssertEqual(transform.a, 0, accuracy: 0.001)
        XCTAssertEqual(abs(transform.b), 1, accuracy: 0.001)
    }

    func test_updateBounce_withNonClimbClip_doesNotRotate() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.updateBounce(clip: "idle", elapsed: 0, intensity: 1.0)

        let transform = avatar.spriteLayer.affineTransform()
        XCTAssertEqual(transform.b, 0, accuracy: 0.001)
    }

    func test_updateBounce_leavingClimbClip_resetsRotation() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.updateBounce(clip: "climb", elapsed: 0, intensity: 1.0)
        avatar.updateBounce(clip: "walk", elapsed: 0, intensity: 1.0)

        let transform = avatar.spriteLayer.affineTransform()
        XCTAssertEqual(transform.b, 0, accuracy: 0.001)
    }

    func test_init_sizesLayerToHitboxTimesScale() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        XCTAssertEqual(avatar.spriteLayer.bounds.size, CGSize(width: 120, height: 140))
    }

    // MARK: - updateScale (Settings size slider, 2026-07-29)

    func test_updateScale_resizesTheLayerFromTheOriginalHitbox() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult() // hitbox 120x140
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.updateScale(0.5)

        XCTAssertEqual(avatar.spriteLayer.bounds.size, CGSize(width: 60, height: 70))
    }

    func test_updateScale_appliedTwice_isNotCumulative() throws {
        // Each call recomputes from the original hitbox, not the layer's
        // current (already-scaled) bounds -- otherwise repeated slider
        // changes would compound instead of just reflecting the latest value.
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.updateScale(0.5)
        avatar.updateScale(2.0)

        XCTAssertEqual(avatar.spriteLayer.bounds.size, CGSize(width: 240, height: 280))
    }

    // MARK: - showEmotion (Settings emotion mapping, 2026-07-29)

    func test_showEmotion_setsLayerContentsFromTheMappedPNG() throws {
        try writePNG(named: "idle", color: .red)
        try writePNG(named: "happy", color: .green)
        let loadResult = try makeLoadResult(emotions: ["happy": "happy"])
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())
        avatar.play(clip: "idle", loop: true)
        let idleContents = avatar.spriteLayer.contents

        avatar.showEmotion("happy")

        XCTAssertFalse((avatar.spriteLayer.contents as! CGImage) === (idleContents as! CGImage))
    }

    func test_showEmotion_unmappedKey_isSilentNoOp() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult() // no emotions at all
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())
        avatar.play(clip: "idle", loop: true)
        let idleContents = avatar.spriteLayer.contents

        avatar.showEmotion("thinking") // not in the (empty) emotions table

        XCTAssertTrue((avatar.spriteLayer.contents as! CGImage) === (idleContents as! CGImage))
    }

    // MARK: - setUpsideDown (F3 ceiling-crawling, 2026-07-29)

    /// A Y-only flip, not a 180deg rotation -- rotation would also reverse
    /// the apparent left/right walking direction while upside-down.
    func test_setUpsideDownTrue_flipsLayerVertically() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.setUpsideDown(true)

        let transform = avatar.spriteLayer.affineTransform()
        XCTAssertEqual(transform.a, 1, accuracy: 0.0001)
        XCTAssertEqual(transform.d, -1, accuracy: 0.0001)
    }

    func test_setUpsideDownFalse_afterTrue_restoresIdentity() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.setUpsideDown(true)
        avatar.setUpsideDown(false)

        let transform = avatar.spriteLayer.affineTransform()
        XCTAssertEqual(transform.d, 1, accuracy: 0.0001)
    }

    func test_setUpsideDown_combinesWithFacingLeft() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.setFacing(.left)
        avatar.setUpsideDown(true)

        let transform = avatar.spriteLayer.affineTransform()
        XCTAssertEqual(transform.a, -1, accuracy: 0.0001)
        XCTAssertEqual(transform.d, -1, accuracy: 0.0001)
    }

    /// OverlayWindowController tears down and recreates every window+SpriteLayerView
    /// on a real display change -- mirrors USDZAvatar.reparent's precedent.
    func test_reparent_movesTheSpriteLayerToTheNewParent() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let oldParent = CALayer()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: oldParent)
        XCTAssertTrue(oldParent.sublayers?.contains(avatar.spriteLayer) ?? false)

        let newParent = CALayer()
        avatar.reparent(to: newParent)

        XCTAssertFalse(oldParent.sublayers?.contains(avatar.spriteLayer) ?? false)
        XCTAssertTrue(newParent.sublayers?.contains(avatar.spriteLayer) ?? false)
    }
}
