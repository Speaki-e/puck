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

    private func makeLoadResult(clips: [String: String] = ["idle": "idle"]) throws -> AvatarLoadResult {
        let clipsJSON = clips.map { "\"\($0.key)\": \"\($0.value)\"" }.joined(separator: ", ")
        let json = """
        {
          "schema_version": 1, "name": "test", "type": "sprites", "scale": 1.0,
          "hitbox": { "width": 120, "height": 140 },
          "clips": { \(clipsJSON) },
          "sounds": {}
        }
        """
        return try AvatarLoader.load(manifestData: Data(json.utf8))
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

    func test_setScreenPosition_setsLayerPositionDirectly_noConversion() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        avatar.setScreenPosition(CGPoint(x: 42, y: 99))

        XCTAssertEqual(avatar.spriteLayer.position, CGPoint(x: 42, y: 99))
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

    func test_init_sizesLayerToHitboxTimesScale() throws {
        try writePNG(named: "idle", color: .red)
        let loadResult = try makeLoadResult()
        let avatar = SpriteAvatar(avatarDirectory: packageDirectory, loadResult: loadResult, parent: CALayer())

        XCTAssertEqual(avatar.spriteLayer.bounds.size, CGSize(width: 120, height: 140))
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
