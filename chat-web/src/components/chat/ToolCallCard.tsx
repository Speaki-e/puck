import { useState } from "react";
import { ChevronRight, Wrench } from "lucide-react";
import { cn } from "@/lib/utils";
import type { JSONValue } from "@/lib/bridge-types";

interface ToolCallCardProps {
  tool: string;
  args: JSONValue | null;
}

export function ToolCallCard({ tool, args }: ToolCallCardProps) {
  const [open, setOpen] = useState(false);

  return (
    <div className="max-w-[420px] rounded-xl border border-hairline bg-surface">
      <button type="button" onClick={() => setOpen((value) => !value)} className="flex w-full items-center gap-2 px-3 py-2 text-left text-sm">
        <ChevronRight className={cn("size-3.5 shrink-0 text-muted-foreground transition-transform", open && "rotate-90")} />
        <Wrench className="size-3.5 shrink-0 text-muted-foreground" />
        <span className="min-w-0 flex-1 truncate font-mono text-xs">{tool}</span>
      </button>
      {open && (
        <pre className="overflow-x-auto border-t border-hairline px-3 py-2 font-mono text-[11px] text-muted-foreground select-text">
          {JSON.stringify(args, null, 2)}
        </pre>
      )}
    </div>
  );
}
