//
//  CodeEditorHostView.swift
//  Puck
//
//  Thin wrapper around CodeEditSourceEditor's SourceEditor -- the
//  tree-sitter-backed syntax-highlighted text view. Deliberately minimal
//  configuration: no autocomplete/LSP coordinators, no minimap, no diff
//  mode. Language is detected by CodeEditLanguages itself from the file's
//  URL/extension, independent of EditorLanguage's own (display-name-only)
//  extension table.
//

import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import SwiftUI

struct CodeEditorHostView: View {
    @Binding var content: String
    let isEditable: Bool
    let path: String
    /// The range a code tour (or anything else) asked to be shown. Applied
    /// only by the editor whose tab it names.
    let reveal: EditorPaneStore.RevealRequest?

    @State private var state = SourceEditorState()
    @State private var revealCoordinator = EditorRevealCoordinator()
    /// The revealed lines, in the text view's coordinates. Turned into a band
    /// on screen by subtracting the current scroll offset, so it follows the
    /// pane as the user scrolls away from it and back.
    @State private var highlightSpan: ClosedRange<CGFloat>?
    @Environment(\.clientPalette) private var palette

    var body: some View {
        SourceEditor(
            $content,
            language: CodeLanguage.detectLanguageFrom(url: URL(fileURLWithPath: path)),
            configuration: SourceEditorConfiguration(
                appearance: .init(
                    theme: Self.theme(for: palette),
                    font: .monospacedSystemFont(ofSize: 12, weight: .regular),
                    wrapLines: false
                ),
                behavior: .init(isEditable: isEditable, indentOption: .spaces(count: 2))
            ),
            state: $state,
            coordinators: [revealCoordinator]
        )
        .overlay(alignment: .topLeading) { highlightBand }
        .clipped()
        // task(id:), not onChange: a tour usually reveals a file that was
        // not open, so this view is created *because* of the request and
        // there is no change for onChange to see.
        .task(id: reveal?.token) {
            guard let reveal, reveal.path == path else { return }
            revealCoordinator.onScrollTarget = { state.scrollPosition = $0 }
            revealCoordinator.onHighlightSpan = { highlightSpan = $0 }
            revealCoordinator.reveal(lines: reveal.lines)
        }
    }

    /// The band over the lines a tour stop is talking about, in the Mac's own
    /// accent colour -- the same "look here" the rest of the system uses.
    ///
    /// Drawn here rather than by the editor because neither thing the editor
    /// offers works for this: see EditorRevealCoordinator.onHighlightSpan.
    /// Translucent, and never taking the mouse, because the code underneath
    /// still has to be readable and clickable.
    @ViewBuilder
    private var highlightBand: some View {
        if let highlightSpan, let scrollY = state.scrollPosition?.y {
            let accent = Color(nsColor: .controlAccentColor)
            RoundedRectangle(cornerRadius: 4)
                .fill(accent.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(accent.opacity(0.9), lineWidth: 1.5)
                )
                .frame(height: highlightSpan.upperBound - highlightSpan.lowerBound)
                .offset(y: highlightSpan.lowerBound - scrollY)
                .allowsHitTesting(false)
        }
    }

    private static func theme(for palette: ClientPalette) -> EditorTheme {
        let text = EditorTheme.Attribute(color: NSColor(palette.textPrimary))
        let keyword = EditorTheme.Attribute(color: NSColor(red: 0.78, green: 0.53, blue: 0.90, alpha: 1), bold: true)
        let type = EditorTheme.Attribute(color: NSColor(red: 0.40, green: 0.75, blue: 0.85, alpha: 1))
        let literal = EditorTheme.Attribute(color: NSColor(red: 0.60, green: 0.80, blue: 0.50, alpha: 1))
        let string = EditorTheme.Attribute(color: NSColor(palette.accent))
        let comment = EditorTheme.Attribute(color: NSColor(palette.textSecondary), italic: true)
        return EditorTheme(
            text: text,
            insertionPoint: NSColor(palette.accent),
            invisibles: EditorTheme.Attribute(color: NSColor(palette.textSecondary)),
            background: NSColor(palette.background),
            lineHighlight: NSColor(palette.surface),
            selection: NSColor(palette.accent).withAlphaComponent(0.25),
            keywords: keyword,
            commands: text,
            types: type,
            attributes: text,
            variables: text,
            values: literal,
            numbers: literal,
            strings: string,
            characters: string,
            comments: comment
        )
    }
}
