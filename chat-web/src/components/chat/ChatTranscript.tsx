import { useEffect, useMemo, useRef } from "react";
import type { SessionStateJSON, TimelineEntryJSON } from "@/lib/bridge-types";
import { MessageBubble } from "./MessageBubble";
import { ToolCallCard } from "./ToolCallCard";
import { ToolResultRow } from "./ToolResultRow";
import { RunningStatusLine } from "./RunningStatusLine";
import { EmptyTranscript } from "./EmptyTranscript";

interface ChatTranscriptProps {
  session: SessionStateJSON;
  assistantName: string;
  /** Active workspace's project path, for RunningStatusLine. Model is out of
   *  scope for the web layer -- see RunningStatusLine.tsx. */
  projectPath: string | null;
}

type ToolResultEntry = Extract<TimelineEntryJSON, { kind: "toolResult" }>;

export function ChatTranscript({ session, assistantName, projectPath }: ChatTranscriptProps) {
  const bottomRef = useRef<HTMLDivElement>(null);

  // toolCall and toolResult entries share the same id (the tool_use id --
  // see ChatSession.swift), so a call's result is folded into its card
  // instead of rendering as a second, separate row.
  const resultsByCallId = useMemo(() => {
    const map = new Map<string, ToolResultEntry>();
    for (const entry of session.timeline) {
      if (entry.kind === "toolResult") map.set(entry.id, entry);
    }
    return map;
  }, [session.timeline]);
  const callIds = useMemo(() => new Set(session.timeline.filter((entry) => entry.kind === "toolCall").map((entry) => entry.id)), [session.timeline]);

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
              return <ToolCallCard key={`call:${entry.id}`} tool={entry.tool} args={entry.args} result={resultsByCallId.get(entry.id) ?? null} />;
            case "toolResult":
              // Rendered as part of the matching toolCall's card above; only
              // fall back to a standalone row if that pairing didn't hold.
              if (callIds.has(entry.id)) return null;
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
        {session.isRunning && <RunningStatusLine model={null} projectPath={projectPath} />}
        <div ref={bottomRef} />
      </div>
    </div>
  );
}
