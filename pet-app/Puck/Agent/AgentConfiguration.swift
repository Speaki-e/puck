//
//  AgentConfiguration.swift
//  Puck
//
//  F15 · owner: 박해영 (Haeyoung Park)
//  Where the agent's API key and model name come from.
//
//  Never the source tree's *tracked* files: plan/04_ai-module.md section 3.1
//  says the key is injected and the module stores none of it, and a key in a
//  committed file is a key in git history. `.env` is already in .gitignore,
//  which is what makes it a safe place to put one.
//
//  Looked up in this order, first hit wins:
//
//   1. The process environment -- an Xcode scheme variable, or `OPENAI_API_KEY=…`
//      in front of the binary. Beats every file so a one-off override doesn't
//      mean editing one.
//   2. `.env` in the current working directory -- running the built binary
//      from a terminal inside the repo.
//   3. `.env` in the repo this build was compiled from (Debug builds only,
//      see `repositoryDirectory`) -- a double-clicked Debug build has `/` for
//      a working directory, so without this, `pet-app/.env` would work from a
//      terminal and silently not from Xcode.
//   4. `.env` in `~/Library/Application Support/Puck/` -- the same folder
//      as bridge.sock and the logs, and the only one of these that a shipped
//      (non-Debug) build can read.
//
//  Same order decides `AGENT_PROVIDER` (`openai`, `anthropic` or `cli`,
//  default `openai`; an unrecognized value falls back to `openai` rather than
//  crashing -- see `AgentProvider.resolved(fromRawValue:)`). The provider then
//  decides which key is read: `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`, or
//  none at all for `cli`; the selected coding CLI's stable credential is
//  resolved separately by `codingAgentCredentials`. Model
//  override is provider-specific too -- `OPENAI_MODEL` / `ANTHROPIC_MODEL` --
//  with the provider-neutral `AGENT_MODEL` as a fallback for either one, so
//  `OPENAI_MODEL` keeps winning for existing OpenAI users even if `AGENT_MODEL`
//  is also set.
//

import Foundation

struct AgentConfiguration {
    let apiKey: String?
    let model: String
    let provider: AgentProvider
    let codingAgent: CodingAgentKind
    let credentialVariable: String?
    /// Which of the search paths actually supplied the key. Surfaced in
    /// Settings because "I changed the key and nothing happened" is otherwise
    /// unanswerable -- an env var or a nearer .env silently outranking the one
    /// you edited looks identical to the setting not saving.
    let keySource: KeySource?

    enum KeySource: Equatable {
        case environment(variable: String)
        case file(URL)

        var displayName: String {
            switch self {
            case .environment(let variable): return String(format: Strings.text(.keySourceEnvironmentFormat), variable)
            case .file(let url):
                return url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            }
        }
    }

    /// Used when nothing names one, for `.openai`.
    ///
    /// Must be a model `GPTClient`'s endpoint actually serves. It posts to
    /// v1/chat/completions, and OpenAI's `*-codex` models are Responses-API
    /// only: asking for one there is a 404 whose body says "use the
    /// v1/responses endpoint instead", which this app then reports as
    /// "모델을 찾을 수 없어요" -- so the default shipped unusable, and looked
    /// like a bad API key. `/v1/models` lists codex models regardless, so
    /// checking availability that way does not catch it; only a real request
    /// to this endpoint does.
    ///
    /// gpt-5.5 fills the same balanced-default role as the Anthropic default
    /// below -- the plain model, not the `-pro` frontier one. Verified against
    /// the live endpoint with a tools payload, since tool calling is the whole
    /// loop here and a model that only answers prose would be useless.
    static let defaultModel = "gpt-5.5"

    /// Used when nothing names one, for `.anthropic`. `claude-sonnet-5` is
    /// Anthropic's "best combination of speed and intelligence" model per
    /// platform.claude.com/docs/en/about-claude/models/overview (checked
    /// 2026-08-15) -- the same balanced-default role the OpenAI default
    /// plays above, rather than the priciest frontier model. Anthropic revs its lineup
    /// often; re-check that page when this stops being current.
    static let defaultAnthropicModel = "claude-sonnet-5"

    init(
        apiKey: String?,
        model: String,
        provider: AgentProvider,
        keySource: KeySource?,
        codingAgent: CodingAgentKind = .claude,
        credentialVariable: String? = nil
    ) {
        self.apiKey = apiKey
        self.model = model
        self.provider = provider
        self.keySource = keySource
        self.codingAgent = codingAgent
        self.credentialVariable = credentialVariable
    }

    /// For `.cli`, `apiKey` holds the first stable credential accepted by the
    /// selected coding agent; interactive login state is not considered.
    var isConfigured: Bool {
        guard requiresCredential else { return true }
        return !(apiKey ?? "").isEmpty
    }

    var requiresCredential: Bool { provider.requiresAPIKey || provider == .cli }

    var credentialEnvironmentVariables: [String] {
        if provider == .cli { return codingAgent.apiKeyEnvironmentVariables }
        return provider.apiKeyEnvironmentVariable.map { [$0] } ?? []
    }

    var writableCredentialEnvironmentVariable: String? {
        if provider == .cli {
            return credentialVariable ?? codingAgent.preferredCredentialEnvironmentVariable
        }
        return provider.apiKeyEnvironmentVariable
    }

    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        searchPaths: [URL] = AgentConfiguration.defaultSearchPaths
    ) -> AgentConfiguration {
        let provider = provider(environment: environment, searchPaths: searchPaths)
        let selectedCodingAgent = codingAgent(environment: environment, searchPaths: searchPaths)
        let credentialVariables = provider == .cli
            ? selectedCodingAgent.apiKeyEnvironmentVariables
            : provider.apiKeyEnvironmentVariable.map { [$0] } ?? []
        guard !credentialVariables.isEmpty else {
            return AgentConfiguration(
                apiKey: nil,
                model: model(provider: provider, environment: environment, searchPaths: searchPaths),
                provider: provider,
                keySource: nil,
                codingAgent: selectedCodingAgent
            )
        }
        for keyVariable in credentialVariables {
            if let fromEnvironment = environment[keyVariable]?.nilIfBlank {
                return AgentConfiguration(
                    apiKey: fromEnvironment,
                    model: model(provider: provider, environment: environment, searchPaths: searchPaths),
                    provider: provider,
                    keySource: .environment(variable: keyVariable),
                    codingAgent: selectedCodingAgent,
                    credentialVariable: keyVariable
                )
            }
        }
        for directory in searchPaths {
            let file = directory.appendingPathComponent(".env")
            let values = DotEnv.parse(fileAt: file)
            for keyVariable in credentialVariables {
                if let fromFile = values[keyVariable]?.nilIfBlank {
                    return AgentConfiguration(
                        apiKey: fromFile,
                        model: model(provider: provider, environment: environment, searchPaths: searchPaths),
                        provider: provider,
                        keySource: .file(file),
                        codingAgent: selectedCodingAgent,
                        credentialVariable: keyVariable
                    )
                }
            }
        }
        return AgentConfiguration(
            apiKey: nil,
            model: model(provider: provider, environment: environment, searchPaths: searchPaths),
            provider: provider,
            keySource: nil,
            codingAgent: selectedCodingAgent
        )
    }

    /// Resolved the same way the key is: process environment beats the
    /// nearest `.env` that sets it. An unrecognized value (a stale `.env`, a
    /// provider this build predates) falls back to the default rather than
    /// crashing -- mirrors `ClientThemeStyle.resolved(fromDefaultsValue:)`.
    ///
    /// That default is `.cli`, which pairs with `codingAgent()`'s own default
    /// of `.claude`: the coding agent this repo vendors self-contained, so it
    /// is the one already present on a fresh install. It still needs a
    /// credential -- `requiresCredential` counts `.cli` too, because the ACP
    /// child gets a private HOME and never inherits an interactive login.
    private static func provider(environment: [String: String], searchPaths: [URL]) -> AgentProvider {
        if let fromEnvironment = environment["AGENT_PROVIDER"]?.nilIfBlank {
            return AgentProvider.resolved(fromRawValue: fromEnvironment)
        }
        for directory in searchPaths {
            if let fromFile = DotEnv.parse(fileAt: directory.appendingPathComponent(".env"))["AGENT_PROVIDER"]?.nilIfBlank {
                return AgentProvider.resolved(fromRawValue: fromFile)
            }
        }
        return AgentProvider.fallback
    }

    /// Which ACP coding agent `code_editor` runs. A **different axis** from
    /// `provider` above, which picks the pet's own brain: the pet can think
    /// with OpenAI while handing edits to Claude Code, and that combination is
    /// a normal one rather than a misconfiguration. Named `codingAgent` to
    /// match the setting workspace used, so an existing `.env` keeps working.
    static func codingAgent(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        searchPaths: [URL] = AgentConfiguration.defaultSearchPaths
    ) -> CodingAgentKind {
        if let fromEnvironment = environment["CODING_AGENT"]?.nilIfBlank,
           let kind = CodingAgentKind(rawValue: fromEnvironment.lowercased()) {
            return kind
        }
        for directory in searchPaths {
            if let fromFile = DotEnv.parse(fileAt: directory.appendingPathComponent(".env"))["CODING_AGENT"]?.nilIfBlank,
               let kind = CodingAgentKind(rawValue: fromFile.lowercased()) {
                return kind
            }
        }
        // claude, not the pet's own provider: it is the agent this repo
        // vendors self-contained, so it is the one that works with no further
        // setup (codex additionally needs its CLI installed).
        return .claude
    }

    /// The credentials to hand the ACP agent, and nothing else -- the child
    /// process gets only the variables its own agent reads.
    ///
    /// Resolved from the same places the pet's own key is, so a `.env` holding
    /// one key for both purposes just works. The child has a private HOME, so
    /// interactive CLI login files are deliberately not copied: refresh-token
    /// rotation would either corrupt the user's real login or lose the new
    /// token when the sandbox is removed. Claude setup-tokens and API keys are
    /// stable credentials and are forwarded explicitly instead.
    func codingAgentCredentials(
        for kind: CodingAgentKind,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        searchPaths: [URL] = AgentConfiguration.defaultSearchPaths
    ) -> [String: String] {
        var credentials: [String: String] = [:]
        for variable in kind.apiKeyEnvironmentVariables {
            if let fromEnvironment = environment[variable]?.nilIfBlank {
                credentials[variable] = fromEnvironment
                continue
            }
            for directory in searchPaths {
                if let fromFile = DotEnv.parse(fileAt: directory.appendingPathComponent(".env"))[variable]?.nilIfBlank {
                    credentials[variable] = fromFile
                    break
                }
            }
        }
        // The pet's own Anthropic key doubles as claude-agent-acp's when only
        // one of the two was ever set -- they are the same credential.
        if kind == .claude, credentials["ANTHROPIC_API_KEY"] == nil, provider == .anthropic, let apiKey {
            credentials["ANTHROPIC_API_KEY"] = apiKey
        }
        return credentials
    }

    /// Resolved independently of the key: a `.env` that only sets the model is
    /// a reasonable thing to have next to one that only sets the key.
    ///
    /// Checks the provider-specific variable (`OPENAI_MODEL` /
    /// `ANTHROPIC_MODEL`) before the provider-neutral `AGENT_MODEL`, at each
    /// search path, so an existing `OPENAI_MODEL` keeps winning for OpenAI
    /// users even if `AGENT_MODEL` is also set somewhere.
    private static func model(provider: AgentProvider, environment: [String: String], searchPaths: [URL]) -> String {
        // A provider whose model is not ours to choose (the CLI picks its own)
        // resolves nothing at all: honouring AGENT_MODEL there would report a
        // model name that nothing sends anywhere.
        guard let providerVariable = provider.modelEnvironmentVariable else { return provider.defaultModel }
        if let fromEnvironment = environment[providerVariable]?.nilIfBlank { return fromEnvironment }
        if let fromEnvironment = environment["AGENT_MODEL"]?.nilIfBlank { return fromEnvironment }
        for directory in searchPaths {
            let values = DotEnv.parse(fileAt: directory.appendingPathComponent(".env"))
            if let fromFile = values[providerVariable]?.nilIfBlank { return fromFile }
            if let fromFile = values["AGENT_MODEL"]?.nilIfBlank { return fromFile }
        }
        return provider.defaultModel
    }

    /// Where Settings writes a key typed into it: the one search path both
    /// apps can reach. Puck shows the field, PuckClient runs the
    /// agent, and they are separate ad-hoc-signed apps -- sharing a Keychain
    /// item between those means an access-group entitlement they cannot have,
    /// or an "allow access" prompt every launch.
    ///
    /// ponytail: 0600 file, not the Keychain. Upgrade path if these ever ship
    /// under one team ID: a shared access group, and this becomes the fallback.
    static var writableEnvFile: URL {
        supportDirectory.appendingPathComponent(".env")
    }

    /// Every directory a `.env` is looked for in, in precedence order. Shown
    /// to the user verbatim when no key is found, so it is also the answer to
    /// "where do I put it".
    static var defaultSearchPaths: [URL] {
        var paths = [URL(fileURLWithPath: FileManager.default.currentDirectoryPath)]
        if let repositoryDirectory { paths.append(repositoryDirectory) }
        paths.append(supportDirectory)
        return paths
    }

    /// Same folder as bridge.sock and the logs -- one place to know about
    /// rather than three, and the only search path that survives moving the
    /// .app to another machine.
    static var supportDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Puck", isDirectory: true)
    }

    /// The `pet-app/` directory this file was compiled from.
    ///
    /// `#filePath` is a compile-time constant, so this is the machine that
    /// built the binary -- meaningless in anything shipped, which is why it is
    /// `#if DEBUG`. It exists because the alternative is telling every
    /// developer that `pet-app/.env` works from a terminal but not from
    /// Xcode, which is the kind of rule people rediscover at 3am.
    static var repositoryDirectory: URL? {
        #if DEBUG
        // …/pet-app/Puck/Agent/AgentConfiguration.swift -> …/pet-app
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Agent
            .deletingLastPathComponent() // Puck
            .deletingLastPathComponent() // pet-app
        #else
        return nil
        #endif
    }
}

/// Which LLM host the agent talks to. Surfaced in Settings as a picker;
/// `AgentConfiguration` uses it to pick the right API key and default model.
enum AgentProvider: String, CaseIterable {
    case openai
    case anthropic
    /// The vendor coding-agent CLI driven over ACP -- the same child process
    /// `code_editor` uses, asked to hold a conversation instead of editing.
    /// It receives a stable setup-token or API key, never copied interactive
    /// login state.
    ///
    /// Which CLI is `CODING_AGENT`'s existing claude/codex choice, not a
    /// second axis (see `AgentConfiguration.codingAgent`).
    case cli

    /// Shown in Settings' provider picker.
    var displayName: String {
        switch self {
        case .openai: return "ChatGPT (OpenAI)"
        case .anthropic: return "Claude (Anthropic)"
        case .cli: return Strings.text(.codingAgentLabel)
        }
    }

    /// nil for `.cli` because its accepted credential variables depend on the
    /// selected `CODING_AGENT`; AgentConfiguration resolves those dynamically.
    var apiKeyEnvironmentVariable: String? {
        switch self {
        case .openai: return "OPENAI_API_KEY"
        case .anthropic: return "ANTHROPIC_API_KEY"
        case .cli: return nil
        }
    }

    var requiresAPIKey: Bool { apiKeyEnvironmentVariable != nil }

    /// nil when the model is not ours to pick: the ACP protocol has no model
    /// field, so a `.cli` turn runs on whatever the CLI itself is configured
    /// for. Settings hides the model field rather than offering one that would
    /// be written and then ignored.
    var modelEnvironmentVariable: String? {
        switch self {
        case .openai: return "OPENAI_MODEL"
        case .anthropic: return "ANTHROPIC_MODEL"
        case .cli: return nil
        }
    }

    var supportsModelSelection: Bool { modelEnvironmentVariable != nil }

    var defaultModel: String {
        switch self {
        case .openai: return AgentConfiguration.defaultModel
        case .anthropic: return AgentConfiguration.defaultAnthropicModel
        // Empty rather than a name: nothing sends a model for this provider,
        // and inventing one here would put a lie in Settings' status line.
        case .cli: return ""
        }
    }

    /// Same resolve-with-fallback shape as
    /// `ClientThemeStyle.resolved(fromDefaultsValue:)` -- a raw value this
    /// build doesn't recognize (a stale `.env`, a future provider) falls back
    /// to `.openai` instead of crashing.
    /// What an absent or unreadable setting resolves to. See
    /// `AgentConfiguration.provider(environment:searchPaths:)`.
    static let fallback: AgentProvider = .cli

    static func resolved(fromRawValue raw: String?) -> AgentProvider {
        raw.flatMap(AgentProvider.init(rawValue:)) ?? AgentProvider.fallback
    }
}

/// A `.env` reader: `KEY=VALUE` lines, `#` comments, blank lines, optional
/// `export ` prefix and optional surrounding quotes. Deliberately not a full
/// shell parser -- no interpolation, no multi-line values. A key is one line.
enum DotEnv {
    static func parse(fileAt url: URL) -> [String: String] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return parse(contents)
    }

    static func parse(_ contents: String) -> [String: String] {
        var values: [String: String] = [:]
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst("export ".count)) }

            // Split on the FIRST '=' only: an API key can contain one, and
            // splitting on all of them truncates the value.
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            values[key] = unquote(String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces))
        }
        return values
    }

    /// Sets one key in a `.env`, leaving every other line -- comments
    /// included -- exactly as it was. A rewrite-the-whole-file version would
    /// eat the template's comments the first time Settings saved anything.
    ///
    /// The file is created 0600 and re-chmod'd on every write: it holds an API
    /// key, and the default 0644 makes that readable by every process running
    /// as anyone on the machine.
    @discardableResult
    static func write(key: String, value: String?, to url: URL) -> Bool {
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var lines = existing.isEmpty ? [] : existing.components(separatedBy: "\n")
        let assignment = value.map { "\(key)=\($0)" }

        // Replace in place if the key is already assigned somewhere, so its
        // position (and any comment above it) is preserved.
        let index = lines.firstIndex { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#") else { return false }
            let withoutExport = trimmed.hasPrefix("export ") ? String(trimmed.dropFirst("export ".count)) : trimmed
            return withoutExport.split(separator: "=", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespaces) == key
        }
        switch (index, assignment) {
        case (let index?, let assignment?):
            lines[index] = assignment
        case (let index?, nil):
            lines.remove(at: index)
        case (nil, let assignment?):
            lines.append(assignment)
        case (nil, nil):
            return true // asked to clear something that was never set
        }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            // After the write, not before: the atomic write replaces the file,
            // and with it any permissions set on the old one.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    private static func unquote(_ value: String) -> String {
        for quote in ["\"", "'"] where value.count >= 2 && value.hasPrefix(quote) && value.hasSuffix(quote) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}

private extension String {
    /// A key pasted into a file almost always arrives with surrounding
    /// whitespace, and a trailing newline in an Authorization header is an
    /// invalid-header crash rather than a 401.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
