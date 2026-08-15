//
//  ToolRegistry.swift
//  Puck
//
//  Tool registry mirror (docs/tools.md, plan/01_protocol.md section 4).
//  Reference implementation -- consumers copy this file, the way pet-app
//  already copies BridgeMessages.swift and ToolTimeouts.swift.
//
//  Why a Swift mirror now: the registry was TS-only because the only Swift
//  consumer (pet-app's executor) is told which tool to run by the wire and
//  never has to enumerate them. An agent does -- it has to hand the model the
//  full tool list -- and the agent now runs in Swift, inside PuckClient.
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
    /// tool_dispatch; `delegated` ones are run by the agent's own host through
    /// a closure it was constructed with, never over the socket.
    ///
    /// The `workspace` and `ai-module` cases are gone with the apps that named
    /// them (2026-08-15). `ai-module` never dispatched anything in the first
    /// place -- its one entry was always handled inline -- and `workspace`'s
    /// three tools are all delegated now, which is what `delegated` says.
    enum Executor: String {
        case petApp = "pet-app"
        case delegated
    }

    /// A parameter's JSON type, as it appears in the tool's argument object.
    enum ParameterType: String {
        case string
        case number
        case object
    }

    /// How a tool's approval requirement works. Mirrors TypeScript's ToolApproval
    /// union (src/types/tools.ts) -- `.requiredWithWhitelist`/`.acpInternal` are
    /// their own cases (not folded into a Bool) because they change *who*
    /// decides, not just *whether* a prompt appears: requiredWithWhitelist
    /// (run_shell) skips the prompt only for allowlisted commands; acpInternal
    /// (code_editor) routes through Claude Code's own ACP approval flow, so
    /// pet-app never shows a prompt for it at all.
    enum Approval: String {
        case notRequired = "not_required"
        case required = "required"
        case requiredWithWhitelist = "required_with_whitelist"
        case acpInternal = "acp_internal"
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
        /// The full approval semantics -- see `Approval`.
        let approval: Approval
        let parameters: [Parameter]

        /// Whether a consumer should prompt before running, collapsing
        /// `.acpInternal`/`.notRequired` to false and `.required`/
        /// `.requiredWithWhitelist` to true -- the coarse view most call
        /// sites (e.g. AgentRunner's gating) actually need.
        var requiresApproval: Bool {
            switch approval {
            case .notRequired, .acpInternal: return false
            case .required, .requiredWithWhitelist: return true
            }
        }

        var timeoutSeconds: TimeInterval { ToolTimeouts.seconds(for: name) }
    }

    static let all: [Tool] = [
        Tool(name: "launch_app", executor: .petApp, approval: .notRequired, parameters: [
            Parameter(name: "app_name", type: .string, isRequired: false),
            Parameter(name: "bundle_id", type: .string, isRequired: false),
        ]),
        Tool(name: "list_running_apps", executor: .petApp, approval: .notRequired, parameters: []),
        Tool(name: "get_frontmost_window", executor: .petApp, approval: .notRequired, parameters: []),
        Tool(name: "find_ui_element", executor: .petApp, approval: .notRequired, parameters: [
            Parameter(name: "pid", type: .number, isRequired: true),
            Parameter(name: "role", type: .string, isRequired: false),
            Parameter(name: "title_contains", type: .string, isRequired: false),
        ]),
        Tool(name: "point_at", executor: .petApp, approval: .notRequired, parameters: [
            Parameter(name: "frame", type: .object, isRequired: true),
        ]),
        Tool(name: "click_element", executor: .petApp, approval: .required, parameters: [
            Parameter(name: "frame", type: .object, isRequired: true),
        ]),
        Tool(name: "run_shell", executor: .petApp, approval: .requiredWithWhitelist, parameters: [
            Parameter(name: "command", type: .string, isRequired: true),
        ]),
        Tool(name: "run_applescript", executor: .petApp, approval: .required, parameters: [
            Parameter(name: "script", type: .string, isRequired: true),
        ]),
        // Delegated executor -- none of these are dispatched over bridge.sock
        // like a .petApp tool; each is offered to the model only when
        // AgentRunner is constructed with the matching delegate closure
        // (delegateCodeEditor/delegateReadFile/delegateOpenInEditor).
        // code_editor spawns an ACP agent through CodeEditorRunner;
        // open_in_editor/read_file are answered by PuckClient's own native
        // editor pane (Puck/ClientWindow/Editor).
        Tool(name: "code_editor", executor: .delegated, approval: .acpInternal, parameters: [
            Parameter(name: "task", type: .string, isRequired: true),
            Parameter(name: "project_path", type: .string, isRequired: true),
        ]),
        Tool(name: "open_in_editor", executor: .delegated, approval: .notRequired, parameters: [
            Parameter(name: "path", type: .string, isRequired: true),
        ]),
        Tool(name: "read_file", executor: .delegated, approval: .notRequired, parameters: [
            Parameter(name: "path", type: .string, isRequired: true),
        ]),
        // Branches the casual conversation into a task session. Never crosses
        // the socket, which is why its registry timeout is a placeholder 0
        // rather than a duration.
        Tool(name: "open_task_session", executor: .delegated, approval: .notRequired, parameters: [
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
