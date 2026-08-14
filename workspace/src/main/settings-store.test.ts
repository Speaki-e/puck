import { mkdtemp } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { SettingsStore } from "./settings-store.js";

describe("SettingsStore", () => {
  it("기본값으로 시작하고 update로 반영·저장된다", async () => {
    const directory = await mkdtemp(path.join(os.tmpdir(), "workspace-settings-"));
    const store = new SettingsStore(path.join(directory, "settings.json"));
    expect(store.current.logLevel).toBe("info");
    expect(store.current.codingAgent).toBe("claude");

    const updated = await store.update({ logLevel: "debug", fileSizeLimitBytes: 4 * 1024 * 1024, codingAgent: "codex" });
    expect(updated).toMatchObject({ logLevel: "debug", fileSizeLimitBytes: 4 * 1024 * 1024, codingAgent: "codex" });
    expect(store.current).toMatchObject(updated);

    const reloaded = new SettingsStore(path.join(directory, "settings.json"));
    await expect(reloaded.load()).resolves.toMatchObject({ logLevel: "debug", codingAgent: "codex" });
  });

  it("잘못된 값은 무시하고 기존 값을 유지한다", async () => {
    const directory = await mkdtemp(path.join(os.tmpdir(), "workspace-settings-invalid-"));
    const store = new SettingsStore(path.join(directory, "settings.json"));
    const updated = await store.update({ logLevel: "not-a-level" as never, fileSizeLimitBytes: 10, codingAgent: "gpt5" as never });
    expect(updated.logLevel).toBe("info");
    expect(updated.fileSizeLimitBytes).toBe(2 * 1024 * 1024);
    expect(updated.codingAgent).toBe("claude");
  });

  it("파일이 없으면 기본값을 반환한다", async () => {
    const directory = await mkdtemp(path.join(os.tmpdir(), "workspace-settings-missing-"));
    const store = new SettingsStore(path.join(directory, "missing.json"));
    await expect(store.load()).resolves.toMatchObject({ logLevel: "info", codingAgent: "claude" });
  });
});
