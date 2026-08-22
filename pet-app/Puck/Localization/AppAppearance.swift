//
//  AppAppearance.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  In-app light/dark override.
//  An explicit user setting (Settings' General tab) rather than only ever
//  following the system appearance -- .system still exists as the option
//  that does that.
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
    /// instead of silently continuing to follow the real system appearance,
    /// since dark mode and the system's own dark appearance don't render
    /// identically across AppKit chrome.
    var nsApplicationAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// The UserDefaults key SettingsStore persists this under, in Puck's
    /// own defaults domain.
    static let defaultsKey = "Puck.appearance"

    /// Resolves a raw UserDefaults string (or nil/unrecognized) the same way
    /// everywhere this is read from -- SettingsStore's own getter and
    /// PuckClient's cross-process reader both go through this, so they
    /// can't disagree on what counts as "unset."
    static func resolved(fromDefaultsValue raw: String?) -> AppAppearance {
        raw.flatMap(AppAppearance.init(rawValue:)) ?? .system
    }
}
