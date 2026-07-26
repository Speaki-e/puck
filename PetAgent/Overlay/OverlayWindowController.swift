//
//  OverlayWindowController.swift
//  PetAgent
//
//  F1 · owner: Sangwoo Kang
//  Creates/positions one overlay window per display, orderOut when idle
//
//  TODO(perf, plan/02_pet-app.md F1): downshift frame rate 60->15 after 30s
//  idle, and orderOut windows on displays with no character on them. Needs
//  the FSM wired in (P2+) to know where the character actually is; placing
//  one window per display unconditionally is the correct starting point.

import AppKit

/// Creates and positions one OverlayWindow (hosting a PetARView) per
/// display, rebuilding whenever ScreenManager reports a display change.
/// Window frames use ScreenManager's `appKitFrames` (real AppKit screen
/// coordinates), NOT `normalizedScreenFrames` — the normalized, Y-down space
/// is for movement/FSM logic only; actual window placement needs AppKit's
/// own bottom-left-origin coordinates (plan/02_pet-app.md F3: "모든 이동
/// 로직은 픽셀 좌표만 다루고 렌더 직전에만 3D 변환").
final class OverlayWindowController {
    private(set) var windows: [OverlayWindow] = []
    private let screenManager: ScreenManager

    /// Fires every time `windows` is torn down and recreated (initial start()
    /// and every real display change) -- consumers holding a reference into a
    /// specific window/PetARView (e.g. the avatar's RealityKit parent entity)
    /// must re-fetch it here or they're left pointing at an orphaned window.
    var onWindowsRebuilt: (() -> Void)?

    init(screenManager: ScreenManager) {
        self.screenManager = screenManager
    }

    func start() {
        rebuildWindows(for: screenManager.current)
        screenManager.onChange = { [weak self] space in
            self?.rebuildWindows(for: space)
        }
        screenManager.startObserving()
    }

    func stop() {
        screenManager.stopObserving()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func rebuildWindows(for space: GlobalScreenSpace) {
        windows.forEach { $0.orderOut(nil) }
        windows = space.appKitFrames.map { frame in
            let window = OverlayWindow(screenFrame: frame)
            let arView = PetARView(frame: NSRect(origin: .zero, size: frame.size))
            arView.autoresizingMask = [.width, .height]
            window.contentView = arView
            window.orderFrontRegardless()
            return window
        }
        onWindowsRebuilt?()
    }
}
