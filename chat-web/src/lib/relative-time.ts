/** Sidebar/tab timestamps. Korean, deliberately coarse -- this is a glanceable
 *  hint, not a log. `now` is injected so it is testable without faking clocks. */
export function relativeTime(epochMs: number | null, now: number): string {
  if (epochMs === null) return "";
  const diff = now - epochMs;
  if (diff < 0) return "방금";
  const min = Math.floor(diff / 60_000);
  if (min < 1) return "방금";
  if (min < 60) return `${min}분`;
  const hour = Math.floor(min / 60);
  if (hour < 24) return `${hour}시간`;
  const day = Math.floor(hour / 24);
  if (day === 1) return "어제";
  if (day < 7) return `${day}일`;
  const d = new Date(epochMs);
  return `${d.getMonth() + 1}월 ${d.getDate()}일`;
}
