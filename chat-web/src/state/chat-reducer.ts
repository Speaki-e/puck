import type {
  BridgeInboundMessage,
  SessionStateJSON,
  SessionSummaryJSON,
  ThemeStyle,
  WorkspaceJSON,
} from "../lib/bridge-types";

export interface ChatState {
  hydrated: boolean;
  themeStyle: ThemeStyle;
  workspaces: WorkspaceJSON[];
  activeWorkspaceId: string;
  activeSessionId: string;
  sessionsByWorkspace: Record<string, SessionSummaryJSON[]>;
  activeSession: SessionStateJSON | null;
  editorOpen: boolean;
  editorCanOpen: boolean;
}

// Local-only action, never sent by Swift: ChatInputBar dispatches this on
// submit for an immediate echo, matching ChatView.send()'s
// session.appendUserMessage call today -- a view-layer concern, not
// something that needs a round trip through the bridge.
export type LocalOptimisticUserMessage = {
  type: "local:optimisticUserMessage";
  payload: { workspaceId: string; sessionId: string; id: string; text: string };
};

export type ChatAction = BridgeInboundMessage | LocalOptimisticUserMessage;

export const initialChatState: ChatState = {
  hydrated: false,
  themeStyle: "dark",
  workspaces: [],
  activeWorkspaceId: "default",
  activeSessionId: "default",
  sessionsByWorkspace: {},
  activeSession: null,
  editorOpen: false,
  editorCanOpen: false,
};

function markSessionRunning(
  sessionsByWorkspace: ChatState["sessionsByWorkspace"],
  workspaceId: string,
  sessionId: string,
  isRunning: boolean,
): ChatState["sessionsByWorkspace"] {
  const sessions = sessionsByWorkspace[workspaceId];
  if (!sessions) return sessionsByWorkspace;
  return {
    ...sessionsByWorkspace,
    [workspaceId]: sessions.map((session) => (session.id === sessionId ? { ...session, isRunning } : session)),
  };
}

/**
 * Folds bridge pushes into UI state. Deliberately dumb: Swift (ClientWindowStore/
 * ChatSession, the real source of truth) has already computed everything --
 * this must not re-derive session/streaming logic itself, or it drifts from
 * the native behavior it's supposed to mirror (docs/decisions.md, the
 * textChunk append/insert split below is why session:textChunk carries an
 * explicit `append` flag instead of this reducer guessing).
 */
export function chatReducer(state: ChatState, message: ChatAction): ChatState {
  switch (message.type) {
    case "local:optimisticUserMessage": {
      const { workspaceId, sessionId, id, text } = message.payload;
      if (!state.activeSession || state.activeSession.workspaceId !== workspaceId || state.activeSession.id !== sessionId) {
        return state;
      }
      return {
        ...state,
        activeSession: {
          ...state.activeSession,
          timeline: [...state.activeSession.timeline, { kind: "userMessage" as const, id, text }],
        },
      };
    }

    case "state:hydrate": {
      const { payload } = message;
      return {
        ...state,
        hydrated: true,
        themeStyle: payload.themeStyle,
        workspaces: payload.workspaces,
        activeWorkspaceId: payload.activeWorkspaceId,
        activeSessionId: payload.activeSessionId,
        sessionsByWorkspace: payload.sessionsByWorkspace,
        activeSession: payload.activeSession,
        editorOpen: payload.editorOpen,
        editorCanOpen: payload.workspaces.find((workspace) => workspace.id === payload.activeWorkspaceId)?.canOpenEditor ?? false,
      };
    }

    case "state:workspaces": {
      const { payload } = message;
      const activeWorkspace = payload.workspaces.find((workspace) => workspace.id === payload.activeWorkspaceId);
      return {
        ...state,
        workspaces: payload.workspaces,
        activeWorkspaceId: payload.activeWorkspaceId,
        editorCanOpen: activeWorkspace?.canOpenEditor ?? false,
      };
    }

    case "state:sessions": {
      const { payload } = message;
      return {
        ...state,
        sessionsByWorkspace: { ...state.sessionsByWorkspace, [payload.workspaceId]: payload.sessions },
      };
    }

    case "state:activeSession": {
      return { ...state, activeSession: message.payload.session };
    }

    case "session:timelineAppend": {
      const { workspaceId, sessionId, entry } = message.payload;
      if (!state.activeSession || state.activeSession.workspaceId !== workspaceId || state.activeSession.id !== sessionId) {
        return state;
      }
      return {
        ...state,
        activeSession: { ...state.activeSession, timeline: [...state.activeSession.timeline, entry] },
      };
    }

    case "session:textChunk": {
      const { workspaceId, sessionId, entryId, delta, append } = message.payload;
      if (!state.activeSession || state.activeSession.workspaceId !== workspaceId || state.activeSession.id !== sessionId) {
        return state;
      }
      const timeline = state.activeSession.timeline;
      if (append) {
        const updated = timeline.map((entry) =>
          entry.kind === "assistantText" && entry.id === entryId ? { ...entry, text: entry.text + delta } : entry,
        );
        return { ...state, activeSession: { ...state.activeSession, timeline: updated } };
      }
      const inserted = [...timeline, { kind: "assistantText" as const, id: entryId, text: delta }];
      return { ...state, activeSession: { ...state.activeSession, timeline: inserted } };
    }

    case "session:runningChanged": {
      const { workspaceId, sessionId, isRunning } = message.payload;
      const sessionsByWorkspace = markSessionRunning(state.sessionsByWorkspace, workspaceId, sessionId, isRunning);
      if (!state.activeSession || state.activeSession.workspaceId !== workspaceId || state.activeSession.id !== sessionId) {
        return { ...state, sessionsByWorkspace };
      }
      return { ...state, sessionsByWorkspace, activeSession: { ...state.activeSession, isRunning } };
    }

    case "session:pendingApproval": {
      const { workspaceId, sessionId, approval } = message.payload;
      if (!state.activeSession || state.activeSession.workspaceId !== workspaceId || state.activeSession.id !== sessionId) {
        return state;
      }
      return { ...state, activeSession: { ...state.activeSession, pendingApproval: approval } };
    }

    case "state:editorOpen": {
      return { ...state, editorOpen: message.payload.isOpen, editorCanOpen: message.payload.canOpen };
    }

    case "state:projectFolderChosen":
      // Handled by whichever component is awaiting it (NewWorkspaceDialog) --
      // not folded into ChatState, see usePuckBridge's dedicated subscription.
      return state;

    default:
      return state;
  }
}
