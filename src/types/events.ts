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

/** workspace -> pet-app: state events that drive the pet's reactions. */
export type BridgeEvent =
  | { event: "agent_thinking" }
  | { event: "tool_call"; tool: string; detail?: JSONValue }
  | { event: "tool_result"; ok: boolean }
  | { event: "await_approval"; summary: string }
  | { event: "agent_done"; ok: boolean; summary: string };

export type BridgeEventMessage = { type: "event" } & BridgeEvent;

export type UserInputSource = "voice" | "text";

/** pet-app -> workspace: voice/text command input. */
export interface UserInput {
  type: "user_input";
  text: string;
  source: UserInputSource;
}

/** Every JSON Lines message on the socket, discriminated by `type`. */
export type BridgeMessage =
  | ToolDispatch
  | ToolCancel
  | ToolResult
  | BridgeEventMessage
  | UserInput;
