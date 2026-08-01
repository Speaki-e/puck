//
//  ClientThemeStyle.swift
//  Shaydi
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  Which of the three ClientWindow themes is active -- byeolki: "테마 종류를
//  다크, 화이트, 글래스로". Independent of Shaydi's own system-wide
//  AppAppearance (Settings' light/dark/system toggle, used by the pet
//  overlay/Notch/Settings) -- persisted separately, in ShaydiAgent's own
//  UserDefaults domain, and read by ClientWindowStore.
//

import SwiftUI

enum ClientThemeStyle: String, CaseIterable, Identifiable {
    case light, dark, glass

    var id: String { rawValue }

    /// Shown in the sidebar's theme popover.
    var displayName: String {
        switch self {
        case .light: return "화이트"
        case .dark: return "다크"
        case .glass: return "글래스"
        }
    }

    /// `.glass` always renders dark -- see ClientPalette.glass's own doc
    /// comment for why a light-glass variant doesn't exist.
    var colorScheme: ColorScheme {
        switch self {
        case .light: return .light
        case .dark, .glass: return .dark
        }
    }

    var palette: ClientPalette {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .glass: return .glass
        }
    }

    static let defaultsKey = "ShaydiAgent.clientThemeStyle"

    /// Same resolve-with-fallback shape as AppAppearance.resolved(fromDefaultsValue:)
    /// -- `.dark` (not `.light`) is the fallback since that's this app's
    /// original, already-shipped look.
    static func resolved(fromDefaultsValue raw: String?) -> ClientThemeStyle {
        raw.flatMap(ClientThemeStyle.init(rawValue:)) ?? .dark
    }
}
