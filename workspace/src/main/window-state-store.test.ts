import { mkdtemp } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { normalizeWindowState, WindowStateStore } from "./window-state-store.js";

describe("WindowStateStore", () => {
  it("창 상태를 저장하고 복구한다", async () => {
    const directory = await mkdtemp(path.join(os.tmpdir(), "workspace-window-"));
    const store = new WindowStateStore(path.join(directory, "window.json"));
    const state = { x: 10, y: 20, width: 1000, height: 700, maximized: true };
    await store.save(state);
    await expect(store.load()).resolves.toEqual(state);
  });

  it("화면 밖의 창은 현재 디스플레이 중앙으로 복구한다", () => {
    const result = normalizeWindowState(
      { x: 50_000, y: 50_000, width: 1200, height: 700, maximized: false },
      [{ x: 0, y: 0, width: 1920, height: 1080 }],
    );
    expect(result).toEqual({ x: 360, y: 190, width: 1200, height: 700, maximized: false });
  });
});
