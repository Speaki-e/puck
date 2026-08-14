//
//  PathContainmentTests.swift
//  Puck
//

import XCTest
@testable import Puck

final class PathContainmentTests: XCTestCase {
    func test_rootItself_isInside() {
        XCTAssertTrue(PathContainment.isInside(root: "/a/b", candidate: "/a/b"))
    }

    func test_childPath_isInside() {
        XCTAssertTrue(PathContainment.isInside(root: "/a/b", candidate: "/a/b/c"))
    }

    func test_siblingWithSharedPrefix_isNotInside() {
        // "/a/bc" shares the "/a/b" text prefix but is not inside "/a/b".
        XCTAssertFalse(PathContainment.isInside(root: "/a/b", candidate: "/a/bc"))
    }

    func test_parentPath_isNotInside() {
        XCTAssertFalse(PathContainment.isInside(root: "/a/b", candidate: "/a"))
    }

    func test_unrelatedAbsolutePath_isNotInside() {
        XCTAssertFalse(PathContainment.isInside(root: "/a/b", candidate: "/etc/passwd"))
    }

    func test_rootWithTrailingSlash_normalizesTheSameAsWithout() {
        XCTAssertTrue(PathContainment.isInside(root: "/a/b/", candidate: "/a/b/c"))
        XCTAssertTrue(PathContainment.isInside(root: "/a/b/", candidate: "/a/b"))
    }
}
