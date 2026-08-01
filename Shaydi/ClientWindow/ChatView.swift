//
//  ChatView.swift
//  Shaydi
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
                    .frame(maxWidth: ClientTheme.Metrics.contentMaxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, ClientTheme.Metrics.spacingLarge)
                    .padding(.bottom, ClientTheme.Metrics.spacingLarge)
                    .padding(.top, ClientTheme.Metrics.spacingMedium)
                }
                .overlay {
                    if session.timeline.isEmpty {
                        EmptyTranscript(onPromptSelected: { draftText = $0 })
                    }
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

    /// 2026-08-01 (byeolki: "Orbita로 해봐봐"): Orbita's own input bar is a
    /// solid, always-anchored card, not a floating glass capsule -- and it
    /// carries a disclaimer caption underneath, which this adopts too (a
    /// real, honest addition regardless of the reference: this client runs
    /// an actual agent that can be wrong).
    private var inputBar: some View {
        VStack(spacing: ClientTheme.Metrics.spacingSmall) {
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
                    // Filled with `accent`, not just glass -- the one button
                    // every reference shot (Sense, the dark chat, Orbita)
                    // treats as the single colored anchor in an otherwise
                    // neutral bar.
                    let canSend = !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .fontWeight(.semibold)
                            .foregroundStyle(ClientTheme.Colors.onAccent)
                            .padding(7)
                            .glassControl(in: Circle(), tint: ClientTheme.Colors.accent)
                    }
                    .buttonStyle(.plain)
                    .opacity(canSend ? 1 : 0.4)
                    .disabled(!canSend)
                }
            }
            .padding(.leading, ClientTheme.Metrics.spacingLarge)
            .padding(.trailing, ClientTheme.Metrics.spacingSmall)
            .padding(.vertical, ClientTheme.Metrics.spacingMedium)
            .glassSurface(in: ClientTheme.Shapes.card)

            Text("\(AppIdentity.displayName)는 실수를 할 수 있어요.")
                .font(ClientTheme.Typography.caption)
                .foregroundStyle(ClientTheme.Colors.secondaryText)
        }
        .frame(maxWidth: ClientTheme.Metrics.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ClientTheme.Metrics.spacingLarge)
        .padding(.top, ClientTheme.Metrics.spacingSmall)
        .padding(.bottom, ClientTheme.Metrics.spacingLarge)
        .background(VisualEffectBackground(material: .contentBackground))
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
/// 2026-08-01 (byeolki: "Orbita로 해봐봐"): Orbita's own empty state isn't
/// just an icon and one line -- a subtitle under the greeting, then a row of
/// suggestion chips the user can tap instead of typing from nothing. Orbita's
/// own chips are app-specific actions (Connect Calendar, Browse
/// Integrations) this client has no equivalent for; what carries over
/// honestly is example *prompts*, since prefilling the input is a real thing
/// this client can do.
private struct EmptyTranscript: View {
    let onPromptSelected: (String) -> Void

    private static let examplePrompts: [(icon: String, text: String)] = [
        ("doc.text.magnifyingglass", "이 코드 설명해줘"),
        ("ladybug.fill", "여기 버그 있는지 찾아줘"),
        ("checkmark.seal", "테스트 작성해줘"),
        ("wand.and.stars", "리팩토링 해줘"),
    ]

    var body: some View {
        VStack(spacing: ClientTheme.Metrics.spacingLarge) {
            ZStack {
                // A soft glow behind the mark -- Sense's gradient orb and
                // Orbita's gradient circle both use exactly this to make an
                // otherwise flat icon read as the app's "hero" rather than
                // just another asset.
                Circle()
                    .fill(ClientTheme.Colors.accent.opacity(0.35))
                    .frame(width: 96, height: 96)
                    .blur(radius: 24)
                // The pumpkin is the app's mark (byeolki, 2026-07-30: "호박을
                // 로고로 쓰고 싶어") -- it's also the app icon, and the toy the
                // pet plays with.
                Image("PumpkinLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
            }

            VStack(spacing: 4) {
                Text("무엇을 도와드릴까요?")
                    .font(ClientTheme.Typography.greeting)
                    .foregroundStyle(ClientTheme.Colors.bubbleText)
                Text("코드든 잡담이든, 편하게 말 걸어보세요.")
                    .font(ClientTheme.Typography.greetingSubtitle)
                    .foregroundStyle(ClientTheme.Colors.secondaryText)
            }

            FlowChips(items: Self.examplePrompts, onSelect: onPromptSelected)
        }
        .padding(ClientTheme.Metrics.spacingLarge * 1.5)
        .frame(maxWidth: ClientTheme.Metrics.contentMaxWidth)
    }
}

/// The example-prompt row under the empty-state greeting -- wraps onto a
/// second line rather than overflowing or scrolling horizontally, since the
/// window's min width (640) is narrower than four chips laid out in one row.
private struct FlowChips: View {
    let items: [(icon: String, text: String)]
    let onSelect: (String) -> Void

    var body: some View {
        FlowLayout(spacing: ClientTheme.Metrics.spacingSmall) {
            ForEach(items, id: \.text) { item in
                Button {
                    onSelect(item.text)
                } label: {
                    Label(item.text, systemImage: item.icon)
                        .font(ClientTheme.Typography.caption)
                        .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
                        .padding(.vertical, ClientTheme.Metrics.spacingSmall)
                        .glassControl(in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A minimal wrapping row layout -- SwiftUI has no built-in equivalent, and
/// pulling in a dependency for four chips isn't worth it.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > width {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: width.isFinite ? width : rowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = bounds.origin
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x > bounds.minX, origin.x + size.width > bounds.maxX {
                origin.x = bounds.minX
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: origin, proposal: .unspecified)
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
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

/// 2026-08-01 redesign: every reference shot (Sense, the dark chat, Orbita)
/// labels who's speaking above each message, so both sides now get a small
/// sender row (avatar + name) -- and the user's own bubble is the one place
/// besides the send button and "새 채팅" pill that `accent` shows up, which
/// is what actually tells the two sides apart now (previously that job fell
/// to "only the user gets a background at all", the flattest possible
/// version of the same idea).
private struct MessageBubble: View {
    let text: String
    let isUser: Bool

    private var content: some View {
        Text(text)
            .font(ClientTheme.Typography.messageBody)
            .foregroundStyle(isUser ? ClientTheme.Colors.onAccent : ClientTheme.Colors.bubbleText)
            .textSelection(.enabled)
            .padding(.horizontal, ClientTheme.Metrics.spacingMedium)
            .padding(.vertical, ClientTheme.Metrics.spacingSmall + 2)
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            senderRow
            HStack {
                if isUser { Spacer(minLength: 0) }
                Group {
                    if isUser {
                        content.glassSurface(in: ClientTheme.Shapes.bubble, tint: ClientTheme.Colors.accent)
                    } else {
                        content.glassSurface(in: ClientTheme.Shapes.bubble)
                    }
                }
                .frame(maxWidth: 420, alignment: isUser ? .trailing : .leading)
                if !isUser { Spacer(minLength: 0) }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var senderRow: some View {
        HStack(spacing: 5) {
            if !isUser { avatar }
            Text(isUser ? "나" : AppIdentity.displayName)
                .font(ClientTheme.Typography.senderLabel)
                .foregroundStyle(ClientTheme.Colors.secondaryText)
            if isUser { avatar }
        }
    }

    private var avatar: some View {
        Group {
            if isUser {
                Image(systemName: "person.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(ClientTheme.Colors.accent)
            } else {
                Image("PumpkinLogo")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: ClientTheme.Metrics.avatarSize, height: ClientTheme.Metrics.avatarSize)
        .background(isUser ? ClientTheme.Colors.accentSoft : Color.clear, in: Circle())
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
