//
//  AppLanguage.swift
//  Puck
//
//  The language the UI is written in, as an in-app setting rather than the
//  system locale. Same shape as ClientThemeStyle: persisted in Puck's own
//  UserDefaults domain by SettingsStore, and broadcast to PuckClient over
//  DistributedNotificationCenter so a second process picks the change up
//  immediately instead of only at its next launch.
//
//  An in-app setting because the pet talks: a user who runs macOS in English
//  may still want the pet speaking Korean, and macOS's own per-app language
//  override cannot be reached from inside the app.
//

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case korean = "ko"
    case english = "en"

    var id: String { rawValue }

    /// Each language names itself, the way system language pickers do -- a
    /// user looking for their own language should not have to read the
    /// current one first.
    var displayName: String {
        switch self {
        case .korean: return "한국어"
        case .english: return "English"
        }
    }

    /// The UserDefaults key SettingsStore persists this under, in Puck's own
    /// defaults domain.
    static let defaultsKey = "Puck.language"

    /// What an unset or unrecognized value resolves to: the system's own
    /// preferred language when that is one this app speaks, English
    /// otherwise. Same resolve-with-fallback shape as
    /// `ClientThemeStyle.resolved(fromDefaultsValue:)`, so every reader
    /// agrees on what counts as "unset."
    static func resolved(fromDefaultsValue raw: String?) -> AppLanguage {
        raw.flatMap(AppLanguage.init(rawValue:)) ?? systemDefault
    }

    /// Matched on the language subtag alone: `Locale.preferredLanguages`
    /// reports region and script too ("ko-KR", "en-US"), and this app draws
    /// no distinction between regions of the same language.
    static var systemDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? "en"
        let subtag = preferred.split(separator: "-").first.map(String.init) ?? preferred
        return AppLanguage(rawValue: subtag.lowercased()) ?? .english
    }

    /// Posted by Puck's AppDelegate whenever the setting changes, so
    /// PuckClient -- a separate process with no access to Puck's UserDefaults
    /// domain -- follows along.
    static let crossProcessChangeNotification = Notification.Name("com.speaki-e.Puck.languageChanged")

    private static let crossProcessUserInfoKey = "language"

    /// Carries the new value with the notification rather than making the
    /// receiver re-read UserDefaults: a write in one process is not
    /// guaranteed visible to another by the time a distributed notification
    /// posted right after it is delivered.
    var crossProcessUserInfo: [AnyHashable: Any] {
        [Self.crossProcessUserInfoKey: rawValue]
    }

    /// nil when the notification carried no recognizable value, so the
    /// receiver can fall back to its own read instead of treating a
    /// malformed notification as unset.
    static func resolved(fromCrossProcessUserInfo userInfo: [AnyHashable: Any]?) -> AppLanguage? {
        guard let raw = userInfo?[crossProcessUserInfoKey] as? String else { return nil }
        return resolved(fromDefaultsValue: raw)
    }
}
