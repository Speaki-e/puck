//
//  ClientThemeStyleTests.swift
//  Puck
//

import XCTest
@testable import Puck

final class ClientThemeStyleTests: XCTestCase {
    func test_hasExactlyTwoCases() {
        XCTAssertEqual(ClientThemeStyle.allCases, [.light, .dark])
    }

    func test_light_isLightColorScheme() {
        XCTAssertEqual(ClientThemeStyle.light.colorScheme, .light)
    }

    func test_dark_isDarkColorScheme() {
        XCTAssertEqual(ClientThemeStyle.dark.colorScheme, .dark)
    }

    func test_displayName_isDistinctForEveryCase() {
        let names = Set(ClientThemeStyle.allCases.map(\.displayName))
        XCTAssertEqual(names.count, ClientThemeStyle.allCases.count)
    }

    func test_resolved_withKnownRawValue_returnsMatchingCase() {
        XCTAssertEqual(ClientThemeStyle.resolved(fromDefaultsValue: "light"), .light)
    }

    func test_resolved_withNilOrUnknownRawValue_defaultsToDark() {
        XCTAssertEqual(ClientThemeStyle.resolved(fromDefaultsValue: nil), .dark)
        XCTAssertEqual(ClientThemeStyle.resolved(fromDefaultsValue: "glass"), .dark)
    }

    func test_crossProcessUserInfo_roundTripsThroughResolved() {
        for style in ClientThemeStyle.allCases {
            XCTAssertEqual(ClientThemeStyle.resolved(fromCrossProcessUserInfo: style.crossProcessUserInfo), style)
        }
    }

    func test_resolved_fromMissingCrossProcessUserInfoKey_isNil() {
        XCTAssertNil(ClientThemeStyle.resolved(fromCrossProcessUserInfo: [:]))
        XCTAssertNil(ClientThemeStyle.resolved(fromCrossProcessUserInfo: nil))
    }
}
