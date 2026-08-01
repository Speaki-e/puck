//
//  ClientTheme.swift
//  Shaydi
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
    enum Typography {
        static let sectionHeader = Font.system(.caption, design: .rounded).weight(.semibold)
        static let workspaceName = Font.system(.body, design: .rounded).weight(.medium)
        static let sessionTitle = Font.system(.callout, design: .rounded)
        static let messageBody = Font.system(.body)
        static let toolLabel = Font.system(.callout, design: .rounded).weight(.medium)
        static let mono = Font.system(.caption, design: .monospaced)
        static let summary = Font.system(.callout, design: .rounded).weight(.semibold)
        /// The empty-state greeting.
        static let greeting = Font.system(.largeTitle, design: .rounded).weight(.bold)
        /// The line under the greeting.
        static let greetingSubtitle = Font.system(.body, design: .rounded)
        /// The example-prompt chips under the greeting, and the disclaimer
        /// caption under the input bar.
        static let caption = Font.system(.caption, design: .rounded)
        /// Sender labels above a message bubble ("나" / the app's name).
        static let senderLabel = Font.system(.caption2, design: .rounded).weight(.semibold)
    }

    enum Metrics {
        /// 2026-08-01 rebuild: a real, non-popover sidebar (ClientSidebarView)
        /// replaces the icon-only rail -- collapsible between these two widths.
        static let sidebarWidthExpanded: CGFloat = 240
        static let sidebarWidthCollapsed: CGFloat = 56
        static let railButtonSize: CGFloat = 36
        /// The centered column width the transcript, empty state, and input
        /// bar all cap themselves to.
        static let contentMaxWidth: CGFloat = 720
        static let spacingSmall: CGFloat = 6
        static let spacingMedium: CGFloat = 10
        static let spacingLarge: CGFloat = 16
        static let bubbleCornerRadius: CGFloat = 18
        static let cardCornerRadius: CGFloat = 14
        static let rowCornerRadius: CGFloat = 12
        /// The small sender avatar drawn above each message bubble.
        static let avatarSize: CGFloat = 22
    }

    /// The shapes surfaces are cut to. Spelled once here rather than
    /// `RoundedRectangle(cornerRadius:style:)` at every call site -- the
    /// corner style has to match across surfaces or the window stops looking
    /// like one system.
    enum Shapes {
        static let bubble = RoundedRectangle(cornerRadius: Metrics.bubbleCornerRadius, style: .continuous)
        static let card = RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
        static let row = RoundedRectangle(cornerRadius: Metrics.rowCornerRadius, style: .continuous)
        static let panel = RoundedRectangle(cornerRadius: 28, style: .continuous)
    }
}
