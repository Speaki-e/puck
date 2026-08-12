//
//  ClientTheme.swift
//  Puck
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  Type/spacing/shape tokens for the client window -- theme-independent
//  (colors live in ClientPalette/ClientThemeStyle instead, see 2026-08-01's
//  design-system rebuild). Everything the client window's views draw with
//  should come from here or ClientPalette rather than ad hoc system colors/
//  fonts, so the look stays consistent and has one place to retune.
//

import SwiftUI

enum ClientTheme {
    // workspace (the source of truth, see ClientPalette) sets its type in
    // Geist, which pet-app doesn't bundle -- the system default design is
    // the closer approximation without adding a font dependency here.
    enum Typography {
        static let sectionHeader = Font.system(.caption).weight(.semibold)
        static let workspaceName = Font.system(.body).weight(.medium)
        static let sessionTitle = Font.system(.callout)
        static let messageBody = Font.system(.body)
        static let toolLabel = Font.system(.callout).weight(.medium)
        static let mono = Font.system(.caption, design: .monospaced)
        static let summary = Font.system(.callout).weight(.semibold)
        /// The empty-state greeting.
        static let greeting = Font.system(.largeTitle).weight(.bold)
        /// The line under the greeting.
        static let greetingSubtitle = Font.system(.body)
        /// The example-prompt chips under the greeting, and the disclaimer
        /// caption under the input bar.
        static let caption = Font.system(.caption)
        /// Sender labels above a message bubble ("나" / the app's name).
        static let senderLabel = Font.system(.caption2).weight(.semibold)
    }

    enum Metrics {
        /// 2026-08-01 rebuild: a real, non-popover sidebar (ClientSidebarView)
        /// replaces the icon-only rail -- collapsible between these two widths.
        /// 2026-08-02: widths pulled to match byeolki's 5 Figma references
        /// exactly (220/68), not just "close enough" approximations.
        static let sidebarWidthExpanded: CGFloat = 220
        static let sidebarWidthCollapsed: CGFloat = 68
        static let railButtonSize: CGFloat = 36
        /// The centered column width the transcript, empty state, and input
        /// bar all cap themselves to.
        static let contentMaxWidth: CGFloat = 720
        /// A single message bubble's own cap, well short of `contentMaxWidth`
        /// -- long line lengths hurt readability regardless of how wide the
        /// window is, the same reason chat UIs generally cap a bubble's width
        /// even in a wide column.
        static let bubbleMaxWidth: CGFloat = 420
        static let spacingSmall: CGFloat = 6
        static let spacingMedium: CGFloat = 10
        static let spacingLarge: CGFloat = 16
        /// Matches workspace's own radii (src/renderer/styles.css: 12px
        /// panels, 6px buttons/rows) -- see ClientPalette.
        static let bubbleCornerRadius: CGFloat = 10
        static let cardCornerRadius: CGFloat = 12
        static let rowCornerRadius: CGFloat = 6
        /// The small sender avatar drawn above each message bubble.
        static let avatarSize: CGFloat = 22
        /// The client window's own floor -- sidebar expanded (220) + the main
        /// column's own minimum (420), rounded up a little for breathing
        /// room. `ClientWindowView`'s SwiftUI `.frame(minWidth:minHeight:)`
        /// and `PuckClient/AppDelegate`'s AppKit-level `NSWindow.minSize`
        /// both read this single constant -- they used to disagree (640/420
        /// vs. the enforced 760/520), which meant the SwiftUI-declared
        /// minimum was never actually reachable and the two numbers could
        /// silently drift apart again the next time either one changed.
        static let windowMinWidth: CGFloat = 960
        static let windowMinHeight: CGFloat = 640
    }

    /// The shapes surfaces are cut to. Spelled once here rather than
    /// `RoundedRectangle(cornerRadius:style:)` at every call site -- the
    /// corner style has to match across surfaces or the window stops looking
    /// like one system.
    enum Shapes {
        static let bubble = RoundedRectangle(cornerRadius: Metrics.bubbleCornerRadius, style: .continuous)
        static let card = RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
        static let row = RoundedRectangle(cornerRadius: Metrics.rowCornerRadius, style: .continuous)
        static let panel = RoundedRectangle(cornerRadius: 12, style: .continuous)
    }
}
