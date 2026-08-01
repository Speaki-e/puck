//
//  NotchShape.swift
//  Shaydi
//
//  Notch · owner: 박해영 (Haeyoung Park)
//  The real notch's flare -- concave curves at the top corners flowing
//  into convex curves at the bottom, not a plain rounded rectangle. Ported
//  from boring.notch (components/Notch/NotchShape.swift, itself from
//  https://github.com/MrKai77/DynamicNotchKit), MIT-licensed -- byeolki,
//  2026-08-01, after cloning boring.notch's source to fix "다이내믹 아일랜드
//  쪽 파트가 이상한데": the first pass used RoundedRectangle, which reads as
//  a floating pill rather than an extension of the screen's own top edge.
//

import SwiftUI

struct NotchShape: Shape {
    private var topCornerRadius: CGFloat
    private var bottomCornerRadius: CGFloat

    init(topCornerRadius: CGFloat, bottomCornerRadius: CGFloat) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    /// Lets SwiftUI interpolate both radii smoothly across the
    /// collapsed<->expanded transition, the same way a plain
    /// RoundedRectangle's cornerRadius already animated.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )

        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))

        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))

        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))

        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        return path
    }
}

/// The two corner-radius pairs the notch morphs between -- collapsed hugs
/// the real notch's own tight bezel curve, expanded flares out like
/// boring.notch's own opened state (values ported as-is: they're tuned to
/// how a notch bezel actually curves, not proportional to window size).
enum NotchCornerRadii {
    static let collapsed: (top: CGFloat, bottom: CGFloat) = (top: 6, bottom: 14)
    static let expanded: (top: CGFloat, bottom: CGFloat) = (top: 19, bottom: 24)
}
