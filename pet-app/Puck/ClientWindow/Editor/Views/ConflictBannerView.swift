//
//  ConflictBannerView.swift
//  Puck
//
//  Shown when EditorTab.diskChanged is set -- the disk copy changed since
//  this tab last synced with it (a failed save's revision mismatch, or an
//  external edit detected while the tab was open). Exactly two resolutions,
//  no diff view: keep the in-editor draft, or discard it for what's on disk.
//

import SwiftUI

struct ConflictBannerView: View {
    let onKeepMine: () -> Void
    let onUseDisk: () -> Void

    @Environment(\.clientPalette) private var palette

    var body: some View {
        HStack(spacing: ClientTheme.Metrics.spacingMedium) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(palette.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("디스크에서 파일이 변경됐습니다")
                    .font(ClientTheme.Typography.toolLabel)
                Text("저장하기 전에 사용할 버전을 선택하세요.")
                    .font(ClientTheme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("디스크 내용 사용", action: onUseDisk)
            Button("내 내용 유지", action: onKeepMine)
                .buttonStyle(.borderedProminent)
        }
        .padding(ClientTheme.Metrics.spacingMedium)
        .background(palette.surface)
        .clipShape(ClientTheme.Shapes.card)
        .overlay(ClientTheme.Shapes.card.stroke(palette.surfaceBorder))
        .padding(ClientTheme.Metrics.spacingMedium)
    }
}
