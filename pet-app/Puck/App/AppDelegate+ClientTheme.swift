//
//  AppDelegate+ClientTheme.swift
//  Puck
//
//  F13 · owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Persists the client (chat) window's theme and broadcasts it to
//  PuckClient over DistributedNotificationCenter.
//

import Foundation

extension AppDelegate {
    // MARK: - Client (chat) window theme, broadcast to PuckClient

    /// byeolki, 2026-08-02: "테마는 셰이디앱과 동기화 되어서 메뉴막대를 통한
    /// 셰이디 설정으로 변경할 수 있어야하거든" -- ClientThemeStyle (the
    /// client window's own light/dark theme, separate from the
    /// system-wide appearance above) is a Settings item here, but only
    /// PuckClient's client window actually renders with it -- this process
    /// never applies it locally, just persists it (via SettingsStore) and
    /// broadcasts it, same DistributedNotificationCenter shape as
    /// onAppearanceChanged above.
    func setUpClientThemeStyle() {
        broadcastClientThemeStyle(settingsStore.clientThemeStyle)
        settingsStore.onClientThemeStyleChanged = { [weak self] style in
            self?.broadcastClientThemeStyle(style)
        }
    }

    private func broadcastClientThemeStyle(_ style: ClientThemeStyle) {
        // userInfo carries the value itself, not just a "something changed"
        // ping -- re-reading UserDefaults on receipt would race against
        // whether this process's write above had actually propagated to
        // cfprefsd by the time PuckClient's observer fires (the same race
        // AppAppearance's broadcast hit first).
        DistributedNotificationCenter.default().postNotificationName(
            ClientThemeStyle.crossProcessChangeNotification,
            object: nil,
            userInfo: style.crossProcessUserInfo,
            deliverImmediately: true
        )
    }
}
