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
    /// Room left at the top for the window's floating header, which is drawn
    /// over this view rather than above it.
    var topInset: CGFloat = 0

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
                    .padding(.horizontal, ClientTheme.Metrics.spacingLarge)
                    .padding(.bottom, ClientTheme.Metrics.spacingLarge)
                    .padding(.top, topInset + ClientTheme.Metrics.spacingMedium)
                }
                .overlay {
                    if session.timeline.isEmpty { EmptyTranscript() }
                }
                .onChange(of: session.timeline.count) {
                    guard let lastId = session.timeline.last?.id else { return }
                    withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                }
                // safeAreaInset, not a VStack row below the scroll view: the
                // transcript has to scroll *under* the glass capsule for the
                // refraction to be visible at all.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        if let pending = session.pendingApproval {
                            ApprovalBanner(summary: pending.summary) { approved in
                                store.respondToPendingApproval(in: session, approved: approved)
                            }
                        }

                        inputBar
                    }
                }
            }
        }
    }

    /// A glass capsule floating over the transcript rather than a bar
    /// welded to the bottom edge -- the Apple-style treatment, and the one
    /// place the window most needs to read as its own app.
    private var inputBar: some View {
        GlassGroup(spacing: ClientTheme.Metrics.spacingSmall) {
            HStack(spacing: ClientTheme.Metrics.spacingMedium) {
                TextField("메시지를 입력하세요", text: $draftText, onCommit: send)
                    .textFieldStyle(.plain)
                    .font(ClientTheme.Typography.messageBody)

                if session.isRunning {
                    Button(action: { store.cancelActiveRun() }) {
                        Image(systemName: "stop.fill")
                            .foregroundStyle(ClientTheme.Colors.failure)
                            .padding(7)
                            .glassControl(in: Circle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .padding(7)
                            .glassControl(in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.leading, ClientTheme.Metrics.spacingLarge)
            .padding(.trailing, ClientTheme.Metrics.spacingSmall)
            .padding(.vertical, ClientTheme.Metrics.spacingSmall)
            .glassSurface(in: Capsule())
        }
        .padding(ClientTheme.Metrics.spacingMedium)
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

/// A new session opens onto a large empty pane; without this it reads as a
/// rendering failure rather than "say something".
private struct EmptyTranscript: View {
    var body: some View {
        VStack(spacing: ClientTheme.Metrics.spacingMedium) {
            // The pumpkin is the app's mark (byeolki, 2026-07-30: "호박을
            // 로고로 쓰고 싶어") -- it's also the app icon, and the toy the
            // pet plays with.
            Image("PumpkinLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
            Text("무엇을 도와드릴까요?")
                .font(ClientTheme.Typography.summary)
                .foregroundStyle(ClientTheme.Colors.secondaryText)
        }
        .padding(ClientTheme.Metrics.spacingLarge * 1.5)
        .glassSurface(in: ClientTheme.Shapes.panel)
        .allowsHitTesting(false)
    }
}

private struct DisconnectedBanner: View {
    var body: some View {
        Label("워크스페이스가 꺼져 있어요", systemImage: "bolt.horizontal.circle")
            .font(ClientTheme.Typography.sectionHeader)
            .foregroundStyle(ClientTheme.Colors.failure)
            .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
            .padding(.vertical, ClientTheme.Metrics.spacingSmall)
            .glassSurface(in: Capsule())
            .padding(ClientTheme.Metrics.spacingSmall)
    }
}

private struct ApprovalBanner: View {
    let summary: String
    let onRespond: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ClientTheme.Metrics.spacingSmall) {
            Label(summary, systemImage: "exclamationmark.triangle.fill")
                .font(ClientTheme.Typography.messageBody)
                .foregroundStyle(ClientTheme.Colors.warning)
            HStack {
                // Weight, not hue, is what marks the default action now.
                Button("허용") { onRespond(true) }
                    .buttonStyle(.plain)
                    .fontWeight(.semibold)
                    .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
                    .padding(.vertical, ClientTheme.Metrics.spacingSmall)
                    .glassControl(in: Capsule())
                Button("거부") { onRespond(false) }
                    .buttonStyle(.plain)
                    .foregroundStyle(ClientTheme.Colors.failure)
                    .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
                    .padding(.vertical, ClientTheme.Metrics.spacingSmall)
                    .glassControl(in: Capsule())
            }
        }
        .padding(ClientTheme.Metrics.spacingMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(in: ClientTheme.Shapes.card)
        .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
    }
}

/// Only the user's side gets a bubble, and it's glass rather than a colored
/// fill (there is no accent color any more). The agent's text sits directly
/// on the page like it does in Mail or Notes -- with both sides bubbled and
/// no hue to tell them apart, the transcript read as two identical columns.
private struct MessageBubble: View {
    let text: String
    let isUser: Bool

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 0) }
            Text(text)
                .font(ClientTheme.Typography.messageBody)
                .foregroundStyle(ClientTheme.Colors.bubbleText)
                .textSelection(.enabled)
                .padding(.horizontal, isUser ? ClientTheme.Metrics.spacingMedium : 0)
                .padding(.vertical, isUser ? ClientTheme.Metrics.spacingSmall + 2 : 0)
                .glassSurface(in: ClientTheme.Shapes.bubble, isEnabled: isUser)
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
            .glassSurface(in: ClientTheme.Shapes.card)

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
            .glassSurface(in: ClientTheme.Shapes.card)

        case .approvalRequested(_, _, let summary):
            Label(summary, systemImage: "hand.raised.fill")
                .font(ClientTheme.Typography.mono)
                .foregroundStyle(ClientTheme.Colors.warning)

        case .done(let ok, let summary):
            Label(summary, systemImage: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(ClientTheme.Typography.summary)
                .foregroundStyle(ok ? Color.primary : ClientTheme.Colors.failure)
        }
    }
}
