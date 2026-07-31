//
//  AgentConfiguration.swift
//  PetAgent
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
//   4. `.env` in `~/Library/Application Support/PetAgent/` -- the same folder
//      as bridge.sock and the logs, and the only one of these that a shipped
//      (non-Debug) build can read.
//
//  Keys: `OPENAI_API_KEY`, and `OPENAI_MODEL` to try a different model
//  without a rebuild.
//

import Foundation

struct AgentConfiguration {
    let apiKey: String?
    let model: String
    /// Which of the search paths actually supplied the key. Surfaced in
    /// Settings because "I changed the key and nothing happened" is otherwise
    /// unanswerable -- an env var or a nearer .env silently outranking the one
    /// you edited looks identical to the setting not saving.
    let keySource: KeySource?

    enum KeySource: Equatable {
        case environment
        case file(URL)

        var displayName: String {
            switch self {
            case .environment: return "환경변수 OPENAI_API_KEY"
            case .file(let url):
                return url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            }
        }
    }

    /// Used when nothing names one.
    static let defaultModel = "gpt-4o"

    var isConfigured: Bool { !(apiKey ?? "").isEmpty }

    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        searchPaths: [URL] = AgentConfiguration.defaultSearchPaths
    ) -> AgentConfiguration {
        if let fromEnvironment = environment["OPENAI_API_KEY"]?.nilIfBlank {
            return AgentConfiguration(
                apiKey: fromEnvironment,
                model: model(environment: environment, searchPaths: searchPaths),
                keySource: .environment
            )
        }
        for directory in searchPaths {
            let file = directory.appendingPathComponent(".env")
            if let fromFile = DotEnv.parse(fileAt: file)["OPENAI_API_KEY"]?.nilIfBlank {
                return AgentConfiguration(
                    apiKey: fromFile,
                    model: model(environment: environment, searchPaths: searchPaths),
                    keySource: .file(file)
                )
            }
        }
        return AgentConfiguration(
            apiKey: nil,
            model: model(environment: environment, searchPaths: searchPaths),
            keySource: nil
        )
    }

    /// Resolved independently of the key: a `.env` that only sets the model is
    /// a reasonable thing to have next to one that only sets the key.
    private static func model(environment: [String: String], searchPaths: [URL]) -> String {
        if let fromEnvironment = environment["OPENAI_MODEL"]?.nilIfBlank { return fromEnvironment }
        for directory in searchPaths {
            if let fromFile = DotEnv.parse(fileAt: directory.appendingPathComponent(".env"))["OPENAI_MODEL"]?.nilIfBlank {
                return fromFile
            }
        }
        return defaultModel
    }

    /// Where Settings writes a key typed into it: the one search path both
    /// apps can reach. PetAgent shows the field, PetAgentClient runs the
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
            .appendingPathComponent("Library/Application Support/PetAgent", isDirectory: true)
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
        // …/pet-app/PetAgent/Agent/AgentConfiguration.swift -> …/pet-app
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Agent
            .deletingLastPathComponent() // PetAgent
            .deletingLastPathComponent() // pet-app
        #else
        return nil
        #endif
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
