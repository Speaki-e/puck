//
//  SettingsStore.swift
//  PetAgent
//
//  Shared · owner: Sangwoo Kang / Haeyoung Park
//  UserDefaults wrapper: volume, hotkeys, language, misc options
//

import CoreGraphics
import Foundation

final class SettingsStore {
    private enum Keys {
        static let volume = "PetAgent.volume"
        static let isMuted = "PetAgent.isMuted"
        static let autoMuteOnFocus = "PetAgent.autoMuteOnFocus"
        static let avoidClimbingFocusedWindow = "PetAgent.avoidClimbingFocusedWindow"
        static let walkSpeedMultiplier = "PetAgent.walkSpeedMultiplier"
        static let toyScale = "PetAgent.toyScale"
        static let speechLocale = "PetAgent.speechLocale"
        static let language = "PetAgent.language"
        static let appearance = "PetAgent.appearance"
        static let pushToTalk = "PetAgent.hotkey.pushToTalk"
        static let textInput = "PetAgent.hotkey.textInput"
        static let characterSummon = "PetAgent.hotkey.characterSummon"
        static let hasRequestedAccessibility = "PetAgent.hasRequestedAccessibility"
    }

    private let defaults: UserDefaults

    /// Settings changes only persisted to UserDefaults with no way for a
    /// running session to react -- AppDelegate subscribes to these so
    /// Volume/Mute in Settings take effect on the live SFXPlayer immediately
    /// instead of only after a restart.
    var onVolumeChanged: ((Float) -> Void)?
    var onMuteChanged: ((Bool) -> Void)?
    var onWalkSpeedMultiplierChanged: ((Double) -> Void)?
    /// byeolki: "한국어 언어모드도 만들어주고" -- the menu bar's own text
    /// (built once at construction, unlike SwiftUI's live-recomputed body)
    /// needs this to update its titles when Settings' language picker changes.
    var onLanguageChanged: ((AppLanguage) -> Void)?
    /// byeolki: "화이트모드 다크모드 추가하고" -- the client window (F13) is a
    /// separate SwiftUI hierarchy from Settings, so it needs its own signal to
    /// pick up a live appearance change instead of only reading it at open time.
    var onAppearanceChanged: ((AppAppearance) -> Void)?

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

    var language: AppLanguage {
        get {
            defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:)) ?? AppLanguage.systemDefault()
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.language)
            onLanguageChanged?(newValue)
        }
    }

    var appearance: AppAppearance {
        get {
            defaults.string(forKey: Keys.appearance).flatMap(AppAppearance.init(rawValue:)) ?? .system
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
                characterSummon: binding(forKey: Keys.characterSummon) ?? HotkeyBindings.defaults.characterSummon
            )
        }
        set {
            setBinding(newValue.pushToTalk, forKey: Keys.pushToTalk)
            setBinding(newValue.textInput, forKey: Keys.textInput)
            setBinding(newValue.characterSummon, forKey: Keys.characterSummon)
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
