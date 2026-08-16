//
//  EditorTabStripView.swift
//  Puck
//
//  Design system v2 (2026-08-14): switched internal spacing/padding to
//  ClientTheme.Metrics -- see docs/decisions.md (tab strip pattern).
//  stripHeight/tabHeight stay plain literals rather than derived from a
//  spacing token -- they're this view's own dimensions, not a spacing
//  concern, and coupling them to a generic token would let retuning that
//  token silently resize the tab strip.
//

import SwiftUI

struct EditorTabStripView: View {
    let tabs: [EditorTab]
    let activeTabPath: String?
    let canSave: Bool
    let onSelect: (String) -> Void
    let onClose: (String) -> Void
    let onSave: () -> Void

    @Environment(\.clientPalette) private var palette

    private static let stripHeight: CGFloat = 28

    private static let tabHeight: CGFloat = 24

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(tabs) { tab in
                        tabButton(for: tab)
                    }
                }
            }
            saveButton
        }
        .frame(height: Self.stripHeight)
        .background(palette.surface)
    }

    /// Always present, not only while something is dirty: it is where ⌘S is
    /// declared, and a shortcut that exists only once the user has already
    /// typed is a shortcut nobody discovers. Disabled it is also what makes
    /// ⌘S a silent no-op with nothing to save instead of a system beep.
    private var saveButton: some View {
        Button(action: onSave) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .foregroundStyle(canSave ? palette.textPrimary : palette.textSecondary)
        .opacity(canSave ? 1 : 0.35)
        .keyboardShortcut("s", modifiers: .command)
        .help("저장 (⌘S)")
        .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
        .accessibilityIdentifier("editor.save")
    }

    private func tabButton(for tab: EditorTab) -> some View {
        let isActive = tab.path == activeTabPath
        return HStack(spacing: ClientTheme.Metrics.spacingSmall) {
            Text((tab.path as NSString).lastPathComponent)
                .font(ClientTheme.Typography.caption)
                .lineLimit(1)
            if tab.isDirty {
                StatusDotView(status: .active, palette: palette, diameter: 5, pulses: false)
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
