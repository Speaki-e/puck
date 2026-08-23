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

    /// Closing the window takes the tank with it. Pinning is what keeps the
    /// pet home while the window sits behind something else, and it must not
    /// keep it home when there is no window -- the pet was left standing in
    /// the space where the window had been.
    func test_aClosedWindowHasNoTankEvenWhilePinned() {
        let store = ClientWindowStore(sender: UserInputSender(transport: { nil }))
        store.isTankPinned = true
        store.setTankSegment(CGRect(x: 200, y: 800, width: 600, height: 90), for: .chat)

        store.setWindowIsOpen(false)

        XCTAssertFalse(store.windowIsOpen)
        XCTAssertFalse(store.windowIsFrontmost, "a closed window is not the one being looked at either")
    }

    /// The segments are remembered, so reopening does not depend on a layout
    /// pass arriving before the pet is asked for.
    func test_reopeningRestoresTheTank() {
        let store = ClientWindowStore(sender: UserInputSender(transport: { nil }))
        let frame = CGRect(x: 200, y: 800, width: 600, height: 90)
        store.setTankSegment(frame, for: .chat)
        store.setWindowIsOpen(false)

        store.setWindowIsOpen(true)

        XCTAssertTrue(store.windowIsOpen)
        XCTAssertEqual(store.tankFrame, frame)
    }
}
