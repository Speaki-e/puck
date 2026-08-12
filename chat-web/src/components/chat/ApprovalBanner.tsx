import { TriangleAlert } from "lucide-react";
import { Button } from "@/components/ui/button";
import type { PendingApprovalJSON } from "@/lib/bridge-types";

interface ApprovalBannerProps {
  approval: PendingApprovalJSON;
  onRespond(approved: boolean): void;
}

export function ApprovalBanner({ approval, onRespond }: ApprovalBannerProps) {
  return (
    <div className="mb-2 flex items-center gap-3 rounded-xl border border-warning/30 bg-warning/10 px-3 py-2">
      <TriangleAlert className="size-4 shrink-0 text-warning" />
      <p className="min-w-0 flex-1 text-sm text-foreground">{approval.summary}</p>
      <div className="flex shrink-0 gap-1.5">
        <Button type="button" size="sm" variant="ghost" className="text-destructive hover:text-destructive" onClick={() => onRespond(false)}>거부</Button>
        <Button type="button" size="sm" onClick={() => onRespond(true)}>허용</Button>
      </div>
    </div>
  );
}
