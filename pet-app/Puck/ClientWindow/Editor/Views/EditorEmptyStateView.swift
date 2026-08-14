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
            return "이 워크스페이스에는 연결된 프로젝트가 없어요"
        case .unavailable(.pathMissing):
            return "프로젝트 폴더를 찾을 수 없어요 -- 이동되었거나 삭제된 것 같아요"
        case .unavailable(.notADirectory):
            return "연결된 경로가 폴더가 아니에요"
        case .unavailable(.notReadable):
            return "프로젝트 폴더를 읽을 권한이 없어요"
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
