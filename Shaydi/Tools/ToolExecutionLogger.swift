//
//  ToolExecutionLogger.swift
//  Shaydi
//
//  F11 · owner: Haeyoung Park
//  Records tool_exec_start/end in the protocol section 7 log format
//

import Foundation

enum ToolExecutionLogEvent: Equatable {
    case execStart(id: String)
    case execEnd(id: String, ok: Bool)
}

protocol ToolExecutionLogging {
    func log(_ event: ToolExecutionLogEvent)
}

/// One JSON Lines entry, formatted per protocol repo section 7 (joinable
/// across agent/pet-app/workspace logs by `id`).
struct ToolExecutionLogLine: Encodable {
    let event: ToolExecutionLogEvent
    let timestamp: String

    private enum CodingKeys: String, CodingKey {
        case ts, src, kind, id, ok
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .ts)
        try container.encode("pet-app", forKey: .src)
        switch event {
        case .execStart(let id):
            try container.encode("tool_exec_start", forKey: .kind)
            try container.encode(id, forKey: .id)
        case .execEnd(let id, let ok):
            try container.encode("tool_exec_end", forKey: .kind)
            try container.encode(id, forKey: .id)
            try container.encode(ok, forKey: .ok)
        }
    }
}

/// Appends log lines to ~/Library/Application Support/Shaydi/logs/, one
/// file per day (UTC). Thin file-I/O wrapper — not unit tested beyond
/// ToolExecutionLogLine's pure formatting.
final class ToolExecutionLogger: ToolExecutionLogging {
    static let defaultLogDirectory: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shaydi", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
    }()

    private let directory: URL
    private let queue = DispatchQueue(label: "Shaydi.ToolExecutionLogger")

    init(directory: URL = ToolExecutionLogger.defaultLogDirectory) {
        self.directory = directory
    }

    func log(_ event: ToolExecutionLogEvent) {
        let line = ToolExecutionLogLine(event: event, timestamp: ISO8601DateFormatter().string(from: Date()))
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
