//
//  USDZAvatar.swift
//  PetAgent
//
//  F2 · owner: Sangwoo Kang
//  First-pass implementation: RealityKit Entity.load + playAnimation crossfade
//
//  One usdz per clip (see docs/avatar-spec.md for why) — resolvedClipName
//  gives a file stem and this loads {avatarDirectory}/{stem}.usdz.
//
//  Only the clip named by `meshClip` needs to carry the skinned mesh; every
//  other file may be an animation-only export sharing the same skeleton,
//  which is what Mixamo produces when you download a clip "without skin".
//  Those files have no geometry at all, so swapping the displayed entity per
//  clip made the pet vanish the moment it walked. One mesh stays parented for
//  the whole session and clips only supply the animation played on it — which
//  also lets playAnimation crossfade instead of popping, and keeps a ten-clip
//  package near 3MB instead of shipping the same mesh ten times.

import RealityKit
import CoreGraphics
import Foundation
import simd

final class USDZAvatar: AvatarPlayable {
    private let avatarDirectory: URL
    private let loadResult: AvatarLoadResult
    private var screenSpaceMapper: ScreenSpaceMapper
    private let rootEntity: Entity
    private var loadedEntities: [String: Entity] = [:]
    /// The one entity that is actually rendered.
    private var meshEntity: Entity?

    init(avatarDirectory: URL, loadResult: AvatarLoadResult, parent: Entity, screenSpaceMapper: ScreenSpaceMapper) {
        self.avatarDirectory = avatarDirectory
        self.loadResult = loadResult
        self.screenSpaceMapper = screenSpaceMapper
        rootEntity = Entity()
        // manifest.scale compensates for source meshes not natively 1 unit
        // tall (docs/avatar-spec.md's "scale gotcha") -- without this, a
        // Mixamo-style rig authored in cm renders ~100x too large.
        let scale = Float(loadResult.manifest.scale)
        rootEntity.scale = SIMD3(repeating: scale)
        parent.addChild(rootEntity)

        // The mesh is loaded once and stays for the session; clips only drive
        // the animation played on it.
        if let meshClipName = AvatarLoader.resolvedClipName(for: Self.meshClip, in: loadResult) {
            let entity = loadedEntity(named: meshClipName)
            rootEntity.addChild(entity)
            meshEntity = entity
        }
    }

    /// Which clip's file carries the skinned mesh. idle is required by the
    /// manifest schema, so it is the one file guaranteed to be present.
    static let meshClip = "idle"

    func play(clip: String, loop: Bool) {
        guard let target = meshEntity else { return }
        guard let fileName = AvatarLoader.resolvedClipName(for: clip, in: loadResult) else { return }

        guard let animation = loadedEntity(named: fileName).availableAnimations.first else {
            // An animation-less file leaves the current clip running rather
            // than freezing the pet mid-pose.
            AppLogger.shared.log(.warning, "Avatar clip '\(clip)' (\(fileName).usdz) contains no animation")
            return
        }
        let playback = loop ? animation.repeat() : animation
        target.playAnimation(playback, transitionDuration: 0.2, startsPaused: false)
    }

    func stop() {
        meshEntity?.stopAllAnimations()
    }

    func setScreenPosition(_ position: CGPoint) {
        rootEntity.position = screenSpaceMapper.worldPosition(forScreenPoint: position)
    }

    func setFacing(_ facing: AvatarFacing) {
        rootEntity.transform.rotation = facing == .left
            ? simd_quatf(angle: .pi, axis: [0, 1, 0])
            : simd_quatf(angle: 0, axis: [0, 1, 0])
    }

    /// OverlayWindowController tears down and recreates its window+PetARView
    /// on every real display change, orphaning whatever the avatar was
    /// parented to at setup time. Callers must re-parent (to the rebuilt
    /// PetARView's contentAnchor) and supply a mapper sized to the new
    /// window whenever OverlayWindowController.onWindowsRebuilt fires.
    func reparent(to newParent: Entity, screenSpaceMapper: ScreenSpaceMapper) {
        rootEntity.removeFromParent()
        newParent.addChild(rootEntity)
        self.screenSpaceMapper = screenSpaceMapper
    }

    /// Only caches on a successful load -- caching a failure's placeholder
    /// Entity would make a transient load error (e.g. file briefly locked
    /// during an avatar import) permanent for the rest of the process, with
    /// no retry and nothing ever surfaced.
    private func loadedEntity(named fileName: String) -> Entity {
        if let cached = loadedEntities[fileName] {
            return cached
        }
        let url = avatarDirectory.appendingPathComponent("\(fileName).usdz")
        do {
            let entity = try Entity.load(contentsOf: url)
            loadedEntities[fileName] = entity
            return entity
        } catch {
            AppLogger.shared.log(.error, "Failed to load avatar clip at \(url.path): \(error)")
            return Entity()
        }
    }
}
