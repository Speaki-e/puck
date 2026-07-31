//
//  AvatarManagementView.swift
//  Shaydi
//
//  F2 · owner: Sangwoo Kang
//  Avatar import/switch UI, wired to AvatarImportValidator. 2026-07-29: also
//  hosts the size slider and per-emotion image mapping (both edit the active
//  avatar's manifest.json via AvatarManifestEditor). Embedded as the
//  Settings window's "Avatar" tab (byeolki's UI/UX redesign request,
//  2026-07-29) rather than a separate window.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AvatarManagementView: View {
    /// The emotion keys always shown, matching the canonical example in
    /// plan/01_protocol.md section 6 -- plus whatever custom keys the
    /// manifest already has (loaded in onAppear) or the user adds below.
    private static let defaultEmotionKeys = ["happy", "thinking", "sad"]

    let language: AppLanguage

    /// Called when the size slider changes, so AppDelegate can apply it to
    /// the *running* avatar immediately -- editing manifest.json alone only
    /// takes effect on next launch.
    var onScaleChanged: ((Double) -> Void)?

    @State private var reportMessage = ""
    @State private var scale: Double = 1.0
    @State private var emotionKeys: [String] = AvatarManagementView.defaultEmotionKeys
    @State private var mappedEmotions: Set<String> = []
    @State private var newEmotionName: String = ""
    @State private var emotionMessage = ""

    private func text(_ key: L10nKey) -> String { Strings.text(key, language) }

    // Plain SettingsSections, not cards (2026-07-31, byeolki: "pokopet
    // 설정창과 비슷하게") -- the window's panel is the only surface. No
    // ScrollView of its own; SettingsView scrolls the whole column.
    var body: some View {
        VStack(alignment: .leading, spacing: ClientTheme.Metrics.spacingLarge) {
            SettingsSection(title: text(.avatarsHeader)) {
                SettingsActionRow(label: text(.importAvatarButton), systemImage: "square.and.arrow.down") {
                    importAvatar()
                }
                if !reportMessage.isEmpty {
                    Text(reportMessage)
                        .font(.footnote)
                        .foregroundStyle(ClientTheme.Colors.secondaryText)
                        .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
                }
                SettingsStackedRow(label: text(.sizeHeader), value: String(format: "%.2fx", scale)) {
                    Slider(value: $scale, in: 0.25...3.0)
                        .onChange(of: scale) { applyScale($0) }
                }
            }

            SettingsSection(title: text(.emotionsHeader)) {
                Text(text(.emotionsExplanation))
                    .font(.footnote)
                    .foregroundStyle(ClientTheme.Colors.secondaryText)
                    .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
                // Collapsed by default: the shipped avatar maps sixteen
                // emotions, and sixteen always-open rows pushed the toy grid
                // and every other section off the bottom of the window --
                // the opposite of the compact reference this was matched to.
                DisclosureGroup {
                    VStack(spacing: ClientTheme.Metrics.spacingMedium) {
                        ForEach(emotionKeys, id: \.self) { emotion in
                            SettingsRow(label: emotion) {
                                Text(mappedEmotions.contains(emotion) ? text(.mappedLabel) : text(.notMappedLabel))
                                    .font(.caption)
                                    .foregroundStyle(ClientTheme.Colors.secondaryText)
                                Button(text(.chooseImageButton)) { chooseEmotionImage(for: emotion) }
                                    .controlSize(.small)
                            }
                        }
                        HStack {
                            TextField(text(.customEmotionPlaceholder), text: $newEmotionName)
                                .textFieldStyle(.roundedBorder)
                            Button(text(.addButton)) { addCustomEmotion() }
                                .controlSize(.small)
                                .disabled(newEmotionName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
                    }
                    .padding(.top, ClientTheme.Metrics.spacingSmall)
                } label: {
                    Text(String(format: text(.mappedCountFormat), "\(mappedEmotions.count)", "\(emotionKeys.count)"))
                        .font(ClientTheme.Typography.sessionTitle)
                }
                .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
                if !emotionMessage.isEmpty {
                    Text(emotionMessage)
                        .font(.footnote)
                        .foregroundStyle(ClientTheme.Colors.secondaryText)
                        .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
                }
            }
        }
        .onAppear { loadCurrentManifest() }
    }

    private func loadCurrentManifest() {
        guard let manifest = try? AvatarManifestEditor.loadManifest(directory: AvatarManifestEditor.currentAvatarDirectory) else {
            return
        }
        scale = manifest.scale
        let mappedKeys = Set((manifest.emotions ?? [:]).keys)
        mappedEmotions = mappedKeys
        // Known keys first (stable order), then any custom keys the manifest already has.
        emotionKeys = Self.defaultEmotionKeys + mappedKeys.subtracting(Self.defaultEmotionKeys).sorted()
    }

    private func applyScale(_ newScale: Double) {
        guard (try? AvatarManifestEditor.updateScale(newScale, directory: AvatarManifestEditor.currentAvatarDirectory)) != nil else {
            return
        }
        onScaleChanged?(newScale)
    }

    private func addCustomEmotion() {
        let name = newEmotionName.trimmingCharacters(in: .whitespaces)
        // AvatarManifestEditor.setEmotionImage rejects this same shape
        // defensively, but checking here too keeps an invalid name from ever
        // reaching the emotion list in the first place (found via review: a
        // name with "/" or ".." used unsanitized as a file path component).
        guard !name.isEmpty, !emotionKeys.contains(name), AvatarManifestEditor.isValidEmotionName(name) else { return }
        emotionKeys.append(name)
        newEmotionName = ""
    }

    private func chooseEmotionImage(for emotion: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png]
        panel.prompt = text(.choosePanelPrompt)
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        do {
            try AvatarManifestEditor.setEmotionImage(
                named: emotion,
                sourceFile: sourceURL,
                directory: AvatarManifestEditor.currentAvatarDirectory
            )
            mappedEmotions.insert(emotion)
            emotionMessage = String(format: text(.updatedEmotionFormat), emotion)
        } catch {
            emotionMessage = String(format: text(.failedToSetEmotionFormat), emotion, String(describing: error))
        }
    }

    private func importAvatar() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = text(.importPanelPrompt)
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        let report: AvatarImportValidator.Report
        do {
            report = try AvatarImportValidator.validate(packageDirectory: sourceURL)
        } catch {
            reportMessage = String(format: text(.failedToValidateFormat), String(describing: error))
            return
        }
        guard report.isValid else {
            reportMessage = String(format: text(.rejectedMissingRequiredFormat), report.missingRequiredClipFiles.joined(separator: ", "))
            return
        }

        // Avatars/ itself may not exist yet on a fresh install (only the
        // dummy avatar's own directory is guaranteed to be pre-seeded).
        let avatarsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shaydi/Avatars", isDirectory: true)

        // Previously reimplemented the copy-in here by hand, which silently
        // skipped AvatarInstaller's Git-LFS-pointer-file check -- an import
        // of a package with un-pulled LFS pointers reported false success
        // with broken assets (found via review). overwriteExisting: true
        // because the user explicitly chose to import over whatever's there.
        let outcome = AvatarInstaller.installIfNeeded(
            bundledPackage: sourceURL,
            intoAvatarsDirectory: avatarsDirectory,
            overwriteExisting: true
        )
        switch outcome {
        case .installed:
            reportMessage = report.missingRecommendedClipFiles.isEmpty
                ? String(format: text(.installedFormat), report.manifest.name)
                : String(
                    format: text(.installedMissingRecommendedFormat),
                    report.manifest.name,
                    report.missingRecommendedClipFiles.joined(separator: ", ")
                )
        case .failed(let reason):
            reportMessage = String(format: text(.failedToInstallFormat), report.manifest.name, reason)
        case .alreadyPresent, .noBundledPackage:
            reportMessage = String(format: text(.failedToInstallFormat), report.manifest.name, String(describing: outcome))
        }
    }
}
