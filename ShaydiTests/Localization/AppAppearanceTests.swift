//
//  AppAppearanceTests.swift
//  Shaydi
//
//  Shared test · owner: 박해영 (Haeyoung Park)
//  byeolki: "화이트모드 다크모드 추가하고" -- an explicit in-app appearance
//  override, same shape as AppLanguage (a user setting, not a passive
//  follow-the-system default).
//

import XCTest
import SwiftUI
@testable import Shaydi

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

    // byeolki, 2026-08-01: "테마가 내가 아마 다크모드일텐데, 시스템모드랑
    // 다크모드랑 생긴게 다른데?" -- ClientWindowStore.appearance (ShaydiAgent,
    // a separate process from Shaydi's own SettingsStore) never actually
    // received the Settings picker's value, so it stayed permanently at
    // .system regardless of what was picked. defaultsKey/resolved(...) let
    // ShaydiAgent read Shaydi's UserDefaults domain directly instead.
    func test_defaultsKey_matchesSettingsStoresPersistedKey() {
        XCTAssertEqual(AppAppearance.defaultsKey, "Shaydi.appearance")
    }

    func test_resolved_fromNilValue_isSystem() {
        XCTAssertEqual(AppAppearance.resolved(fromDefaultsValue: nil), .system)
    }

    func test_resolved_fromKnownValues_matchesTheCase() {
        XCTAssertEqual(AppAppearance.resolved(fromDefaultsValue: "light"), .light)
        XCTAssertEqual(AppAppearance.resolved(fromDefaultsValue: "dark"), .dark)
        XCTAssertEqual(AppAppearance.resolved(fromDefaultsValue: "system"), .system)
    }

    func test_resolved_fromUnrecognizedValue_fallsBackToSystem() {
        XCTAssertEqual(AppAppearance.resolved(fromDefaultsValue: "garbage"), .system)
    }

    // NSVisualEffectView materials, NSPopover's own chrome, and other
    // AppKit-native rendering follow NSApp.appearance, not SwiftUI's
    // .preferredColorScheme -- without this, forcing "Dark" only recolored
    // SwiftUI content while glass/blur backgrounds kept following whatever
    // the real system appearance happened to be.
    func test_system_hasNoNSApplicationAppearanceOverride() {
        XCTAssertNil(AppAppearance.system.nsApplicationAppearance)
    }

    func test_light_mapsToAquaNSApplicationAppearance() {
        XCTAssertEqual(AppAppearance.light.nsApplicationAppearance?.name, .aqua)
    }

    func test_dark_mapsToDarkAquaNSApplicationAppearance() {
        XCTAssertEqual(AppAppearance.dark.nsApplicationAppearance?.name, .darkAqua)
    }
}
