import { mkdtemp, readFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { describe, expect, it, vi } from "vitest";
import { AcpAdapter } from "./acp-adapter.js";

describe("AcpAdapter", () => {
  it("공식 SDK로 Mock ACP Agent를 실행하고 변경 파일을 수집한다", async () => {
    const projectPath = await mkdtemp(path.join(os.tmpdir(), "workspace-acp-"));
    const fixture = path.resolve("tests/fixtures/mock-acp-agent.mjs");
    const onUpdate = vi.fn();
    const adapter = new AcpAdapter({ command: process.execPath, args: [fixture], onUpdate });
    const result = await adapter.run({
      requestId: "r1",
      workspaceId: "w1",
      task: "파일을 수정해줘",
      projectPath,
      signal: new AbortController().signal,
    });

    expect(result).toMatchObject({ ok: true, summary: "Mock ACP 작업 완료" });
    expect(result.changedFiles).toContain("mock-change.txt");
    await expect(readFile(path.join(projectPath, "mock-change.txt"), "utf8")).resolves.toBe("changed by mock acp\n");
    expect(onUpdate).toHaveBeenCalled();
  });

  it("이미 취소된 요청은 프로세스를 실행하지 않는다", async () => {
    const spawnProcess = vi.fn();
    const controller = new AbortController();
    controller.abort();
    const adapter = new AcpAdapter({ spawnProcess: spawnProcess as never });
    const result = await adapter.run({
      requestId: "r2",
      workspaceId: "w1",
      task: "실행하지 마",
      projectPath: process.cwd(),
      signal: controller.signal,
    });
    expect(result).toMatchObject({ ok: false, error: "cancelled" });
    expect(spawnProcess).not.toHaveBeenCalled();
  });
});
