//
//  AppLogger.swift
//  Shaydi
//
//  Shared · owner: Sangwoo Kang / Haeyoung Park
//  Shared logging utility (~/Library/Application Support/Shaydi/logs/)
//
//  General app diagnostics — distinct from ToolExecutionLogger (F11), which
//  writes the specific protocol section 7 tool_exec_start/end format joinable
//  across agent/pet-app/workspace logs. This one is just "what happened".

import Foundation

enum LogLevel: String, Encodable {
    case debug, info, warning, error
}

struct AppLogLine: Encodable {
    let ts: String
    let level: LogLevel
    let message: String
}

/// Thin file-I/O wrapper — not unit tested beyond what AppLogLine's plain
/// Encodable conformance already guarantees.
final class AppLogger {
    static let shared = AppLogger(directory: isRunningTests ? testLogDirectory : defaultLogDirectory)

    static let defaultLogDirectory: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shaydi", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
    }()

    /// The test bundle exercises SpriteAvatar, CharacterController and the
    /// rest with throwaway fixtures, and every failure they log went into the
    /// *real* diagnostics log -- "Failed to load avatar sprite at /var/.../
    /// walk.png" and "unregistered StateKind walk" appeared there on every
    /// `xcodebuild test`, indistinguishable from something the running app
    /// had hit. Tests write to a temp directory instead.
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private static let testLogDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ShaydiTestLogs", isDirectory: true)

    private let directory: URL
    private let queue = DispatchQueue(label: "Shaydi.AppLogger")

    init(directory: URL = AppLogger.defaultLogDirectory) {
        self.directory = directory
    }

    func log(_ level: LogLevel, _ message: String) {
        let line = AppLogLine(ts: ISO8601DateFormatter().string(from: Date()), level: level, message: message)
        queue.async { [directory] in
            guard var data = try? JSONEncoder().encode(line) else { return }
            data.append(0x0A)

            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent(Self.logFileName(for: Date()))

            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    private static func logFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date) + ".jsonl"
    }
}
