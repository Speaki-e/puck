import { useState, type KeyboardEvent } from "react";
import { ArrowUp, Square } from "lucide-react";
import { cn } from "@/lib/utils";

interface ChatInputBarProps {
  isRunning: boolean;
  onSend(text: string): void;
  onCancel(): void;
}

export function ChatInputBar({ isRunning, onSend, onCancel }: ChatInputBarProps) {
  const [draft, setDraft] = useState("");

  const submit = () => {
    const trimmed = draft.trim();
    if (!trimmed) return;
    onSend(trimmed);
    setDraft("");
  };

  const handleKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      submit();
    }
  };

  return (
    <div className="px-4 pb-4">
      <div className="mx-auto flex max-w-[720px] flex-col gap-1.5">
        <div className="flex items-end gap-2 rounded-3xl border border-hairline bg-surface px-3.5 py-2 focus-within:border-brand/50">
          <textarea
            value={draft}
            onChange={(event) => setDraft(event.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Agent에게 메시지를 보내세요…"
            rows={1}
            className="max-h-32 min-h-8 flex-1 resize-none bg-transparent py-1 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none"
          />
          {isRunning ? (
            <button
              type="button"
              onClick={onCancel}
              aria-label="중지"
              className="flex size-8 shrink-0 items-center justify-center rounded-full bg-hairline text-foreground hover:bg-hairline-soft"
            >
              <Square className="size-3.5 fill-current" />
            </button>
          ) : (
            <button
              type="button"
              onClick={submit}
              disabled={!draft.trim()}
              aria-label="전송"
              className={cn(
                "flex size-8 shrink-0 items-center justify-center rounded-full transition-colors",
                draft.trim() ? "bg-brand text-on-brand" : "bg-hairline-soft text-muted-foreground",
              )}
            >
              <ArrowUp className="size-4" />
            </button>
          )}
        </div>
        <p className="text-center text-[11px] text-muted-foreground">Puck는 실수를 할 수 있어요.</p>
      </div>
    </div>
  );
}
