//
//  EditorTabStripViewTests.swift
//  Puck
//

import XCTest
@testable import Puck

final class EditorTabStripViewTests: XCTestCase {
    func test_stripHeight_matchesNamedToken() {
        XCTAssertEqual(EditorTabStripView.stripHeight, ClientTheme.Metrics.spacingLarge * 2 + 4)
    }
}
