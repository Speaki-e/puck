//
//  TankBackgroundTests.swift
//  Puck
//
//  The tank's backdrop is pure rendering except for one decision: turning a
//  stored string back into a theme. That is the part a bad stored value can
//  break, so it is the part with a test.
//

import XCTest
@testable import Puck

final class TankBackgroundTests: XCTestCase {
    func test_everyThemeSurvivesTheRoundTripThroughItsStoredValue() {
        for theme in TankBackground.allCases {
            XCTAssertEqual(TankBackground(rawValue: theme.rawValue), theme)
        }
    }

    /// A key written by a newer version, or edited by hand. Falling back beats
    /// the tank refusing to draw.
    func test_anUnknownStoredValue_fallsBackToPlain() {
        XCTAssertEqual(TankBackground(rawValue: "aquarium") ?? .plain, .plain)
        XCTAssertEqual(TankBackground(rawValue: "") ?? .plain, .plain)
    }

    /// The context menu lists `allCases` in order, and `plain` is the way back
    /// to the tank the user started with -- it belongs first, not buried.
    func test_plainIsTheFirstOptionOffered() {
        XCTAssertEqual(TankBackground.allCases.first, .plain)
    }

    func test_everyThemeHasAName() {
        for theme in TankBackground.allCases {
            XCTAssertFalse(theme.name.isEmpty, "\(theme.rawValue) has no localized name")
        }
    }
}
