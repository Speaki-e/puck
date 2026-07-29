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
                Text("워크스페이스가 꺼져 있어요")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    .background(Color.red)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(session.timeline) { entry in
                            ChatTimelineEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(12)
                }
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

            HStack(spacing: 8) {
                TextField("메시지를 입력하세요", text: $draftText, onCommit: send)
                    .textFieldStyle(.roundedBorder)
                if session.isRunning {
                    Button("중지") { store.cancelActiveRun() }
                } else {
                    Button("전송") { send() }
                        .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(8)
        }
    }

    private func send() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let delivery = store.sendMessage(text, source: .text)
        showDisconnectedBanner = (delivery == .workspaceDisconnected)
        draftText = ""
    }
}

private struct ApprovalBanner: View {
    let summary: String
    let onRespond: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary).font(.callout)
            HStack {
                Button("허용") { onRespond(true) }
                Button("거부") { onRespond(false) }
                    .foregroundStyle(.red)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.2))
    }
}

private struct ChatTimelineEntryRow: View {
    let entry: ChatTimelineEntry

    var body: some View {
        switch entry {
        case .assistantText(_, let text):
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .toolCall(_, let tool, let args):
            DisclosureGroup {
                if let args {
                    Text(String(describing: args))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            } label: {
                Label(tool, systemImage: "wrench.and.screwdriver")
                    .font(.callout)
            }

        case .toolResult(_, let ok, let data, let error, let detail):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: ok ? "checkmark.circle" : "xmark.circle")
                    .foregroundStyle(ok ? .green : .red)
                if let error {
                    Text("\(error)\(detail.map { ": \($0)" } ?? "")")
                        .font(.caption)
                } else if let data {
                    Text(String(describing: data))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

        case .approvalRequested(_, _, let summary):
            Text("승인 요청: \(summary)")
                .font(.caption)
                .foregroundStyle(.orange)

        case .done(let ok, let summary):
            Label(summary, systemImage: ok ? "checkmark.seal" : "exclamationmark.triangle")
                .font(.callout.bold())
                .foregroundStyle(ok ? Color.primary : Color.red)
        }
    }
}
