//
//  ToolRegistry.swift
//  protocol
//
//  Tool registry mirror (docs/tools.md, plan/01_protocol.md section 4).
//  Reference implementation -- consumers copy this file, the way pet-app
//  already copies BridgeMessages.swift and ToolTimeouts.swift.
//
//  Why a Swift mirror now: the registry was TS-only because the only Swift
//  consumer (pet-app's executor) is told which tool to run by the wire and
//  never has to enumerate them. An agent does -- it has to hand the model the
//  full tool list -- and the agent now runs in Swift, inside PetAgentClient.
//  Hardcoding that list in the agent is exactly what the repo root README
//  forbids, so it lands here instead.
//
//  What is deliberately NOT here: each tool's `description` text. That is
//  owned by ai-module (docs/tools.md notes), because it is prompt-tuning
//  material rather than contract -- it changes without the wire changing.
//  The Swift agent keeps its descriptions next to its prompt for the same
//  reason.
//
//  Update this file together with src/types/tools.ts and docs/tools.md on any
//  registry change (see repo root README, change management rules).
//

import Foundation

enum ToolRegistry {
    /// Which side runs the tool. `pet-app` tools travel over bridge.sock as
    /// tool_dispatch; `workspace` tools are executed in-process by whoever
    /// hosts the editor.
    enum Executor: String {
        case petApp = "pet-app"
        case workspace
        /// Handled inline by the agent's own loop -- never dispatched over the
        /// socket, so it has no timeout that means anything.
        case aiModule = "ai-module"
    }

    /// A parameter's JSON type, as it appears in the tool's argument object.
    enum ParameterType: String {
        case string
        case number
        case object
    }

    struct Parameter {
        let name: String
        let type: ParameterType
        /// False for parameters that are only required in combination with
        /// another (`launch_app` takes app_name *or* bundle_id;
        /// `find_ui_element` takes pid plus role *or* title_contains). The
        /// registry cannot express one-of, so those read as optional here and
        /// the constraint is stated in the agent's description text.
        let isRequired: Bool
    }

    struct Tool {
        let name: String
        let executor: Executor
        /// Approval is the *agent's* gate, not the executor's: it happens
        /// before dispatch, and `denied_by_user` never crosses the socket
        /// (docs/socket.md).
        let requiresApproval: Bool
        let parameters: [Parameter]

        var timeoutSeconds: TimeInterval { ToolTimeouts.seconds(for: name) }
    }

    static let all: [Tool] = [
        Tool(name: "launch_app", executor: .petApp, requiresApproval: false, parameters: [
            Parameter(name: "app_name", type: .string, isRequired: false),
            Parameter(name: "bundle_id", type: .string, isRequired: false),
        ]),
        Tool(name: "list_running_apps", executor: .petApp, requiresApproval: false, parameters: []),
        Tool(name: "get_frontmost_window", executor: .petApp, requiresApproval: false, parameters: []),
        Tool(name: "find_ui_element", executor: .petApp, requiresApproval: false, parameters: [
            Parameter(name: "pid", type: .number, isRequired: true),
            Parameter(name: "role", type: .string, isRequired: false),
            Parameter(name: "title_contains", type: .string, isRequired: false),
        ]),
        Tool(name: "point_at", executor: .petApp, requiresApproval: false, parameters: [
            Parameter(name: "frame", type: .object, isRequired: true),
        ]),
        Tool(name: "click_element", executor: .petApp, requiresApproval: true, parameters: [
            Parameter(name: "frame", type: .object, isRequired: true),
        ]),
        Tool(name: "run_shell", executor: .petApp, requiresApproval: true, parameters: [
            Parameter(name: "command", type: .string, isRequired: true),
        ]),
        Tool(name: "run_applescript", executor: .petApp, requiresApproval: true, parameters: [
            Parameter(name: "script", type: .string, isRequired: true),
        ]),
        // workspace executor -- listed because the registry is the registry,
        // but the workspace repo has shipped none of them, so an agent with no
        // editor executor injected must not offer these to the model.
        Tool(name: "code_editor", executor: .workspace, requiresApproval: false, parameters: [
            Parameter(name: "task", type: .string, isRequired: true),
            Parameter(name: "project_path", type: .string, isRequired: false),
        ]),
        Tool(name: "open_in_editor", executor: .workspace, requiresApproval: false, parameters: [
            Parameter(name: "path", type: .string, isRequired: true),
        ]),
        Tool(name: "read_file", executor: .workspace, requiresApproval: false, parameters: [
            Parameter(name: "path", type: .string, isRequired: true),
        ]),
        // ai-module executor -- branches the casual conversation into a task
        // session. Never crosses the socket, which is why its registry
        // timeout is a placeholder 0 rather than a duration.
        Tool(name: "open_task_session", executor: .aiModule, requiresApproval: false, parameters: [
            Parameter(name: "title", type: .string, isRequired: true),
            Parameter(name: "brief", type: .string, isRequired: true),
        ]),
    ]

    static func tool(named name: String) -> Tool? {
        all.first { $0.name == name }
    }

    static func tools(for executor: Executor) -> [Tool] {
        all.filter { $0.executor == executor }
    }
}
