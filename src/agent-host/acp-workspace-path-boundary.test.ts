import { access, mkdir, mkdtemp, readFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { describe, expect, it, vi } from "vitest";
import { AcpAdapter } from "./acp-adapter.js";
import { WorkspaceRegistry } from "../main/workspace-registry.js";

/**
 * W5 공통 "ACP가 사용할 수 있는 경로가 WorkspaceRegistry 경로와 일치하는지 통합 검증".
 * W6의 이미 완료된 "세션 workspace를 기준으로 실제 project path 강제"(tool-executors.test.ts)는
 * 모델이 args로 보낸 project_path를 Main의 tool-executor 레이어에서 무시한다는 걸 확인할 뿐이다.
 * 여기서는 그 강제된 projectPath가 실제로 자식 프로세스(Mock ACP)의 cwd까지 그대로 전달되는지,
 * 그리고 그 값이 정확히 WorkspaceRegistry가 realpath로 정규화한 경로와 일치하는지를 다른 레이어에서
 * 다시 확인한다.
 */
describe("ACP 프로세스 경로 경계와 WorkspaceRegistry", () => {
  it("Mock ACP 자식 프로세스는 WorkspaceRegistry의 realProjectPath를 그대로 cwd로 받는다", async () => {
    const root = await mkdtemp(path.join(os.tmpdir(), "workspace-acp-boundary-"));
    const project = path.join(root, "project");
    await mkdir(project);
    const registry = new WorkspaceRegistry(path.join(root, "data", "workspaces.json"));
    const workspace = await registry.create("경계 시험", project, "w-boundary");
    expect(workspace.realProjectPath).toBeTruthy();

    const fixture = path.resolve("tests/fixtures/mock-acp-agent.mjs");
    const spawnSpy = vi.fn();
    const realSpawn = (await import("node:child_process")).spawn;
    const adapter = new AcpAdapter({
      command: process.execPath,
      args: [fixture],
      spawnProcess: (command, args, options) => {
        spawnSpy(options?.cwd);
        return realSpawn(command, args, options) as never;
      },
    });

    const result = await adapter.run({
      requestId: "boundary",
      workspaceId: workspace.id,
      task: "평범한 작업",
      projectPath: workspace.realProjectPath!,
      signal: new AbortController().signal,
    });

    expect(result.ok).toBe(true);
    // spawn에 실제로 전달된 cwd가 WorkspaceRegistry의 realProjectPath와 정확히 일치해야 한다.
    expect(spawnSpy).toHaveBeenCalledWith(workspace.realProjectPath);
    // Mock ACP가 session/new로 받은 cwd 기준으로 파일을 쓰므로, 그 결과물이 실제로
    // realProjectPath 밑에 나타났다는 것 자체가 ACP 프로세스가 받은 cwd == registry 경로임을 증명한다.
    await expect(readFile(path.join(workspace.realProjectPath!, "mock-change.txt"), "utf8")).resolves.toBe(
      "changed by mock acp\n",
    );
  });

  it("Mock ACP가 워크스페이스 경계 밖 절대경로에 쓰기를 시도해도 결과(changedFiles)는 새지 않는다", async () => {
    const root = await mkdtemp(path.join(os.tmpdir(), "workspace-acp-escape-"));
    const project = path.join(root, "project");
    await mkdir(project);
    const registry = new WorkspaceRegistry(path.join(root, "data", "workspaces.json"));
    const workspace = await registry.create("경계 이탈 시험", project, "w-escape");

    const outsideDir = await mkdtemp(path.join(os.tmpdir(), "workspace-acp-escape-target-"));
    const escapeTarget = path.join(outsideDir, "escaped.txt");

    const fixture = path.resolve("tests/fixtures/mock-acp-agent.mjs");
    const adapter = new AcpAdapter({ command: process.execPath, args: [fixture] });

    const result = await adapter.run({
      requestId: "escape",
      workspaceId: workspace.id,
      task: `ESCAPE:${escapeTarget}`,
      projectPath: workspace.realProjectPath!,
      signal: new AbortController().signal,
    });

    expect(result.ok).toBe(true);
    // 핵심 검증: changedFiles에는 워크스페이스 밖 경로가 전혀 보고되지 않는다(상대경로 필터링,
    // acp-adapter.ts의 relativeProjectPath가 ".."/절대경로를 걸러낸다).
    for (const file of result.changedFiles) {
      expect(path.isAbsolute(file)).toBe(false);
      expect(file.split("/")).not.toContain("..");
    }
    expect(result.changedFiles.join(",")).not.toContain("escaped.txt");

    // 알려진 갭(TODO.md에 별도 항목으로 기록): AcpAdapter는 spawn에 cwd만 지정할 뿐 OS 수준
    // 샌드박싱이 없어서, 절대경로 쓰기 자체는 실제로 성공한다 -- "결과가 새지 않는다"까지만
    // 보장되고 "파일 시스템 쓰기 자체가 차단된다"는 보장은 아니라는 걸 이 assertion으로 명시해둔다.
    await expect(readFile(escapeTarget, "utf8")).resolves.toBe("escaped write from mock acp\n");
    await expect(access(path.join(workspace.realProjectPath!, "escaped.txt"))).rejects.toThrow();
  });
});
