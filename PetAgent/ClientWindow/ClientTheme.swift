//
//  ClientTheme.swift
//  PetAgent
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  A small, self-contained design system for the client window -- byeolki:
//  "자체 앱 만들듯이 새로 UI 디자인시스템 짜서 디자인해와" (default SwiftUI/
//  List chrome read as a generic macOS settings pane). Everything the client
//  window's views draw with should come from here rather than ad hoc system
//  colors/fonts, so the look stays consistent and has one place to retune.
//

import SwiftUI

enum ClientTheme {
    /// **No accent color** -- byeolki tried lime #A2E048 (deleted
    /// 2026-07-30), then a pumpkin accent, then removed that too
    /// (2026-07-31: "그냥 포인터 컬러 제거해줘"). Surfaces are Liquid Glass
    /// (see GlassSurface) and what distinguishes them is elevation and
    /// weight rather than hue. The only colors left are semantic status
    /// ones (a failed tool result has to be red whatever the palette is).
    enum Colors {
        /// Sidebar/toolbar chrome uses VisualEffectBackground (real
        /// NSVisualEffectView vibrancy), not a flat color here -- a flat
        /// Color reads as a plain settings pane no matter what tone it is.
        static let contentBackground = Color(nsColor: .textBackgroundColor)

        static let bubbleText = Color.primary

        static let success = Color.green
        static let failure = Color.red
        /// Approval is a state that must interrupt, so it keeps a hue.
        static let warning = Color.orange
        static let secondaryText = Color.secondary
    }

    enum Typography {
        static let sectionHeader = Font.system(.caption, design: .rounded).weight(.semibold)
        static let workspaceName = Font.system(.body, design: .rounded).weight(.medium)
        static let sessionTitle = Font.system(.callout, design: .rounded)
        static let messageBody = Font.system(.body)
        static let toolLabel = Font.system(.callout, design: .rounded).weight(.medium)
        static let mono = Font.system(.caption, design: .monospaced)
        static let summary = Font.system(.callout, design: .rounded).weight(.semibold)
    }

    enum Metrics {
        static let sidebarWidth: CGFloat = 232
        static let spacingSmall: CGFloat = 6
        static let spacingMedium: CGFloat = 10
        static let spacingLarge: CGFloat = 16
        static let bubbleCornerRadius: CGFloat = 16
        static let cardCornerRadius: CGFloat = 10
        static let rowCornerRadius: CGFloat = 8
    }

    /// The shapes glass is cut to. Spelled once here rather than
    /// `RoundedRectangle(cornerRadius:style:)` at every call site -- the
    /// corner style has to match across surfaces or the window stops looking
    /// like one material.
    enum Shapes {
        static let bubble = RoundedRectangle(cornerRadius: Metrics.bubbleCornerRadius, style: .continuous)
        static let card = RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
        static let row = RoundedRectangle(cornerRadius: Metrics.rowCornerRadius, style: .continuous)
        static let panel = RoundedRectangle(cornerRadius: 28, style: .continuous)
    }
}
