//
//  AgentSettingsView.swift
//  ShaydiAgent
//
//  F15 · owner: 박해영 (Haeyoung Park)
//  The agent's OpenAI API key, moved here from Shaydi's own SettingsView --
//  byeolki, 2026-08-02: "기존 셰이디앱에 있던 에이전트 관련 설정은 전부
//  셰이디에이전트 설정으로 옮기고". The agent that actually reads the key
//  (AgentHost, in this process) runs here, not in Shaydi -- Shaydi's panel
//  only ever showed this field because ShaydiAgent had no Settings surface
//  of its own yet. Opened via the App menu's "설정…" (Cmd+,), same
//  convention every other Mac app uses.
//

import SwiftUI

struct AgentSettingsView: View {
    /// What's typed into the key field before it's saved, and the resolved
    /// configuration the status line reports on.
    @State private var apiKeyDraft = ""
    @State private var apiKeyMessage: String?
    @State private var agentConfiguration = AgentConfiguration.load()

    private func text(_ key: L10nKey) -> String { Strings.text(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: ClientTheme.Metrics.spacingMedium) {
            Text(text(.agentHeader))
                .font(ClientTheme.Typography.sectionHeader)

            HStack {
                // SecureField, so a key isn't left legible on a screen that
                // gets shared or recorded.
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

            Text(apiKeyStatus)
                .font(.footnote)
                .foregroundStyle(agentConfiguration.isConfigured ? .secondary : Color.orange)

            Text(text(.apiKeyExplanation))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(ClientTheme.Metrics.spacingLarge)
        .frame(width: 420)
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
}
