//
//  RelativeTimeTests.swift
//  PuckTests
//
//  Ports chat-web/src/lib/relative-time.test.ts, which went with chat-web.
//  The rules are the sidebar's, not the formatter's, so they need to keep
//  being asserted somewhere.
//

import XCTest
@testable import Puck

final class RelativeTimeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func ago(_ interval: TimeInterval) -> Date {
        now.addingTimeInterval(-interval)
    }

    func testNoActivityRendersNothing() {
        // The sidebar shows a session that has never run; an empty string is
        // what leaves the row clean, not "0분".
        XCTAssertEqual(RelativeTime.short(since: nil, now: now), "")
    }

    func testUnderAMinuteIsJustNow() {
        XCTAssertEqual(RelativeTime.short(since: ago(0), now: now), "방금")
        XCTAssertEqual(RelativeTime.short(since: ago(59), now: now), "방금")
    }

    func testMinutesThenHoursThenDays() {
        XCTAssertEqual(RelativeTime.short(since: ago(60), now: now), "1분")
        XCTAssertEqual(RelativeTime.short(since: ago(59 * 60), now: now), "59분")
        XCTAssertEqual(RelativeTime.short(since: ago(60 * 60), now: now), "1시간")
        XCTAssertEqual(RelativeTime.short(since: ago(23 * 3600), now: now), "23시간")
    }

    func testOneDayIsYesterdayRatherThanOneDay() {
        XCTAssertEqual(RelativeTime.short(since: ago(24 * 3600), now: now), "어제")
        XCTAssertEqual(RelativeTime.short(since: ago(2 * 24 * 3600), now: now), "2일")
        XCTAssertEqual(RelativeTime.short(since: ago(6 * 24 * 3600), now: now), "6일")
    }

    func testAWeekOrMoreFallsBackToADate() {
        let old = ago(30 * 24 * 3600)
        let components = Calendar.current.dateComponents([.month, .day], from: old)

        XCTAssertEqual(
            RelativeTime.short(since: old, now: now),
            "\(components.month!)월 \(components.day!)일"
        )
    }

    func testAClockThatMovedBackwardsDoesNotRenderANegativeAge() {
        // The TS version guarded this after a NaN reached the date branch and
        // rendered "NaN월 NaN일" in the sidebar. Swift can't produce NaN here,
        // but an NTP correction or a timezone edit can still put lastActivityAt
        // in the future.
        XCTAssertEqual(RelativeTime.short(since: now.addingTimeInterval(120), now: now), "방금")
    }
}
