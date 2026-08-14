import { useState } from "react";
import { ChevronRight, PanelLeft, PanelLeftClose, Plus, SquarePen } from "lucide-react";
import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import { cn } from "@/lib/utils";
import { useChatState } from "@/state/chat-context";
import { usePuckBridge } from "@/hooks/usePuckBridge";
import type { SessionSummaryJSON, WorkspaceJSON } from "@/lib/bridge-types";
import { SessionRow } from "./SessionRow";
import { NewWorkspaceDialog } from "./NewWorkspaceDialog";

const EXPANDED_WIDTH = 220;
const COLLAPSED_WIDTH = 68;

export function Sidebar() {
  const state = useChatState();
  const { switchSession, newSession } = usePuckBridge();
  const [expanded, setExpanded] = useState(true);
  const [showNewWorkspace, setShowNewWorkspace] = useState(false);
  // Collapsed *workspace groups*, not the sidebar itself -- no persistence,
  // matches the plain "click to expand" tree the spec asks for.
  const [collapsedWorkspaceIds, setCollapsedWorkspaceIds] = useState<Set<string>>(new Set());

  const toggleWorkspace = (workspaceId: string) => {
    setCollapsedWorkspaceIds((prev) => {
      const next = new Set(prev);
      if (next.has(workspaceId)) next.delete(workspaceId);
      else next.add(workspaceId);
      return next;
    });
  };

  return (
    <aside
      className="flex h-full shrink-0 flex-col border-r border-hairline bg-surface transition-[width] duration-[180ms] ease-in-out"
      style={{ width: expanded ? EXPANDED_WIDTH : COLLAPSED_WIDTH }}
    >
      <div className="h-7 shrink-0" /> {/* clears the native titlebar traffic lights -- see TopBar.tsx's comment */}

      <div className={cn("flex items-center gap-1.5 border-b border-hairline px-2.5 pb-2", !expanded && "flex-col")}>
        <span className="flex size-6 shrink-0 items-center justify-center rounded-sm bg-brand text-[11px] font-medium text-on-brand">
          P
        </span>
        {expanded && <span className="min-w-0 flex-1 truncate text-sm font-medium text-foreground">Puck</span>}
        <Button
          type="button"
          variant="ghost"
          size="icon-sm"
          className={cn("shrink-0", expanded && "ml-auto")}
          onClick={() => setExpanded((value) => !value)}
          aria-label={expanded ? "사이드바 접기" : "사이드바 펼치기"}
        >
          {expanded ? <PanelLeftClose className="size-4" /> : <PanelLeft className="size-4" />}
        </Button>
      </div>

      {expanded ? (
        <ScrollArea className="min-h-0 flex-1">
          <div className="flex flex-col gap-1 px-1.5 py-2">
            {state.workspaces.map((workspace) => (
              <WorkspaceGroup
                key={workspace.id}
                workspace={workspace}
                sessions={state.sessionsByWorkspace[workspace.id] ?? []}
                activeSessionId={state.activeSessionId}
                collapsed={collapsedWorkspaceIds.has(workspace.id)}
                onToggle={() => toggleWorkspace(workspace.id)}
                onSelectSession={(sessionId) => switchSession(workspace.id, sessionId)}
                onNewSession={() => newSession(workspace.id, "새 채팅")}
              />
            ))}
          </div>
        </ScrollArea>
      ) : (
        <div className="min-h-0 flex-1" />
      )}

      <div className="shrink-0 border-t border-hairline p-1.5">
        <Button
          type="button"
          variant="outline"
          className={cn("w-full justify-start gap-2", !expanded && "justify-center px-0")}
          onClick={() => setShowNewWorkspace(true)}
        >
          <Plus className="size-4" />
          {expanded && "새 워크스페이스"}
        </Button>
      </div>

      <NewWorkspaceDialog open={showNewWorkspace} onOpenChange={setShowNewWorkspace} />
    </aside>
  );
}

interface WorkspaceGroupProps {
  workspace: WorkspaceJSON;
  sessions: SessionSummaryJSON[];
  activeSessionId: string;
  collapsed: boolean;
  onToggle(): void;
  onSelectSession(sessionId: string): void;
  onNewSession(): void;
}

function WorkspaceGroup({
  workspace,
  sessions,
  activeSessionId,
  collapsed,
  onToggle,
  onSelectSession,
  onNewSession,
}: WorkspaceGroupProps) {
  return (
    <div className="flex flex-col">
      <div className="group/workspace flex items-center gap-1 rounded-sm px-1.5 py-1 hover:bg-hairline-soft">
        <button type="button" onClick={onToggle} className="flex min-w-0 flex-1 items-center gap-1.5 text-left">
          <ChevronRight className={cn("size-3 shrink-0 text-mute transition-transform", !collapsed && "rotate-90")} />
          <span className="min-w-0 flex-1 truncate text-xs font-medium text-foreground">{workspace.name}</span>
          <span className="shrink-0 font-mono text-[10px] text-mute">{sessions.length}</span>
        </button>
        <Button
          type="button"
          variant="ghost"
          size="icon-sm"
          className="size-5 shrink-0 opacity-0 group-hover/workspace:opacity-100"
          onClick={onNewSession}
          aria-label={`${workspace.name}에 새 채팅`}
        >
          <SquarePen className="size-3" />
        </Button>
      </div>

      {!collapsed && workspace.projectPath && (
        <div className="truncate px-6 pb-0.5 font-mono text-[10px] text-faint">{workspace.projectPath}</div>
      )}

      {!collapsed && (
        <div className="flex flex-col gap-0.5">
          {sessions.map((session) => (
            <SessionRow
              key={session.id}
              session={session}
              active={session.id === activeSessionId}
              onSelect={() => onSelectSession(session.id)}
            />
          ))}
        </div>
      )}
    </div>
  );
}
