//
//  AppDelegate+Language.swift
//  Puck
//
//  Applies the selected UI language to this process and broadcasts it to
//  PuckClient over DistributedNotificationCenter.
//

import Foundation

extension AppDelegate {
    // MARK: - UI language, applied here and broadcast to PuckClient

    /// Unlike the client theme, this process renders in the language too --
    /// the menu bar panel, Settings, and the pet's own speech bubbles all go
    /// through `Strings`. So the value is applied locally *and* broadcast,
    /// rather than only broadcast.
    func setUpLanguage() {
        applyLanguage(settingsStore.language)
        settingsStore.onLanguageChanged = { [weak self] language in
            self?.applyLanguage(language)
        }
    }

    private func applyLanguage(_ language: AppLanguage) {
        Localization.shared.apply(language)
        // userInfo carries the value itself: re-reading UserDefaults on
        // receipt would race against whether this process's write had
        // propagated to cfprefsd by the time PuckClient's observer fires --
        // the same race the theme broadcast documents.
        DistributedNotificationCenter.default().postNotificationName(
            AppLanguage.crossProcessChangeNotification,
            object: nil,
            userInfo: language.crossProcessUserInfo,
            deliverImmediately: true
        )
    }
}
