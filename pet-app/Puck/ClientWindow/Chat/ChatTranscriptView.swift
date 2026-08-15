//
//  ChatTranscriptView.swift
//  Puck
//
//  The conversation itself, native again (2026-08-15). Replaces chat-web's
//  ChatTranscript/MessageBubble/ToolCallCard/ToolResultRow/RunningStatusLine.
//
//  Renders ChatSession.timeline directly -- that array is already exactly what
//  a transcript needs (ChatSession folds the BridgeEvent stream into it), so
//  there is no view model between them.
//

import SwiftUI

struct ChatTranscriptView: View {
    @ObservedObject var session: ChatSession
    let onApproval: (Bool) -> Void

    var body: some View {
        if session.timeline.isEmpty && !session.isRunning {
            EmptyTranscript()
        } else {
            transcript
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // 14, and tool rows tighten to 6 against the call above them
                // (see row spacing below): a call and its result are one
                // thought, two messages are two.
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(session.timeline) { entry in
                        row(for: entry)
                            .id(entry.id)
                            .frame(maxWidth: .infinity, alignment: alignment(for: entry))
                            // A run's own rows -- the tool calls it made and
                            // the line that ends it -- read as one block under
                            // the message that caused them, rather than as
                            // separate turns.
                            .padding(.top, entry.startsNewTurn ? 6 : -6)
                    }
                    if session.isRunning {
                        RunningStatusLine()
                            .id(Self.runningRowID)
                    }
                }
                .padding(16)
            }
            .onChange(of: session.timeline.count) { scrollToEnd(proxy) }
            .onChange(of: session.isRunning) { scrollToEnd(proxy) }
            // The last entry grows in place while text streams in, so its
            // count never changes -- without this the view stops following
            // mid-answer, which is the whole stretch worth following.
            .onChange(of: streamingTextLength) { scrollToEnd(proxy) }
        }
    }

    private static let runningRowID = "running"

    private var streamingTextLength: Int {
        if case .assistantText(_, let text) = session.timeline.last { return text.count }
        return 0
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        let target: AnyHashable? = session.isRunning
            ? AnyHashable(Self.runningRowID)
            : session.timeline.last?.id
        guard let target else { return }
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .bottom) }
    }

    private func alignment(for entry: ChatTimelineEntry) -> Alignment {
        if case .userMessage = entry { return .trailing }
        return .leading
    }

    @ViewBuilder
    private func row(for entry: ChatTimelineEntry) -> some View {
        switch entry {
        case .userMessage(_, let text):
            MessageBubble(text: text, isFromUser: true)

        case .assistantText(_, let text):
            MessageBubble(text: text, isFromUser: false)

        case .toolCall(let id, let tool, let args):
            ToolCallRow(tool: tool, args: args, result: result(forCall: id))

        case .toolResult:
            // Rendered inside its own tool_call row, correlated by id -- a
            // result on its own line would separate it from the call it
            // answers, which is the only thing that makes it readable.
            EmptyView()

        case .approvalRequested(_, _, let summary):
            ApprovalBanner(summary: summary, isResolved: session.pendingApproval == nil, onApproval: onApproval)

        case .done(_, let ok, let summary):
            DoneRow(ok: ok, summary: summary)
        }
    }

    private func result(forCall callID: String) -> ChatTimelineEntry? {
        session.timeline.first {
            if case .toolResult(let id, _, _, _, _) = $0 { return id == callID }
            return false
        }
    }
}

// MARK: - Rows

private struct MessageBubble: View {
    let text: String
    let isFromUser: Bool

    var body: some View {
        Text(text)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isFromUser ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .rect(cornerRadius: 12))
            .foregroundStyle(isFromUser ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(maxWidth: 520, alignment: isFromUser ? .trailing : .leading)
    }
}

/// A tool call and, once it lands, its result. Collapsed by default: the
/// arguments matter when something went wrong and are noise otherwise.
private struct ToolCallRow: View {
    let tool: String
    let args: JSONValue?
    let result: ChatTimelineEntry?

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                if let args, let rendered = Self.pretty(args) {
                    Text(rendered)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                if let detail = resultDetail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(iconStyle)
                Text(tool)
                    .font(.system(.body, design: .monospaced))
                if isPending {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
        .frame(maxWidth: 520, alignment: .leading)
    }

    private var isPending: Bool { result == nil }

    private var ok: Bool? {
        if case .toolResult(_, let ok, _, _, _) = result { return ok }
        return nil
    }

    private var resultDetail: String? {
        if case .toolResult(_, _, _, let error, let detail) = result {
            return [error?.rawValue, detail].compactMap { $0 }.joined(separator: " — ")
        }
        return nil
    }

    private var icon: String {
        switch ok {
        case .some(true): return "checkmark.circle.fill"
        case .some(false): return "exclamationmark.triangle.fill"
        case nil: return "wrench.and.screwdriver"
        }
    }

    private var iconStyle: Color {
        switch ok {
        case .some(true): return .green
        case .some(false): return .orange
        case nil: return .secondary
        }
    }

    /// Pretty-printed with sorted keys so the same call always reads the same
    /// way -- JSON object order is otherwise arbitrary between runs.
    static func pretty(_ value: JSONValue) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private struct ApprovalBanner: View {
    let summary: String
    let isResolved: Bool
    let onApproval: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(summary, systemImage: "hand.raised.fill")
            if isResolved {
                Text("응답함")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Button("허용") { onApproval(true) }
                        .keyboardShortcut(.defaultAction)
                    Button("거부", role: .cancel) { onApproval(false) }
                }
            }
        }
        .padding(12)
        .background(.yellow.opacity(0.12), in: .rect(cornerRadius: 10))
        .frame(maxWidth: 520, alignment: .leading)
    }
}

private struct DoneRow: View {
    let ok: Bool
    let summary: String

    var body: some View {
        Label(summary.isEmpty ? (ok ? "완료" : "실패") : summary,
              systemImage: ok ? "checkmark.circle" : "xmark.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }
}

/// Shown instead of an empty scroll view. Carried over from chat-web's
/// EmptyTranscript, which the native rewrite dropped -- a new chat opened onto
/// a blank rectangle with no indication it was ready for input.
private struct EmptyTranscript: View {
    @Environment(\.clientPalette) private var palette

    var body: some View {
        VStack(spacing: 12) {
            Text("🎃")
                .font(.system(size: 34))
                .frame(width: 72, height: 72)
                .background(palette.accent.opacity(0.12), in: .circle)
            VStack(spacing: 4) {
                Text("무엇을 도와드릴까요?")
                    .font(.title3.weight(.semibold))
                Text("코드든 잡담이든, 편하게 말 걸어보세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RunningStatusLine: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("생각 중…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
