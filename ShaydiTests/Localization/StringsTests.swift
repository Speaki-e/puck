//
//  StringsTests.swift
//  Shaydi
//
//  Shared test · owner: 박해영 (Haeyoung Park)
//

import XCTest
@testable import Shaydi

final class StringsTests: XCTestCase {
    /// The one thing that would break the UI silently: a key with no
    /// string, falling back to the raw key name on screen.
    func test_everyKey_hasANonEmptyString() {
        for key in L10nKey.allCases {
            let value = Strings.text(key)
            XCTAssertFalse(value.isEmpty, "\(key) is missing a string")
            XCTAssertNotEqual(value, key.rawValue, "\(key) falls back to its raw key name")
        }
    }

    func test_text_returnsTheExpectedStringForAKnownKey() {
        XCTAssertEqual(Strings.text(.menuQuit), "Shaydi 종료")
    }
}
