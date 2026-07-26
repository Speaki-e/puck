//
//  SettingsStoreTests.swift
//  PetAgent
//
//  Shared test · owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Uses a dedicated UserDefaults suite (never .standard) so tests can't
//  pollute or be polluted by the developer's real defaults.
//

import XCTest
import CoreGraphics
@testable import PetAgent

final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "PetAgentTests.\(UUID().uuidString)"
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

    func test_settingIsMuted_firesOnMuteChanged() {
        let store = SettingsStore(defaults: defaults)
        var received: Bool?
        store.onMuteChanged = { received = $0 }

        store.isMuted = true

        XCTAssertEqual(received, true)
    }

    func test_hotkeyBindings_roundTrip() {
        let store = SettingsStore(defaults: defaults)
        var bindings = HotkeyBindings.defaults
        bindings.pushToTalk = HotkeyBinding(keyCode: 12, modifierFlags: [.maskControl])

        store.hotkeyBindings = bindings

        XCTAssertEqual(store.hotkeyBindings, bindings)
    }
}
