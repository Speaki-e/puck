import { useState } from "react";
import { Check, Copy } from "lucide-react";
import { cn } from "@/lib/utils";

interface MessageBubbleProps {
  isUser: boolean;
  text: string;
  senderLabel: string;
}

export function MessageBubble({ isUser, text, senderLabel }: MessageBubbleProps) {
  const [copied, setCopied] = useState(false);
  const [hovering, setHovering] = useState(false);

  const copy = () => {
    void navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 1200);
  };

  return (
    <div
      className={cn("flex flex-col gap-1", isUser ? "items-end" : "items-start")}
      onMouseEnter={() => setHovering(true)}
      onMouseLeave={() => setHovering(false)}
    >
      <div className={cn("flex items-center gap-1.5", isUser && "flex-row-reverse")}>
        <div className="flex size-[22px] items-center justify-center rounded-full bg-brand/16 text-[10px] font-medium text-brand">
          {senderLabel.slice(0, 1)}
        </div>
        <span className="text-xs text-muted-foreground">{senderLabel}</span>
      </div>
      <div className="max-w-[420px] whitespace-pre-wrap rounded-[10px] bg-brand/6 px-3 py-2 text-sm text-foreground selection:bg-brand/30">
        {text}
      </div>
      {!isUser && hovering && (
        <button
          type="button"
          onClick={copy}
          className="flex items-center gap-1 rounded-full border border-hairline bg-surface px-2 py-0.5 text-[11px] text-muted-foreground transition-opacity hover:text-foreground"
        >
          {copied ? <Check className="size-3" /> : <Copy className="size-3" />}
          {copied ? "복사됨" : "복사"}
        </button>
      )}
    </div>
  );
}
