//
//  EditorTabStripView.swift
//  Puck
//
//  Design system v2 (2026-08-14): switched from hardcoded spacing/size
//  literals to ClientTheme.Metrics -- see
//  docs/superpowers/specs/2026-08-14-design-system-v2-design.md §4 (tab
//  strip pattern).
//

import SwiftUI

struct EditorTabStripView: View {
    let tabs: [EditorTab]
    let activeTabPath: String?
    let onSelect: (String) -> Void
    let onClose: (String) -> Void

    @Environment(\.clientPalette) private var palette

    static let stripHeight: CGFloat = ClientTheme.Metrics.spacingLarge * 2 + 4

    private static let tabHeight: CGFloat = stripHeight - 4

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(tabs) { tab in
                    tabButton(for: tab)
                }
            }
        }
        .frame(height: Self.stripHeight)
        .background(palette.surface)
    }

    private func tabButton(for tab: EditorTab) -> some View {
        let isActive = tab.path == activeTabPath
        return HStack(spacing: ClientTheme.Metrics.spacingSmall) {
            Text((tab.path as NSString).lastPathComponent)
                .font(ClientTheme.Typography.caption)
                .lineLimit(1)
            if tab.isDirty {
                StatusDotView(status: .active, palette: palette, diameter: 5)
            }
            Button(action: { onClose(tab.path) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .opacity(0.6)
        }
        .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
        .frame(height: Self.tabHeight)
        .background(isActive ? palette.background : Color.clear)
        .foregroundStyle(isActive ? palette.textPrimary : palette.textSecondary)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(tab.path) }
    }
}
