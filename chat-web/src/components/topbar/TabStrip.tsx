import { useEffect, useState } from "react";
import { Plus, X } from "lucide-react";
import { StatusDot, sessionDotState } from "@/components/ui/status-dot";
import { cn } from "@/lib/utils";
import { useChatState } from "@/state/chat-context";
import { usePuckBridge } from "@/hooks/usePuckBridge";
import { EditorToggleButton } from "./EditorToggleButton";
import { SettingsButton } from "./SettingsButton";

interface OpenTab {
  workspaceId: string;
  sessionId: string;
}

function isSameTab(a: OpenTab, b: OpenTab) {
  return a.workspaceId === b.workspaceId && a.sessionId === b.sessionId;
}

/**
 * Open tabs are renderer-local UI state, never bridge state: an array of
 * {workspaceId, sessionId}. "Active" is *not* stored per-tab -- it's derived
 * from `state.activeSession`, the one thing the bridge round-trips reliably
 * on every `switchSession` (unlike `state.activeWorkspaceId`/`activeSessionId`,
 * which only update on hydrate/workspace-list pushes -- see chat-reducer.ts).
 * Selecting a session anywhere (sidebar or a tab) always goes through
 * `switchSession`, so the effect below is the single place a session is
 * added to the strip.
 */
export function TabStrip() {
  const state = useChatState();
  const { switchSession, newSession } = usePuckBridge();
  const [tabs, setTabs] = useState<OpenTab[]>([]);

  const activeWorkspaceId = state.activeSession?.workspaceId;
  const activeSessionId = state.activeSession?.id;

  useEffect(() => {
    if (!activeWorkspaceId || !activeSessionId) return;
    const current = { workspaceId: activeWorkspaceId, sessionId: activeSessionId };
    setTabs((prev) => (prev.some((tab) => isSameTab(tab, current)) ? prev : [...prev, current]));
  }, [activeWorkspaceId, activeSessionId]);

  const closeTab = (tab: OpenTab) => {
    const index = tabs.findIndex((t) => isSameTab(t, tab));
    if (index === -1) return;
    const remaining = [...tabs.slice(0, index), ...tabs.slice(index + 1)];
    setTabs(remaining);

    const wasActive = activeWorkspaceId === tab.workspaceId && activeSessionId === tab.sessionId;
    if (wasActive && remaining.length > 0) {
      // Activate a neighbour: whatever slid into this slot, else the new last tab.
      const neighbour = remaining[index] ?? remaining[index - 1];
      switchSession(neighbour.workspaceId, neighbour.sessionId);
    }
    // Closing the last tab intentionally leaves nothing active in the strip --
    // the bridge's active session is untouched, it just has no open tab.
  };

  return (
    <div className="flex h-[34px] shrink-0 items-stretch bg-surface border-b border-hairline">
      {tabs.map((tab) => {
        const session = state.sessionsByWorkspace[tab.workspaceId]?.find((s) => s.id === tab.sessionId);
        const active = activeWorkspaceId === tab.workspaceId && activeSessionId === tab.sessionId;
        const title = session?.title ?? state.activeSession?.title ?? "";
        return (
          <div
            key={`${tab.workspaceId}:${tab.sessionId}`}
            className={cn(
              "relative flex max-w-[260px] shrink-0 items-center gap-1.5 border-r border-hairline px-2.5 text-xs text-muted-foreground",
              active && "bg-canvas text-foreground before:absolute before:inset-x-0 before:top-0 before:h-0.5 before:bg-brand before:content-['']",
            )}
          >
            <button
              type="button"
              onClick={() => switchSession(tab.workspaceId, tab.sessionId)}
              className="flex min-w-0 items-center gap-1.5"
              title={title}
            >
              <StatusDot state={session ? sessionDotState(session) : "idle"} />
              <span className="max-w-[200px] truncate">{title}</span>
            </button>
            <button
              type="button"
              onClick={() => closeTab(tab)}
              aria-label={`${title} 탭 닫기`}
              className="shrink-0 text-faint hover:text-foreground"
            >
              <X className="size-3" />
            </button>
          </div>
        );
      })}

      <button
        type="button"
        onClick={() => activeWorkspaceId && newSession(activeWorkspaceId, "새 채팅")}
        disabled={!activeWorkspaceId}
        aria-label="새 채팅"
        className="flex w-[30px] shrink-0 items-center justify-center text-mute hover:text-foreground disabled:opacity-40"
      >
        <Plus className="size-3.5" />
      </button>

      <div className="ml-auto flex items-center gap-0.5 px-2">
        <EditorToggleButton />
        <SettingsButton />
      </div>
    </div>
  );
}
