//
//  AgentSettingsView.swift
//  PuckClient
//
//  F15 · owner: 박해영 (Haeyoung Park)
//  The agent's provider choice and API key, moved here from Puck's own
//  SettingsView -- the agent's settings belong to this app rather than
//  설정은 전부 셰이디에이전트 설정으로 옮기고". The agent that actually reads
//  the key (AgentHost, in this process) runs here, not in Puck -- Puck's
//  panel only ever showed this field because PuckClient had no Settings
//  surface of its own yet. Opened via the App menu's "설정…" (Cmd+,), same
//  convention every other Mac app uses.
//
//  F15 (task 4): the provider picker lives right above the key field rather
//  than in Puck's SettingsView next to the theme picker it otherwise
//  mirrors the style of -- this is the one place a key is ever typed, so
//  it's the one place "which provider does this key belong to" can be
//  answered without the user needing to remember a setting that lives in a
//  different app's window. It persists to the same .env the key already
//  writes to (`AgentConfiguration.writableEnvFile`, `AGENT_PROVIDER`) rather
//  than to UserDefaults: Puck and PuckClient are separate processes with no
//  change notification between them, and the key field already solved that
//  by being a file both of them re-read on every access -- splitting
//  provider into a second mechanism would mean the two could disagree.
//

import SwiftUI

struct AgentSettingsView: View {
    /// What's typed into the key field before it's saved, and the resolved
    /// configuration the status line reports on.
    @State private var apiKeyDraft = ""
    @State private var apiKeyMessage: String?
    @State private var agentConfiguration = AgentConfiguration.load()

    private func text(_ key: L10nKey) -> String { Strings.text(key) }

    /// Reuses Puck's own SettingsSection/SettingsStackedRow rather than
    /// hand-approximating their padding/typography, which drifted visibly
    /// when it was tried.
    /// The first version of this file rebuilt the layout by eye instead of
    /// reusing the real components, and it drifted: the section title was
    /// missing SettingsSection's `.secondary` tint (read as a heading, not a
    /// muted label), the "OpenAI API 키" row label was dropped entirely, and
    /// the outer spacing didn't match SettingsStackedRow's tighter
    /// label-to-control rhythm. Sharing the component instead of the
    /// constants means this can't drift again.
    var body: some View {
        SettingsSection(title: text(.agentHeader)) {
            // Same segmented-Picker-over-CaseIterable-plus-displayName shape
            // as SettingsView's theme picker, and the same
            // read-current-value/write-and-reload round trip the key field
            // right below it already does -- `.onChange` here writes
            // `AGENT_PROVIDER` instead of a UserDefaults key for the reason
            // given in this file's header comment.
            SettingsStackedRow(label: text(.providerLabel)) {
                Picker("", selection: providerBinding) {
                    ForEach(AgentProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            SettingsStackedRow(label: String(format: text(.apiKeyLabelFormat), agentConfiguration.provider.displayName)) {
                HStack {
                    // SecureField, so a key isn't left legible on a screen
                    // that gets shared or recorded.
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

            Text(String(format: text(.apiKeyExplanationFormat), agentConfiguration.provider.apiKeyEnvironmentVariable))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
        }
        .padding(ClientTheme.Metrics.spacingLarge)
        .frame(width: 420)
    }

    /// Reads/writes `AGENT_PROVIDER` in the same `.env` the key field itself
    /// writes to. A plain `@State` can't own this the way it owns
    /// `apiKeyDraft`: the value has to come back out of `agentConfiguration`
    /// (the single source of truth both apps re-read) rather than drift from
    /// it, the same reason `saveAPIKey` re-loads after every write instead of
    /// trusting what it just wrote.
    private var providerBinding: Binding<AgentProvider> {
        Binding(
            get: { agentConfiguration.provider },
            set: { newProvider in
                guard newProvider != agentConfiguration.provider else { return }
                DotEnv.write(key: "AGENT_PROVIDER", value: newProvider.rawValue, to: AgentConfiguration.writableEnvFile)
                // The draft is provider-specific (an OpenAI key typed before
                // switching to Anthropic belongs to neither field once the
                // switch happens), so it's cleared the same way saveAPIKey
                // clears it after a successful save.
                apiKeyDraft = ""
                apiKeyMessage = nil
                agentConfiguration = .load()
            }
        )
    }

    private var apiKeyStatus: String {
        if let message = apiKeyMessage { return message }
        guard let source = agentConfiguration.keySource else { return text(.apiKeyMissing) }
        return String(format: text(.apiKeySourceFormat), source.displayName)
    }

    /// Passing nil removes the assignment, which is how the Remove button
    /// falls back to whatever other source (an env var, the project's .env)
    /// was being shadowed. Writes the *selected* provider's key variable, so
    /// saving while Anthropic is selected can never clobber an OpenAI key
    /// sitting in the same file.
    private func saveAPIKey(_ key: String?) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = AgentConfiguration.writableEnvFile
        let keyVariable = agentConfiguration.provider.apiKeyEnvironmentVariable
        guard DotEnv.write(key: keyVariable, value: trimmed?.isEmpty == false ? trimmed : nil, to: target) else {
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
