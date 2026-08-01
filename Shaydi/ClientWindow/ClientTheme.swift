//
//  ClientTheme.swift
//  Shaydi
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
    /// byeolki, 2026-08-01: "이거 3개 참고해" -- pointing at three Dribbble
    /// shots (Sense, an AI chat dark theme, Orbita GPT) for a design
    /// renewal. All three are otherwise neutral/glass surfaces with exactly
    /// ONE deliberate color used sparingly (a gradient mark, a filled send
    /// button, one CTA pill) -- not color everywhere. `accent` brings that
    /// back after two prior removals (lime #A2E048, then a flat pumpkin
    /// tint) that both read as a generic "pointer color" slapped onto
    /// unrelated surfaces. This one is scoped on purpose: the send button,
    /// the primary "새 채팅" pill, the active nav indicator, the user's own
    /// bubble, and the empty-state glow -- and it's pulled from the pumpkin
    /// mark that's already this app's identity, not a system color.
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

        /// A burnt pumpkin-ember, warmer and darker than system `.orange`
        /// (already used for `warning`) so the two don't read as the same
        /// color at a glance.
        static let accent = Color(red: 0.86, green: 0.47, blue: 0.15)
        static let accentSoft = accent.opacity(0.16)
        /// Text/icons drawn directly on a solid `accent` fill (the send
        /// button, the New Chat pill) need to stay legible regardless of
        /// light/dark mode -- `.primary` would go black-on-orange in light
        /// mode, unreadable.
        static let onAccent = Color.white
    }

    enum Typography {
        static let sectionHeader = Font.system(.caption, design: .rounded).weight(.semibold)
        static let workspaceName = Font.system(.body, design: .rounded).weight(.medium)
        static let sessionTitle = Font.system(.callout, design: .rounded)
        static let messageBody = Font.system(.body)
        static let toolLabel = Font.system(.callout, design: .rounded).weight(.medium)
        static let mono = Font.system(.caption, design: .monospaced)
        static let summary = Font.system(.callout, design: .rounded).weight(.semibold)
        /// The empty-state greeting -- Sense's "Good Morning" and Orbita's
        /// "Hi, there" are both bold and noticeably larger than any other
        /// text on screen; `summary` alone read as just another label.
        static let greeting = Font.system(.title2, design: .rounded).weight(.bold)
        /// Sender labels above a message bubble ("나" / the app's name).
        static let senderLabel = Font.system(.caption2, design: .rounded).weight(.semibold)
    }

    enum Metrics {
        static let sidebarWidth: CGFloat = 232
        static let spacingSmall: CGFloat = 6
        static let spacingMedium: CGFloat = 10
        static let spacingLarge: CGFloat = 16
        static let bubbleCornerRadius: CGFloat = 18
        static let cardCornerRadius: CGFloat = 14
        static let rowCornerRadius: CGFloat = 12
        /// The small sender avatar drawn above each message bubble.
        static let avatarSize: CGFloat = 22
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
