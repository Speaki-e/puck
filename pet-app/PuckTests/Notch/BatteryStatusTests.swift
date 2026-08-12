//
//  BatteryStatusTests.swift
//  Puck
//
//  Notch test · owner: 박해영 (Haeyoung Park)
//  byeolki, 2026-08-01: "다이내믹 아일랜드 걍 Boring Notch 클론코딩을
//  기반으로 하고" -- boring.notch's own battery indicator reads IOKit's
//  power-source dictionary directly (kIOPSCurrentCapacityKey/
//  kIOPSMaxCapacityKey/"Is Charging"), not ProcessInfo.batteryState. This
//  is the pure parsing seam: real IOKit calls aren't fakeable in a unit
//  test, but the dictionary -> BatteryStatus conversion is.
//

import XCTest
import IOKit.ps
@testable import Puck

final class BatteryStatusTests: XCTestCase {
    func test_parses_percentageAndCharging() {
        let description: [String: Any] = [
            kIOPSCurrentCapacityKey: 42,
            kIOPSMaxCapacityKey: 100,
            kIOPSIsChargingKey: true,
        ]

        let status = BatteryStatus.parse(from: description)

        XCTAssertEqual(status?.percentage, 42)
        XCTAssertEqual(status?.isCharging, true)
    }

    func test_roundsPercentage_whenMaxCapacityIsntOneHundred() {
        let description: [String: Any] = [
            kIOPSCurrentCapacityKey: 33,
            kIOPSMaxCapacityKey: 50,
            kIOPSIsChargingKey: false,
        ]

        // 33/50 = 66%.
        XCTAssertEqual(BatteryStatus.parse(from: description)?.percentage, 66)
    }

    func test_missingIsChargingKey_defaultsToNotCharging() {
        let description: [String: Any] = [
            kIOPSCurrentCapacityKey: 80,
            kIOPSMaxCapacityKey: 100,
        ]

        XCTAssertEqual(BatteryStatus.parse(from: description)?.isCharging, false)
    }

    func test_missingCapacityKeys_returnsNil() {
        XCTAssertNil(BatteryStatus.parse(from: [:]))
    }

    func test_zeroMaxCapacity_returnsNil() {
        let description: [String: Any] = [
            kIOPSCurrentCapacityKey: 0,
            kIOPSMaxCapacityKey: 0,
        ]

        XCTAssertNil(BatteryStatus.parse(from: description))
    }
}
