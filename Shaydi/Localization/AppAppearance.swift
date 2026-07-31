//
//  AppAppearance.swift
//  Shaydi
//
//  Shared · owner: 박해영 (Haeyoung Park)
//  In-app light/dark override -- byeolki: "화이트모드 다크모드 추가하고".
//  An explicit user setting (Settings' General tab, same shape as
//  AppLanguage) rather than only ever following the system appearance --
//  .system still exists as the option that does that.
//

import AppKit
import SwiftUI

enum AppAppearance: String, Equatable, CaseIterable {
    case system
    case light
    case dark

    /// Fed straight into SwiftUI's `.preferredColorScheme(_:)`. `nil` (system)
    /// leaves the system's own light/dark setting in charge.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// `.preferredColorScheme` only affects the SwiftUI view hierarchy it's
    /// applied to -- NSVisualEffectView materials, NSPopover's own chrome,
    /// and other AppKit-native rendering follow `NSApp.appearance` instead,
    /// which SwiftUI's modifier never touches. Set this alongside
    /// `.preferredColorScheme` (see AppDelegate in both targets) so glass/
    /// blur backgrounds actually match an explicit Light/Dark override
    /// instead of silently continuing to follow the real system appearance
    /// -- byeolki, 2026-08-01: "시스템모드랑 다크모드랑 생긴게 다른데?".
    var nsApplicationAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// The UserDefaults key SettingsStore persists this under, in Shaydi's
    /// own defaults domain -- exposed here (not just inside SettingsStore)
    /// because ShaydiAgent is a separate process with no access to
    /// SettingsStore itself (pulling that whole class in would also drag in
    /// HotkeyBindings and everything else it depends on). ShaydiAgent reads
    /// this key directly via `UserDefaults(suiteName: AppIdentity.shaydiBundleID)`.
    static let defaultsKey = "Shaydi.appearance"

    /// Posted (via DistributedNotificationCenter, not the ordinary
    /// NotificationCenter, since the two processes don't share one) whenever
    /// Shaydi's own appearance setting changes, so ShaydiAgent can react
    /// immediately instead of only picking up the new value at its own next
    /// launch.
    static let crossProcessChangeNotification = Notification.Name("com.speaki-e.Shaydi.appearanceChanged")

    /// Resolves a raw UserDefaults string (or nil/unrecognized) the same way
    /// everywhere this is read from -- SettingsStore's own getter and
    /// ShaydiAgent's cross-process reader both go through this, so they
    /// can't disagree on what counts as "unset."
    static func resolved(fromDefaultsValue raw: String?) -> AppAppearance {
        raw.flatMap(AppAppearance.init(rawValue:)) ?? .system
    }

    /// The key `crossProcessUserInfo` carries this value under, and
    /// `resolved(fromCrossProcessUserInfo:)` reads it back from.
    private static let crossProcessUserInfoKey = "appearance"

    /// Carries the actual new value alongside `crossProcessChangeNotification`
    /// -- byeolki, 2026-08-01: "셰이디에이전트에는 테마 변경에 대한 적용이
    /// 안됨." The live-update path used to have ShaydiAgent re-read Shaydi's
    /// UserDefaults domain in response to the notification, but
    /// `UserDefaults.set()` isn't guaranteed to be visible to a second
    /// process by the time a Darwin/distributed notification posted right
    /// afterward is delivered and handled -- a real race, not just a
    /// theoretical one. Sending the value directly removes ShaydiAgent's
    /// dependency on that timing entirely for the live path (only its own
    /// launch-time seed, before any notification has arrived, still reads
    /// UserDefaults).
    var crossProcessUserInfo: [AnyHashable: Any] {
        [Self.crossProcessUserInfoKey: rawValue]
    }

    /// nil if `userInfo` carries no recognizable value at all (missing key,
    /// or the notification came with none) -- distinguishing "nothing here"
    /// from "system" lets the caller fall back to its own UserDefaults read
    /// instead of silently treating a malformed notification as "system."
    static func resolved(fromCrossProcessUserInfo userInfo: [AnyHashable: Any]?) -> AppAppearance? {
        guard let raw = userInfo?[crossProcessUserInfoKey] as? String else { return nil }
        return resolved(fromDefaultsValue: raw)
    }
}
