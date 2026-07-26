//
//  AvatarManifest.swift
//  PetAgent
//
//  F2 · 담당: 강상우
//  manifest.json Codable 모델 (protocol 저장소 6절 스키마 미러)
//

/// clips 테이블의 값. usdz/sprites 타입은 클립 이름 문자열, video 타입은 {"in":초,"out":초} 구간이다.
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
