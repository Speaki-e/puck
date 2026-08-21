//
//  EditorEmptyStateView.swift
//  Puck
//
//  Replaces EditorUnavailableView -- now distinguishes "no project bound"
//  from the specific reasons a bound project can be unavailable (moved,
//  deleted, unreadable), instead of collapsing every case into one generic
//  message.
//

import SwiftUI

struct EditorEmptyStateView: View {
    let availability: EditorAvailability

    @Environment(\.clientPalette) private var palette

    private var message: String {
        switch availability {
        case .ready:
            return ""
        case .noProject:
            return Strings.text(.chatNoProjectLinked)
        case .unavailable(.pathMissing):
            return Strings.text(.editorProjectFolderMissing)
        case .unavailable(.notADirectory):
            return Strings.text(.editorProjectPathNotAFolder)
        case .unavailable(.notReadable):
            return Strings.text(.editorProjectFolderUnreadable)
        }
    }

    var body: some View {
        VStack(spacing: ClientTheme.Metrics.spacingMedium) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .font(ClientTheme.Typography.sessionTitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(ClientTheme.Metrics.spacingLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
    }
}
