//
//  ToolExecutionLoggerTests.swift
//  Shaydi
//
//  F11 test · owner: 박해영 (Haeyoung Park)
//  JSON Lines log formatting, per protocol/01_protocol.md section 7
//  ("로그 포맷 (분산 디버깅 표준)").
//

import XCTest
@testable import Shaydi

final class ToolExecutionLoggerTests: XCTestCase {
    func test_execStart_formatsWithoutOkField() throws {
        let line = ToolExecutionLogLine(event: .execStart(id: "t1"), timestamp: "2026-07-26T12:00:00.000Z")

        let data = try JSONEncoder().encode(line)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["src"] as? String, "pet-app")
        XCTAssertEqual(json?["kind"] as? String, "tool_exec_start")
        XCTAssertEqual(json?["id"] as? String, "t1")
        XCTAssertEqual(json?["ts"] as? String, "2026-07-26T12:00:00.000Z")
        XCTAssertNil(json?["ok"])
    }

    func test_execEnd_includesOkField() throws {
        let line = ToolExecutionLogLine(event: .execEnd(id: "t1", ok: false), timestamp: "2026-07-26T12:00:00.100Z")

        let data = try JSONEncoder().encode(line)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["kind"] as? String, "tool_exec_end")
        XCTAssertEqual(json?["ok"] as? Bool, false)
    }
}
