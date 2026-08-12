//
//  SettingsView.swift
//  Puck
//
//  Shared · owner: Sangwoo Kang / Haeyoung Park
//  The menu bar panel: everything the app can be told to do, in one column.
//  Laid out as pokoPet's menu bar popover is -- one narrow scrolling column
//  on a single translucent panel, plain sections, a tinted item grid, action
//  rows at the foot -- dropping straight from the status item rather than
//  opening a separate window.
//
//  The F15 API-key section lives in PuckClient's own Settings window
//  (AgentSettingsView, Cmd+,) instead of here -- the agent that actually
//  reads the key runs there, not here (see AgentConfiguration's own doc
//  comment for why a shared .env rather than the Keychain in the first
//  place).
//

import SwiftUI

struct SettingsView: View {
    let store: SettingsStore
    var onAvatarScaleChanged: ((Double) -> Void)?

    /// Which toys are out when the panel opens. The panel is rebuilt on every
    /// open, so this is a seed rather than a source of truth -- the toy box
    /// itself is that.
    var initialToysOut: Set<String> = []
    /// Returns the toys that are out *after* the toggle -- from what the toy
    /// box actually did, not from what was asked.
    var onToggleToy: ((Toy) -> Set<String>)?

    /// The action rows the NSMenu used to hold.
    var initialIsCharacterHidden: Bool = false
    var onOpenClient: (() -> Void)?
    var onToggleVisibility: (() -> Void)?
    var onQuit: (() -> Void)?

    @State private var appearance: AppAppearance
    @State private var clientThemeStyle: ClientThemeStyle
    @State private var volume: Double
    @State private var isMuted: Bool
    @State private var autoMuteOnFocus: Bool
    @State private var isMuteComplaintEnabled: Bool
    @State private var avoidClimbingFocusedWindow: Bool
    @State private var toyScale: Double
    @State private var walkSpeedMultiplier: Double
    @State private var toysOut: Set<String>
    /// Tracked locally so the hide/show row relabels itself immediately --
    /// the panel stays open after the toggle, and rebuilding it just to
    /// change one word would dismiss whatever else the user was doing.
    @State private var isCharacterHidden: Bool

    init(
        store: SettingsStore,
        onAvatarScaleChanged: ((Double) -> Void)? = nil,
        initialToysOut: Set<String> = [],
        onToggleToy: ((Toy) -> Set<String>)? = nil,
        initialIsCharacterHidden: Bool = false,
        onOpenClient: (() -> Void)? = nil,
        onToggleVisibility: (() -> Void)? = nil,
        onQuit: (() -> Void)? = nil
    ) {
        self.store = store
        self.onAvatarScaleChanged = onAvatarScaleChanged
        self.initialToysOut = initialToysOut
        self.onToggleToy = onToggleToy
        self.initialIsCharacterHidden = initialIsCharacterHidden
        self.onOpenClient = onOpenClient
        self.onToggleVisibility = onToggleVisibility
        self.onQuit = onQuit
        _appearance = State(initialValue: store.appearance)
        _clientThemeStyle = State(initialValue: store.clientThemeStyle)
        _volume = State(initialValue: Double(store.volume))
        _isMuted = State(initialValue: store.isMuted)
        _autoMuteOnFocus = State(initialValue: store.autoMuteOnFocus)
        _isMuteComplaintEnabled = State(initialValue: store.isMuteComplaintEnabled)
        _avoidClimbingFocusedWindow = State(initialValue: store.avoidClimbingFocusedWindow)
        _walkSpeedMultiplier = State(initialValue: store.walkSpeedMultiplier)
        _toyScale = State(initialValue: store.toyScale)
        _toysOut = State(initialValue: initialToysOut)
        _isCharacterHidden = State(initialValue: initialIsCharacterHidden)
    }

    private func text(_ key: L10nKey) -> String { Strings.text(key) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: ClientTheme.Metrics.spacingLarge) {
                    avatarSection
                    toySection
                    soundSection
                    movementSection
                    generalSection
                }
                .padding(ClientTheme.Metrics.spacingMedium)
            }
            Divider().opacity(0.5)
            actionSection
        }
        .frame(width: MenuBarController.panelSize.width, height: MenuBarController.panelSize.height)
        .preferredColorScheme(appearance.colorScheme)
        // `.id` forces SwiftUI to discard and rebuild this subtree instead of
        // diffing it in place -- byeolki, 2026-08-01: "라이트 테마에서 다크
        // 테마로 가면 멀쩡한데, 라이트 테마에서 시스템 테마로 가면 이상함."
        // Explicit->explicit (Light->Dark) is a genuine value change SwiftUI
        // diffs correctly; explicit->nil (System) is a documented SwiftUI
        // quirk where `.preferredColorScheme(nil)` sometimes fails to
        // invalidate a previously-applied explicit override in place, leaving
        // stale light-derived rendering under what should now be system
        // (dark) chrome. Keying identity on the enum itself sidesteps the
        // diff path entirely for every transition, not just this one.
        .id(appearance)
    }

    /// The reference opens with its mark and name; ours is the pumpkin that
    /// is already the app icon and the pet's toy.
    private var header: some View {
        HStack(spacing: ClientTheme.Metrics.spacingSmall) {
            Image("PumpkinLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
            Text(AppIdentity.displayName)
                .font(ClientTheme.Typography.workspaceName)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
        .padding(.vertical, ClientTheme.Metrics.spacingMedium)
    }

    private var avatarSection: some View {
        AvatarManagementView(
            onScaleChanged: onAvatarScaleChanged,
            initialSelectedAvatarName: store.selectedAvatarName,
            onSelectAvatar: { store.selectedAvatarName = $0 }
        )
    }

    /// The reference's "아이템" grid. Ours is the toy box, which until now
    /// was reachable only from the menu bar's submenu.
    private var toySection: some View {
        SettingsSection(title: text(.menuToys)) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: ClientTheme.Metrics.spacingMedium),
                          GridItem(.flexible(), spacing: ClientTheme.Metrics.spacingMedium)],
                spacing: ClientTheme.Metrics.spacingMedium
            ) {
                ForEach(ToyCatalogue.all, id: \.name) { toy in
                    ToyTile(
                        name: text(ToyPresentation.label(for: toy)),
                        artwork: ToyThumbnail.image(for: toy, boundingSide: 64),
                        tint: ToyPresentation.tint(for: toy),
                        isOut: toysOut.contains(toy.name)
                    ) {
                        guard let onToggleToy else { return }
                        toysOut = onToggleToy(toy)
                    }
                }
            }
            SettingsStackedRow(label: text(.toySizeLabel), value: String(format: "%.2fx", toyScale)) {
                Slider(value: $toyScale, in: 0.5...3.0)
                    .onChange(of: toyScale) { store.toyScale = $0 }
            }
        }
    }

    private var soundSection: some View {
        SettingsSection(title: text(.tabSound)) {
            SettingsStackedRow(label: text(.volumeLabel)) {
                Slider(value: $volume, in: 0...1)
                    .onChange(of: volume) { store.volume = Float($0) }
            }
            SettingsRow(label: text(.muteLabel)) {
                Toggle("", isOn: $isMuted)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: isMuted) { store.isMuted = $0 }
            }
            SettingsRow(label: text(.autoMuteLabel)) {
                Toggle("", isOn: $autoMuteOnFocus)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: autoMuteOnFocus) { store.autoMuteOnFocus = $0 }
            }
            SettingsRow(label: text(.muteComplaintLabel)) {
                Toggle("", isOn: $isMuteComplaintEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: isMuteComplaintEnabled) { store.isMuteComplaintEnabled = $0 }
            }
        }
    }

    private var movementSection: some View {
        SettingsSection(title: text(.tabMovement)) {
            SettingsRow(label: text(.avoidClimbingLabel)) {
                Toggle("", isOn: $avoidClimbingFocusedWindow)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: avoidClimbingFocusedWindow) { store.avoidClimbingFocusedWindow = $0 }
            }
            SettingsStackedRow(label: text(.speedLabel), value: String(format: "%.2fx", walkSpeedMultiplier)) {
                Slider(value: $walkSpeedMultiplier, in: 0.25...3.0)
                    .onChange(of: walkSpeedMultiplier) { store.walkSpeedMultiplier = $0 }
            }
        }
    }

    private var generalSection: some View {
        SettingsSection(title: text(.tabGeneral)) {
            // byeolki: "화이트모드 다크모드 추가하고" -- an explicit override,
            // not just passively following the system (.system does that).
            SettingsStackedRow(label: text(.appearanceLabel)) {
                Picker("", selection: $appearance) {
                    Text(text(.appearanceSystem)).tag(AppAppearance.system)
                    Text(text(.appearanceLight)).tag(AppAppearance.light)
                    Text(text(.appearanceDark)).tag(AppAppearance.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: appearance) { store.appearance = $0 }
            }
            // byeolki, 2026-08-02: "테마는 셰이디앱과 동기화 되어서 메뉴막대를
            // 통한 셰이디 설정으로 변경할 수 있어야하거든" -- the client
            // (chat) window's own theme, moved here from a ClientWindow-
            // local popover so it's controlled from the same place as every
            // other appearance setting.
            SettingsStackedRow(label: text(.clientThemeLabel)) {
                Picker("", selection: $clientThemeStyle) {
                    ForEach(ClientThemeStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: clientThemeStyle) { store.clientThemeStyle = $0 }
            }
            SettingsRow(label: text(.accessibilityLabel)) {
                Text(AccessibilityPermission.isTrusted(prompt: false) ? text(.accessibilityGranted) : text(.accessibilityNotGranted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // The launch prompt only appears once, so this is the way back
            // for anyone who dismissed it or revoked the grant later.
            SettingsActionRow(label: text(.openSystemSettingsButton), systemImage: "gearshape") {
                AccessibilityPermission.openSystemSettings()
            }
            Text(text(.accessibilityExplanation))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
        }
    }

    /// What the NSMenu used to be, now that the icon opens this panel
    /// instead. Pinned below the scroll view rather than scrolled to: quit
    /// has to be reachable without first scrolling past every setting.
    private var actionSection: some View {
        VStack(spacing: 0) {
            SettingsActionRow(label: text(.menuOpenClient), systemImage: "bubble.left.and.bubble.right") {
                onOpenClient?()
            }
            SettingsActionRow(
                label: text(isCharacterHidden ? .menuShow : .menuHide),
                systemImage: isCharacterHidden ? "eye" : "eye.slash"
            ) {
                isCharacterHidden.toggle()
                onToggleVisibility?()
            }
            SettingsActionRow(label: text(.menuQuit), systemImage: "power") {
                onQuit?()
            }
        }
        .padding(ClientTheme.Metrics.spacingSmall)
    }

}
