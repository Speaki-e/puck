//
//  JSONLinesDecoderTests.swift
//  PetAgent
//
//  Socket test · owner: 박해영 (Haeyoung Park)
//  Incremental JSON Lines parsing over an arbitrarily-chunked byte stream,
//  per protocol/01_protocol.md section 2 ("인코딩: JSON Lines").
//

import XCTest
@testable import PetAgent

final class JSONLinesDecoderTests: XCTestCase {
    private func line(_ json: String) -> Data {
        Data((json + "\n").utf8)
    }

    func test_feedsOneCompleteLine_returnsOneMessage() {
        var decoder = JSONLinesDecoder()
        let messages = decoder.feed(line(#"{"type":"event","event":"agent_thinking"}"#))

        XCTAssertEqual(messages, [.event(.agentThinking)])
    }

    func test_feedsPartialLine_returnsNothingUntilNewlineArrives() {
        var decoder = JSONLinesDecoder()
        let partial = Data(#"{"type":"event","event":"agent_thinking""#.utf8) // no closing brace, no newline

        XCTAssertEqual(decoder.feed(partial), [])
        XCTAssertEqual(decoder.feed(Data("}\n".utf8)), [.event(.agentThinking)])
    }

    func test_feedsMultipleLinesAtOnce_returnsAllMessages() {
        var decoder = JSONLinesDecoder()
        let chunk = line(#"{"type":"event","event":"agent_thinking"}"#)
            + line(#"{"type":"event","event":"tool_result","ok":true}"#)

        XCTAssertEqual(decoder.feed(chunk), [.event(.agentThinking), .event(.toolResult(ok: true))])
    }

    func test_malformedLine_isSkipped_subsequentLinesStillParse() {
        var decoder = JSONLinesDecoder()
        let chunk = line("not json") + line(#"{"type":"event","event":"agent_thinking"}"#)

        XCTAssertEqual(decoder.feed(chunk), [.event(.agentThinking)])
    }

    func test_emptyLine_isSkipped() {
        var decoder = JSONLinesDecoder()
        XCTAssertEqual(decoder.feed(Data("\n".utf8)), [])
    }
}
