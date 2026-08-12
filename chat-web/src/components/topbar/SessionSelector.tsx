import { useState } from "react";
import { ChevronDown, MessageSquare, Plus } from "lucide-react";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { useChatState } from "@/state/chat-context";
import { usePuckBridge } from "@/hooks/usePuckBridge";

export function SessionSelector() {
  const state = useChatState();
  const { switchSession, newSession } = usePuckBridge();
  const [open, setOpen] = useState(false);
  const sessions = state.sessionsByWorkspace[state.activeWorkspaceId] ?? [];
  const activeTitle = state.activeSession?.title ?? "";

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <button
          type="button"
          className="flex items-center gap-1.5 rounded-md bg-hairline-soft px-2.5 py-1 text-sm text-foreground hover:bg-hairline"
        >
          <span className="max-w-48 truncate">{activeTitle}</span>
          <ChevronDown className="size-3 shrink-0 text-muted-foreground" />
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" className="w-60 p-1">
        <div className="flex flex-col gap-0.5">
          {sessions.map((session) => (
            <button
              key={session.id}
              type="button"
              onClick={() => { switchSession(state.activeWorkspaceId, session.id); setOpen(false); }}
              className="flex items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm hover:bg-hairline-soft"
            >
              <MessageSquare className={session.id === state.activeSessionId ? "size-3.5 shrink-0 text-brand" : "size-3.5 shrink-0 text-muted-foreground"} />
              <span className="min-w-0 flex-1 truncate">{session.title}</span>
            </button>
          ))}
          <button
            type="button"
            onClick={() => { newSession(state.activeWorkspaceId, "새 채팅"); setOpen(false); }}
            className="flex items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm text-muted-foreground hover:bg-hairline-soft"
          >
            <Plus className="size-3.5 shrink-0" />
            새 채팅
          </button>
        </div>
      </PopoverContent>
    </Popover>
  );
}
