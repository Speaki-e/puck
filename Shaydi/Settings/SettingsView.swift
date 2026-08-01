//
//  SettingsView.swift
//  Shaydi
//
//  Shared · owner: Sangwoo Kang / Haeyoung Park
//  The menu bar panel: everything the app can be told to do, in one column.
//
//  2026-07-29 redesign (byeolki: "세팅 ui ux 좀 다시 설계해줘. 한국어
//  언어모드도 만들어주고"): was a single long Form mixing sound, movement,
//  and permission controls with no grouping beyond section headers, and
//  Avatar management lived in an entirely separate window reachable only
//  from a second menu-bar item.
//
//  2026-07-31 (byeolki: "pokopet 설정창과 비슷하게", then "이 설정 이거 위에
//  아이콘 누르면 바로 나오게 그 창을"): the tabbed GlassCard window that
//  replaced it is gone in turn. The reference is pokoPet's menu bar popover
//  -- one narrow scrolling column on a single translucent panel, plain
//  sections, a tinted item grid, action rows at the foot -- and it drops
//  straight from the status item, so this is no longer a window at all.
//  Tabs went with it: the reference has none, and four tabs over twelve
//  controls was chrome the content never needed.
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

    @State private var language: AppLanguage
    @State private var appearance: AppAppearance
    @State private var volume: Double
    @State private var isMuted: Bool
    @State private var autoMuteOnFocus: Bool
    @State private var isMuteComplaintEnabled: Bool
    @State private var avoidClimbingFocusedWindow: Bool
    @State private var isNotchEnabled: Bool
    @State private var toyScale: Double
    @State private var walkSpeedMultiplier: Double
    @State private var toysOut: Set<String>
    /// F15: what is typed into the key field before it is saved, and the
    /// resolved configuration the status line reports on.
    @State private var apiKeyDraft = ""
    @State private var apiKeyMessage: String?
    @State private var agentConfiguration = AgentConfiguration.load()
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
        _language = State(initialValue: store.language)
        _appearance = State(initialValue: store.appearance)
        _volume = State(initialValue: Double(store.volume))
        _isMuted = State(initialValue: store.isMuted)
        _autoMuteOnFocus = State(initialValue: store.autoMuteOnFocus)
        _isMuteComplaintEnabled = State(initialValue: store.isMuteComplaintEnabled)
        _avoidClimbingFocusedWindow = State(initialValue: store.avoidClimbingFocusedWindow)
        _isNotchEnabled = State(initialValue: store.isNotchEnabled)
        _walkSpeedMultiplier = State(initialValue: store.walkSpeedMultiplier)
        _toyScale = State(initialValue: store.toyScale)
        _toysOut = State(initialValue: initialToysOut)
        _isCharacterHidden = State(initialValue: initialIsCharacterHidden)
    }

    private func text(_ key: L10nKey) -> String { Strings.text(key, language) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: ClientTheme.Metrics.spacingLarge) {
                    avatarSection
                    toySection
                    agentSection
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
            language: language,
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

    /// F15 (2026-07-31, byeolki: "설정 같은데에서 api 키 넣을 수 있게").
    /// The key goes to a .env both apps read -- this panel is Shaydi's, and
    /// the agent that needs the key runs in ShaydiAgent (see
    /// AgentConfiguration.writableEnvFile for why not the Keychain).
    private var agentSection: some View {
        SettingsSection(title: text(.agentHeader)) {
            SettingsStackedRow(label: text(.apiKeyLabel)) {
                HStack {
                    // SecureField, so a key isn't left legible on a screen
                    // that gets shared or recorded.
                    // Not in Strings: an OpenAI key prefix is the same string
                    // in every language, and the table's test rejects entries
                    // whose translations are identical.
                    SecureField("sk-…", text: $apiKeyDraft)
                        .textFieldStyle(.roundedBorder)
                    Button(text(.apiKeySave)) { saveAPIKey(apiKeyDraft) }
                        .controlSize(.small)
                        .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if agentConfiguration.isConfigured {
                        Button(text(.apiKeyClear)) { saveAPIKey(nil) }
                            .controlSize(.small)
                    }
                }
            }

            Text(apiKeyStatus)
                .font(.footnote)
                .foregroundStyle(agentConfiguration.isConfigured ? .secondary : Color.orange)
                .padding(.horizontal, ClientTheme.Metrics.spacingSmall)

            Text(text(.apiKeyExplanation))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
        }
    }

    private var apiKeyStatus: String {
        if let message = apiKeyMessage { return message }
        guard let source = agentConfiguration.keySource else { return text(.apiKeyMissing) }
        return String(format: text(.apiKeySourceFormat), source.displayName)
    }

    /// Passing nil removes the assignment, which is how the Remove button
    /// falls back to whatever other source (an env var, the project's .env)
    /// was being shadowed.
    private func saveAPIKey(_ key: String?) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = AgentConfiguration.writableEnvFile
        guard DotEnv.write(key: "OPENAI_API_KEY", value: trimmed?.isEmpty == false ? trimmed : nil, to: target) else {
            apiKeyMessage = text(.apiKeySaveFailed)
            return
        }
        apiKeyDraft = ""
        // Re-read rather than assumed: the field only wins if nothing with
        // higher precedence is already supplying a key, and saying "saved"
        // while a stale env var keeps winning is the confusion keySource
        // exists to prevent.
        agentConfiguration = .load()
        apiKeyMessage = trimmed?.isEmpty == false
            ? String(format: text(.apiKeySavedFormat), target.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
            : nil
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
            SettingsStackedRow(label: text(.languageLabel)) {
                Picker("", selection: $language) {
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
            // byeolki, 2026-08-01: "다이내믹 아일랜드 끄고 킬 수 있는 버튼
            // 추가해줘" -- the toy-summon pill at the top of the screen.
            SettingsRow(label: text(.notchEnabledLabel)) {
                Toggle("", isOn: $isNotchEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: isNotchEnabled) { store.isNotchEnabled = $0 }
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
