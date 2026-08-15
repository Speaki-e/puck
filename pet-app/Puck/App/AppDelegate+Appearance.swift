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

    /// .preferredColorScheme (SettingsView)
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
