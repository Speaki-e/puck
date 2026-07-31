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

    // 2026-07-31 (byeolki: "전체적인 ui를 리퀴드 글라스 느낌으로"): the stock
    // TabView + Form chrome was the last surface still reading as the default
    // macOS settings pane. Same vocabulary as the client window now -- glass
    // capsule tabs and GlassCard sections over behind-window vibrancy.
    var body: some View {
        VStack(spacing: ClientTheme.Metrics.spacingLarge) {
            tabBar
            ScrollView {
                // One GlassGroup around the whole tab: each GlassCard's
                // glassEffect is otherwise its own backdrop-sampling pass,
                // and the container is also what blends adjacent glass as
                // one material (see GlassGroup's doc).
                GlassGroup {
                    switch selectedTab {
                    case .general: generalTab
                    case .sound: soundTab
                    case .movement: movementTab
                    case .avatar:
                        AvatarManagementView(language: language, onScaleChanged: onAvatarScaleChanged)
                    }
                }
                .padding([.horizontal, .bottom], ClientTheme.Metrics.spacingLarge)
            }
        }
        .padding(.top, ClientTheme.Metrics.spacingMedium)
        .frame(width: 460, height: 480)
        .background(VisualEffectBackground(material: .sidebar).ignoresSafeArea())
        .preferredColorScheme(appearance.colorScheme)
    }

    private var tabBar: some View {
        GlassGroup(spacing: ClientTheme.Metrics.spacingSmall) {
            HStack(spacing: ClientTheme.Metrics.spacingSmall) {
                tabButton(.general, icon: "gearshape", label: .tabGeneral)
                tabButton(.sound, icon: "speaker.wave.2", label: .tabSound)
                tabButton(.movement, icon: "figure.walk", label: .tabMovement)
                tabButton(.avatar, icon: "person.crop.square", label: .tabAvatar)
            }
        }
    }

    private func tabButton(_ tab: Tab, icon: String, label: L10nKey) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Label(text(label), systemImage: icon)
                .font(ClientTheme.Typography.toolLabel)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassControl(in: Capsule(), isEnabled: selectedTab == tab)
        .foregroundStyle(selectedTab == tab ? ClientTheme.Colors.bubbleText : ClientTheme.Colors.secondaryText)
    }

    private var generalTab: some View {
        VStack(spacing: ClientTheme.Metrics.spacingMedium) {
            GlassCard(title: text(.languageLabel)) {
                Picker(text(.languageLabel), selection: $language) {
                    ForEach(AppLanguage.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: language) { store.language = $0 }
            }
            // byeolki: "화이트모드 다크모드 추가하고" -- an explicit override,
            // not just passively following the system (.system does that).
            GlassCard(title: text(.appearanceLabel)) {
                Picker(text(.appearanceLabel), selection: $appearance) {
                    Text(text(.appearanceSystem)).tag(AppAppearance.system)
                    Text(text(.appearanceLight)).tag(AppAppearance.light)
                    Text(text(.appearanceDark)).tag(AppAppearance.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: appearance) { store.appearance = $0 }
            }
            GlassCard(title: text(.accessibilityLabel)) {
                // The launch prompt only appears once, so this is the way back
                // for anyone who dismissed it or revoked the grant later.
                LabeledContent(text(.accessibilityLabel)) {
                    Text(AccessibilityPermission.isTrusted(prompt: false) ? text(.accessibilityGranted) : text(.accessibilityNotGranted))
                        .foregroundStyle(.secondary)
                }
                Button(text(.openSystemSettingsButton)) {
                    AccessibilityPermission.openSystemSettings()
                }
                .glassButton()
                Text(text(.accessibilityExplanation))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var soundTab: some View {
        GlassCard(title: text(.tabSound)) {
            Slider(value: $volume, in: 0...1) { Text(text(.volumeLabel)) }
                .onChange(of: volume) { store.volume = Float($0) }
            Toggle(text(.muteLabel), isOn: $isMuted)
                .onChange(of: isMuted) { store.isMuted = $0 }
            Toggle(text(.autoMuteLabel), isOn: $autoMuteOnFocus)
                .onChange(of: autoMuteOnFocus) { store.autoMuteOnFocus = $0 }
        }
    }

    private var movementTab: some View {
        GlassCard(title: text(.tabMovement)) {
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
    }
}
