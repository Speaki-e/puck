//
//  ChatView.swift
//  PetAgent
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  Renders one ChatSession's timeline + input, per plan/02_pet-app.md F13:
//  "onTextChunk 스트리밍, onToolCallStart/Result를 id로 짝지은 접이식
//  타임라인, onApprovalRequired는 요청 요약+허용/거부 버튼, 중지 버튼".
//

import SwiftUI

struct ChatView: View {
    @ObservedObject var session: ChatSession
    let store: ClientWindowStore

    @State private var draftText = ""
    @State private var showDisconnectedBanner = false

    var body: some View {
        VStack(spacing: 0) {
            if showDisconnectedBanner {
                DisconnectedBanner()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: ClientTheme.Metrics.spacingMedium) {
                        ForEach(session.timeline) { entry in
                            ChatTimelineEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(ClientTheme.Metrics.spacingLarge)
                }
                .background(ClientTheme.Colors.contentBackground)
                .onChange(of: session.timeline.count) {
                    guard let lastId = session.timeline.last?.id else { return }
                    withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                }
            }

            if let pending = session.pendingApproval {
                ApprovalBanner(summary: pending.summary) { approved in
                    store.respondToPendingApproval(in: session, approved: approved)
                }
            }

            Divider()
            inputBar
        }
    }

    private var inputBar: some View {
        HStack(spacing: ClientTheme.Metrics.spacingMedium) {
            TextField("메시지를 입력하세요", text: $draftText, onCommit: send)
                .textFieldStyle(.plain)
                .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
                .padding(.vertical, ClientTheme.Metrics.spacingSmall + 2)
                .background(ClientTheme.Colors.assistantBubble)
                .clipShape(RoundedRectangle(cornerRadius: ClientTheme.Metrics.cardCornerRadius, style: .continuous))

            if session.isRunning {
                Button(action: { store.cancelActiveRun() }) {
                    Image(systemName: "stop.fill")
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Circle().fill(ClientTheme.Colors.failure))
                }
                .buttonStyle(.plain)
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Circle().fill(ClientTheme.Colors.accent))
                }
                .buttonStyle(.plain)
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(ClientTheme.Metrics.spacingMedium)
        .background(VisualEffectBackground(material: .headerView))
    }

    private func send() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        session.appendUserMessage(text)
        let delivery = store.sendMessage(text, source: .text)
        showDisconnectedBanner = (delivery == .workspaceDisconnected)
        draftText = ""
    }
}

private struct DisconnectedBanner: View {
    var body: some View {
        Text("워크스페이스가 꺼져 있어요")
            .font(ClientTheme.Typography.sectionHeader)
            .foregroundStyle(.white)
            .padding(ClientTheme.Metrics.spacingSmall)
            .frame(maxWidth: .infinity)
            .background(ClientTheme.Colors.failure)
    }
}

private struct ApprovalBanner: View {
    let summary: String
    let onRespond: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ClientTheme.Metrics.spacingSmall) {
            Label(summary, systemImage: "exclamationmark.triangle.fill")
                .font(ClientTheme.Typography.messageBody)
                .foregroundStyle(.orange)
            HStack {
                Button("허용") { onRespond(true) }
                    .buttonStyle(.borderedProminent)
                    .tint(ClientTheme.Colors.accent)
                Button("거부") { onRespond(false) }
                    .buttonStyle(.bordered)
                    .foregroundStyle(ClientTheme.Colors.failure)
            }
        }
        .padding(ClientTheme.Metrics.spacingMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ClientTheme.Colors.approvalBackground)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(ClientTheme.Colors.approvalBorder), alignment: .top)
    }
}

/// A left/right-aligned bubble shared by user + assistant text rows -- the
/// one visual cue that most makes this read as a chat app rather than a log
/// viewer.
private struct MessageBubble: View {
    let text: String
    let isUser: Bool

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 0) }
            Text(text)
                .font(ClientTheme.Typography.messageBody)
                .textSelection(.enabled)
                .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
                .padding(.vertical, ClientTheme.Metrics.spacingSmall + 2)
                .background(isUser ? ClientTheme.Colors.userBubble : ClientTheme.Colors.assistantBubble)
                .foregroundStyle(isUser ? ClientTheme.Colors.userBubbleText : ClientTheme.Colors.assistantBubbleText)
                .clipShape(RoundedRectangle(cornerRadius: ClientTheme.Metrics.bubbleCornerRadius, style: .continuous))
                .frame(maxWidth: 420, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ChatTimelineEntryRow: View {
    let entry: ChatTimelineEntry

    var body: some View {
        switch entry {
        case .userMessage(_, let text):
            MessageBubble(text: text, isUser: true)

        case .assistantText(_, let text):
            MessageBubble(text: text, isUser: false)

        case .toolCall(_, let tool, let args):
            DisclosureGroup {
                if let args {
                    Text(String(describing: args))
                        .font(ClientTheme.Typography.mono)
                        .textSelection(.enabled)
                        .padding(.top, ClientTheme.Metrics.spacingSmall)
                }
            } label: {
                Label(tool, systemImage: "wrench.and.screwdriver.fill")
                    .font(ClientTheme.Typography.toolLabel)
            }
            .padding(ClientTheme.Metrics.spacingMedium)
            .background(ClientTheme.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: ClientTheme.Metrics.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ClientTheme.Metrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(ClientTheme.Colors.cardBorder, lineWidth: 1)
            )

        case .toolResult(_, let ok, let data, let error, let detail):
            HStack(alignment: .top, spacing: ClientTheme.Metrics.spacingSmall) {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(ok ? ClientTheme.Colors.success : ClientTheme.Colors.failure)
                if let error {
                    Text("\(error)\(detail.map { ": \($0)" } ?? "")")
                        .font(ClientTheme.Typography.mono)
                } else if let data {
                    Text(String(describing: data))
                        .font(ClientTheme.Typography.mono)
                        .textSelection(.enabled)
                }
            }
            .padding(ClientTheme.Metrics.spacingMedium)
            .background(ClientTheme.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: ClientTheme.Metrics.cardCornerRadius, style: .continuous))

        case .approvalRequested(_, _, let summary):
            Label(summary, systemImage: "hand.raised.fill")
                .font(ClientTheme.Typography.mono)
                .foregroundStyle(.orange)

        case .done(let ok, let summary):
            Label(summary, systemImage: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(ClientTheme.Typography.summary)
                .foregroundStyle(ok ? Color.primary : ClientTheme.Colors.failure)
        }
    }
}
