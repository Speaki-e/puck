/**
 * ai-module interface (plan/01_protocol.md section 5; protocol's own docs/agent-interface.md was removed).
 */

import type { Attachment, JSONValue, ToolErrorCode } from "./events.js";

export interface Frame {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface WindowInfo {
  owner_name: string;
  title: string;
  frame: Frame;
}

export interface Context {
  frontmostApp?: string;
  openWindows?: WindowInfo[];
  editorOpenFiles?: string[];
  recentActions?: string[];
  /**
   * project_path of the workspace the current session belongs to (2026-07-29).
   * Auto-injected by the caller so code_editor calls don't need the model to
   * specify it every time.
   */
  projectPath?: string;
}

/**
 * Superset of the socket-level ToolErrorCode (events.ts) with `denied_by_user`
 * added. denied_by_user never crosses the socket -- approval happens inside
 * ai-module before dispatch -- so it only ever appears in the value
 * AgentCallbacks.onToolResult reports back to the model, never in a
 * events.ts ToolResult read off the wire.
 */
export type ToolResultErrorCode = ToolErrorCode | "denied_by_user";

/**
 * Local result shape returned by ToolExecutor.execute -- distinct from
 * events.ts's ToolResult (which carries the wire fields `type`/`id`). This
 * is the pre-wire value a petAppProxy/editorLocal executor resolves with;
 * petAppProxy's implementation is the one that additionally speaks the wire
 * ToolResult format under the hood.
 */
export interface ToolExecutionResult {
  ok: boolean;
  data?: JSONValue;
  error?: ToolResultErrorCode;
  detail?: string;
}

export interface AgentCallbacks {
  onTextChunk(text: string): void;
  /** `id` is the tool_use id -- Claude can emit multiple tool_use blocks per turn (parallel tool use). */
  onToolCallStart(id: string, tool: string, args: JSONValue): void;
  onToolResult(
    id: string,
    ok: boolean,
    data?: JSONValue,
    error?: ToolResultErrorCode,
    detail?: string,
  ): void;
  onApprovalRequired(summary: string, resolve: (approved: boolean) => void): void;
  /**
   * Fires when the agent calls open_task_session on its own judgement
   * (2026-07-29, plan/04_ai-module.md 3.7). The caller (workspace) converts
   * this into a session_create(origin=agent) socket event so pet-app's
   * sidebar picks it up.
   */
  onSessionCreated(sessionId: string, title: string): void;
  onDone(ok: boolean, summary: string): void;
}

export interface ToolExecutor {
  execute(tool: string, args: JSONValue, signal?: AbortSignal): Promise<ToolExecutionResult>;
}

/**
 * ai-module's entry point. Constructed with two ToolExecutor instances
 * (petAppProxy: socket proxy to pet-app, editorLocal: in-process workspace
 * executor) and API key/model injected at construction time -- ai-module
 * does not persist either. CLI testing substitutes a mock ToolExecutor.
 *
 * `sessionId` (2026-07-29): the caller invokes run() once per session, and
 * ai-module keeps each session's history separate under this key -- memory
 * never bleeds between sessions (plan/04_ai-module.md 3.4).
 *
 * `attachments` (2026-07-29, optional): images attached to this turn (e.g.
 * F14 drag capture).
 *
 * `signal`: user-initiated abort. On abort, ai-module stops streaming, sends
 * tool_cancel via petAppProxy for any in-flight pet-app executor call, then
 * resolves via onDone(false, "aborted").
 */
export type AgentRun = (
  command: string,
  sessionId: string,
  context: Context,
  callbacks: AgentCallbacks,
  attachments?: Attachment[],
  signal?: AbortSignal,
) => Promise<void>;
