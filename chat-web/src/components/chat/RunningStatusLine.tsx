// `model` isn't plumbed onto the bridge yet -- the native status bar (Task 3
// of this plan) is the one guaranteed-correct place it's shown today.
// Callers must pass `null` until that follow-up lands; don't invent a value
// here.
export function RunningStatusLine({ model, projectPath }: { model: string | null; projectPath: string | null }) {
  return (
    <div className="flex items-center gap-2 py-1.5 text-[11px] text-mute">
      <span className="size-2 animate-spin rounded-full border-[1.5px] border-hairline border-t-brand" />
      <span>
        실행 중… <span className="font-mono">esc</span> 로 중단
      </span>
      <span className="ml-auto font-mono text-faint">
        {[model, projectPath].filter(Boolean).join(" · ")}
      </span>
    </div>
  );
}
