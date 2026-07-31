//
//  AppIdentityTests.swift
//  Shaydi
//
//  Shared test · owner: 박해영 (Haeyoung Park)
//  A regression guard for exactly the kind of drift a rename risks: if
//  project.yml's bundle id and AppIdentity.swift's constant ever disagree,
//  CompanionAppLauncher's cross-process lookups fail silently at runtime,
//  with nothing to point at why. This test bundle runs hosted inside
//  Shaydi.app, so Bundle.main really is Shaydi's own bundle here.
//

import XCTest
@testable import Shaydi

final class AppIdentityTests: XCTestCase {
    func test_shaydiBundleID_matchesTheRunningBundle() {
        XCTAssertEqual(AppIdentity.shaydiBundleID, Bundle.main.bundleIdentifier)
    }
}
