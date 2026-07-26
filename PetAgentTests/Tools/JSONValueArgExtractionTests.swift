//
//  JSONValueArgExtractionTests.swift
//  PetAgent
//
//  F11 test · owner: Haeyoung Park
//  Shared JSONValue arg-extraction helpers used across tool handlers.
//

import XCTest
import CoreGraphics
@testable import PetAgent

final class JSONValueArgExtractionTests: XCTestCase {
    func test_extractString_returnsValue_whenKeyIsAString() {
        let args = JSONValue.object(["command": .string("ls -la")])
        XCTAssertEqual(args.extractString(key: "command"), "ls -la")
    }

    func test_extractString_returnsNil_whenKeyMissing() {
        let args = JSONValue.object([:])
        XCTAssertNil(args.extractString(key: "command"))
    }

    func test_extractString_returnsNil_whenKeyIsWrongType() {
        let args = JSONValue.object(["command": .number(42)])
        XCTAssertNil(args.extractString(key: "command"))
    }

    func test_extractString_returnsNil_whenArgsIsNotAnObject() {
        let args = JSONValue.string("not an object")
        XCTAssertNil(args.extractString(key: "command"))
    }

    func test_extractFrame_returnsValue_whenFieldsPresent() {
        let args = JSONValue.object([
            "frame": .object(["x": .number(1), "y": .number(2), "width": .number(3), "height": .number(4)]),
        ])
        XCTAssertEqual(args.extractFrame(), CGRect(x: 1, y: 2, width: 3, height: 4))
    }
}
