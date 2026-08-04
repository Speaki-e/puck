import { access, mkdtemp, readFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { AcpAdapter } from "./acp-adapter.js";
import { CodeEditorQueue } from "./code-editor-queue.js";

/**
 * code-editor-queue.test.ts는 CodeEditorQueue 자체가 워크스페이스별로만 직렬화하고 서로 다른
 * 워크스페이스는 병렬 실행한다는 걸 mock execute 함수로 확인한다(W5, 이미 완료). 이 파일은 그 정책을
 * 실제 CodeEditorQueue + AcpAdapter + Mock ACP 자식 프로세스(tests/fixtures/mock-acp-agent.mjs) 조합
 * 으로, 서로 다른 두 워크스페이스에 진짜 ACP 작업을 동시에 붙여 검증한다(공통 W0/필수 장애 시험
 * "두 워크스페이스에서 ACP 병렬 작업 시험").
 */
describe("CodeEditorQueue + AcpAdapter 두 워크스페이스 병렬 통합", () => {
  it("서로 다른 워크스페이스의 ACP 작업은 서로 기다리지 않고, 결과 파일도 각자 프로젝트 폴더에만 남는다", async () => {
    const fixture = path.resolve("tests/fixtures/mock-acp-agent.mjs");
    const projectA = await mkdtemp(path.join(os.tmpdir(), "workspace-acp-parallel-a-"));
    const projectB = await mkdtemp(path.join(os.tmpdir(), "workspace-acp-parallel-b-"));
    const queue = new CodeEditorQueue();

    // 워크스페이스 A는 WAIT로 세션을 붙잡아 둔다 -- session/cancel 알림이 와야만 풀린다.
    const controllerA = new AbortController();
    const runA = queue.enqueue({
      requestId: "req-a",
      workspaceId: "workspace-a",
      signal: controllerA.signal,
      execute: (signal) => new AcpAdapter({ command: process.execPath, args: [fixture] }).run({
        requestId: "req-a",
        workspaceId: "workspace-a",
        task: "WAIT",
        projectPath: projectA,
        signal,
      }),
    });

    // 워크스페이스 A가 큐에 등록되고 실제로 실행(started)되기까지 한 틱 기다린다.
    await new Promise((resolve) => setTimeout(resolve, 50));
    expect(queue.position("req-a")).toBe(0);

    // 워크스페이스 B는 즉시 끝나는 일반 작업이다. A가 CodeEditorQueue를 워크스페이스 구분 없이
    // 직렬화했다면 A가 풀릴 때까지 B도 절대 끝나지 않아야 한다 -- 반대로 B가 여기서 정상 완료되면
    // 서로 다른 워크스페이스가 실제로 병렬 실행됐다는 뜻이다.
    const runB = queue.enqueue({
      requestId: "req-b",
      workspaceId: "workspace-b",
      execute: (signal) => new AcpAdapter({ command: process.execPath, args: [fixture] }).run({
        requestId: "req-b",
        workspaceId: "workspace-b",
        task: "평범한 작업",
        projectPath: projectB,
        signal,
      }),
    });

    const resultB = await runB;
    expect(resultB).toMatchObject({ ok: true, summary: "Mock ACP 작업 완료" });
    expect(resultB.changedFiles).toContain("mock-change.txt");
    await expect(readFile(path.join(projectB, "mock-change.txt"), "utf8")).resolves.toBe("changed by mock acp\n");

    // B가 끝난 시점에도 A는 여전히 대기 중이어야 한다(서로 다른 워크스페이스라 순서를 안 기다림) --
    // A의 결과 파일이 아직 없다는 것으로 확인한다.
    await expect(access(path.join(projectA, "mock-change.txt"))).rejects.toThrow();

    // 마무리: A를 취소해 자식 프로세스를 정리한다.
    controllerA.abort();
    const resultA = await runA;
    expect(resultA).toMatchObject({ ok: false, error: "cancelled" });
    await expect(access(path.join(projectA, "mock-change.txt"))).rejects.toThrow();

    // B의 결과물이 A의 프로젝트 폴더로 새지 않았는지(워크스페이스 격리) 다시 한번 확인.
    await expect(access(path.join(projectA, "mock-change.txt"))).rejects.toThrow();
  }, 15_000);

  it("같은 워크스페이스 안에서는 여전히 순차 실행되지만 다른 워크스페이스에는 영향 없다", async () => {
    const fixture = path.resolve("tests/fixtures/mock-acp-agent.mjs");
    const projectA1 = await mkdtemp(path.join(os.tmpdir(), "workspace-acp-serial-a1-"));
    const projectA2 = await mkdtemp(path.join(os.tmpdir(), "workspace-acp-serial-a2-"));
    const projectC = await mkdtemp(path.join(os.tmpdir(), "workspace-acp-serial-c-"));
    const queue = new CodeEditorQueue();

    const controllerA1 = new AbortController();
    const runA1 = queue.enqueue({
      requestId: "req-a1",
      workspaceId: "workspace-a",
      signal: controllerA1.signal,
      execute: (signal) => new AcpAdapter({ command: process.execPath, args: [fixture] }).run({
        requestId: "req-a1",
        workspaceId: "workspace-a",
        task: "WAIT",
        projectPath: projectA1,
        signal,
      }),
    });
    await new Promise((resolve) => setTimeout(resolve, 50));

    const runA2 = queue.enqueue({
      requestId: "req-a2",
      workspaceId: "workspace-a",
      execute: (signal) => new AcpAdapter({ command: process.execPath, args: [fixture] }).run({
        requestId: "req-a2",
        workspaceId: "workspace-a",
        task: "평범한 작업",
        projectPath: projectA2,
        signal,
      }),
    });
    // 같은 워크스페이스라 req-a1이 끝나기 전엔 req-a2는 대기열에서 실행되지 않는다.
    expect(queue.position("req-a2")).toBe(1);

    const runC = queue.enqueue({
      requestId: "req-c",
      workspaceId: "workspace-c",
      execute: (signal) => new AcpAdapter({ command: process.execPath, args: [fixture] }).run({
        requestId: "req-c",
        workspaceId: "workspace-c",
        task: "평범한 작업",
        projectPath: projectC,
        signal,
      }),
    });
    const resultC = await runC;
    expect(resultC.ok).toBe(true);

    controllerA1.abort();
    const [resultA1, resultA2] = await Promise.all([runA1, runA2]);
    expect(resultA1).toMatchObject({ ok: false, error: "cancelled" });
    expect(resultA2).toMatchObject({ ok: true, summary: "Mock ACP 작업 완료" });
  }, 15_000);
});
