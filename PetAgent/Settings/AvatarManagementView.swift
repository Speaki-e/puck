//
//  AvatarManagementView.swift
//  PetAgent
//
//  F2 · owner: Sangwoo Kang
//  Avatar import/switch UI, wired to AvatarImportValidator
//

import AppKit
import SwiftUI

struct AvatarManagementView: View {
    @State private var reportMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Avatars").font(.headline)
            Button("Import Avatar Package…") { importAvatar() }
            if !reportMessage.isEmpty {
                Text(reportMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 340)
    }

    private func importAvatar() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        do {
            let report = try AvatarImportValidator.validate(packageDirectory: sourceURL)
            guard report.isValid else {
                reportMessage = "Rejected — missing required clip file(s): \(report.missingRequiredClipFiles.joined(separator: ", "))"
                return
            }

            let destination = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PetAgent/Avatars/\(report.manifest.name)", isDirectory: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: sourceURL, to: destination)

            reportMessage = report.missingRecommendedClipFiles.isEmpty
                ? "Installed '\(report.manifest.name)'."
                : "Installed '\(report.manifest.name)' — missing recommended clips (falls back to idle): "
                    + report.missingRecommendedClipFiles.joined(separator: ", ")
        } catch {
            reportMessage = "Failed to validate: \(error)"
        }
    }
}
