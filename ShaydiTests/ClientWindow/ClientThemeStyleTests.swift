//
//  ClientThemeStyleTests.swift
//  Shaydi
//
//  F13 test · owner: 박해영 (Haeyoung Park)
//

import XCTest
@testable import Shaydi

final class ClientThemeStyleTests: XCTestCase {
    func test_hasExactlyThreeCases() {
        XCTAssertEqual(ClientThemeStyle.allCases, [.light, .dark, .glass])
    }

    func test_light_isLightColorScheme() {
        XCTAssertEqual(ClientThemeStyle.light.colorScheme, .light)
    }

    // .glass always renders dark -- translucency over a light backdrop
    // doesn't hold together, and a separate glass-on-light variant doubles
    // the design surface for no real gain (see the design spec).
    func test_dark_and_glass_areBothDarkColorScheme() {
        XCTAssertEqual(ClientThemeStyle.dark.colorScheme, .dark)
        XCTAssertEqual(ClientThemeStyle.glass.colorScheme, .dark)
    }

    func test_light_and_dark_useFlatSurfaces_glassUsesGlassSurfaces() {
        XCTAssertFalse(ClientThemeStyle.light.palette.usesGlassSurfaces)
        XCTAssertFalse(ClientThemeStyle.dark.palette.usesGlassSurfaces)
        XCTAssertTrue(ClientThemeStyle.glass.palette.usesGlassSurfaces)
    }

    func test_displayName_isDistinctForEveryCase() {
        let names = Set(ClientThemeStyle.allCases.map(\.displayName))
        XCTAssertEqual(names.count, ClientThemeStyle.allCases.count)
    }

    func test_resolved_withKnownRawValue_returnsMatchingCase() {
        XCTAssertEqual(ClientThemeStyle.resolved(fromDefaultsValue: "glass"), .glass)
    }

    func test_resolved_withNilOrUnknownRawValue_defaultsToDark() {
        XCTAssertEqual(ClientThemeStyle.resolved(fromDefaultsValue: nil), .dark)
        XCTAssertEqual(ClientThemeStyle.resolved(fromDefaultsValue: "sepia"), .dark)
    }
}
