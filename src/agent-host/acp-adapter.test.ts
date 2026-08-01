import { access, mkdtemp, readFile } from "node:fs/promises";
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

  it("ACP 프로세스가 비정상 종료된 뒤 다음 작업에서 새 프로세스로 복구한다", async () => {
    const projectPath = await mkdtemp(path.join(os.tmpdir(), "workspace-acp-crash-"));
    const fixture = path.resolve("tests/fixtures/mock-acp-agent.mjs");
    const adapter = new AcpAdapter({ command: process.execPath, args: [fixture] });

    const crashed = await adapter.run({
      requestId: "crash",
      workspaceId: "w1",
      task: "CRASH",
      projectPath,
      signal: new AbortController().signal,
    });
    expect(crashed).toMatchObject({ ok: false, error: "acp_error" });
    expect(crashed.detail).toContain("intentional mock ACP crash");

    const recovered = await adapter.run({
      requestId: "recover",
      workspaceId: "w1",
      task: "recover",
      projectPath,
      signal: new AbortController().signal,
    });
    expect(recovered.ok).toBe(true);
    expect(recovered.changedFiles).toContain("mock-change.txt");
  });

  it("실행 중 취소하면 쓰기 전에 멈춰 부분 파일을 남기지 않는다", async () => {
    const projectPath = await mkdtemp(path.join(os.tmpdir(), "workspace-acp-cancel-"));
    const fixture = path.resolve("tests/fixtures/mock-acp-agent.mjs");
    const adapter = new AcpAdapter({ command: process.execPath, args: [fixture] });
    const controller = new AbortController();
    const run = adapter.run({
      requestId: "cancel",
      workspaceId: "w1",
      task: "WAIT",
      projectPath,
      signal: controller.signal,
    });
    setTimeout(() => controller.abort(), 150);

    await expect(run).resolves.toMatchObject({ ok: false, error: "cancelled", changedFiles: [] });
    await expect(access(path.join(projectPath, "mock-change.txt"))).rejects.toThrow();
  });
});
