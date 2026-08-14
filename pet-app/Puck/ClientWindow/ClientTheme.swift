//
//  ClientTheme.swift
//  Puck
//
//  Design system v2 (2026-08-14) -- see docs/decisions.md. Colors
//  live in ClientPalette; this file is type/spacing/shape. Pruned to only
//  the tokens still actually consumed -- the 2026-08-13 chat-web migration
//  (docs/decisions.md) deleted ChatView.swift/ClientSidebarView.swift but
//  left their token definitions here; this rewrite removes them rather
//  than redesigning values nothing reads anymore.
//

import SwiftUI

enum ClientTheme {
    enum Typography {
        static let sectionHeader = Font.system(.caption).weight(.semibold)
        static let workspaceName = Font.system(.callout).weight(.medium)
        static let sessionTitle = Font.system(.footnote)
        static let toolLabel = Font.system(.footnote).weight(.medium)
        static let mono = Font.system(.caption, design: .monospaced)
        static let caption = Font.system(.caption2)
    }

    enum Metrics {
        static let spacingSmall: CGFloat = 4
        static let spacingMedium: CGFloat = 8
        static let spacingLarge: CGFloat = 12
        /// v2: matches chat-web/workspace's shrunk --radius base (Task 6).
        static let cardCornerRadius: CGFloat = 6
        static let rowCornerRadius: CGFloat = 4
        /// The client window's own floor -- unchanged by v2, not a density
        /// concern. See git blame for the original reasoning (sidebar +
        /// main column minimums) if this ever needs to move again.
        static let windowMinWidth: CGFloat = 960
        static let windowMinHeight: CGFloat = 640
    }

    /// The shapes surfaces are cut to. Spelled once here rather than
    /// `RoundedRectangle(cornerRadius:style:)` at every call site.
    enum Shapes {
        static let card = RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
        static let row = RoundedRectangle(cornerRadius: Metrics.rowCornerRadius, style: .continuous)
    }
}
