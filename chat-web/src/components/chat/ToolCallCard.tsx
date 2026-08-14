import { useState } from "react";
import { ChevronRight } from "lucide-react";
import { cn } from "@/lib/utils";
import { StatusDot, type DotState } from "@/components/ui/status-dot";
import type { JSONValue, ToolErrorCode } from "@/lib/bridge-types";

export interface ToolCallResult {
  ok: boolean;
  data: JSONValue | null;
  error: ToolErrorCode | null;
  detail: string | null;
}

interface ToolCallCardProps {
  tool: string;
  args: JSONValue | null;
  /** null while the call is still running (no matching toolResult entry yet). */
  result: ToolCallResult | null;
}

export function ToolCallCard({ tool, args, result }: ToolCallCardProps) {
  const [open, setOpen] = useState(false);

  const state: DotState = result === null ? "active" : result.ok ? "ok" : "error";

  return (
    <div className="max-w-[420px] rounded-md border border-hairline bg-surface">
      <button type="button" onClick={() => setOpen((value) => !value)} className="flex w-full items-center gap-2 px-2.5 py-1.5 text-left">
        <ChevronRight className={cn("size-3 shrink-0 text-faint transition-transform", open && "rotate-90")} />
        <StatusDot state={state} />
        <span className="min-w-0 flex-1 truncate font-mono text-[11px] text-ink">{tool}</span>
      </button>
      {open && (
        <div className="space-y-1 border-t border-hairline px-2.5 py-1.5">
          <KVRows value={args} />
          {result && (
            <div className="space-y-1 border-t border-hairline pt-1.5 mt-1.5">
              {result.ok ? (
                <KVRows value={result.data} />
              ) : (
                <KVRows value={{ error: result.error ?? "execution_failed", ...(result.detail ? { detail: result.detail } : {}) }} />
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

/** Dense `키: 값` row rendering shared by ToolCallCard's body/result section and
 *  ToolResultRow's standalone fallback -- keeps the two from drifting in style. */
export function KVRows({ value }: { value: JSONValue | null }) {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    const entries = Object.entries(value);
    if (entries.length === 0) {
      return <p className="font-mono text-[11px] text-faint select-text">{"{}"}</p>;
    }
    return (
      <>
        {entries.map(([key, val]) => (
          <div key={key} className="flex items-start gap-1.5 font-mono text-[11px]">
            <span className="shrink-0 text-faint select-text">{key}:</span>
            <span className="min-w-0 flex-1 break-words text-mute select-text">{stringifyValue(val)}</span>
          </div>
        ))}
      </>
    );
  }
  return <p className="min-w-0 break-words font-mono text-[11px] text-mute select-text">{stringifyValue(value)}</p>;
}

function stringifyValue(value: JSONValue | null): string {
  if (value === null) return "null";
  if (typeof value === "string") return value;
  return JSON.stringify(value);
}
