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
        // The window's floor depends on what it is showing, so there are two
        // of them (2026-08-15). One number cannot be right for both: it was
        // 960, which is generous for a chat and 160pt short of a chat plus an
        // editor -- the shortfall came out of the file tree, whose rows were
        // clipped rather than truncated at the smallest window.
        //
        // Both are derived from the panes rather than picked: each is the sum
        // of the minimum widths the views inside actually declare, plus the
        // splitters between them. Change a pane's minimum and change these.

        /// Sidebar (180) + chat column (380). The chat column's floor is what
        /// keeps the composer's placeholder on one line.
        static let windowMinWidth: CGFloat = 560
        /// The above, plus the editor pane: file tree (180) + code (360), and
        /// two splitters.
        static let windowMinWidthWithEditor: CGFloat = 1120
        /// The detached editor window: file tree (180) + code (360), without
        /// the chat's share of the split.
        static let editorWindowMinWidth: CGFloat = 540
        static let windowMinHeight: CGFloat = 640
    }

    /// The shapes surfaces are cut to. Spelled once here rather than
    /// `RoundedRectangle(cornerRadius:style:)` at every call site.
    enum Shapes {
        static let card = RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
        static let row = RoundedRectangle(cornerRadius: Metrics.rowCornerRadius, style: .continuous)
    }
}
