//
//  AvatarLoader.swift
//  PetAgent
//
//  F2 · owner: 강상우 (Sangwoo Kang)
//  Scans the Avatars directory + parses the manifest + validates required
//  clips (idle, walk).
//

import Foundation

enum AvatarLoaderError: Error, Equatable {
    case avatarNotFound(name: String)
    case manifestNotDecodable(underlying: String)
}

/// Result of a manifest load: the parsed manifest, plus the clips that are
/// missing and must fall back to idle.
struct AvatarLoadResult: Equatable {
    let manifest: AvatarManifest
    let missingClips: [String]
}

enum AvatarLoader {
    /// Clips that must exist — there's no fallback target if these are missing.
    static let requiredClips = ["idle", "walk"]
    /// Clips that fall back to idle if missing, but are still warned about at startup.
    static let recommendedClips = [
        "climb", "fall", "land", "point", "type", "listen", "react_click", "react_drag",
    ]

    /// Reads and loads ~/Library/Application Support/PetAgent/Avatars/{name}/manifest.json.
    static func load(avatarDirectory: URL) throws -> AvatarLoadResult {
        let manifestURL = avatarDirectory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw AvatarLoaderError.avatarNotFound(name: avatarDirectory.lastPathComponent)
        }
        return try load(manifestData: data)
    }

    /// Parses manifest.json bytes and computes which required/recommended clips are missing.
    static func load(manifestData: Data) throws -> AvatarLoadResult {
        let manifest: AvatarManifest
        do {
            manifest = try JSONDecoder().decode(AvatarManifest.self, from: manifestData)
        } catch {
            throw AvatarLoaderError.manifestNotDecodable(underlying: String(describing: error))
        }

        let missingClips = (requiredClips + recommendedClips).filter { manifest.clips[$0] == nil }
        return AvatarLoadResult(manifest: manifest, missingClips: missingClips)
    }

    /// Returns the requested clip's name if present in the manifest, otherwise
    /// falls back to idle's name, otherwise nil if even idle is missing
    /// (string clip names only, i.e. the usdz/sprites case).
    static func resolvedClipName(for clip: String, in result: AvatarLoadResult) -> String? {
        if case .name(let name) = result.manifest.clips[clip] {
            return name
        }
        if case .name(let name) = result.manifest.clips["idle"] {
            return name
        }
        return nil
    }
}
