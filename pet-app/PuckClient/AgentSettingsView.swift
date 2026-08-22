//
//  AgentSettingsView.swift
//  PuckClient
//
//  owner: 박해영 (Haeyoung Park)
//  Everything the agent needs configured: which provider it talks to, the
//  API key for the providers that take one, the model where the model is ours
//  to choose, and which coding CLI backs the CLI provider.
//
//  It lives in this app rather than in Puck's own SettingsView because the
//  agent that reads any of it (AgentHost) runs in this process. Puck's panel
//  only ever showed the key field because PuckClient had no Settings surface
//  of its own yet. Opened via the App menu's "설정…" (Cmd+,), same convention
//  every other Mac app uses.
//
//  Everything here persists to the same `.env`
//  (`AgentConfiguration.writableEnvFile`) rather than to UserDefaults: Puck
//  and PuckClient are separate processes with no change notification between
//  them, and the key field already solved that by writing a file both of them
//  re-read on every access. A second mechanism would mean the two could
//  disagree. Every control below therefore reads its value back out of
//  `agentConfiguration` after writing, instead of trusting what it just wrote
//  -- an environment variable or a nearer `.env` can outrank this file, and
//  saying "saved" while something else keeps winning is exactly the confusion
//  `keySource` exists to prevent.
//

import SwiftUI

struct AgentSettingsView: View {
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared

    /// What's typed into the key/model fields before they're saved, and the
    /// resolved configuration every status line reports on.
    @State private var apiKeyDraft = ""
    @State private var apiKeyMessage: String?
    @State private var modelDraft = ""
    @State private var agentConfiguration = AgentConfiguration.load()

    private func text(_ key: L10nKey) -> String {
        Strings.text(key, language: localization.language)
    }

    /// Reuses Puck's own SettingsSection/SettingsStackedRow rather than
    /// hand-approximating their padding/typography, which drifted visibly
    /// when it was tried: the section title lost SettingsSection's
    /// `.secondary` tint, a row label was dropped entirely, and the outer
    /// spacing didn't match SettingsStackedRow's tighter label-to-control
    /// rhythm. Sharing the component instead of the constants means this
    /// can't drift again.
    var body: some View {
        SettingsSection(title: text(.agentHeader)) {
            // Same segmented-Picker-over-CaseIterable-plus-displayName shape
            // as SettingsView's theme picker, and the same
            // read-current-value/write-and-reload round trip every field
            // below it does.
            SettingsStackedRow(label: text(.providerLabel)) {
                Picker("", selection: providerBinding) {
                    ForEach(AgentProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if agentConfiguration.provider == .cli {
                codingAgentRows
            }
            if agentConfiguration.requiresCredential { apiKeyRows }

            if agentConfiguration.provider.supportsModelSelection {
                modelRows
            }
        }
        .padding(ClientTheme.Metrics.spacingLarge)
        .frame(width: 420)
    }

    // MARK: - Rows

    @ViewBuilder
    private var apiKeyRows: some View {
        SettingsStackedRow(label: credentialFieldLabel) {
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

        Text(String(
            format: text(.apiKeyExplanationFormat),
            agentConfiguration.credentialEnvironmentVariables.joined(separator: " 또는 ")
        ))
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
    }

    private var credentialFieldLabel: String {
        if agentConfiguration.provider == .cli {
            return "\(agentConfiguration.codingAgent.displayName) 설정 토큰 / API 키"
        }
        return String(format: text(.apiKeyLabelFormat), agentConfiguration.provider.displayName)
    }

    /// Shown only for the CLI provider. The picker writes the *same*
    /// `CODING_AGENT` the `code_editor` tool already reads, rather than a
    /// parallel setting: the pet thinking with a CLI and editing with a
    /// different one would be a distinction nobody asked for.
    @ViewBuilder
    private var codingAgentRows: some View {
        SettingsStackedRow(label: text(.codingAgentLabel)) {
            Picker("", selection: codingAgentBinding) {
                ForEach(CodingAgentKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }

        // Stated here rather than discovered when the pet fails to move: this
        // provider genuinely cannot call the pet's tools, and the prompt the
        // CLI receives says the same thing (CodingAgentCLIClient).
        Text(text(.cliProviderExplanation))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
    }

    /// Free text rather than a picker: a hardcoded list of model names goes
    /// stale every time a provider ships one, and being unable to type the
    /// model you have access to is worse than having to know its name. The
    /// row's trailing value shows what is actually in effect, so the default
    /// is visible without being typed.
    @ViewBuilder
    private var modelRows: some View {
        SettingsStackedRow(label: text(.modelLabel), value: agentConfiguration.model) {
            HStack {
                TextField(agentConfiguration.provider.defaultModel, text: $modelDraft)
                    .textFieldStyle(.roundedBorder)
                Button(text(.apiKeySave)) { saveModel(modelDraft) }
                    .controlSize(.small)
                    .disabled(modelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(text(.modelReset)) { saveModel(nil) }
                    .controlSize(.small)
            }
        }

        Text(String(
            format: text(.modelExplanationFormat),
            agentConfiguration.provider.defaultModel,
            agentConfiguration.provider.modelEnvironmentVariable ?? ""
        ))
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, ClientTheme.Metrics.spacingSmall)
    }

    // MARK: - Bindings

    /// Reads/writes `AGENT_PROVIDER` in the same `.env` the key field itself
    /// writes to. A plain `@State` can't own this the way it owns
    /// `apiKeyDraft`: the value has to come back out of `agentConfiguration`
    /// (the single source of truth both apps re-read) rather than drift from
    /// it.
    private var providerBinding: Binding<AgentProvider> {
        Binding(
            get: { agentConfiguration.provider },
            set: { newProvider in
                guard newProvider != agentConfiguration.provider else { return }
                DotEnv.write(key: "AGENT_PROVIDER", value: newProvider.rawValue, to: AgentConfiguration.writableEnvFile)
                // Both drafts are provider-specific (an OpenAI key or model
                // typed before switching to Anthropic belongs to neither field
                // once the switch happens), so they're cleared the same way a
                // successful save clears them.
                apiKeyDraft = ""
                modelDraft = ""
                apiKeyMessage = nil
                agentConfiguration = .load()
            }
        )
    }

    /// `CODING_AGENT`, the variable `code_editor` has always read.
    private var codingAgentBinding: Binding<CodingAgentKind> {
        Binding(
            get: { agentConfiguration.codingAgent },
            set: { newKind in
                guard newKind != agentConfiguration.codingAgent else { return }
                DotEnv.write(key: "CODING_AGENT", value: newKind.rawValue, to: AgentConfiguration.writableEnvFile)
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
        guard let keyVariable = agentConfiguration.writableCredentialEnvironmentVariable else { return }
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = AgentConfiguration.writableEnvFile
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

    /// Same shape as `saveAPIKey`, against the provider-specific model
    /// variable. nil clears the assignment, which is what the 기본값 button
    /// does -- the resolved value then falls back to `AGENT_MODEL` or the
    /// provider's default, and the row's trailing value shows which it landed
    /// on.
    private func saveModel(_ model: String?) {
        guard let modelVariable = agentConfiguration.provider.modelEnvironmentVariable else { return }
        let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        DotEnv.write(
            key: modelVariable,
            value: trimmed?.isEmpty == false ? trimmed : nil,
            to: AgentConfiguration.writableEnvFile
        )
        modelDraft = ""
        agentConfiguration = .load()
    }
}
