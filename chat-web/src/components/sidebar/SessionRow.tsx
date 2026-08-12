import { MessageSquare } from "lucide-react";
import { cn } from "@/lib/utils";
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
        "flex w-full items-center gap-2 rounded-md px-2.5 py-1.5 text-left text-sm transition-colors",
        active ? "bg-brand/14 text-foreground" : "text-muted-foreground hover:bg-hairline-soft",
      )}
    >
      <MessageSquare className={cn("size-3.5 shrink-0", active && "text-brand")} />
      <span className="min-w-0 flex-1 truncate">{session.title}</span>
      {session.isRunning && (
        <span className="size-3 shrink-0 animate-spin rounded-full border-2 border-muted-foreground/40 border-t-brand" />
      )}
    </button>
  );
}
