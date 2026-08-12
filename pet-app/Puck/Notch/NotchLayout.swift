//
//  NotchLayout.swift
//  Puck
//
//  Notch · owner: 박해영 (Haeyoung Park)
//  Pure placement math for the notch window.
//

import CoreGraphics

/// Where the notch window sits: always horizontally centered on the screen,
/// its top edge pinned to `topY` regardless of size -- so collapsing or
/// expanding only ever grows/shrinks it downward, away from the menu bar,
/// rather than shifting where its top edge lands.
enum NotchLayout {
    static func frame(screenMidX: CGFloat, topY: CGFloat, size: CGSize) -> CGRect {
        CGRect(
            x: screenMidX - size.width / 2,
            y: topY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
