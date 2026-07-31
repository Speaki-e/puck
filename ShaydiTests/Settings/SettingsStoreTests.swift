//
//  SettingsStoreTests.swift
//  Shaydi
//
//  Shared test · owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Uses a dedicated UserDefaults suite (never .standard) so tests can't
//  pollute or be polluted by the developer's real defaults.
//

import XCTest
import CoreGraphics
@testable import Shaydi

final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "ShaydiTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_volume_defaultsToOne() {
        XCTAssertEqual(SettingsStore(defaults: defaults).volume, 1.0)
    }

    func test_volume_roundTrips() {
        let store = SettingsStore(defaults: defaults)
        store.volume = 0.4
        XCTAssertEqual(store.volume, 0.4)
    }

    func test_isMuted_defaultsToFalse() {
        XCTAssertFalse(SettingsStore(defaults: defaults).isMuted)
    }

    func test_autoMuteOnFocus_defaultsToFalse() {
        // Off by default -- FocusModeObserver's detection is unverified on
        // modern macOS, so this shouldn't silently mute SFX for everyone.
        XCTAssertFalse(SettingsStore(defaults: defaults).autoMuteOnFocus)
    }

    func test_avoidClimbingFocusedWindow_defaultsToTrue() {
        XCTAssertTrue(SettingsStore(defaults: defaults).avoidClimbingFocusedWindow)
    }

    func test_isNotchEnabled_defaultsToTrue() {
        XCTAssertTrue(SettingsStore(defaults: defaults).isNotchEnabled)
    }

    func test_settingIsNotchEnabled_firesOnNotchEnabledChanged() {
        let store = SettingsStore(defaults: defaults)
        var received: Bool?
        store.onNotchEnabledChanged = { received = $0 }

        store.isNotchEnabled = false

        XCTAssertEqual(received, false)
    }

    func test_speechRecognitionLocaleIdentifier_defaultsToSystemLocale() {
        XCTAssertEqual(
            SettingsStore(defaults: defaults).speechRecognitionLocaleIdentifier,
            Locale.current.identifier
        )
    }

    func test_speechRecognitionLocaleIdentifier_roundTrips() {
        let store = SettingsStore(defaults: defaults)
        store.speechRecognitionLocaleIdentifier = "en-US"
        XCTAssertEqual(store.speechRecognitionLocaleIdentifier, "en-US")
    }

    func test_hotkeyBindings_defaultToPlanDefaults() {
        XCTAssertEqual(SettingsStore(defaults: defaults).hotkeyBindings, .defaults)
    }

    func test_settingVolume_firesOnVolumeChanged() {
        let store = SettingsStore(defaults: defaults)
        var received: Float?
        store.onVolumeChanged = { received = $0 }

        store.volume = 0.6

        XCTAssertEqual(received, 0.6)
    }

    func test_walkSpeedMultiplier_defaultsToOne() {
        XCTAssertEqual(SettingsStore(defaults: defaults).walkSpeedMultiplier, 1.0)
    }

    func test_walkSpeedMultiplier_roundTrips() {
        let store = SettingsStore(defaults: defaults)
        store.walkSpeedMultiplier = 1.8
        XCTAssertEqual(store.walkSpeedMultiplier, 1.8)
    }

    func test_settingWalkSpeedMultiplier_firesOnWalkSpeedMultiplierChanged() {
        let store = SettingsStore(defaults: defaults)
        var received: Double?
        store.onWalkSpeedMultiplierChanged = { received = $0 }

        store.walkSpeedMultiplier = 0.5

        XCTAssertEqual(received, 0.5)
    }

    func test_settingIsMuted_firesOnMuteChanged() {
        let store = SettingsStore(defaults: defaults)
        var received: Bool?
        store.onMuteChanged = { received = $0 }

        store.isMuted = true

        XCTAssertEqual(received, true)
    }

    // byeolki: "한국어 언어모드도 만들어주고" -- an in-app language setting.
    func test_language_defaultsToTheSystemLanguage() {
        XCTAssertEqual(SettingsStore(defaults: defaults).language, AppLanguage.systemDefault())
    }

    func test_language_roundTrips() {
        let store = SettingsStore(defaults: defaults)
        store.language = .korean
        XCTAssertEqual(store.language, .korean)
    }

    func test_settingLanguage_firesOnLanguageChanged() {
        let store = SettingsStore(defaults: defaults)
        var received: AppLanguage?
        store.onLanguageChanged = { received = $0 }

        store.language = .korean

        XCTAssertEqual(received, .korean)
    }

    // byeolki: "화이트모드 다크모드 추가하고" -- an explicit in-app appearance setting.
    func test_appearance_defaultsToSystem() {
        XCTAssertEqual(SettingsStore(defaults: defaults).appearance, .system)
    }

    func test_appearance_roundTrips() {
        let store = SettingsStore(defaults: defaults)
        store.appearance = .dark
        XCTAssertEqual(store.appearance, .dark)
    }

    func test_settingAppearance_firesOnAppearanceChanged() {
        let store = SettingsStore(defaults: defaults)
        var received: AppAppearance?
        store.onAppearanceChanged = { received = $0 }

        store.appearance = .light

        XCTAssertEqual(received, .light)
    }

    func test_hotkeyBindings_roundTrip() {
        let store = SettingsStore(defaults: defaults)
        var bindings = HotkeyBindings.defaults
        bindings.pushToTalk = HotkeyBinding(keyCode: 12, modifierFlags: [.maskControl])

        store.hotkeyBindings = bindings

        XCTAssertEqual(store.hotkeyBindings, bindings)
    }
}
