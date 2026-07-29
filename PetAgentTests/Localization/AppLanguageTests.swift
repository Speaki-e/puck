//
//  AppLanguageTests.swift
//  PetAgent
//
//  Shared test · owner: 박해영 (Haeyoung Park)
//  byeolki: "한국어 언어모드도 만들어주고" -- an in-app language mode,
//  defaulting to Korean on a Korean system locale.
//

import XCTest
@testable import PetAgent

final class AppLanguageTests: XCTestCase {
    func test_systemDefault_koreanLanguageCode_returnsKorean() {
        XCTAssertEqual(AppLanguage.systemDefault(languageCode: "ko"), .korean)
    }

    func test_systemDefault_koreanRegionVariant_returnsKorean() {
        XCTAssertEqual(AppLanguage.systemDefault(languageCode: "ko-KR"), .korean)
    }

    func test_systemDefault_isCaseInsensitive() {
        XCTAssertEqual(AppLanguage.systemDefault(languageCode: "KO"), .korean)
    }

    func test_systemDefault_otherLanguageCode_returnsEnglish() {
        XCTAssertEqual(AppLanguage.systemDefault(languageCode: "en"), .english)
        XCTAssertEqual(AppLanguage.systemDefault(languageCode: "ja"), .english)
    }

    func test_systemDefault_nilLanguageCode_returnsEnglish() {
        XCTAssertEqual(AppLanguage.systemDefault(languageCode: nil), .english)
    }

    func test_displayName_isTheLanguagesOwnName() {
        XCTAssertEqual(AppLanguage.english.displayName, "English")
        XCTAssertEqual(AppLanguage.korean.displayName, "한국어")
    }
}
