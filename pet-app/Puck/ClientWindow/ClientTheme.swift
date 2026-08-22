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
        /// A settings section's title. `.caption` was small enough that
        /// "일반" and "에이전트" read as captions on the rows below rather
        /// than as the headings they are.
        static let sectionHeader = Font.system(.subheadline).weight(.semibold)
        static let workspaceName = Font.system(.callout).weight(.medium)
        static let sessionTitle = Font.system(.footnote)
        static let toolLabel = Font.system(.footnote).weight(.medium)
        static let mono = Font.system(.caption, design: .monospaced)
        static let caption = Font.system(.caption2)

        // The agent's reply is read as a document rather than glanced at in a
        // balloon, so it gets its own scale instead of `.body` (13pt): 15pt is
        // one step up, the size the composer already types at, and it keeps a
        // ~75-character line inside the transcript column. Fixed sizes rather
        // than text styles because the headings have to stay *above* the body
        // -- `.headline` is 13pt on macOS, i.e. smaller than this body.
        static let transcriptBody = Font.system(size: 15)
        static let transcriptCode = Font.system(size: 13, design: .monospaced)

        static func transcriptHeading(level: Int) -> Font {
            switch level {
            case 1: return .system(size: 22, weight: .semibold)
            case 2: return .system(size: 19, weight: .semibold)
            default: return .system(size: 16, weight: .semibold)
            }
        }
    }

    enum Metrics {
        static let spacingSmall: CGFloat = 4
        static let spacingMedium: CGFloat = 8
        static let spacingLarge: CGFloat = 12
        /// Between one settings section and the next. Larger than the spacing
        /// inside a section, so the grouping is visible without a divider.
        static let sectionSpacing: CGFloat = 20
        /// Top and bottom of a settings window. Deliberately more than the
        /// horizontal padding: a short window reads as cramped long before a
        /// narrow one does, because the first and last rows sit against the
        /// title bar and the frame.
        static let windowEdgePadding: CGFloat = 20
        /// The transcript's text column. Every row in it -- message, tool
        /// card, approval banner -- is capped at this one measure and the
        /// column is centred, so widening the window adds margin instead of
        /// stretching the lines. ~75 characters at `transcriptBody`.
        static let transcriptColumnWidth: CGFloat = 640
        /// Kept outside the column, so the text never sits against the window
        /// chrome or the editor pane's divider. Fixed at every width -- the
        /// column is what gives way when the pane is narrow.
        static let transcriptHorizontalPadding: CGFloat = 24
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
        /// The above, plus the file explorer on the right (200) and the code
        /// column a file click opens, which splits the chat's column
        /// rather than adding one at the edge: sidebar (180), conversation
        /// (320), code (300), explorer (200), three splitters.
        static let windowMinWidthWithCode: CGFloat = 1040
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
