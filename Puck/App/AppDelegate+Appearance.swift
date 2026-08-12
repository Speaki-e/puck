//
//  AppDelegate+Appearance.swift
//  Puck
//
//  Shared · owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  System-wide light/dark appearance override, applied to NSApp and kept
//  live via SettingsStore's onAppearanceChanged callback.
//

import AppKit

extension AppDelegate {
    // MARK: - Appearance (light/dark override)

    /// byeolki, 2026-08-01: "테마가 내가 아마 다크모드일텐데, 시스템모드랑
    /// 다크모드랑 생긴게 다른데?" -- .preferredColorScheme (SettingsView)
    /// only recolors SwiftUI content; NSPopover's own chrome and any
    /// NSVisualEffectView material follow NSApp.appearance instead, which
    /// nothing was setting. Seeded here at launch and kept live via
    /// onAppearanceChanged.
    func setUpAppearance() {
        applyAppKitAppearance(settingsStore.appearance)
        settingsStore.onAppearanceChanged = { [weak self] appearance in
            self?.applyAppKitAppearance(appearance)
        }
    }

    private func applyAppKitAppearance(_ appearance: AppAppearance) {
        NSApp.appearance = appearance.nsApplicationAppearance
    }
}
