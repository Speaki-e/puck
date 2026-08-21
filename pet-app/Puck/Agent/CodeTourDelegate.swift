//
//  CodeTourDelegate.swift
//  Puck
//
//  show_code's body: highlight a line range in the editor pane, then send the
//  pet to stand in front of it. One call is one stop of a tour; the tour
//  itself is just the model calling this several times in reading order.
//
//  Here rather than in PuckClient for the reason EditorFileDelegate is:
//  PuckTests compiles the Puck target, so anything needing coverage has to
//  live where @testable import Puck reaches it.
//

import AppKit
import CoreGraphics
import Foundation

final class CodeTourDelegate {
    /// How long the pet holds one stop. The next stop or agent_done releases
    /// it first in practice; this is only what happens when neither arrives,
    /// and PointAtHandler caps it at the same value anyway.
    static let holdSeconds: TimeInterval = 60
    /// workspaceId -> that workspace's bound project path. Injected for the
    /// same reason EditorFileDelegate injects it: this type has no business
    /// knowing ClientWindowStore exists.
    private let resolveProjectPath: (String) -> String?
    /// Brings the editor pane on screen. Pointing at a pane the user cannot
    /// see is not showing them anything, and the pane only publishes a rect
    /// once it is actually visible.
    private let showEditorPane: (String, String) -> Void
    /// Dispatches point_at, so the tests do not need a live socket.
    private let point: (CGRect, TimeInterval) async -> DispatchedToolResult

    init(
        resolveProjectPath: @escaping (String) -> String?,
        showEditorPane: @escaping (String, String) -> Void,
        point: @escaping (CGRect, TimeInterval) async -> DispatchedToolResult
    ) {
        self.resolveProjectPath = resolveProjectPath
        self.showEditorPane = showEditorPane
        self.point = point
    }

    /// nil when the range starts past the end of the file. Otherwise clamped
    /// into 1...lineCount: a model a few lines off should not abort a tour.
    static func clamp(start: Int, end: Int, lineCount: Int) -> ClosedRange<Int>? {
        guard lineCount > 0, start <= lineCount else { return nil }
        let low = max(1, min(start, lineCount))
        let high = max(low, min(max(start, end), lineCount))
        return low...high
    }

    /// Files in the project whose *name* is the last component of `path`.
    ///
    /// The model sends a bare file name often enough to be worth answering
    /// (seen live: show_code with "AgentRunner.swift"), and telling it to
    /// check list_files is not a real recovery in a large project -- that
    /// list truncates at 400 paths, and this repo has 8,000. So the lookup
    /// happens here, where the whole tree is already in hand.
    static func candidates(matching path: String, in tree: [FileTreeEntry]) -> [String] {
        let name = (path as NSString).lastPathComponent
        guard !name.isEmpty else { return [] }
        return FileTreeEntry.flattenedPaths(tree).filter { ($0 as NSString).lastPathComponent == name }
    }

    /// Several files share the name, so the model picks -- with the candidates
    /// in hand, which costs it no extra call. Guessing one instead would put
    /// the pet in front of a file nobody asked about.
    static func ambiguityDetail(for path: String, candidates: [String]) -> String {
        let shown = candidates.prefix(maximumCandidatesShown)
        let more = candidates.count > shown.count ? " 외 \(candidates.count - shown.count)개" : ""
        return "\(path)와 이름이 같은 파일이 여러 개예요: \(shown.joined(separator: ", "))\(more)."
            + " 이 중 하나를 전체 경로로 다시 불러주세요."
    }

    /// Enough to choose from, few enough not to bury the ask.
    static let maximumCandidatesShown = 8

    @MainActor
    func showCode(
        path: String,
        startLine: Int,
        endLine: Int,
        workspaceId: String
    ) async -> DispatchedToolResult {
        guard let projectPath = resolveProjectPath(workspaceId) else {
            return .failed("이 워크스페이스에는 연결된 프로젝트가 없어요.")
        }
        let store: EditorPaneStore
        do {
            store = try EditorPaneStorePool.shared.store(
                forWorkspace: workspaceId,
                root: URL(fileURLWithPath: projectPath, isDirectory: true),
                onRootChanged: {}
            )
        } catch let error as WorkspaceFileServiceError {
            return .failed(error.agentDetail)
        } catch {
            return .failed(error.localizedDescription)
        }

        store.open(path: path)
        var openPath = path
        if store.activeTabPath != path {
            switch Self.candidates(matching: path, in: store.tree) {
            case let candidates where candidates.count == 1:
                openPath = candidates[0]
                store.open(path: openPath)
            case let candidates where candidates.count > 1:
                return .failed(Self.ambiguityDetail(for: path, candidates: candidates))
            default:
                return .failed(store.lastError?.agentDetail ?? "\(path)를 열지 못했어요.")
            }
        }
        guard store.activeTabPath == openPath else {
            return .failed(store.lastError?.agentDetail ?? "\(openPath)를 열지 못했어요.")
        }
        let lineCount = store.activeTab?.content.split(separator: "\n", omittingEmptySubsequences: false).count ?? 0
        guard let lines = Self.clamp(start: startLine, end: endLine, lineCount: lineCount) else {
            return .failed("\(openPath)에는 \(startLine)번째 줄이 없어요. (\(lineCount)줄짜리 파일이에요)")
        }
        showEditorPane(workspaceId, openPath)
        store.reveal(path: openPath, lines: lines)

        guard
            let appKitFrame = await paneFrame(of: store),
            let space = GlobalScreenSpace.current()
        else {
            // The highlight is up; the pet just has nowhere to go. A success
            // with a reason, so the explanation still reaches the chat rather
            // than the model apologising for a failed tool call.
            return .succeeded(detail: "에디터가 화면에 없어서 펫은 가지 못했어요. 코드는 표시했습니다.")
        }

        let pointed = await point(Self.normalized(appKitFrame, in: space), Self.holdSeconds)
        guard pointed.ok else {
            return .succeeded(detail: "펫이 가지 못했지만 코드는 표시했어요. (\(pointed.error ?? "unknown"))")
        }
        return .succeeded(detail: nil)
    }

    /// The pane publishes its rect from a layout pass, so the frame is not
    /// there yet on the first stop of a tour -- the window it lives in may
    /// have been brought on screen a moment ago by `showEditorPane`.
    ///
    /// ponytail: polled rather than awaited on a signal. A Combine
    /// subscription for a wait this short would be more machinery than the
    /// half-second it saves; if the pane ever gets slower to lay out, make
    /// `paneScreenFrame` awaited instead of raising the attempt count.
    @MainActor
    private func paneFrame(of store: EditorPaneStore) async -> CGRect? {
        for _ in 0..<Self.paneFrameAttempts {
            if let frame = store.paneScreenFrame, !frame.isEmpty { return frame }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return store.paneScreenFrame
    }

    private static let paneFrameAttempts = 10

    /// point_at speaks Quartz global coordinates (top-left origin), which is
    /// what find_ui_element hands the model; the pane reports AppKit's
    /// bottom-left ones.
    private static func normalized(_ appKitFrame: CGRect, in space: GlobalScreenSpace) -> CGRect {
        CGRect(
            origin: space.normalized(fromAppKit: CGPoint(x: appKitFrame.minX, y: appKitFrame.maxY)),
            size: appKitFrame.size
        )
    }
}
