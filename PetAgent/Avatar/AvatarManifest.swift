//
//  AvatarManifest.swift
//  PetAgent
//
//  F2 · owner: 강상우 (Sangwoo Kang)
//  manifest.json Codable model (mirrors protocol repo section 6 schema).
//

/// A value in the clips table.
///
/// For `type: usdz`, `.name(String)` is the file stem of a **single-animation**
/// usdz living alongside manifest.json (e.g. "idle" -> Avatars/{name}/idle.usdz)
/// — NOT an animation name to look up inside one shared model. RealityKit
/// effectively only plays a usdz's first animation regardless of how many
/// `availableAnimations` entries it reports, so one avatar with 10 named clips
/// baked into a single usdz does not work; each clip needs its own file. See
/// pet-app/docs/avatar-spec.md for the full external-creator requirements.
///
/// `type: sprites` reuses the same file-stem convention. `type: video` uses
/// a {"in":sec,"out":sec} time range instead (`.timeRange`).
enum ClipReference: Equatable {
    case name(String)
    case timeRange(in: Double, out: Double)
}

extension ClipReference: Codable {
    private enum CodingKeys: String, CodingKey {
        case `in`, out
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let start = try? container.decode(Double.self, forKey: .in),
           let end = try? container.decode(Double.self, forKey: .out) {
            self = .timeRange(in: start, out: end)
            return
        }
        let single = try decoder.singleValueContainer()
        self = .name(try single.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .name(let name):
            var container = encoder.singleValueContainer()
            try container.encode(name)
        case .timeRange(let start, let end):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(start, forKey: .in)
            try container.encode(end, forKey: .out)
        }
    }
}

struct AvatarManifest: Equatable, Codable {
    enum AvatarType: String, Codable {
        case usdz
        case video
        case sprites
    }

    struct Hitbox: Equatable, Codable {
        let width: Double
        let height: Double
    }

    let schemaVersion: Int
    let name: String
    let type: AvatarType
    let scale: Double
    let hitbox: Hitbox
    let clips: [String: ClipReference]
    let sounds: [String: String]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case name, type, scale, hitbox, clips, sounds
    }
}
