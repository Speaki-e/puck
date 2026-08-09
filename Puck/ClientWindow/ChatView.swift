//
//  ChatView.swift
//  Puck
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  Renders one ChatSession's timeline + input, per plan/02_pet-app.md F13:
//  "onTextChunk 스트리밍, onToolCallStart/Result를 id로 짝지은 접이식
//  타임라인, onApprovalRequired는 요청 요약+허용/거부 버튼, 중지 버튼".
//
//  2026-08-01 design-system rebuild: assistant messages no longer carry a
//  bubble background (only the user's own message does -- see
//  MessageBubble below), and every card/row/bubble routes through
//  themedSurface(_:in:) so it renders flat-bordered or real glass
//  depending on the active ClientThemeStyle. A hover-revealed inline
//  action pill on assistant messages (copy) is new, ported from
//  reference screenshot #3's inline "Reply" affordance -- screenshot #3's
//  input-field autocomplete is explicitly out of scope (no backend signal
//  to suggest from; see the design spec).
//

import SwiftUI

struct ChatView: View {
    @ObservedObject var session: ChatSession
    let store: ClientWindowStore
    @Environment(\.clientPalette) private var palette

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
                    .frame(maxWidth: ClientTheme.Metrics.contentMaxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, ClientTheme.Metrics.spacingLarge)
                    .padding(.bottom, ClientTheme.Metrics.spacingLarge)
                    .padding(.top, ClientTheme.Metrics.spacingMedium)
                }
                .overlay {
                    if session.timeline.isEmpty {
                        EmptyTranscript()
                    }
                }
                .onChange(of: session.timeline.count) {
                    guard let lastId = session.timeline.last?.id else { return }
                    withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                }
                // safeAreaInset, not a VStack row below the scroll view: the
                // transcript has to scroll *under* the input card for it to
                // read as anchored rather than just another row.
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
        .background(palette.background)
    }

    /// A solid, always-anchored card, plus a disclaimer caption underneath --
    /// a real, honest addition regardless of the reference: this client runs
    /// an actual agent that can be wrong. 2026-08-02: the session-context
    /// pill that used to sit above the text field is gone -- the topBar's
    /// new session-selector pill (added the same day) already names the
    /// active session, so this was a second, redundant place saying the same
    /// thing; Figma's own input container has no such pill either.
    private var inputBar: some View {
        VStack(spacing: ClientTheme.Metrics.spacingSmall) {
            HStack(spacing: ClientTheme.Metrics.spacingMedium) {
                TextField("메시지를 입력하세요", text: $draftText, onCommit: send)
                    .textFieldStyle(.plain)
                    .font(ClientTheme.Typography.messageBody)
                    .foregroundStyle(palette.textPrimary)

                if session.isRunning {
                    Button(action: { store.cancelActiveRun() }) {
                        Image(systemName: "stop.fill")
                            .foregroundStyle(palette.failure)
                            .padding(7)
                            .themedSurface(palette, in: Circle())
                    }
                    .buttonStyle(.plain)
                } else {
                    let canSend = !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    // Figma's send button is a flat gray disc until there's
                    // something to send, then a solid dark fill -- matched
                    // here as gray-vs-brand-accent rather than an opacity
                    // fade, which is what byeolki asked to be fixed
                    // ("그냥 똑같이 해달라고").
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .fontWeight(.semibold)
                            .foregroundStyle(canSend ? palette.onAccent : palette.textSecondary)
                            .padding(7)
                            .background(canSend ? palette.accent : palette.surfaceBorder, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
            }
            .padding(.leading, ClientTheme.Metrics.spacingLarge)
            .padding(.trailing, ClientTheme.Metrics.spacingSmall)
            .padding(.vertical, ClientTheme.Metrics.spacingMedium)
            // A full pill, not a rounded card -- byeolki's slothGPT
            // reference (2026-08-02, "이거에 좀 더 맞춰봐") uses
            // `rounded-[9999px]` for its message input specifically, distinct
            // from its own cards/bubbles.
            .themedSurface(palette, in: Capsule())

            Text("\(AppIdentity.displayName)는 실수를 할 수 있어요.")
                .font(ClientTheme.Typography.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: ClientTheme.Metrics.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ClientTheme.Metrics.spacingLarge)
        .padding(.top, ClientTheme.Metrics.spacingSmall)
        .padding(.bottom, ClientTheme.Metrics.spacingLarge)
        .background(palette.background)
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
///
/// 2026-08-02: dropped the example-prompt cards entirely (byeolki: "프롬프트
/// 추천 기능은 없애고") -- just the mark and the greeting now.
private struct EmptyTranscript: View {
    @Environment(\.clientPalette) private var palette

    var body: some View {
        VStack(spacing: ClientTheme.Metrics.spacingLarge) {
            // The pumpkin is the app's mark (byeolki, 2026-07-30: "호박을
            // 로고로 쓰고 싶어") -- it's also the app icon, and the toy the
            // pet plays with. byeolki, 2026-08-02: "호박 주변에 빛 효과
            // 그런거 있는거 없애조" -- the glow behind it is gone, just the
            // plain mark now.
            Image("PumpkinLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)

            VStack(spacing: 4) {
                Text("무엇을 도와드릴까요?")
                    .font(ClientTheme.Typography.greeting)
                    .foregroundStyle(palette.textPrimary)
                Text("코드든 잡담이든, 편하게 말 걸어보세요.")
                    .font(ClientTheme.Typography.greetingSubtitle)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(ClientTheme.Metrics.spacingLarge * 1.5)
        .frame(maxWidth: ClientTheme.Metrics.contentMaxWidth)
    }
}

private struct DisconnectedBanner: View {
    @Environment(\.clientPalette) private var palette

    var body: some View {
        Label("워크스페이스가 꺼져 있어요", systemImage: "bolt.horizontal.circle")
            .font(ClientTheme.Typography.sectionHeader)
            .foregroundStyle(palette.failure)
            .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
            .padding(.vertical, ClientTheme.Metrics.spacingSmall)
            .themedSurface(palette, in: Capsule())
            .padding(ClientTheme.Metrics.spacingSmall)
    }
}

private struct ApprovalBanner: View {
    let summary: String
    let onRespond: (Bool) -> Void
    @Environment(\.clientPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: ClientTheme.Metrics.spacingSmall) {
            Label(summary, systemImage: "exclamationmark.triangle.fill")
                .font(ClientTheme.Typography.messageBody)
                .foregroundStyle(palette.warning)
            HStack {
                // Weight, not hue, is what marks the default action.
                Button("허용") { onRespond(true) }
                    .buttonStyle(.plain)
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
                    .padding(.vertical, ClientTheme.Metrics.spacingSmall)
                    .themedSurface(palette, in: Capsule())
                Button("거부") { onRespond(false) }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.failure)
                    .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
                    .padding(.vertical, ClientTheme.Metrics.spacingSmall)
                    .themedSurface(palette, in: Capsule())
            }
        }
        .padding(ClientTheme.Metrics.spacingMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedSurface(palette, in: ClientTheme.Shapes.card)
        .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
    }
}

/// 2026-08-01 rebuild: only the **user's** message got a tinted bubble at
/// first -- the assistant's text flowed directly on the column background,
/// sender row (avatar + name) above it either way.
///
/// 2026-08-02 (first pass): the user bubble's fill went from a solid
/// `accent` block to `accent.opacity(0.14)`, matching the neutral,
/// low-contrast bubble in byeolki's first Figma reference.
///
/// 2026-08-02 (second pass, "이거에 좀 더 맞춰봐"): byeolki's slothGPT
/// reference gives **both** sides the exact same subtle bubble fill,
/// differentiated only by the avatar/name row -- not by bubble color at
/// all. Matched here by giving the assistant the same faint tint as the
/// user (dropped further, to 0.06, since it now has to read as a neutral
/// "message surface" rather than a "this is you" accent, and both bubbles
/// carry it). `textPrimary` throughout either way, since a fill this light
/// can't carry white text.
private struct MessageBubble: View {
    let text: String
    let isUser: Bool
    @Environment(\.clientPalette) private var palette
    @State private var isHovering = false

    private var content: some View {
        Text(text)
            .font(ClientTheme.Typography.messageBody)
            .foregroundStyle(palette.textPrimary)
            .textSelection(.enabled)
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            senderRow
            HStack {
                if isUser { Spacer(minLength: 0) }
                VStack(alignment: isUser ? .trailing : .leading, spacing: ClientTheme.Metrics.spacingSmall) {
                    content
                        .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
                        .padding(.vertical, ClientTheme.Metrics.spacingSmall + 2)
                        .background(palette.accent.opacity(0.06), in: ClientTheme.Shapes.bubble)
                    if !isUser, isHovering { inlineActions }
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.12), value: isHovering)
                .frame(maxWidth: ClientTheme.Metrics.bubbleMaxWidth, alignment: isUser ? .trailing : .leading)
                if !isUser { Spacer(minLength: 0) }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .onHover { isHovering = $0 }
    }

    /// Screenshot #3's inline hover "Reply" affordance, adapted: a small
    /// copy pill that fades in on hover without reflowing the row above it
    /// (it's appended below the text, not overlaid).
    private var inlineActions: some View {
        HStack(spacing: ClientTheme.Metrics.spacingSmall) {
            Button {
                #if canImport(AppKit)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                #endif
            } label: {
                Label("복사", systemImage: "doc.on.doc")
                    .font(ClientTheme.Typography.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.textSecondary)
        }
    }

    private var senderRow: some View {
        HStack(spacing: 5) {
            if !isUser { avatar }
            Text(isUser ? "나" : AppIdentity.displayName)
                .font(ClientTheme.Typography.senderLabel)
                .foregroundStyle(palette.textSecondary)
            if isUser { avatar }
        }
    }

    private var avatar: some View {
        Group {
            if isUser {
                Image(systemName: "person.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.accent)
            } else {
                Image("PumpkinLogo")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: ClientTheme.Metrics.avatarSize, height: ClientTheme.Metrics.avatarSize)
        .background(isUser ? palette.accent.opacity(0.16) : Color.clear, in: Circle())
    }
}

private struct ChatTimelineEntryRow: View {
    let entry: ChatTimelineEntry
    @Environment(\.clientPalette) private var palette

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
                        .foregroundStyle(palette.textPrimary)
                        .textSelection(.enabled)
                        .padding(.top, ClientTheme.Metrics.spacingSmall)
                }
            } label: {
                Label(tool, systemImage: "wrench.and.screwdriver.fill")
                    .font(ClientTheme.Typography.toolLabel)
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(ClientTheme.Metrics.spacingMedium)
            .themedSurface(palette, in: ClientTheme.Shapes.card)

        case .toolResult(_, let ok, let data, let error, let detail):
            HStack(alignment: .top, spacing: ClientTheme.Metrics.spacingSmall) {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(ok ? palette.success : palette.failure)
                if let error {
                    Text("\(error)\(detail.map { ": \($0)" } ?? "")")
                        .font(ClientTheme.Typography.mono)
                        .foregroundStyle(palette.textPrimary)
                } else if let data {
                    Text(String(describing: data))
                        .font(ClientTheme.Typography.mono)
                        .foregroundStyle(palette.textPrimary)
                        .textSelection(.enabled)
                }
            }
            .padding(ClientTheme.Metrics.spacingMedium)
            .themedSurface(palette, in: ClientTheme.Shapes.card)

        case .approvalRequested(_, _, let summary):
            Label(summary, systemImage: "hand.raised.fill")
                .font(ClientTheme.Typography.mono)
                .foregroundStyle(palette.warning)

        case .done(let ok, let summary):
            Label(summary, systemImage: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(ClientTheme.Typography.summary)
                .foregroundStyle(ok ? palette.textPrimary : palette.failure)
        }
    }
}
