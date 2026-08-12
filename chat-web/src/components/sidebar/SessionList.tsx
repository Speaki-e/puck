import { ScrollArea } from "@/components/ui/scroll-area";
import type { SessionSummaryJSON } from "@/lib/bridge-types";
import { SessionRow } from "./SessionRow";

interface SessionListProps {
  sessions: SessionSummaryJSON[];
  activeSessionId: string;
  onSelect(sessionId: string): void;
}

export function SessionList({ sessions, activeSessionId, onSelect }: SessionListProps) {
  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <div className="flex items-center justify-between px-2.5 py-1.5">
        <span className="font-mono text-[10px] tracking-wider text-mute">채팅 {sessions.length}개</span>
      </div>
      <ScrollArea className="min-h-0 flex-1">
        <div className="flex flex-col gap-0.5 px-1.5 pb-2">
          {sessions.map((session) => (
            <SessionRow key={session.id} session={session} active={session.id === activeSessionId} onSelect={() => onSelect(session.id)} />
          ))}
        </div>
      </ScrollArea>
    </div>
  );
}
