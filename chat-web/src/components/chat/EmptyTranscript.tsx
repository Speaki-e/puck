export function EmptyTranscript() {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-3 text-center">
      <div className="flex size-[72px] items-center justify-center rounded-full bg-brand/10 text-3xl">🎃</div>
      <div>
        <p className="text-lg font-semibold text-foreground">무엇을 도와드릴까요?</p>
        <p className="mt-1 text-sm text-muted-foreground">코드든 잡담이든, 편하게 말 걸어보세요.</p>
      </div>
    </div>
  );
}
