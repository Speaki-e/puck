//
//  AppAppearanceTests.swift
//  Puck
//
//  Shared test · owner: 박해영 (Haeyoung Park)
//  An explicit in-app appearance
//  override (Settings' General tab) rather than only ever following the
//  system appearance.
//

import XCTest
import SwiftUI
@testable import Puck

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

    // ClientWindowStore.appearance (PuckClient,
    // a separate process from Puck's own SettingsStore) never actually
    // received the Settings picker's value, so it stayed permanently at
    // .system regardless of what was picked. defaultsKey/resolved(...) let
    // PuckClient read Puck's UserDefaults domain directly instead.
    func test_defaultsKey_matchesSettingsStoresPersistedKey() {
        XCTAssertEqual(AppAppearance.defaultsKey, "Puck.appearance")
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
