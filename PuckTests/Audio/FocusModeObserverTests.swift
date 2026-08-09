//
//  FocusModeObserverTests.swift
//  Puck
//
//  F5 test · owner: 강상우 (Sangwoo Kang)
//  Only verifies the notification wiring itself (posting the known
//  notification name flips state and fires onChange). Whether macOS still
//  posts this notification for real Focus/DND changes on this OS version is
//  NOT verified here — see FocusModeObserver's doc comment.
//

import XCTest
@testable import Puck

final class FocusModeObserverTests: XCTestCase {
    func test_receivingNotification_togglesStateAndFiresOnChange() {
        let observer = FocusModeObserver()
        let expectation = expectation(description: "onChange fired")
        var receivedValue: Bool?

        observer.onChange = { value in
            receivedValue = value
            expectation.fulfill()
        }
        observer.startObserving()
        defer { observer.stopObserving() }

        XCTAssertFalse(observer.isFocusActive)

        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.apple.notificationcenterui.dndStatusChanged"),
            object: nil
        )

        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(receivedValue, true)
        XCTAssertTrue(observer.isFocusActive)
    }

    func test_startAndStopObserving_doNotCrash() {
        let observer = FocusModeObserver()
        observer.startObserving()
        observer.stopObserving()
        observer.stopObserving() // idempotent
    }
}
