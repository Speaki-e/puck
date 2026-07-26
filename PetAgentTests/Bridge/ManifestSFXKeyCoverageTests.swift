//
//  ManifestSFXKeyCoverageTests.swift
//  PetAgent
//
//  Socket test · owner: 박해영 (Haeyoung Park)
//  Code review finding on commit 57615a8, item #7: EventRouter.reaction(for:)
//  can produce an sfxKey ("await_approval") that has no matching entry in the
//  manifest's sounds table (protocol/01_protocol.md section 6), so the
//  "대기 SFX" the spec calls for never actually plays — F5's rule is that an
//  unmapped key is silent. Adding the key to the canonical schema is a
//  protocol-repo change requiring cross-team sign-off (프로젝트_개요.md
//  section 4), so instead of silently patching the manifest here, this test
//  tracks the gap explicitly: it fails if EventRouter starts producing an
//  SFX key that's neither in the manifest nor in this known-gap list, and it
//  fails if the known-gap list goes stale (a key gets added to the manifest
//  but nobody removes it from here).
//

import XCTest
@testable import PetAgent

final class ManifestSFXKeyCoverageTests: XCTestCase {
    private static let knownMissingSFXKeys: Set<String> = ["await_approval"]

    // Mirrors PetAgent/Resources/Avatars/dummy/manifest.json (same fixture
    // AvatarManifestParsingTests.swift uses) — keep in sync if that file changes.
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

    private func loadManifestSoundsKeys() throws -> Set<String> {
        let manifest = try JSONDecoder().decode(AvatarManifest.self, from: Data(dummyManifestJSON.utf8))
        return Set(manifest.sounds.keys)
    }

    private func allEventRouterSFXKeys() -> Set<String> {
        let events: [BridgeEvent] = [
            .agentThinking,
            .toolCall(tool: "code_editor", detail: nil),
            .toolCall(tool: "run_shell", detail: nil),
            .toolResult(ok: true),
            .toolResult(ok: false),
            .awaitApproval(summary: ""),
            .agentDone(ok: true, summary: ""),
            .agentDone(ok: false, summary: ""),
        ]
        return Set(events.compactMap { EventRouter.reaction(for: $0).sfxKey })
    }

    func test_everyEventRouterSFXKey_isInManifestOrAKnownTrackedGap() throws {
        let manifestKeys = try loadManifestSoundsKeys()
        let codeKeys = allEventRouterSFXKeys()

        let unexplainedGaps = codeKeys.subtracting(manifestKeys).subtracting(Self.knownMissingSFXKeys)
        XCTAssertTrue(
            unexplainedGaps.isEmpty,
            "SFX key(s) \(unexplainedGaps) are used by EventRouter but missing from both the manifest "
                + "and knownMissingSFXKeys — add them to the manifest or document them as a tracked gap."
        )
    }

    func test_knownMissingSFXKeys_doesNotGoStale() throws {
        let manifestKeys = try loadManifestSoundsKeys()

        let staleEntries = Self.knownMissingSFXKeys.intersection(manifestKeys)
        XCTAssertTrue(
            staleEntries.isEmpty,
            "\(staleEntries) are now present in the manifest — remove from knownMissingSFXKeys."
        )
    }
}
