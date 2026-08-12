//
//  NotchLayoutTests.swift
//  Puck
//
//  Notch test · owner: 박해영 (Haeyoung Park)
//  Pure placement math for the notch window -- no live NSScreen/NSWindow
//  needed to verify it centers horizontally and pins its top edge.
//

import XCTest
import CoreGraphics
@testable import Puck

final class NotchLayoutTests: XCTestCase {
    func test_frame_isHorizontallyCenteredOnScreenMidX() {
        let frame = NotchLayout.frame(screenMidX: 1000, topY: 800, size: CGSize(width: 200, height: 30))

        XCTAssertEqual(frame.midX, 1000)
    }

    func test_frame_topEdgeIsPinnedToTopY() {
        let frame = NotchLayout.frame(screenMidX: 1000, topY: 800, size: CGSize(width: 200, height: 30))

        XCTAssertEqual(frame.maxY, 800)
    }

    func test_expandedSize_growsDownward_keepingTheSameTopEdge() {
        // AppKit's origin is bottom-left, so growing the panel *downward* on
        // screen (away from the menu bar, never through it) means the
        // window's height grows while its top edge (origin.y + height)
        // stays fixed and only origin.y itself decreases.
        let collapsed = NotchLayout.frame(screenMidX: 1000, topY: 800, size: CGSize(width: 160, height: 24))
        let expanded = NotchLayout.frame(screenMidX: 1000, topY: 800, size: CGSize(width: 260, height: 140))

        XCTAssertEqual(collapsed.maxY, expanded.maxY)
        XCTAssertLessThan(expanded.minY, collapsed.minY)
    }

    func test_widerExpandedSize_stillCentersOnTheSameMidX() {
        let collapsed = NotchLayout.frame(screenMidX: 1000, topY: 800, size: CGSize(width: 160, height: 24))
        let expanded = NotchLayout.frame(screenMidX: 1000, topY: 800, size: CGSize(width: 260, height: 140))

        XCTAssertEqual(collapsed.midX, expanded.midX)
    }
}
