//
//  BatteryStatus.swift
//  Shaydi
//
//  Notch · owner: 박해영 (Haeyoung Park)
//  boring.notch's battery indicator, ported -- byeolki, 2026-08-01: "다이
//  내믹 아일랜드 걍 Boring Notch 클론코딩을 기반으로 하고". Reads IOKit's
//  power-source dictionary directly (the same fields boring.notch's own
//  BatteryActivityManager reads), not the coarser ProcessInfo.batteryState.
//

import Foundation
import IOKit.ps

struct BatteryStatus: Equatable {
    let percentage: Int
    let isCharging: Bool

    /// Pure parsing seam -- `BatteryMonitor` supplies the real IOKit
    /// dictionary; a unit test supplies a literal one. `nil` if the source
    /// carries no usable capacity reading at all (desktop Macs with no
    /// battery report an empty power-source list upstream of this).
    static func parse(from description: [String: Any]) -> BatteryStatus? {
        guard
            let current = description[kIOPSCurrentCapacityKey] as? Int,
            let max = description[kIOPSMaxCapacityKey] as? Int,
            max > 0
        else {
            return nil
        }
        let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
        let percentage = Int((Double(current) / Double(max) * 100).rounded())
        return BatteryStatus(percentage: percentage, isCharging: isCharging)
    }
}
