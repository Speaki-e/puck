import { mkdtemp, mkdir } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { WorkspaceRegistry } from "./workspace-registry.js";

describe("WorkspaceRegistry", () => {
  it("default 워크스페이스와 정규화된 프로젝트를 복구한다", async () => {
    const root = await mkdtemp(path.join(os.tmpdir(), "workspace-registry-"));
    const project = path.join(root, "project");
    await mkdir(project);
    const storage = path.join(root, "data", "workspaces.json");
    const registry = new WorkspaceRegistry(storage);
    expect(registry.get("default")).toBeDefined();
    const created = await registry.create("프로젝트", project, "w1");
    expect(created.realProjectPath).toBeTruthy();

    const restored = new WorkspaceRegistry(storage);
    await restored.load();
    expect(restored.get("w1")?.name).toBe("프로젝트");
  });
});
