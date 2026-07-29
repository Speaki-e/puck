//
//  SettingsView.swift
//  PetAgent
//
//  Shared · owner: Sangwoo Kang / Haeyoung Park
//  SwiftUI settings screen, embedded via NSHostingView (overlay itself stays pure AppKit)
//
//  2026-07-29 redesign (byeolki: "세팅 ui ux 좀 다시 설계해줘. 한국어
//  언어모드도 만들어주고"): was a single long Form mixing sound, movement,
//  and permission controls with no grouping beyond section headers, and
//  Avatar management lived in an entirely separate window reachable only
//  from a second menu-bar item. Restructured into a tabbed window (General
//  /Sound/Movement/Avatar), matching macOS's own System Settings shape, with
//  a language picker in General driving every string in the window live.
//

import SwiftUI

struct SettingsView: View {
    /// AppDelegate's "Switch Avatar…" menu item jumps straight to `.avatar`
    /// instead of opening a second window the way it used to.
    enum Tab {
        case general, sound, movement, avatar
    }

    let store: SettingsStore
    var onAvatarScaleChanged: ((Double) -> Void)?

    @State private var selectedTab: Tab
    @State private var language: AppLanguage
    @State private var appearance: AppAppearance
    @State private var volume: Double
    @State private var isMuted: Bool
    @State private var autoMuteOnFocus: Bool
    @State private var avoidClimbingFocusedWindow: Bool
    @State private var toyScale: Double
    @State private var walkSpeedMultiplier: Double

    init(store: SettingsStore, initialTab: Tab = .general, onAvatarScaleChanged: ((Double) -> Void)? = nil) {
        self.store = store
        self.onAvatarScaleChanged = onAvatarScaleChanged
        _selectedTab = State(initialValue: initialTab)
        _language = State(initialValue: store.language)
        _appearance = State(initialValue: store.appearance)
        _volume = State(initialValue: Double(store.volume))
        _isMuted = State(initialValue: store.isMuted)
        _autoMuteOnFocus = State(initialValue: store.autoMuteOnFocus)
        _avoidClimbingFocusedWindow = State(initialValue: store.avoidClimbingFocusedWindow)
        _walkSpeedMultiplier = State(initialValue: store.walkSpeedMultiplier)
        _toyScale = State(initialValue: store.toyScale)
    }

    private func text(_ key: L10nKey) -> String { Strings.text(key, language) }

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label(text(.tabGeneral), systemImage: "gearshape") }
                .tag(Tab.general)
            soundTab
                .tabItem { Label(text(.tabSound), systemImage: "speaker.wave.2") }
                .tag(Tab.sound)
            movementTab
                .tabItem { Label(text(.tabMovement), systemImage: "figure.walk") }
                .tag(Tab.movement)
            AvatarManagementView(language: language, onScaleChanged: onAvatarScaleChanged)
                .tabItem { Label(text(.tabAvatar), systemImage: "person.crop.square") }
                .tag(Tab.avatar)
        }
        .frame(width: 420, height: 380)
        .preferredColorScheme(appearance.colorScheme)
    }

    private var generalTab: some View {
        Form {
            Section(text(.languageLabel)) {
                Picker(text(.languageLabel), selection: $language) {
                    ForEach(AppLanguage.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: language) { store.language = $0 }
            }
            // byeolki: "화이트모드 다크모드 추가하고" -- an explicit override,
            // not just passively following the system (.system does that).
            Section(text(.appearanceLabel)) {
                Picker(text(.appearanceLabel), selection: $appearance) {
                    Text(text(.appearanceSystem)).tag(AppAppearance.system)
                    Text(text(.appearanceLight)).tag(AppAppearance.light)
                    Text(text(.appearanceDark)).tag(AppAppearance.dark)
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { store.appearance = $0 }
            }
            Section(text(.accessibilityLabel)) {
                // The launch prompt only appears once, so this is the way back
                // for anyone who dismissed it or revoked the grant later.
                LabeledContent(text(.accessibilityLabel)) {
                    Text(AccessibilityPermission.isTrusted(prompt: false) ? text(.accessibilityGranted) : text(.accessibilityNotGranted))
                        .foregroundStyle(.secondary)
                }
                Button(text(.openSystemSettingsButton)) {
                    AccessibilityPermission.openSystemSettings()
                }
                Text(text(.accessibilityExplanation))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var soundTab: some View {
        Form {
            Slider(value: $volume, in: 0...1) { Text(text(.volumeLabel)) }
                .onChange(of: volume) { store.volume = Float($0) }
            Toggle(text(.muteLabel), isOn: $isMuted)
                .onChange(of: isMuted) { store.isMuted = $0 }
            Toggle(text(.autoMuteLabel), isOn: $autoMuteOnFocus)
                .onChange(of: autoMuteOnFocus) { store.autoMuteOnFocus = $0 }
        }
        .padding()
    }

    private var movementTab: some View {
        Form {
            Toggle(text(.avoidClimbingLabel), isOn: $avoidClimbingFocusedWindow)
                .onChange(of: avoidClimbingFocusedWindow) { store.avoidClimbingFocusedWindow = $0 }
            HStack {
                Slider(value: $walkSpeedMultiplier, in: 0.25...3.0) { Text(text(.speedLabel)) }
                    .onChange(of: walkSpeedMultiplier) { store.walkSpeedMultiplier = $0 }
                Text(String(format: "%.2fx", walkSpeedMultiplier))
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
            }
            HStack {
                Slider(value: $toyScale, in: 0.5...3.0) { Text(text(.toySizeLabel)) }
                    .onChange(of: toyScale) { store.toyScale = $0 }
                Text(String(format: "%.2fx", toyScale))
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
            }
        }
        .padding()
    }
}
