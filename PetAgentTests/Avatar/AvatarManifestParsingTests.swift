//
//  AvatarManifestParsingTests.swift
//  PetAgent
//
//  F2 테스트 · 담당: 강상우
//  manifest.json 파싱 + 필수 클립 폴백 검증
//

import XCTest
@testable import PetAgent

final class AvatarManifestParsingTests: XCTestCase {
    // protocol/01_protocol.md 6절 예시와 동일한 구조 (PetAgent/Resources/Avatars/dummy/manifest.json 사본)
    private let dummyManifestJSON = """
    {
      "schema_version": 1,
      "name": "dummy",
      "type": "usdz",
      "scale": 1.0,
      "hitbox": { "width": 120, "height": 140 },
      "clips": {
        "idle": "idle", "walk": "walk", "climb": "climb",
        "fall": "fall", "land": "land", "point": "point",
        "type": "type", "listen": "listen",
        "react_click": "react_click", "react_drag": "react_drag"
      },
      "sounds": {
        "walk": "sounds/footstep.wav",
        "point": "sounds/point.wav",
        "react_click": "sounds/boop.wav",
        "app_launch": "sounds/launch.wav",
        "task_success": "sounds/ding.wav",
        "task_fail": "sounds/buzz.wav",
        "listen_start": "sounds/listen.wav"
      }
    }
    """

    // MARK: - AvatarManifest 파싱

    func test_decodesManifest_allFields() throws {
        let manifest = try JSONDecoder().decode(AvatarManifest.self, from: Data(dummyManifestJSON.utf8))

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.name, "dummy")
        XCTAssertEqual(manifest.type, .usdz)
        XCTAssertEqual(manifest.scale, 1.0)
        XCTAssertEqual(manifest.hitbox, AvatarManifest.Hitbox(width: 120, height: 140))
        XCTAssertEqual(manifest.clips["idle"], .name("idle"))
        XCTAssertEqual(manifest.sounds["walk"], "sounds/footstep.wav")
    }

    func test_clipReference_decodesPlainStringAsName() throws {
        let ref = try JSONDecoder().decode(ClipReference.self, from: Data(#""idle""#.utf8))
        XCTAssertEqual(ref, .name("idle"))
    }

    func test_clipReference_decodesTimeRangeObject() throws {
        let json = #"{"in": 0.5, "out": 1.5}"#
        let ref = try JSONDecoder().decode(ClipReference.self, from: Data(json.utf8))
        XCTAssertEqual(ref, .timeRange(in: 0.5, out: 1.5))
    }

    // MARK: - AvatarLoader: 데이터로부터 로드 + 클립 검증

    func test_load_withAllClipsPresent_reportsNoMissingClips() throws {
        let result = try AvatarLoader.load(manifestData: Data(dummyManifestJSON.utf8))

        XCTAssertEqual(result.manifest.name, "dummy")
        XCTAssertTrue(result.missingClips.isEmpty)
    }

    func test_load_withOnlyRequiredClips_reportsMissingRecommendedClips() throws {
        let json = """
        {
          "schema_version": 1, "name": "minimal", "type": "usdz", "scale": 1.0,
          "hitbox": { "width": 100, "height": 100 },
          "clips": { "idle": "idle", "walk": "walk" },
          "sounds": {}
        }
        """
        let result = try AvatarLoader.load(manifestData: Data(json.utf8))

        XCTAssertEqual(
            Set(result.missingClips),
            Set(["climb", "fall", "land", "point", "type", "listen", "react_click", "react_drag"])
        )
    }

    func test_load_withGarbageJSON_throwsManifestNotDecodable() {
        XCTAssertThrowsError(try AvatarLoader.load(manifestData: Data(#"{"not":"a manifest"}"#.utf8))) { error in
            guard case AvatarLoaderError.manifestNotDecodable = error else {
                return XCTFail("expected .manifestNotDecodable, got \(error)")
            }
        }
    }

    // MARK: - 누락 클립 -> idle 폴백

    func test_resolvedClipName_returnsRequestedClip_whenPresent() throws {
        let result = try AvatarLoader.load(manifestData: Data(dummyManifestJSON.utf8))
        XCTAssertEqual(AvatarLoader.resolvedClipName(for: "walk", in: result), "walk")
    }

    func test_resolvedClipName_fallsBackToIdle_whenClipMissing() throws {
        let json = """
        {
          "schema_version": 1, "name": "minimal", "type": "usdz", "scale": 1.0,
          "hitbox": { "width": 100, "height": 100 },
          "clips": { "idle": "idle", "walk": "walk" },
          "sounds": {}
        }
        """
        let result = try AvatarLoader.load(manifestData: Data(json.utf8))
        XCTAssertEqual(AvatarLoader.resolvedClipName(for: "climb", in: result), "idle")
    }

    func test_resolvedClipName_returnsNil_whenClipAndIdleBothMissing() throws {
        let json = """
        {
          "schema_version": 1, "name": "no-idle", "type": "usdz", "scale": 1.0,
          "hitbox": { "width": 100, "height": 100 },
          "clips": { "walk": "walk" },
          "sounds": {}
        }
        """
        let result = try AvatarLoader.load(manifestData: Data(json.utf8))
        XCTAssertNil(AvatarLoader.resolvedClipName(for: "climb", in: result))
    }

    // MARK: - 디스크에서 로드 (경로 스캔)

    func test_loadFromDirectory_readsManifestFromDisk() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try dummyManifestJSON.write(
            to: directory.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )

        let result = try AvatarLoader.load(avatarDirectory: directory)
        XCTAssertEqual(result.manifest.name, "dummy")
    }

    func test_loadFromDirectory_withoutManifest_throwsAvatarNotFound() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        XCTAssertThrowsError(try AvatarLoader.load(avatarDirectory: directory)) { error in
            guard case AvatarLoaderError.avatarNotFound = error else {
                return XCTFail("expected .avatarNotFound, got \(error)")
            }
        }
    }
}
