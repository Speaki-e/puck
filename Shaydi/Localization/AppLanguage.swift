//
//  AppLanguage.swift
//  Shaydi
//
//  Shared · owner: 박해영 (Haeyoung Park)
//  In-app language mode -- byeolki: "한국어 언어모드도 만들어주고". A
//  user-facing setting (Settings' General tab), not a switch on the real
//  system locale/Bundle localization, so it can be toggled without quitting
//  and tested independent of the machine running the tests.
//

import Foundation

enum AppLanguage: String, Equatable, CaseIterable {
    case english
    case korean

    /// Shown in its own language, not translated -- a Korean speaker looking
    /// for "한국어" in a picker shouldn't have to recognize "Korean" first.
    var displayName: String {
        switch self {
        case .english: return "English"
        case .korean: return "한국어"
        }
    }

    /// Pure: given a BCP-47-ish language code (e.g. "ko", "ko-KR", "en"),
    /// which language to default to. Kept separate from `systemDefault()`
    /// (which reads the real `Locale.current`) so the mapping itself is
    /// testable independent of the machine running the tests.
    static func systemDefault(languageCode: String?) -> AppLanguage {
        languageCode?.lowercased().hasPrefix("ko") == true ? .korean : .english
    }

    static func systemDefault() -> AppLanguage {
        systemDefault(languageCode: Locale.current.language.languageCode?.identifier)
    }
}
