//
//  GitStatusReader.swift
//  Puck
//
//  Runs the two git commands GitStatusParser reads.
//
//  Two calls rather than one: porcelain v2 says what changed and the branch's
//  ahead/behind, and numstat says how much. Neither carries the other.
//

import Foundation

enum GitStatusReader {
    /// Where git usually is, in the order worth trying -- the same shape
    /// AcpAgentCommandResolver uses for node. A `Process` gets no login shell
    /// and so no PATH of the user's own.
    static let candidatePaths = ["/opt/homebrew/bin/git", "/usr/bin/git", "/usr/local/bin/git"]

    static func executable(fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> URL? {
        candidatePaths.first(where: fileExists).map { URL(fileURLWithPath: $0) }
    }

    /// nil when the directory is not a repository, or git is not installed --
    /// both are "there is nothing to show here" rather than errors worth
    /// putting on screen.
    static func read(projectPath: String) -> GitStatus? {
        guard let git = executable() else { return nil }
        guard let status = run(git, ["-C", projectPath, "status", "--porcelain=v2", "--branch"]) else { return nil }
        let numstat = run(git, ["-C", projectPath, "diff", "--numstat", "HEAD"]) ?? ""
        return GitStatusParser.parse(status: status, numstat: numstat)
    }

    /// nil on a non-zero exit, which for these two means "not a repository".
    private static func run(_ executable: URL, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        // Discarded on purpose: the only failure worth reacting to is the
        // exit status, and git's stderr on a non-repository would otherwise
        // reach the console of whoever launched the app.
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
