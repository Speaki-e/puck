import { StatusDot } from "@/components/ui/status-dot";
import { KVRows } from "./ToolCallCard";
import type { JSONValue, ToolErrorCode } from "@/lib/bridge-types";

interface ToolResultRowProps {
  ok: boolean;
  data: JSONValue | null;
  error: ToolErrorCode | null;
  detail: string | null;
}

/**
 * Fallback rendering for a toolResult timeline entry whose matching toolCall
 * id isn't in the visible timeline. Shouldn't normally happen -- toolCall and
 * toolResult share the same tool_use id (ChatSession.swift), so ChatTranscript
 * folds them into a single ToolCallCard and only reaches for this component
 * when that pairing fails. Reuses ToolCallCard's KVRows so the two never
 * drift in styling.
 */
export function ToolResultRow({ ok, data, error, detail }: ToolResultRowProps) {
  return (
    <div className="max-w-[420px] space-y-1 rounded-md border border-hairline bg-surface px-2.5 py-1.5">
      <div className="flex items-center gap-2">
        <StatusDot state={ok ? "ok" : "error"} />
        <span className="font-mono text-[11px] text-ink">result</span>
      </div>
      {ok ? (
        <KVRows value={data} />
      ) : (
        <KVRows value={{ error: error ?? "execution_failed", ...(detail ? { detail } : {}) }} />
      )}
    </div>
  );
}
