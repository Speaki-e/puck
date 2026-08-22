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
    /// Redraws this view when the UI language changes. Needed on every
    /// view that resolves a string, not just the window root: SwiftUI
    /// skips a child whose own inputs are unchanged, and a table lookup
    /// inside `body` is not an input.
    @ObservedObject private var localization = Localization.shared

    let tabs: [EditorTab]
    let activeTabPath: String?
    let canSave: Bool
    let onSelect: (String) -> Void
    let onClose: (String) -> Void
    let onSave: () -> Void
    /// Hides the code column without closing what is open in it. Nil in the
    /// detached window, which has nothing to collapse into.
    var onCollapse: (() -> Void)?
    /// Whether the shell under the code is showing. A binding rather than a
    /// closure: the button draws itself differently depending on the answer,
    /// so it has to know it.
    var isTerminalOpen: Binding<Bool>?

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
            if let isTerminalOpen { terminalButton(isTerminalOpen) }
            if let onCollapse { collapseButton(onCollapse) }
        }
        .frame(height: Self.stripHeight)
        .background(palette.surface)
    }

    /// Opens the shell under the code, or puts it away. ⌃` is where every
    /// editor with a terminal puts this, so it is where this one puts it too.
    private func terminalButton(_ isOpen: Binding<Bool>) -> some View {
        Button {
            isOpen.wrappedValue.toggle()
        } label: {
            Image(systemName: "terminal")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: Self.stripHeight, height: Self.stripHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOpen.wrappedValue ? palette.textPrimary : palette.textSecondary)
        .keyboardShortcut("`", modifiers: .control)
        .accessibilityLabel(Strings.text(.terminalToggle))
        .help(Strings.text(.terminalToggle))
    }

    /// Puts the file away and gives the width back to the conversation.
    /// Distinct from closing the tab: the file stays open, so coming back to
    /// it does not mean finding it again.
    private func collapseButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.right.to.line")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: Self.stripHeight, height: Self.stripHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.text(.editorCollapse))
        .help(Strings.text(.editorCollapse))
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
        .help(Strings.text(.editorSaveHint))
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
