import { useState } from "react";
import { PanelLeft, PanelLeftClose, SquarePen } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { useChatState } from "@/state/chat-context";
import { usePuckBridge } from "@/hooks/usePuckBridge";
import { SessionList } from "./SessionList";
import { WorkspaceSwitcher } from "./WorkspaceSwitcher";

const EXPANDED_WIDTH = 220;
const COLLAPSED_WIDTH = 68;

export function Sidebar() {
  const state = useChatState();
  const { switchWorkspace, switchSession, newSession } = usePuckBridge();
  const [expanded, setExpanded] = useState(true);

  const sessions = state.sessionsByWorkspace[state.activeWorkspaceId] ?? [];

  return (
    <aside
      className="flex h-full shrink-0 flex-col border-r border-hairline bg-surface transition-[width] duration-[180ms] ease-in-out"
      style={{ width: expanded ? EXPANDED_WIDTH : COLLAPSED_WIDTH }}
    >
      <div className="h-7 shrink-0" /> {/* clears the native titlebar traffic lights */}

      <div className={cn("flex items-center gap-1 px-2 pb-2", !expanded && "flex-col")}>
        <WorkspaceSwitcher
          workspaces={state.workspaces}
          activeWorkspaceId={state.activeWorkspaceId}
          expanded={expanded}
          onSelect={switchWorkspace}
        />
        <Button
          type="button"
          variant="ghost"
          size="icon-sm"
          className="ml-auto shrink-0"
          onClick={() => setExpanded((value) => !value)}
          aria-label={expanded ? "사이드바 접기" : "사이드바 펼치기"}
        >
          {expanded ? <PanelLeftClose className="size-4" /> : <PanelLeft className="size-4" />}
        </Button>
      </div>

      <div className="px-2 pb-1">
        <Button
          type="button"
          variant="outline"
          className={cn("w-full justify-start gap-2", !expanded && "justify-center px-0")}
          onClick={() => newSession(state.activeWorkspaceId, "새 채팅")}
        >
          <SquarePen className="size-4" />
          {expanded && "새 채팅"}
        </Button>
      </div>

      {expanded ? (
        <SessionList sessions={sessions} activeSessionId={state.activeSessionId} onSelect={(sessionId) => switchSession(state.activeWorkspaceId, sessionId)} />
      ) : (
        <div className="flex-1" />
      )}
    </aside>
  );
}
