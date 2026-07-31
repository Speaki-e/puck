//
//  CompanionAppLauncherTests.swift
//  Shaydi
//
//  Shared · owner: 박해영 (Haeyoung Park)
//

import XCTest
@testable import Shaydi

final class CompanionAppLauncherTests: XCTestCase {
    func test_launchIfNeeded_doesNothing_whenAlreadyRunning() {
        var launchedIds: [String] = []
        CompanionAppLauncher.launchIfNeeded(
            bundleIdentifier: "com.speaki-e.ShaydiAgent",
            isRunning: { _ in true },
            launch: { launchedIds.append($0) }
        )
        XCTAssertTrue(launchedIds.isEmpty)
    }

    func test_launchIfNeeded_launches_whenNotRunning() {
        var launchedIds: [String] = []
        CompanionAppLauncher.launchIfNeeded(
            bundleIdentifier: "com.speaki-e.ShaydiAgent",
            isRunning: { _ in false },
            launch: { launchedIds.append($0) }
        )
        XCTAssertEqual(launchedIds, ["com.speaki-e.ShaydiAgent"])
    }
}
