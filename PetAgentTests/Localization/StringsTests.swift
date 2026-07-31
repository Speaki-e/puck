//
//  StringsTests.swift
//  PetAgent
//
//  Shared test · owner: 박해영 (Haeyoung Park)
//

import XCTest
@testable import PetAgent

final class StringsTests: XCTestCase {
    /// The one thing that would actually break the Korean language mode
    /// silently: a key added for English but forgotten for Korean, falling
    /// back to the raw key name on screen.
    func test_everyKey_hasANonEmptyStringForEveryLanguage() {
        for key in L10nKey.allCases {
            for language in AppLanguage.allCases {
                let value = Strings.text(key, language)
                XCTAssertFalse(value.isEmpty, "\(key) is missing a string for \(language)")
                XCTAssertNotEqual(value, key.rawValue, "\(key) falls back to its raw key name for \(language)")
            }
        }
    }

    func test_englishAndKorean_areActuallyDifferentText() {
        // Guards against copy-pasting the English string into the Korean
        // slot and calling it done.
        for key in L10nKey.allCases {
            XCTAssertNotEqual(
                Strings.text(key, .english),
                Strings.text(key, .korean),
                "\(key) has identical English and Korean text"
            )
        }
    }

    func test_text_returnsTheExpectedStringForAKnownKey() {
        XCTAssertEqual(Strings.text(.menuQuit, .english), "Quit PetAgent")
        XCTAssertEqual(Strings.text(.menuQuit, .korean), "PetAgent 종료")
    }
}
