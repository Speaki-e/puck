//
//  AcpAgentCommand.swift
//  Puck
//
//  Port of workspace/src/shared/acp-command.ts: which executable and arguments
//  start a given coding agent. The TS version could just use Electron's own
//  bundled node (`process.execPath`); pet-app has no node of its own, so this
//  has to go looking for one.
//
//  Pure and injectable (no Process, no Bundle lookup of its own) so the search
//  order is testable without depending on what happens to be installed on the
//  machine running the tests.
//

import Foundation

enum CodingAgentKind: String, Codable, CaseIterable {
    case claude
    case codex

    /// The vendored bundle in Puck's resources (scripts/vendor-acp.sh).
    var bundledScriptName: String {
        switch self {
        case .claude: return "acp-claude"
        case .codex: return "acp-codex"
        }
    }

    /// The environment variable the agent reads its credentials from. codex
    /// accepts either, and both are forwarded when present -- CODEX_API_KEY
    /// first because it is the more specific of the two.
    var apiKeyEnvironmentVariables: [String] {
        switch self {
        case .claude: return ["ANTHROPIC_API_KEY"]
        case .codex: return ["CODEX_API_KEY", "OPENAI_API_KEY"]
        }
    }
}

enum AcpAgentCommandError: Error, Equatable {
    /// No node on this machine. Only code_editor is affected; everything else
    /// in the app is unaffected, which is why this is an error value rather
    /// than something that stops the app from starting.
    case nodeNotFound
    /// The vendored .mjs is missing from the app bundle -- a packaging bug,
    /// not a user-environment one.
    case agentScriptMissing(CodingAgentKind)
    /// codex-acp is only a shim around the real codex binary, which this repo
    /// does not vendor (see scripts/vendor-acp.sh).
    case codexCLINotFound
}

struct AcpAgentCommand: Equatable {
    let executable: URL
    let arguments: [String]
    /// Extra environment the agent needs beyond the credentials -- currently
    /// only CODEX_PATH, which tells codex-acp where the codex binary is
    /// instead of letting it resolve @openai/codex out of a node_modules tree
    /// that does not exist inside Puck.app.
    let extraEnvironment: [String: String]
}

enum AcpAgentCommandResolver {
    /// Where node usually is, in the order worth trying. PATH is consulted
    /// first (respecting the user's own choice), then the two package
    /// managers, then nvm's versioned installs -- newest first, since nvm
    /// keeps every version it has ever installed.
    static func resolveNode(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        nvmVersions: (URL) -> [String] = { directory in
            (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        }
    ) -> URL? {
        for directory in environment["PATH"]?.split(separator: ":") ?? [] {
            let candidate = "\(directory)/node"
            if fileExists(candidate) { return URL(fileURLWithPath: candidate) }
        }
        for candidate in ["/opt/homebrew/bin/node", "/usr/local/bin/node"] where fileExists(candidate) {
            return URL(fileURLWithPath: candidate)
        }
        guard let home = environment["HOME"] else { return nil }
        let nvmRoot = URL(fileURLWithPath: home).appendingPathComponent(".nvm/versions/node")
        // Sorted descending by semver-ish string order: "v22" before "v20".
        // Not a real semver comparison -- nvm's directory names are uniform
        // enough that this picks the newest, and picking a slightly older node
        // is not a failure mode worth a version parser.
        for version in nvmVersions(nvmRoot).sorted(by: >) {
            let candidate = nvmRoot.appendingPathComponent("\(version)/bin/node").path
            if fileExists(candidate) { return URL(fileURLWithPath: candidate) }
        }
        return nil
    }

    /// codex-acp spawns this rather than resolving @openai/codex as a module.
    static func resolveCodexCLI(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> URL? {
        if let explicit = environment["CODEX_PATH"], fileExists(explicit) {
            return URL(fileURLWithPath: explicit)
        }
        for directory in environment["PATH"]?.split(separator: ":") ?? [] {
            let candidate = "\(directory)/codex"
            if fileExists(candidate) { return URL(fileURLWithPath: candidate) }
        }
        for candidate in ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"] where fileExists(candidate) {
            return URL(fileURLWithPath: candidate)
        }
        return nil
    }

    static func command(
        for kind: CodingAgentKind,
        scriptURL: URL?,
        node: URL?,
        codexCLI: URL?
    ) throws -> AcpAgentCommand {
        guard let node else { throw AcpAgentCommandError.nodeNotFound }
        guard let scriptURL else { throw AcpAgentCommandError.agentScriptMissing(kind) }
        var extraEnvironment: [String: String] = [:]
        if kind == .codex {
            guard let codexCLI else { throw AcpAgentCommandError.codexCLINotFound }
            extraEnvironment["CODEX_PATH"] = codexCLI.path
        }
        return AcpAgentCommand(
            executable: node,
            arguments: [scriptURL.path],
            extraEnvironment: extraEnvironment
        )
    }

    /// The bundled script for `kind`, or nil when the app was packaged without
    /// it. Looked up by name rather than by path: Xcode flattens a resource
    /// group into Resources/, so there is no ACP/ subdirectory to point at.
    static func bundledScriptURL(for kind: CodingAgentKind, in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: kind.bundledScriptName, withExtension: "mjs")
    }
}
