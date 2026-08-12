import { mkdtemp, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { describe, expect, it, vi } from "vitest";
import { createEditorLocalExecutor } from "./tool-executors.js";
import { FileService } from "./file-service.js";

async function fixture() {
  const root = await mkdtemp(path.join(os.tmpdir(), "workspace-tool-executors-"));
  await writeFile(path.join(root, "main.ts"), "export const value = 1;\n", "utf8");
  const service = await FileService.create(root);
  return { root, service };
}

describe("createEditorLocalExecutor: code_editor", () => {
  it("모델이 보낸 project_path를 무시하고 세션 workspace의 실제 경로를 강제한다", async () => {
    const request = vi.fn().mockResolvedValue({ ok: true, summary: "완료", changedFiles: ["a.ts"] });
    const executor = createEditorLocalExecutor({
      workspaceId: "w1",
      sessionId: "s1",
      projectPath: "/real/project/path",
      agentHost: { request },
      editorGateway: { requestOpenTab: vi.fn() },
      fileServiceFor: async () => { throw new Error("not used"); },
    });
    const result = await executor.execute("code_editor", { task: "버그 수정", project_path: "/etc/passwd" });
    expect(request).toHaveBeenCalledWith(
      "runCodeEditor",
      expect.objectContaining({ workspaceId: "w1", sessionId: "s1", task: "버그 수정", projectPath: "/real/project/path" }),
      expect.any(Number),
    );
    expect(result).toEqual({ ok: true, data: { ok: true, summary: "완료", changedFiles: ["a.ts"] } });
  });

  it("실패 결과의 acp_error를 execution_failed로 정규화한다", async () => {
    const request = vi.fn().mockResolvedValue({ ok: false, summary: "실패", changedFiles: [], error: "acp_error", detail: "boom" });
    const executor = createEditorLocalExecutor({
      workspaceId: "w1",
      sessionId: "s1",
      projectPath: "/real/project/path",
      agentHost: { request },
      editorGateway: { requestOpenTab: vi.fn() },
      fileServiceFor: async () => { throw new Error("not used"); },
    });
    const result = await executor.execute("code_editor", { task: "t" });
    expect(result.ok).toBe(false);
    expect(result.error).toBe("execution_failed");
    expect(result.detail).toContain("boom");
  });

  it("trackCodeEditorRequest로 requestId를 알리고 완료 시 정리 콜백을 호출한다", async () => {
    const request = vi.fn().mockResolvedValue({ ok: true, summary: "완료", changedFiles: [] });
    const untrack = vi.fn();
    const trackCodeEditorRequest = vi.fn().mockReturnValue(untrack);
    const executor = createEditorLocalExecutor({
      workspaceId: "w1",
      sessionId: "s1",
      projectPath: "/p",
      agentHost: { request },
      editorGateway: { requestOpenTab: vi.fn() },
      fileServiceFor: async () => { throw new Error("not used"); },
      trackCodeEditorRequest,
    });
    await executor.execute("code_editor", { task: "t" });
    expect(trackCodeEditorRequest).toHaveBeenCalledWith(expect.any(String));
    expect(untrack).toHaveBeenCalledTimes(1);
  });

  it("취소되면 cancelCodeEditor를 호출한다", async () => {
    const controller = new AbortController();
    const request = vi.fn((method: string) => {
      if (method === "runCodeEditor") {
        return new Promise((resolve) => {
          controller.signal.addEventListener("abort", () => resolve({ ok: false, summary: "중단됨", changedFiles: [], error: "cancelled" }));
        });
      }
      return Promise.resolve({ cancelled: true });
    });
    const executor = createEditorLocalExecutor({
      workspaceId: "w1",
      sessionId: "s1",
      projectPath: "/p",
      agentHost: { request: request as never },
      editorGateway: { requestOpenTab: vi.fn() },
      fileServiceFor: async () => { throw new Error("not used"); },
    });
    const pending = executor.execute("code_editor", { task: "t" }, controller.signal);
    controller.abort();
    const result = await pending;
    expect(result).toMatchObject({ ok: false, error: "cancelled" });
    expect(request).toHaveBeenCalledWith("cancelCodeEditor", expect.objectContaining({ requestId: expect.any(String) }), expect.any(Number));
  });
});

describe("createEditorLocalExecutor: open_in_editor", () => {
  it("파일이 존재하면 EditorGateway에 open 요청을 보낸다", async () => {
    const { root, service } = await fixture();
    const requestOpenTab = vi.fn();
    const executor = createEditorLocalExecutor({
      workspaceId: "w1",
      sessionId: "s1",
      projectPath: root,
      agentHost: { request: vi.fn() },
      editorGateway: { requestOpenTab },
      fileServiceFor: async () => service,
    });
    const result = await executor.execute("open_in_editor", { path: "main.ts" });
    expect(result.ok).toBe(true);
    expect(requestOpenTab).toHaveBeenCalledWith("w1", "main.ts");
  });

  it("존재하지 않는 파일은 file_not_found를 표준 에러로 반환한다", async () => {
    const { service } = await fixture();
    const executor = createEditorLocalExecutor({
      workspaceId: "w1",
      sessionId: "s1",
      projectPath: "/p",
      agentHost: { request: vi.fn() },
      editorGateway: { requestOpenTab: vi.fn() },
      fileServiceFor: async () => service,
    });
    const result = await executor.execute("open_in_editor", { path: "missing.ts" });
    expect(result.ok).toBe(false);
    expect(result.error).toBe("execution_failed");
    expect(result.detail).toContain("file_not_found");
  });
});

describe("createEditorLocalExecutor: read_file", () => {
  it("프로젝트 내부 파일을 읽기 전용으로 반환한다", async () => {
    const { service } = await fixture();
    const executor = createEditorLocalExecutor({
      workspaceId: "w1",
      sessionId: "s1",
      projectPath: "/p",
      agentHost: { request: vi.fn() },
      editorGateway: { requestOpenTab: vi.fn() },
      fileServiceFor: async () => service,
    });
    const result = await executor.execute("read_file", { path: "main.ts" });
    expect(result.ok).toBe(true);
    expect((result.data as { content: string }).content).toContain("value = 1");
  });

  it("프로젝트 밖 경로는 차단한다", async () => {
    const { root, service } = await fixture();
    const outside = path.resolve(root, "..", "outside.txt");
    const executor = createEditorLocalExecutor({
      workspaceId: "w1",
      sessionId: "s1",
      projectPath: root,
      agentHost: { request: vi.fn() },
      editorGateway: { requestOpenTab: vi.fn() },
      fileServiceFor: async () => service,
    });
    const result = await executor.execute("read_file", { path: outside });
    expect(result.ok).toBe(false);
    expect(result.detail).toContain("path_outside_workspace");
  });

  it("바이너리 파일은 표준 에러로 반환한다", async () => {
    const { root, service } = await fixture();
    await writeFile(path.join(root, "binary.bin"), Buffer.from([0, 1, 2]));
    const executor = createEditorLocalExecutor({
      workspaceId: "w1",
      sessionId: "s1",
      projectPath: root,
      agentHost: { request: vi.fn() },
      editorGateway: { requestOpenTab: vi.fn() },
      fileServiceFor: async () => service,
    });
    const result = await executor.execute("read_file", { path: "binary.bin" });
    expect(result.ok).toBe(false);
    expect(result.detail).toContain("binary_file");
  });
});
