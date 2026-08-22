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
    @Environment(\.clientPalette) private var palette

    var body: some View {
        SourceEditor(
            $content,
            language: CodeLanguage.detectLanguageFrom(url: URL(fileURLWithPath: path)),
            configuration: SourceEditorConfiguration(
                appearance: .init(
                    theme: Self.theme(for: palette),
                    // The size the transcript renders inline code at, so a
                    // snippet quoted in the conversation and the file it came
                    // from are the same text at the same scale.
                    font: .monospacedSystemFont(ofSize: 13, weight: .regular),
                    wrapLines: false
                ),
                behavior: .init(isEditable: isEditable, indentOption: .spaces(count: 2))
            ),
            state: $state,
            coordinators: [revealCoordinator]
        )
        // task(id:), not onChange: a tour usually reveals a file that was
        // not open, so this view is created *because* of the request and
        // there is no change for onChange to see.
        .task(id: reveal?.token) {
            guard let reveal, reveal.path == path else { return }
            revealCoordinator.onScrollTarget = { state.scrollPosition = $0 }
            revealCoordinator.reveal(lines: reveal.lines)
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
