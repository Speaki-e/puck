import { CheckCircle2, XCircle } from "lucide-react";
import type { JSONValue, ToolErrorCode } from "@/lib/bridge-types";

interface ToolResultRowProps {
  ok: boolean;
  data: JSONValue | null;
  error: ToolErrorCode | null;
  detail: string | null;
}

export function ToolResultRow({ ok, data, error, detail }: ToolResultRowProps) {
  const body = !ok ? `${error ?? "execution_failed"}${detail ? `: ${detail}` : ""}` : JSON.stringify(data, null, 2);

  return (
    <div className="flex max-w-[420px] items-start gap-2 rounded-xl border border-hairline bg-surface px-3 py-2">
      {ok ? (
        <CheckCircle2 className="mt-0.5 size-3.5 shrink-0 text-emerald-500" />
      ) : (
        <XCircle className="mt-0.5 size-3.5 shrink-0 text-destructive" />
      )}
      <pre className="min-w-0 flex-1 overflow-x-auto whitespace-pre-wrap break-words font-mono text-[11px] text-muted-foreground select-text">{body}</pre>
    </div>
  );
}
