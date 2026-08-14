//
//  EditorTabStripView.swift
//  Puck
//

import SwiftUI

struct EditorTabStripView: View {
    let tabs: [EditorTab]
    let activeTabPath: String?
    let onSelect: (String) -> Void
    let onClose: (String) -> Void

    @Environment(\.clientPalette) private var palette

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(tabs) { tab in
                    tabButton(for: tab)
                }
            }
        }
        .frame(height: 32)
        .background(palette.surface)
    }

    private func tabButton(for tab: EditorTab) -> some View {
        let isActive = tab.path == activeTabPath
        return HStack(spacing: 6) {
            Text((tab.path as NSString).lastPathComponent)
                .font(ClientTheme.Typography.caption)
                .lineLimit(1)
            if tab.isDirty {
                Circle().fill(palette.accent).frame(width: 5, height: 5)
            }
            Button(action: { onClose(tab.path) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .opacity(0.6)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(isActive ? palette.background : Color.clear)
        .foregroundStyle(isActive ? palette.textPrimary : palette.textSecondary)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(tab.path) }
    }
}
