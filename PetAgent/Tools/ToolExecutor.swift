//
//  ToolExecutor.swift
//  PetAgent
//
//  F11 · owner: Haeyoung Park
//  protocol + tool_dispatch routing, timeout handling
//

import Foundation

/// protocol repo section 3.1's standard tool_result error codes that pet-app
/// itself can produce (pet_app_disconnected is workspace-side, not ours).
enum ToolExecutionError: Error, Equatable {
    case timeout
    case notSupportedTarget
    case permissionDenied
    case executionFailed(String)

    var protocolErrorCode: String {
        switch self {
        case .timeout: return "timeout"
        case .notSupportedTarget: return "not_supported_target"
        case .permissionDenied: return "permission_denied"
        case .executionFailed: return "execution_failed"
        }
    }
}

/// One entry in the tool registry (protocol repo section 4). `toolName` must
/// match the registry's tool name exactly.
protocol ToolHandler {
    var toolName: String { get }
    func execute(args: JSONValue, completion: @escaping (Result<JSONValue?, ToolExecutionError>) -> Void)
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
        let completeOnce: (Bool, JSONValue?, String?) -> Void = { [logger, completionQueue] ok, data, error in
            let shouldComplete: Bool = completionQueue.sync {
                guard !didComplete else { return false }
                didComplete = true
                return true
            }
            guard shouldComplete else { return }
            logger?.log(.execEnd(id: request.id, ok: ok))
            completion(ToolResult(id: request.id, ok: ok, data: data, error: error))
        }

        guard let handler = handlers[request.tool] else {
            completeOnce(false, nil, ToolExecutionError.executionFailed("unknown tool: \(request.tool)").protocolErrorCode)
            return
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            completeOnce(false, nil, ToolExecutionError.timeout.protocolErrorCode)
        }

        handler.execute(args: request.args) { result in
            switch result {
            case .success(let data):
                completeOnce(true, data, nil)
            case .failure(let error):
                completeOnce(false, nil, error.protocolErrorCode)
            }
        }
    }
}
