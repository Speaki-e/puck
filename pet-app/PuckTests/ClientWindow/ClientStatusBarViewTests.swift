//
//  ClientStatusBarViewTests.swift
//  Puck
//

import XCTest
@testable import Puck

final class ClientStatusBarViewTests: XCTestCase {
    func test_dotStatus_noProject_isIdle() {
        XCTAssertEqual(dotStatus(for: .noProject), .idle)
    }

    func test_dotStatus_ready_isSuccess() {
        XCTAssertEqual(dotStatus(for: .ready(rootURL: URL(fileURLWithPath: "/tmp"))), .success)
    }

    func test_dotStatus_unavailable_isError() {
        XCTAssertEqual(dotStatus(for: .unavailable(.pathMissing)), .error)
        XCTAssertEqual(dotStatus(for: .unavailable(.notADirectory)), .error)
        XCTAssertEqual(dotStatus(for: .unavailable(.notReadable)), .error)
    }
}
