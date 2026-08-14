import { cn } from "@/lib/utils";
import { StatusDot, sessionDotState } from "@/components/ui/status-dot";
import { relativeTime } from "@/lib/relative-time";
import type { SessionSummaryJSON } from "@/lib/bridge-types";

interface SessionRowProps {
  session: SessionSummaryJSON;
  active: boolean;
  onSelect(): void;
}

export function SessionRow({ session, active, onSelect }: SessionRowProps) {
  return (
    <button
      type="button"
      onClick={onSelect}
      className={cn(
        "flex h-[26px] w-full items-center gap-2 rounded-sm pl-5 pr-2 text-left text-xs transition-colors",
        active ? "bg-brand/14 text-foreground" : "text-muted-foreground hover:bg-hairline-soft",
      )}
    >
      <StatusDot state={sessionDotState(session)} />
      <span className="min-w-0 flex-1 truncate">{session.title}</span>
      <span className="shrink-0 text-[10px] text-faint">{relativeTime(session.lastActivityAt, Date.now())}</span>
    </button>
  );
}
