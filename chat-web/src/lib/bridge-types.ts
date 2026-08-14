// Mirrors Puck/ClientWindow/ClientChatBridgeMessages.swift. Keep both in sync
// by hand -- this is a local JS<->Swift contract, not the bridge.sock wire
// protocol (that one's already typed in Puck/Bridge/BridgeMessages.swift and
// doesn't change for this project).

export type JSONValue = string | number | boolean | null | JSONValue[] | { [key: string]: JSONValue };

// Puck/Bridge/BridgeMessages.swift's ToolErrorCode, same raw values.
export type ToolErrorCode =
  | "timeout"
  | "pet_app_disconnected"
  | "permission_denied"
  | "not_supported_target"
  | "execution_failed"
  | "unknown_tool"
  | "cancelled";

export type ThemeStyle = "light" | "dark";

export interface WorkspaceJSON {
  id: string;
  name: string;
  projectPath: string | null;
  canOpenEditor: boolean;
}

export interface SessionSummaryJSON {
  id: string;
  workspaceId: string;
  title: string;
  isRunning: boolean;
  lastActivityAt: number | null;
  lastRunOk: boolean | null;
}

// 1:1 with ChatTimelineEntry (ChatSession.swift).
export type TimelineEntryJSON =
  | { kind: "userMessage"; id: string; text: string }
  | { kind: "assistantText"; id: string; text: string }
  | { kind: "toolCall"; id: string; tool: string; args: JSONValue | null }
  | { kind: "toolResult"; id: string; ok: boolean; data: JSONValue | null; error: ToolErrorCode | null; detail: string | null }
  | { kind: "approvalRequested"; id: string; approvalId: string; summary: string }
  | { kind: "done"; id: string; ok: boolean; summary: string };

export interface PendingApprovalJSON {
  approvalId: string;
  summary: string;
}

export interface SessionStateJSON {
  id: string;
  workspaceId: string;
  title: string;
  timeline: TimelineEntryJSON[];
  isRunning: boolean;
  pendingApproval: PendingApprovalJSON | null;
}

// -- Swift -> JS (window.PuckChatBridge.receive) --

export type BridgeInboundMessage =
  | { type: "state:hydrate"; payload: HydratePayload }
  | { type: "state:workspaces"; payload: { workspaces: WorkspaceJSON[]; activeWorkspaceId: string } }
  | { type: "state:sessions"; payload: { workspaceId: string; sessions: SessionSummaryJSON[] } }
  | { type: "state:activeSession"; payload: { session: SessionStateJSON | null } }
  | { type: "session:timelineAppend"; payload: { workspaceId: string; sessionId: string; entry: TimelineEntryJSON } }
  | { type: "session:textChunk"; payload: { workspaceId: string; sessionId: string; entryId: string; delta: string; append: boolean } }
  | { type: "session:runningChanged"; payload: { workspaceId: string; sessionId: string; isRunning: boolean } }
  | { type: "session:pendingApproval"; payload: { workspaceId: string; sessionId: string; approval: PendingApprovalJSON | null } }
  | { type: "state:editorOpen"; payload: { isOpen: boolean; canOpen: boolean } }
  | { type: "state:projectFolderChosen"; payload: { path: string | null } };

export interface HydratePayload {
  themeStyle: ThemeStyle;
  workspaces: WorkspaceJSON[];
  activeWorkspaceId: string;
  activeSessionId: string;
  sessionsByWorkspace: Record<string, SessionSummaryJSON[]>;
  activeSession: SessionStateJSON | null;
  editorOpen: boolean;
}

// -- JS -> Swift (window.webkit.messageHandlers.puckChat.postMessage) --

export type BridgeOutboundMessage =
  | { type: "action:ready"; payload: Record<string, never> }
  | { type: "action:sendMessage"; payload: { workspaceId: string; sessionId: string; text: string } }
  | { type: "action:newSession"; payload: { workspaceId: string; title: string } }
  | { type: "action:newWorkspace"; payload: { name: string; projectPath: string | null } }
  | { type: "action:chooseProjectFolder"; payload: Record<string, never> }
  | { type: "action:switchWorkspace"; payload: { workspaceId: string } }
  | { type: "action:switchSession"; payload: { workspaceId: string; sessionId: string } }
  | { type: "action:respondApproval"; payload: { workspaceId: string; sessionId: string; approvalId: string; approved: boolean } }
  | { type: "action:cancelRun"; payload: { workspaceId: string; sessionId: string } }
  | { type: "action:toggleEditor"; payload: Record<string, never> }
  | { type: "action:openSettings"; payload: Record<string, never> };
