//
//  AvatarManagementView.swift
//  PetAgent
//
//  F2 · owner: Sangwoo Kang
//  Avatar import/switch UI, wired to AvatarImportValidator. 2026-07-29: also
//  hosts the size slider and per-emotion image mapping (both edit the active
//  avatar's manifest.json via AvatarManifestEditor).
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AvatarManagementView: View {
    /// The emotion keys always shown, matching the canonical example in
    /// plan/01_protocol.md section 6 -- plus whatever custom keys the
    /// manifest already has (loaded in onAppear) or the user adds below.
    private static let defaultEmotionKeys = ["happy", "thinking", "sad"]

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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Avatars").font(.headline)
            Button("Import Avatar Package…") { importAvatar() }
            if !reportMessage.isEmpty {
                Text(reportMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Size").font(.headline)
            HStack {
                Slider(value: $scale, in: 0.25...3.0) { Text("Scale") }
                    .onChange(of: scale) { applyScale($0) }
                Text(String(format: "%.2fx", scale))
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
            }

            Divider()

            Text("Emotions").font(.headline)
            Text("Maps a socket event (agent thinking, task failed, task done) to an image. Falls back to idle if unmapped.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(emotionKeys, id: \.self) { emotion in
                HStack {
                    Text(emotion)
                    Spacer()
                    Text(mappedEmotions.contains(emotion) ? "Mapped" : "Not mapped")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Choose Image…") { chooseEmotionImage(for: emotion) }
                }
            }
            HStack {
                TextField("Custom emotion name", text: $newEmotionName)
                Button("Add") { addCustomEmotion() }
                    .disabled(newEmotionName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !emotionMessage.isEmpty {
                Text(emotionMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 380)
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
        guard !name.isEmpty, !emotionKeys.contains(name) else { return }
        emotionKeys.append(name)
        newEmotionName = ""
    }

    private func chooseEmotionImage(for emotion: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png]
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        do {
            try AvatarManifestEditor.setEmotionImage(
                named: emotion,
                sourceFile: sourceURL,
                directory: AvatarManifestEditor.currentAvatarDirectory
            )
            mappedEmotions.insert(emotion)
            emotionMessage = "Updated '\(emotion)'."
        } catch {
            emotionMessage = "Failed to set '\(emotion)': \(error)"
        }
    }

    private func importAvatar() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        let report: AvatarImportValidator.Report
        do {
            report = try AvatarImportValidator.validate(packageDirectory: sourceURL)
        } catch {
            reportMessage = "Failed to validate: \(error)"
            return
        }
        guard report.isValid else {
            reportMessage = "Rejected — missing required clip file(s): \(report.missingRequiredClipFiles.joined(separator: ", "))"
            return
        }

        do {
            // Avatars/ itself may not exist yet on a fresh install (only the
            // dummy avatar's own directory is guaranteed to be pre-seeded).
            let avatarsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PetAgent/Avatars", isDirectory: true)
            try FileManager.default.createDirectory(at: avatarsDirectory, withIntermediateDirectories: true)

            let destination = avatarsDirectory.appendingPathComponent(report.manifest.name, isDirectory: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } catch {
            reportMessage = "Validated but failed to install '\(report.manifest.name)': \(error)"
            return
        }

        reportMessage = report.missingRecommendedClipFiles.isEmpty
            ? "Installed '\(report.manifest.name)'."
            : "Installed '\(report.manifest.name)' — missing recommended clips (falls back to idle): "
                + report.missingRecommendedClipFiles.joined(separator: ", ")
    }
}
