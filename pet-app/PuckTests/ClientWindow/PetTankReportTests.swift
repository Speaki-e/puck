//
//  PetTankReportTests.swift
//  Puck
//
//  The tank spans the chat column and, when it is open, the editor column.
//  Each reports its own rect; what the pet gets is the union, because the
//  pet crosses the split's divider as if it were not there.
//

import XCTest
import CoreGraphics
@testable import Puck

final class PetTankReportTests: XCTestCase {
    func test_theChatSegmentAloneIsTheTank() {
        let store = ClientWindowStore(sender: UserInputSender(transport: { nil }))

        store.setTankSegment(CGRect(x: 200, y: 800, width: 600, height: 90), for: .chat)

        XCTAssertEqual(store.tankFrame, CGRect(x: 200, y: 800, width: 600, height: 90))
    }

    func test_withTheEditorOpen_theTankIsTheUnion() {
        let store = ClientWindowStore(sender: UserInputSender(transport: { nil }))

        store.setTankSegment(CGRect(x: 200, y: 800, width: 600, height: 90), for: .chat)
        store.setTankSegment(CGRect(x: 810, y: 800, width: 500, height: 90), for: .editor)

        XCTAssertEqual(store.tankFrame, CGRect(x: 200, y: 800, width: 1110, height: 90))
    }

    /// Closing the editor takes its half of the tank with it.
    func test_clearingTheEditorSegmentShrinksTheTank() {
        let store = ClientWindowStore(sender: UserInputSender(transport: { nil }))
        store.setTankSegment(CGRect(x: 200, y: 800, width: 600, height: 90), for: .chat)
        store.setTankSegment(CGRect(x: 810, y: 800, width: 500, height: 90), for: .editor)

        store.setTankSegment(nil, for: .editor)

        XCTAssertEqual(store.tankFrame, CGRect(x: 200, y: 800, width: 600, height: 90))
    }

    func test_noSegmentsMeansNoTank() {
        let store = ClientWindowStore(sender: UserInputSender(transport: { nil }))

        XCTAssertNil(store.tankFrame)
    }
}
