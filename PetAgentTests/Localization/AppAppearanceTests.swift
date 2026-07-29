//
//  AppAppearanceTests.swift
//  PetAgent
//
//  Shared test · owner: 박해영 (Haeyoung Park)
//  byeolki: "화이트모드 다크모드 추가하고" -- an explicit in-app appearance
//  override, same shape as AppLanguage (a user setting, not a passive
//  follow-the-system default).
//

import XCTest
import SwiftUI
@testable import PetAgent

final class AppAppearanceTests: XCTestCase {
    func test_system_hasNoColorSchemeOverride() {
        XCTAssertNil(AppAppearance.system.colorScheme)
    }

    func test_light_mapsToLightColorScheme() {
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
    }

    func test_dark_mapsToDarkColorScheme() {
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
    }
}
