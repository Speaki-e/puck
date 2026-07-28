/**
 * Tool registry (protocol docs/tools.md, plan/01_protocol.md section 4).
 * This is a real .ts module (not .d.ts): executor/approval/timeout are
 * runtime values ai-module imports and uses to build its tool-use request
 * and dispatch routing -- a declaration file cannot hold them.
 */

export type ToolExecutorKind = "pet-app" | "workspace";

/**
 * How a tool's approval requirement works. `whitelisted` and `acp_internal`
 * are their own variants (not booleans) because they change *who* decides,
 * not just *whether* a prompt appears:
 * - `required_with_whitelist`: run_shell -- approval unless the command
 *   matches an allowlist maintained outside this registry.
 * - `acp_internal`: code_editor -- Claude Code's own ACP approval flow
 *   handles this; pet-app never shows a prompt for it.
 */
export type ToolApproval =
  | { kind: "not_required" }
  | { kind: "required" }
  | { kind: "required_with_whitelist" }
  | { kind: "acp_internal" };

export interface ToolParam {
  name: string;
  /** JSON value kind. Object params (e.g. frame) are detailed in `description`. */
  type: "string" | "number" | "boolean" | "object";
  required: boolean;
  description: string;
}

export interface ToolDefinition {
  name: string;
  executor: ToolExecutorKind;
  approval: ToolApproval;
  timeoutSec: number;
  params: ToolParam[];
  description: string;
  /**
   * Freeform note on the tool_result.data shape on success. Most tools
   * return an object or null; run_applescript is the one exception and
   * returns a bare string. workspace-executed tools are marked TBD because
   * workspace has not been implemented yet -- do not treat those notes as
   * settled contract until workspace ships and this file is updated to match.
   */
  responseNote: string;
}

export const not_required: ToolApproval = { kind: "not_required" };
export const required: ToolApproval = { kind: "required" };
export const required_with_whitelist: ToolApproval = { kind: "required_with_whitelist" };
export const acp_internal: ToolApproval = { kind: "acp_internal" };

/**
 * frame coordinate convention (applies to every `frame` param/field below):
 * Quartz global screen coordinates -- primary display top-left origin, Y
 * down, points. Same space as CGWindowList/Accessibility APIs. NOT AppKit's
 * bottom-left origin.
 */
export const TOOL_REGISTRY: readonly ToolDefinition[] = [
  {
    name: "launch_app",
    executor: "pet-app",
    approval: not_required,
    timeoutSec: 15,
    params: [
      { name: "app_name", type: "string", required: false, description: "App display name. Exactly one of app_name/bundle_id must be present." },
      { name: "bundle_id", type: "string", required: false, description: "App bundle identifier. Exactly one of app_name/bundle_id must be present." },
    ],
    description: "Launch an app and return its pid.",
    responseNote: "{ pid: number }",
  },
  {
    name: "list_running_apps",
    executor: "pet-app",
    approval: not_required,
    timeoutSec: 5,
    params: [],
    description: "List currently running apps (regular activation policy only).",
    responseNote: "Array<{ pid: number, name: string, bundle_id: string }>",
  },
  {
    name: "get_frontmost_window",
    executor: "pet-app",
    approval: not_required,
    timeoutSec: 5,
    params: [],
    description: "Return the frontmost window's info.",
    responseNote: "null if no frontmost window, else { owner_name: string, title: string, frame: Frame }",
  },
  {
    name: "find_ui_element",
    executor: "pet-app",
    approval: not_required,
    timeoutSec: 15,
    params: [
      { name: "pid", type: "number", required: true, description: "Target app's pid." },
      { name: "role", type: "string", required: false, description: "AX role to match. At least one of role/title_contains must be present." },
      { name: "title_contains", type: "string", required: false, description: "Substring to match against title. At least one of role/title_contains must be present." },
    ],
    description: "Query Accessibility for a matching UI element.",
    responseNote: "null if not found (this is ok=true, not a failure), else { role: string, title: string, frame?: Frame, enabled?: boolean }",
  },
  {
    name: "point_at",
    executor: "pet-app",
    approval: not_required,
    timeoutSec: 30,
    params: [
      { name: "frame", type: "object", required: true, description: "Frame to point at, in Quartz global screen coordinates." },
    ],
    description: "Pet walks to the coordinate and points. Replies once the Point animation actually starts (not on dispatch).",
    responseNote: "null",
  },
  {
    name: "click_element",
    executor: "pet-app",
    approval: required,
    timeoutSec: 15,
    params: [
      { name: "frame", type: "object", required: true, description: "Frame whose center point receives a synthesized CGEvent click." },
    ],
    description: "Synthesize a click at frame's center. System dialogs are not supported -- see not_supported_target.",
    responseNote: "null. Returns error not_supported_target for system dialog targets; fall back to point_at plus user guidance in that case.",
  },
  {
    name: "run_shell",
    executor: "pet-app",
    approval: required_with_whitelist,
    timeoutSec: 60,
    params: [
      { name: "command", type: "string", required: true, description: "Shell command to execute." },
    ],
    description: "Run a shell command.",
    responseNote: "{ stdout: string, stderr: string, exit_code: number }",
  },
  {
    name: "run_applescript",
    executor: "pet-app",
    approval: required,
    timeoutSec: 60,
    params: [
      { name: "script", type: "string", required: true, description: "AppleScript source to execute." },
    ],
    description: "Run an AppleScript.",
    responseNote: "Bare string (the script's result), NOT an object like every other tool -- e.g. \"ok\":true,\"data\":\"some result\". Consumers must not assume tool_result.data is always an object.",
  },
  {
    name: "code_editor",
    executor: "workspace",
    approval: acp_internal,
    timeoutSec: 600,
    params: [
      { name: "task", type: "string", required: true, description: "Natural-language coding task description." },
      { name: "project_path", type: "string", required: true, description: "Project root to run Claude Code against." },
    ],
    description: "Delegate a coding task to Claude Code via ACP and return a summary of the result.",
    responseNote: "TBD -- workspace has not been implemented yet. Expected to be a summary of the ACP run; update this note once workspace ships code_editor.",
  },
  {
    name: "open_in_editor",
    executor: "workspace",
    approval: not_required,
    timeoutSec: 10,
    params: [
      { name: "path", type: "string", required: true, description: "File path to open as a Monaco tab." },
    ],
    description: "Open a file as a Monaco editor tab.",
    responseNote: "TBD -- workspace has not been implemented yet.",
  },
  {
    name: "read_file",
    executor: "workspace",
    approval: not_required,
    timeoutSec: 10,
    params: [
      { name: "path", type: "string", required: true, description: "File path to read." },
    ],
    description: "Return a file's contents (read-only, does not open a tab).",
    responseNote: "TBD -- workspace has not been implemented yet. Expected to carry file contents as a string; update this note once workspace ships read_file.",
  },
];
