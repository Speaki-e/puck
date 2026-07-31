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
}
