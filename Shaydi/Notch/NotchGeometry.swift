//
//  NotchGeometry.swift
//  Shaydi
//
//  Notch · owner: 박해영 (Haeyoung Park)
//  Pure math for sizing the collapsed pill to match the screen it's on --
//  ported from boring.notch's getClosedNotchSize (sizing/matters.swift).
//  On a real notched Mac this makes the collapsed pill exactly the
//  physical notch's own width/height, so it reads as an extension of the
//  hardware cutout instead of a floating badge guessed at a fixed size --
//  byeolki, 2026-08-01, after cloning boring.notch's source to fix "다이내믹
//  아일랜드 쪽 파트가 이상한데".
//

import CoreGraphics

/// The handful of NSScreen values NotchGeometry needs, pulled out so tests
/// can construct them without a live NSScreen -- same reasoning as
/// NotchWindowController's screenFrameProvider injection.
struct NotchScreenMetrics: Equatable {
    var screenWidth: CGFloat
    /// `NSScreen.safeAreaInsets.top` -- zero on a Mac with no physical
    /// notch (external display, pre-2021 MacBook, non-Pro Air).
    var notchHeight: CGFloat
    /// `NSScreen.auxiliaryTopLeftArea?.width` / `...TopRightArea?.width` --
    /// the two menu-bar segments flanking the real notch. nil on a
    /// non-notched screen or when the API has nothing to report.
    var auxiliaryLeftWidth: CGFloat?
    var auxiliaryRightWidth: CGFloat?
    /// `screen.frame.maxY - screen.visibleFrame.maxY` -- used only as the
    /// collapsed pill's height on a non-notched screen, where there's no
    /// real notch height to match.
    var menuBarHeight: CGFloat
}

enum NotchGeometry {
    /// The pre-2026-08-01 hardcoded pill size -- kept as the fallback for
    /// whichever value real screen metrics can't supply.
    static let fallbackSize = CGSize(width: 170, height: 24)

    static func closedSize(for metrics: NotchScreenMetrics) -> CGSize {
        guard metrics.notchHeight > 0 else {
            let height = metrics.menuBarHeight > 0 ? metrics.menuBarHeight : fallbackSize.height
            return CGSize(width: fallbackSize.width, height: height)
        }

        guard let left = metrics.auxiliaryLeftWidth, let right = metrics.auxiliaryRightWidth else {
            return CGSize(width: fallbackSize.width, height: metrics.notchHeight)
        }

        let width = metrics.screenWidth - left - right + 4
        return CGSize(width: width, height: metrics.notchHeight)
    }
}
