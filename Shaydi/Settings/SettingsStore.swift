//
//  SettingsStore.swift
//  Shaydi
//
//  Shared · owner: Sangwoo Kang / Haeyoung Park
//  UserDefaults wrapper: volume, hotkeys, misc options
//

import CoreGraphics
import Foundation

final class SettingsStore {
    private enum Keys {
        static let volume = "Shaydi.volume"
        static let isMuted = "Shaydi.isMuted"
        static let autoMuteOnFocus = "Shaydi.autoMuteOnFocus"
        static let avoidClimbingFocusedWindow = "Shaydi.avoidClimbingFocusedWindow"
        static let walkSpeedMultiplier = "Shaydi.walkSpeedMultiplier"
        static let toyScale = "Shaydi.toyScale"
        static let speechLocale = "Shaydi.speechLocale"
        static let appearance = AppAppearance.defaultsKey
        static let pushToTalk = "Shaydi.hotkey.pushToTalk"
        static let textInput = "Shaydi.hotkey.textInput"
        static let characterSummon = "Shaydi.hotkey.characterSummon"
        static let toySummon1 = "Shaydi.hotkey.toySummon1"
        static let toySummon2 = "Shaydi.hotkey.toySummon2"
        static let isNotchEnabled = "Shaydi.isNotchEnabled"
        static let isMuteComplaintEnabled = "Shaydi.isMuteComplaintEnabled"
        static let selectedAvatarName = "Shaydi.selectedAvatarName"
        static let hasRequestedAccessibility = "Shaydi.hasRequestedAccessibility"
    }

    private let defaults: UserDefaults

    /// Settings changes only persisted to UserDefaults with no way for a
    /// running session to react -- AppDelegate subscribes to these so
    /// Volume/Mute in Settings take effect on the live SFXPlayer immediately
    /// instead of only after a restart.
    var onVolumeChanged: ((Float) -> Void)?
    var onMuteChanged: ((Bool) -> Void)?
    var onWalkSpeedMultiplierChanged: ((Double) -> Void)?
    /// byeolki: "화이트모드 다크모드 추가하고" -- the client window (F13) is a
    /// separate SwiftUI hierarchy from Settings, so it needs its own signal to
    /// pick up a live appearance change instead of only reading it at open time.
    var onAppearanceChanged: ((AppAppearance) -> Void)?
    /// The notch (2026-08-01) is a persistent NSWindow AppDelegate owns, not
    /// something SettingsView can start/stop directly -- this is how turning
    /// it off in Settings actually tears the window down immediately.
    var onNotchEnabledChanged: ((Bool) -> Void)?
    /// byeolki, 2026-08-01: "아바타를 프리셋 바꾸는거 마냥 바꿀 수 있게
    /// 해주고" -- picking a different installed avatar in Settings has to
    /// swap the *running* pet immediately, not just take effect next launch.
    var onSelectedAvatarChanged: ((String) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether the Accessibility prompt has already been raised once. Must
    /// outlive the process, or every launch is a first launch and the user is
    /// asked again every time.
    var hasRequestedAccessibility: Bool {
        get { defaults.bool(forKey: Keys.hasRequestedAccessibility) }
        set { defaults.set(newValue, forKey: Keys.hasRequestedAccessibility) }
    }

    var volume: Float {
        get { defaults.object(forKey: Keys.volume) as? Float ?? 1.0 }
        set {
            defaults.set(newValue, forKey: Keys.volume)
            onVolumeChanged?(newValue)
        }
    }

    var isMuted: Bool {
        get { defaults.bool(forKey: Keys.isMuted) }
        set {
            defaults.set(newValue, forKey: Keys.isMuted)
            onMuteChanged?(newValue)
        }
    }

    /// Off by default — FocusModeObserver's Do Not Disturb detection is
    /// unverified on modern macOS (see its doc comment), so this shouldn't
    /// silently mute SFX for everyone until someone confirms it works.
    var autoMuteOnFocus: Bool {
        get { defaults.bool(forKey: Keys.autoMuteOnFocus) }
        set { defaults.set(newValue, forKey: Keys.autoMuteOnFocus) }
    }

    /// "포커스 창 위로 안 올라감" wander option (02_pet-app.md F3).
    var avoidClimbingFocusedWindow: Bool {
        get { defaults.object(forKey: Keys.avoidClimbingFocusedWindow) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.avoidClimbingFocusedWindow) }
    }

    /// On by default -- the notch is meant to always be there, like the
    /// real menu bar. byeolki, 2026-08-01: "다이내믹 아일랜드 끄고 킬 수
    /// 있는 버튼 추가해줘".
    var isNotchEnabled: Bool {
        get { defaults.object(forKey: Keys.isNotchEnabled) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Keys.isNotchEnabled)
            onNotchEnabledChanged?(newValue)
        }
    }

    /// Whether muting gets a sulk (angry face + "제 목소리가 시끄러우신거에
    /// 요?") -- byeolki, 2026-08-01, after asking for the sulk to stop
    /// moving the pet to center screen: "이런거 설정 가능하도록 해줘". No
    /// live-callback needed (unlike isNotchEnabled): this is only consulted
    /// at the moment mute is toggled, not applied to something already on
    /// screen.
    var isMuteComplaintEnabled: Bool {
        get { defaults.object(forKey: Keys.isMuteComplaintEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.isMuteComplaintEnabled) }
    }

    /// Which installed avatar (a folder name under AvatarCatalogue.avatars-
    /// Directory) is currently active. "dummy" is the bundled default,
    /// always seeded on first run (see AvatarInstaller).
    var selectedAvatarName: String {
        get { defaults.string(forKey: Keys.selectedAvatarName) ?? "dummy" }
        set {
            defaults.set(newValue, forKey: Keys.selectedAvatarName)
            onSelectedAvatarChanged?(newValue)
        }
    }

    /// Multiplies MovementSolver.walkSpeed for Walk/Climb/WalkOnTop/MoveTo/
    /// Ceiling (byeolki's request, 2026-07-29). 1.0 == the default speed.
    var walkSpeedMultiplier: Double {
        get { defaults.object(forKey: Keys.walkSpeedMultiplier) as? Double ?? 1.0 }
        set {
            defaults.set(newValue, forKey: Keys.walkSpeedMultiplier)
            onWalkSpeedMultiplierChanged?(newValue)
        }
    }

    /// Size of the ball toy, as a multiple of its built-in radius (byeolki:
    /// "호박 크기도 조절 가능 하게", 2026-07-29). Lives here rather than in
    /// the avatar manifest because the toy is bundled with the app, not with
    /// an avatar -- swapping avatars must not resize or remove it.
    var toyScale: Double {
        get { defaults.object(forKey: Keys.toyScale) as? Double ?? 1.0 }
        set {
            defaults.set(newValue, forKey: Keys.toyScale)
            onToyScaleChanged?(newValue)
        }
    }

    var onToyScaleChanged: ((Double) -> Void)?

    // Which toy the pet has stopped being a setting on 2026-07-30: several
    // can be out at once now, and the menu bar's per-toy on/off list is the
    // one place that decides. A stored "current toy" alongside it would just
    // be a second answer to the same question.

    var appearance: AppAppearance {
        get {
            AppAppearance.resolved(fromDefaultsValue: defaults.string(forKey: Keys.appearance))
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.appearance)
            onAppearanceChanged?(newValue)
        }
    }

    var speechRecognitionLocaleIdentifier: String {
        get { defaults.string(forKey: Keys.speechLocale) ?? Locale.current.identifier }
        set { defaults.set(newValue, forKey: Keys.speechLocale) }
    }

    var hotkeyBindings: HotkeyBindings {
        get {
            HotkeyBindings(
                pushToTalk: binding(forKey: Keys.pushToTalk) ?? HotkeyBindings.defaults.pushToTalk,
                textInput: binding(forKey: Keys.textInput) ?? HotkeyBindings.defaults.textInput,
                characterSummon: binding(forKey: Keys.characterSummon) ?? HotkeyBindings.defaults.characterSummon,
                toySummon1: binding(forKey: Keys.toySummon1) ?? HotkeyBindings.defaults.toySummon1,
                toySummon2: binding(forKey: Keys.toySummon2) ?? HotkeyBindings.defaults.toySummon2
            )
        }
        set {
            setBinding(newValue.pushToTalk, forKey: Keys.pushToTalk)
            setBinding(newValue.textInput, forKey: Keys.textInput)
            setBinding(newValue.characterSummon, forKey: Keys.characterSummon)
            setBinding(newValue.toySummon1, forKey: Keys.toySummon1)
            setBinding(newValue.toySummon2, forKey: Keys.toySummon2)
        }
    }

    // CGEventFlags isn't Codable, so bindings are stored as plain
    // [keyCode, rawModifierFlags] dictionaries rather than via JSONEncoder.
    private func binding(forKey key: String) -> HotkeyBinding? {
        guard
            let dict = defaults.dictionary(forKey: key),
            let keyCode = dict["keyCode"] as? Int,
            let modifiers = dict["modifiers"] as? UInt64
        else {
            return nil
        }
        return HotkeyBinding(keyCode: CGKeyCode(keyCode), modifierFlags: CGEventFlags(rawValue: modifiers))
    }

    private func setBinding(_ binding: HotkeyBinding, forKey key: String) {
        defaults.set(["keyCode": Int(binding.keyCode), "modifiers": binding.modifierFlags.rawValue], forKey: key)
    }
}
