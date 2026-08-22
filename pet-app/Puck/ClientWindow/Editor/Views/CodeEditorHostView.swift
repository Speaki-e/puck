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

    /// Built from the palette's own syntax colours rather than from three
    /// interface ones. Derived, every theme's code looked the same however
    /// different its chrome was -- strings took the accent, keywords a fixed
    /// violet nobody chose.
    private static func theme(for palette: ClientPalette) -> EditorTheme {
        func attribute(_ color: Color, bold: Bool = false, italic: Bool = false) -> EditorTheme.Attribute {
            EditorTheme.Attribute(color: NSColor(color), bold: bold, italic: italic)
        }
        let syntax = palette.syntax
        let text = attribute(palette.textPrimary)
        let variable = attribute(syntax.variable)
        let number = attribute(syntax.number)
        let string = attribute(syntax.string)
        return EditorTheme(
            text: text,
            insertionPoint: NSColor(palette.accent),
            invisibles: attribute(syntax.comment),
            background: NSColor(palette.background),
            lineHighlight: NSColor(palette.surface),
            selection: NSColor(palette.accent).withAlphaComponent(0.25),
            keywords: attribute(syntax.keyword, bold: true),
            commands: attribute(syntax.function),
            types: attribute(syntax.type),
            attributes: attribute(syntax.function),
            variables: variable,
            values: number,
            numbers: number,
            strings: string,
            characters: string,
            comments: attribute(syntax.comment, italic: true)
        )
    }
}
