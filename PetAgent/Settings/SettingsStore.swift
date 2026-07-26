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
        static let speechLocale = "PetAgent.speechLocale"
        static let pushToTalk = "PetAgent.hotkey.pushToTalk"
        static let textInput = "PetAgent.hotkey.textInput"
        static let characterSummon = "PetAgent.hotkey.characterSummon"
    }

    private let defaults: UserDefaults

    /// Settings changes only persisted to UserDefaults with no way for a
    /// running session to react -- AppDelegate subscribes to these so
    /// Volume/Mute in Settings take effect on the live SFXPlayer immediately
    /// instead of only after a restart.
    var onVolumeChanged: ((Float) -> Void)?
    var onMuteChanged: ((Bool) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
