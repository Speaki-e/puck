//
//  AvatarLoader.swift
//  PetAgent
//
//  F2 · 담당: 강상우
//  Avatars 경로 스캔 + manifest 파싱 + 필수 클립(idle,walk) 검증
//

import Foundation

enum AvatarLoaderError: Error, Equatable {
    case avatarNotFound(name: String)
    case manifestNotDecodable(underlying: String)
}

/// manifest 로드 결과: 파싱된 manifest와, 존재하지 않아 idle로 폴백해야 하는 클립 목록.
struct AvatarLoadResult: Equatable {
    let manifest: AvatarManifest
    let missingClips: [String]
}

enum AvatarLoader {
    /// 없으면 idle로 폴백조차 불가능한, 반드시 있어야 하는 클립
    static let requiredClips = ["idle", "walk"]
    /// 없어도 idle로 폴백되지만 시작 시 경고 대상인 클립
    static let recommendedClips = [
        "climb", "fall", "land", "point", "type", "listen", "react_click", "react_drag",
    ]

    /// ~/Library/Application Support/PetAgent/Avatars/{name}/manifest.json 을 읽어 로드한다.
    static func load(avatarDirectory: URL) throws -> AvatarLoadResult {
        let manifestURL = avatarDirectory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw AvatarLoaderError.avatarNotFound(name: avatarDirectory.lastPathComponent)
        }
        return try load(manifestData: data)
    }

    /// manifest.json 바이트를 파싱하고, 필수+권장 클립 중 누락된 것을 계산한다.
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

    /// 요청한 클립이 manifest에 있으면 그 클립 이름을, 없으면 idle로 폴백한 이름을,
    /// idle조차 없으면 nil을 반환한다 (usdz/sprites의 문자열 클립 이름 기준).
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
