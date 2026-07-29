/**
 * Socket message types (protocol docs/socket.md, plan/01_protocol.md section 3).
 * Wire format: JSON Lines over the pet-app <-> workspace Unix Domain Socket.
 * Mirrors pet-app/PetAgent/Bridge/{BridgeMessages,JSONValue}.swift.
 */

/** Free-form JSON tree for fields whose shape varies per tool (args/data/detail). */
export type JSONValue =
  | string
  | number
  | boolean
  | null
  | JSONValue[]
  | { [key: string]: JSONValue };

/** workspace -> pet-app: tool execution request. */
export interface ToolDispatch {
  type: "tool_dispatch";
  id: string;
  tool: string;
  args: JSONValue;
}

/**
 * workspace -> pet-app: abandon an in-flight dispatch (user hit stop, or the
 * agent run was aborted). pet-app cancels the handler and replies to the
 * original id with error "cancelled". Unknown/already-completed ids are
 * ignored (idempotent).
 */
export interface ToolCancel {
  type: "tool_cancel";
  id: string;
}

/**
 * Standard tool_result error codes that cross the socket. `denied_by_user`
 * is deliberately excluded here -- approval happens inside ai-module before
 * dispatch, so it never reaches pet-app/workspace on the wire. See
 * ToolResultErrorCode in agent-interface.ts for the model-facing superset.
 */
export type ToolErrorCode =
  | "timeout"
  | "pet_app_disconnected"
  | "permission_denied"
  | "not_supported_target"
  | "execution_failed"
  | "unknown_tool"
  | "cancelled";

/** pet-app -> workspace: tool execution result, matched to a dispatch by id. */
export interface ToolResult {
  type: "tool_result";
  id: string;
  ok: boolean;
  /** Present when ok is true. Shape is tool-specific -- see docs/tools.md. */
  data?: JSONValue;
  /** Present when ok is false. Standard code only -- see ToolErrorCode. */
  error?: ToolErrorCode;
  /** Optional human-readable failure specifics (e.g. shell exit code). */
  detail?: string;
}

/**
 * workspace -> pet-app: state events that drive the pet's reactions.
 *
 * await_approval's approval_id (2026-07-29) exists because the approval UI
 * itself now lives in pet-app's F13 client window rather than workspace's own
 * renderer -- resolving it has to round-trip the socket via ApprovalResponse,
 * so the event needs enough to route that response back to the right pending
 * `resolve` (plan/01_protocol.md 3.6). workspace_id/session_id live on the
 * wrapper (BridgeEventMessage below), since every event kind needs them once
 * multiple sessions can be open at once -- not just await_approval.
 *
 * text_chunk, and tool_call/tool_result's id/args/data/error/detail
 * (2026-07-29) exist because this stream now feeds two audiences, not just
 * the pet's reactions: pet-app's F13 chat view needs a real timeline
 * (streaming assistant text, which tool ran with what args, what it actually
 * returned) -- effectively AgentCallbacks proxied over the socket. `detail`
 * on tool_call is unchanged from its original purpose (a curated summary,
 * e.g. code_editor's `{"path":...}` for jump-on-change) and is distinct from
 * `args` (the tool's raw call arguments, new).
 */
export type BridgeEvent =
  | { event: "agent_thinking" }
  | { event: "text_chunk"; text: string }
  | { event: "tool_call"; id: string; tool: string; args?: JSONValue; detail?: JSONValue }
  | { event: "tool_result"; id: string; ok: boolean; data?: JSONValue; error?: ToolErrorCode; detail?: string }
  | { event: "await_approval"; summary: string; approval_id: string }
  | { event: "agent_done"; ok: boolean; summary: string };

/**
 * workspace_id/session_id (2026-07-29) route the event to the right chat
 * session in pet-app's F13 client window -- without them, once more than one
 * session is open, pet-app has no way to tell which session's timeline an
 * incoming agent_thinking/tool_call/tool_result/agent_done belongs to.
 */
export type BridgeEventMessage = { type: "event"; workspace_id: string; session_id: string } & BridgeEvent;

export type UserInputSource = "voice" | "text";

/** An image attached to a user_input (e.g. F14 drag capture). */
export interface Attachment {
  type: "image";
  /** Local temp file path on the same machine -- not base64, to keep the socket message small. */
  path: string;
}

/**
 * pet-app -> workspace: voice/text command input.
 *
 * workspace_id/session_id (2026-07-29, plan/01_protocol.md 3.4) default to
 * "default" when omitted -- existing single-workspace/single-session
 * consumers are unaffected.
 */
export interface UserInput {
  type: "user_input";
  text: string;
  source: UserInputSource;
  workspace_id?: string;
  session_id?: string;
  attachments?: Attachment[];
}

/**
 * pet-app -> workspace: request a new workspace (project folder or pure-chat).
 * Confirmed by WorkspaceCreate, which is the one that actually assigns
 * workspace_id (2026-07-29, plan/01_protocol.md 3.4).
 */
export interface WorkspaceCreateRequest {
  type: "workspace_create_request";
  name: string;
  /** Omitted for a pure-chat workspace -- code_editor and the editor view are unavailable for it. */
  project_path?: string;
}

/** workspace -> pet-app: confirms a workspace now exists. */
export interface WorkspaceCreate {
  type: "workspace_create";
  workspace_id: string;
  name: string;
  project_path?: string;
}

/**
 * Who created a session: `user` via the sidebar's "new chat", or `agent` when
 * it branched a casual conversation into a task session on its own judgement
 * (ai-module's open_task_session tool, plan/04_ai-module.md 3.7).
 */
export type SessionOrigin = "user" | "agent";

/**
 * pet-app -> workspace: request a new chat session under a workspace.
 * Confirmed by SessionCreate, which assigns session_id.
 */
export interface SessionCreateRequest {
  type: "session_create_request";
  workspace_id: string;
  title: string;
}

/** workspace -> pet-app: confirms a session now exists. */
export interface SessionCreate {
  type: "session_create";
  workspace_id: string;
  session_id: string;
  title: string;
  origin: SessionOrigin;
}

/**
 * workspace -> pet-app: the embeddable editor view bundle (file tree + Monaco)
 * for this workspace is being served at `url`, for pet-app's WKWebView to
 * load (plan/01_protocol.md 3.5). This traffic never crosses this socket
 * itself -- url points at workspace's own local loopback server.
 */
export interface EditorViewReady {
  type: "editor_view_ready";
  workspace_id: string;
  url: string;
}

export type EditorViewUnavailableReason = "no_project_path";

/** workspace -> pet-app: no editor view for this workspace (e.g. no project_path bound). */
export interface EditorViewUnavailable {
  type: "editor_view_unavailable";
  workspace_id: string;
  reason: EditorViewUnavailableReason;
}

/**
 * pet-app -> workspace: resolve a pending await_approval by id. Unknown or
 * already-resolved ids are ignored (idempotent) -- see plan/01_protocol.md 3.6.
 */
export interface ApprovalResponse {
  type: "approval_response";
  approval_id: string;
  approved: boolean;
}

/**
 * pet-app -> workspace: abort the in-flight run() for a session -- the whole
 * conversation turn, a different level from ToolCancel (which abandons one
 * tool dispatch). See plan/01_protocol.md 3.6.
 */
export interface RunCancel {
  type: "run_cancel";
  session_id: string;
}

/** Every JSON Lines message on the socket, discriminated by `type`. */
export type BridgeMessage =
  | ToolDispatch
  | ToolCancel
  | ToolResult
  | BridgeEventMessage
  | UserInput
  | WorkspaceCreateRequest
  | WorkspaceCreate
  | SessionCreateRequest
  | SessionCreate
  | EditorViewReady
  | EditorViewUnavailable
  | ApprovalResponse
  | RunCancel;
