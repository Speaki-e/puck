//
//  BatteryMonitor.swift
//  Shaydi
//
//  Notch · owner: 박해영 (Haeyoung Park)
//  Live IOKit power-source observation -- same
//  IOPSNotificationCreateRunLoopSource pattern boring.notch's own
//  BatteryActivityManager uses, feeding BatteryStatus.parse(from:).
//

import Foundation
import IOKit.ps

final class BatteryMonitor {
    var onChange: ((BatteryStatus?) -> Void)?

    private var runLoopSource: CFRunLoopSource?

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard
            let source = IOPSNotificationCreateRunLoopSource({ context in
                guard let context else { return }
                Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue().refresh()
            }, context)?.takeRetainedValue()
        else {
            return
        }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        refresh()
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
    }

    private func refresh() {
        onChange?(Self.currentStatus())
    }

    private static func currentStatus() -> BatteryStatus? {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
            let source = sources.first,
            let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
        else {
            return nil
        }
        return BatteryStatus.parse(from: description)
    }
}
