import { cn } from "@/lib/utils";

export type DotState = "idle" | "active" | "ok" | "error";

const TONE: Record<DotState, string> = {
  idle: "bg-mute",
  active: "bg-brand animate-pulse",
  ok: "bg-[var(--status-success)]",
  error: "bg-[var(--status-error)]",
};

/** The one status indicator every surface uses: session rows, tabs, tool cards.
 *  Mirrors pet-app's StatusDotView (Swift) -- same four states, same meanings. */
export function StatusDot({ state, className }: { state: DotState; className?: string }) {
  return <span className={cn("size-1.5 shrink-0 rounded-full", TONE[state], className)} />;
}

export function sessionDotState(s: { isRunning: boolean; lastRunOk: boolean | null }): DotState {
  if (s.isRunning) return "active";
  if (s.lastRunOk === true) return "ok";
  if (s.lastRunOk === false) return "error";
  return "idle";
}
