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
//  which is what makes it a safe place to put one (byeolki, 2026-07-31:
//  ".env 에 api 키 넣을 수 있게 해줘").
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
//  Same order decides `AGENT_PROVIDER` (`openai` or `anthropic`, default
//  `openai`; an unrecognized value falls back to `openai` rather than
//  crashing -- see `AgentProvider.resolved(fromRawValue:)`). The provider then
//  decides which key is read: `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`. Model
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
            case .environment(let variable): return "환경변수 \(variable)"
            case .file(let url):
                return url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            }
        }
    }

    /// Used when nothing names one, for `.openai`.
    static let defaultModel = "gpt-4o"

    /// Used when nothing names one, for `.anthropic`. `claude-sonnet-5` is
    /// Anthropic's "best combination of speed and intelligence" model per
    /// platform.claude.com/docs/en/about-claude/models/overview (checked
    /// 2026-08-15) -- the same balanced-default role `gpt-4o` plays above,
    /// rather than the priciest frontier model. Anthropic revs its lineup
    /// often; re-check that page when this stops being current.
    static let defaultAnthropicModel = "claude-sonnet-5"

    var isConfigured: Bool { !(apiKey ?? "").isEmpty }

    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        searchPaths: [URL] = AgentConfiguration.defaultSearchPaths
    ) -> AgentConfiguration {
        let provider = provider(environment: environment, searchPaths: searchPaths)
        let keyVariable = provider.apiKeyEnvironmentVariable
        if let fromEnvironment = environment[keyVariable]?.nilIfBlank {
            return AgentConfiguration(
                apiKey: fromEnvironment,
                model: model(provider: provider, environment: environment, searchPaths: searchPaths),
                provider: provider,
                keySource: .environment(variable: keyVariable)
            )
        }
        for directory in searchPaths {
            let file = directory.appendingPathComponent(".env")
            if let fromFile = DotEnv.parse(fileAt: file)[keyVariable]?.nilIfBlank {
                return AgentConfiguration(
                    apiKey: fromFile,
                    model: model(provider: provider, environment: environment, searchPaths: searchPaths),
                    provider: provider,
                    keySource: .file(file)
                )
            }
        }
        return AgentConfiguration(
            apiKey: nil,
            model: model(provider: provider, environment: environment, searchPaths: searchPaths),
            provider: provider,
            keySource: nil
        )
    }

    /// Resolved the same way the key is: process environment beats the
    /// nearest `.env` that sets it. An unrecognized value (a stale `.env`, a
    /// provider this build predates) falls back to `.openai` rather than
    /// crashing -- mirrors `ClientThemeStyle.resolved(fromDefaultsValue:)`.
    private static func provider(environment: [String: String], searchPaths: [URL]) -> AgentProvider {
        if let fromEnvironment = environment["AGENT_PROVIDER"]?.nilIfBlank {
            return AgentProvider.resolved(fromRawValue: fromEnvironment)
        }
        for directory in searchPaths {
            if let fromFile = DotEnv.parse(fileAt: directory.appendingPathComponent(".env"))["AGENT_PROVIDER"]?.nilIfBlank {
                return AgentProvider.resolved(fromRawValue: fromFile)
            }
        }
        return .openai
    }

    /// Which ACP coding agent `code_editor` runs. A **different axis** from
    /// `provider` above, which picks the pet's own brain: the pet can think
    /// with OpenAI while handing edits to Claude Code, and that combination is
    /// a normal one rather than a misconfiguration. Named `codingAgent` to
    /// match the setting workspace used, so an existing `.env` keeps working.
    var codingAgent: CodingAgentKind {
        Self.codingAgent(environment: Self.loadedEnvironment, searchPaths: Self.loadedSearchPaths)
    }

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
    /// one key for both purposes just works. An agent whose key is missing is
    /// still started: several are authenticated by their own CLI login rather
    /// than an API key, and refusing to start would break that setup.
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

    private static let loadedEnvironment = ProcessInfo.processInfo.environment
    private static let loadedSearchPaths = AgentConfiguration.defaultSearchPaths

    /// Resolved independently of the key: a `.env` that only sets the model is
    /// a reasonable thing to have next to one that only sets the key.
    ///
    /// Checks the provider-specific variable (`OPENAI_MODEL` /
    /// `ANTHROPIC_MODEL`) before the provider-neutral `AGENT_MODEL`, at each
    /// search path, so an existing `OPENAI_MODEL` keeps winning for OpenAI
    /// users even if `AGENT_MODEL` is also set somewhere.
    private static func model(provider: AgentProvider, environment: [String: String], searchPaths: [URL]) -> String {
        let providerVariable = provider.modelEnvironmentVariable
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

    /// Shown in Settings' provider picker.
    var displayName: String {
        switch self {
        case .openai: return "ChatGPT (OpenAI)"
        case .anthropic: return "Claude (Anthropic)"
        }
    }

    var apiKeyEnvironmentVariable: String {
        switch self {
        case .openai: return "OPENAI_API_KEY"
        case .anthropic: return "ANTHROPIC_API_KEY"
        }
    }

    var modelEnvironmentVariable: String {
        switch self {
        case .openai: return "OPENAI_MODEL"
        case .anthropic: return "ANTHROPIC_MODEL"
        }
    }

    var defaultModel: String {
        switch self {
        case .openai: return AgentConfiguration.defaultModel
        case .anthropic: return AgentConfiguration.defaultAnthropicModel
        }
    }

    /// Same resolve-with-fallback shape as
    /// `ClientThemeStyle.resolved(fromDefaultsValue:)` -- a raw value this
    /// build doesn't recognize (a stale `.env`, a future provider) falls back
    /// to `.openai` instead of crashing.
    static func resolved(fromRawValue raw: String?) -> AgentProvider {
        raw.flatMap(AgentProvider.init(rawValue:)) ?? .openai
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
