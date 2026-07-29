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
    /// A warm, friendly accent distinct from the system's default blue --
    /// this app has a character in it, the UI shouldn't look like a plain
    /// settings pane.
    enum Colors {
        static let accent = Color(red: 0.95, green: 0.42, blue: 0.36)
        static let accentSoft = accent.opacity(0.16)

        /// Sidebar/toolbar chrome uses VisualEffectBackground (real
        /// NSVisualEffectView vibrancy), not a flat color here -- a flat
        /// Color reads as a plain settings pane no matter what tone it is.
        static let contentBackground = Color(nsColor: .textBackgroundColor)

        static let userBubble = accent
        static let userBubbleText = Color.white
        static let assistantBubble = Color(nsColor: .controlBackgroundColor)
        static let assistantBubbleText = Color.primary

        static let cardBackground = Color(nsColor: .controlBackgroundColor)
        static let cardBorder = Color(nsColor: .separatorColor)

        static let approvalBackground = Color.orange.opacity(0.14)
        static let approvalBorder = Color.orange.opacity(0.4)

        static let success = Color.green
        static let failure = Color.red
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
        static let maxBubbleWidthRatio: CGFloat = 0.72
    }
}
