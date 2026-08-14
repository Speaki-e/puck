import { describe, expect, it } from "vitest";
import { relativeTime } from "./relative-time";

const NOW = 1_800_000_000_000;

describe("relativeTime", () => {
  it("returns an empty string when there is no timestamp", () => {
    expect(relativeTime(null, NOW)).toBe("");
  });
  it("treats under a minute as 방금", () => {
    expect(relativeTime(NOW - 30_000, NOW)).toBe("방금");
  });
  it("shows minutes under an hour", () => {
    expect(relativeTime(NOW - 12 * 60_000, NOW)).toBe("12분");
  });
  it("shows hours under a day", () => {
    expect(relativeTime(NOW - 2 * 3_600_000, NOW)).toBe("2시간");
  });
  it("shows 어제 for exactly one day", () => {
    expect(relativeTime(NOW - 25 * 3_600_000, NOW)).toBe("어제");
  });
  it("shows days under a week", () => {
    expect(relativeTime(NOW - 3 * 86_400_000, NOW)).toBe("3일");
  });
  it("falls back to a date past a week", () => {
    expect(relativeTime(NOW - 30 * 86_400_000, NOW)).toMatch(/월 \d+일$/);
  });
  it("does not go negative for a clock skew into the future", () => {
    expect(relativeTime(NOW + 5_000, NOW)).toBe("방금");
  });
});
