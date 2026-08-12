/**
 * Distributed debugging log format (protocol docs/logging.md, plan/01_protocol.md
 * section 7). JSON Lines, one file per day under
 * ~/Library/Application Support/Puck/logs/. Joining on `id` across the
 * three sources reconstructs a tool call's full path.
 */

import type { JSONValue } from "./events.js";

export type LogSource = "agent" | "pet-app" | "workspace";

interface LogEntryBase {
  /** ISO 8601 timestamp. */
  ts: string;
  src: LogSource;
  /** Correlates this entry with the other sources' entries for the same call. */
  id: string;
}

export interface ToolCallLogEntry extends LogEntryBase {
  kind: "tool_call";
  src: "agent";
  tool: string;
  args: JSONValue;
}

export interface ToolExecStartLogEntry extends LogEntryBase {
  kind: "tool_exec_start";
  src: "pet-app" | "workspace";
}

export interface ToolExecEndLogEntry extends LogEntryBase {
  kind: "tool_exec_end";
  src: "pet-app" | "workspace";
  ok: boolean;
}

export interface ToolResultLogEntry extends LogEntryBase {
  kind: "tool_result";
  src: "agent";
  ok: boolean;
}

/**
 * The four kinds documented today. Not a closed set by design -- new `kind`
 * values may be added as logging coverage grows; treat unrecognized `kind`
 * values as forward-compatible rather than a parse error.
 */
export type LogEntry =
  | ToolCallLogEntry
  | ToolExecStartLogEntry
  | ToolExecEndLogEntry
  | ToolResultLogEntry;
