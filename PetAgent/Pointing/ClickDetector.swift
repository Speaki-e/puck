//
//  ClickDetector.swift
//  PetAgent
//
//  F10 · owner: Haeyoung Park
//  Global click monitor, checks whether the click point is within a target's frame
//

import AppKit
import CoreGraphics

/// What PointingController needs from click detection — kept as a protocol
/// so it's testable without a real global event monitor.
protocol ClickDetectorProviding: AnyObject {
    var onClickInsideTarget: (() -> Void)? { get set }
    func startMonitoring(targetFrame: CGRect)
    func stopMonitoring()
}

final class ClickDetector: ClickDetectorProviding {
    var onClickInsideTarget: (() -> Void)?

    private var monitor: Any?
    private var targetFrame: CGRect = .zero

    /// Calling this again without an intervening stopMonitoring() (e.g.
    /// re-pointing at a new target before the previous point released)
    /// previously leaked the earlier global monitor.
    func startMonitoring(targetFrame: CGRect) {
        stopMonitoring()
        self.targetFrame = targetFrame
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            self?.handleClick(at: NSEvent.mouseLocation)
        }
    }

    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handleClick(at location: CGPoint) {
        if Self.isClick(at: location, insideTargetFrame: targetFrame) {
            onClickInsideTarget?()
        }
    }

    /// Pure hit test — both values must already be in the same coordinate space.
    static func isClick(at location: CGPoint, insideTargetFrame frame: CGRect) -> Bool {
        frame.contains(location)
    }
}
