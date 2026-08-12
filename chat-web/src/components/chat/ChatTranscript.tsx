import { useEffect, useRef } from "react";
import { Loader2 } from "lucide-react";
import type { SessionStateJSON } from "@/lib/bridge-types";
import { MessageBubble } from "./MessageBubble";
import { ToolCallCard } from "./ToolCallCard";
import { ToolResultRow } from "./ToolResultRow";
import { EmptyTranscript } from "./EmptyTranscript";

interface ChatTranscriptProps {
  session: SessionStateJSON;
  assistantName: string;
}

export function ChatTranscript({ session, assistantName }: ChatTranscriptProps) {
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth", block: "end" });
    // isRunning is included so the thinking indicator's appearance also
    // scrolls into view -- it doesn't change timeline.length.
  }, [session.timeline.length, session.isRunning]);

  if (session.timeline.length === 0 && !session.isRunning) {
    return (
      <div className="min-h-0 flex-1">
        <EmptyTranscript />
      </div>
    );
  }

  return (
    <div className="min-h-0 flex-1 overflow-y-auto px-4 py-3">
      <div className="mx-auto flex max-w-[720px] flex-col gap-3">
        {session.timeline.map((entry) => {
          switch (entry.kind) {
            case "userMessage":
              return <MessageBubble key={entry.id} isUser text={entry.text} senderLabel="나" />;
            case "assistantText":
              return <MessageBubble key={entry.id} isUser={false} text={entry.text} senderLabel={assistantName} />;
            case "toolCall":
              return <ToolCallCard key={`call:${entry.id}`} tool={entry.tool} args={entry.args} />;
            case "toolResult":
              return <ToolResultRow key={`result:${entry.id}`} ok={entry.ok} data={entry.data} error={entry.error} detail={entry.detail} />;
            case "approvalRequested":
              // Deliberately not rendered as a timeline row -- the sticky
              // ApprovalBanner (driven by session.pendingApproval) is the
              // one visible approval surface, see docs/decisions.md.
              return null;
            case "done":
              return (
                <p key={entry.id} className={entry.ok ? "text-sm text-muted-foreground" : "text-sm text-destructive"}>
                  {entry.summary}
                </p>
              );
            default:
              return null;
          }
        })}
        {session.isRunning && (
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <Loader2 className="size-3.5 animate-spin" />
            생각 중…
          </div>
        )}
        <div ref={bottomRef} />
      </div>
    </div>
  );
}
