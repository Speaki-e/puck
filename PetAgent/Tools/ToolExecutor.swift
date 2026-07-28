//
//  ToolExecutor.swift
//  PetAgent
//
//  F11 · owner: Haeyoung Park
//  protocol + tool_dispatch routing, timeout handling
//

import Foundation

/// protocol 3.1's standard tool_result error codes that pet-app itself can
/// produce (pet_app_disconnected is workspace-side, not ours).
enum ToolExecutionError: Error, Equatable {
    case timeout
    /// The dispatched tool isn't in the registry at all -- a registry/agent
    /// mismatch, distinguishable from a tool that exists but failed.
    case unknownTool(String)
    case notSupportedTarget
    case permissionDenied
    case executionFailed(String)

    var protocolErrorCode: String {
        switch self {
        case .timeout: return "timeout"
        case .unknownTool: return "unknown_tool"
        case .notSupportedTarget: return "not_supported_target"
        case .permissionDenied: return "permission_denied"
        case .executionFailed: return "execution_failed"
        }
    }

    /// Human-readable specifics for tool_result's `detail` field -- the code
    /// alone reaches the wire otherwise and the actual failure reason is lost.
    var detail: String? {
        switch self {
        case .timeout, .notSupportedTarget, .permissionDenied:
            return nil
        case .unknownTool(let tool):
            return "unknown tool: \(tool)"
        case .executionFailed(let message):
            return message
        }
    }
}

/// One entry in the tool registry (protocol repo section 4). `toolName` must
/// match the registry's tool name exactly.
protocol ToolHandler: AnyObject {
    var toolName: String { get }
    func execute(args: JSONValue, completion: @escaping (Result<JSONValue?, ToolExecutionError>) -> Void)

    /// Abandon whatever `execute` started. Called when the call times out —
    /// without it a timed-out run_shell leaves its process running forever
    /// with nobody to collect it.
    func cancel()
}

extension ToolHandler {
    /// Most tools finish promptly and have nothing to tear down.
    func cancel() {}
}

/// Routes an incoming tool_dispatch to its registered ToolHandler and enforces
/// a per-call timeout — protocol 3.1: "타임아웃 기본 15초... 초과 시 수신 측이
/// 아닌 송신 측이 timeout 처리" means pet-app (the tool_dispatch *receiver*)
/// must not let a hung handler block a reply forever.
final class ToolExecutor {
    private var handlers: [String: ToolHandler] = [:]
    private let logger: ToolExecutionLogging?
    // Guards each dispatch's completeOnce check-and-set: the timeout closure
    // (DispatchQueue.global()) and a handler's own completion (often fired
    // from a background queue, e.g. RunShellHandler/RunAppleScriptHandler)
    // can race on the same request's didComplete flag without this.
    private let completionQueue = DispatchQueue(label: "PetAgent.ToolExecutor.completion")

    init(logger: ToolExecutionLogging? = nil) {
        self.logger = logger
    }

    func register(_ handler: ToolHandler) {
        handlers[handler.toolName] = handler
    }

    /// - Parameter timeout: seconds before this call is force-completed with a
    ///   timeout error. Defaults to the tools.md registry default (15s);
    ///   callers dispatching a tool with a higher `timeout_sec` should pass it.
    func dispatch(_ request: ToolDispatch, timeout: TimeInterval = 15, completion: @escaping (ToolResult) -> Void) {
        logger?.log(.execStart(id: request.id))

        var didComplete = false
        let completeOnce: (Bool, JSONValue?, ToolExecutionError?) -> Void = { [logger, completionQueue] ok, data, error in
            let shouldComplete: Bool = completionQueue.sync {
                guard !didComplete else { return false }
                didComplete = true
                return true
            }
            guard shouldComplete else { return }
            logger?.log(.execEnd(id: request.id, ok: ok))
            completion(ToolResult(id: request.id, ok: ok, data: data, error: error?.protocolErrorCode, detail: error?.detail))
        }

        guard let handler = handlers[request.tool] else {
            completeOnce(false, nil, .unknownTool(request.tool))
            return
        }

        // A DispatchWorkItem rather than a bare asyncAfter closure so a fast
        // success can cancel it. Left uncancelled, every call held a queued
        // block for its full timeout — 600s in code_editor's case.
        let timeoutWork = DispatchWorkItem { [weak handler] in
            handler?.cancel()
            completeOnce(false, nil, .timeout)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

        handler.execute(args: request.args) { result in
            timeoutWork.cancel()
            switch result {
            case .success(let data):
                completeOnce(true, data, nil)
            case .failure(let error):
                completeOnce(false, nil, error)
            }
        }
    }
}
