import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { FileService } from "./file-service.js";
import { createOpenAiCodeEditorExecutor } from "./openai-code-editor.js";

/** OpenAI 응답을 순서대로 돌려주는 가짜 fetch. 마지막 요청 본문을 남긴다. */
function stubOpenAi(replies: Array<Record<string, unknown>>) {
  const bodies: Array<Record<string, unknown>> = [];
  const fetchImpl = (async (_url: string | URL | Request, init?: RequestInit) => {
    bodies.push(JSON.parse(String(init?.body)) as Record<string, unknown>);
    const message = replies.shift() ?? { content: "끝" };
    return {
      ok: true,
      json: async () => ({ choices: [{ message }] }),
      text: async () => "",
    } as Response;
  }) as unknown as typeof fetch;
  return { fetchImpl, bodies };
}

function toolCall(name: string, args: unknown, id = "c1") {
  return { tool_calls: [{ id, type: "function", function: { name, arguments: JSON.stringify(args) } }], content: null };
}

describe("createOpenAiCodeEditorExecutor", () => {
  const services: FileService[] = [];

  afterEach(async () => {
    for (const service of services.splice(0)) await service.close();
  });

  async function project(files: Record<string, string>) {
    const root = await mkdtemp(path.join(tmpdir(), "openai-editor-"));
    for (const [name, content] of Object.entries(files)) {
      await writeFile(path.join(root, name), content, "utf8");
    }
    const service = await FileService.create(root);
    services.push(service);
    return { root, service };
  }

  it("읽고 쓰기까지 마치면 파일이 실제로 바뀌고 요약이 돌아온다", async () => {
    const { root, service } = await project({ "hello.ts": "export const hello = 1;\n" });
    const { fetchImpl } = stubOpenAi([
      toolCall("read_file", { path: "hello.ts" }),
      toolCall("write_file", { path: "hello.ts", content: "// 인사\nexport const hello = 1;\n" }, "c2"),
      { content: "hello.ts에 주석을 추가했습니다", tool_calls: [] },
    ]);

    const result = await createOpenAiCodeEditorExecutor({
      projectPath: root,
      fileServiceFor: async () => service,
      apiKey: "sk-test",
      model: "gpt-4o",
      fetchImpl,
    }).execute("code_editor", { task: "주석 달아줘" });

    expect(result.ok).toBe(true);
    expect(await readFile(path.join(root, "hello.ts"), "utf8")).toBe("// 인사\nexport const hello = 1;\n");
    expect(result.data).toMatchObject({ summary: "hello.ts에 주석을 추가했습니다", changedFiles: ["hello.ts"] });
  });

  it("없던 파일은 새로 만든다", async () => {
    const { root, service } = await project({});
    const { fetchImpl } = stubOpenAi([
      toolCall("write_file", { path: "src/new.ts", content: "export const x = 1;\n" }),
      { content: "새 파일을 만들었습니다", tool_calls: [] },
    ]);

    const result = await createOpenAiCodeEditorExecutor({
      projectPath: root,
      fileServiceFor: async () => service,
      apiKey: "sk-test",
      model: "gpt-4o",
      fetchImpl,
    }).execute("code_editor", { task: "파일 만들어줘" });

    expect(result.ok).toBe(true);
    expect(await readFile(path.join(root, "src/new.ts"), "utf8")).toBe("export const x = 1;\n");
  });

  /// 모델이 보낸 경로 하나로 워크스페이스 밖에 파일이 생기면 안 된다.
  it("프로젝트 밖 경로 쓰기는 거부하고, 그 사실을 모델에게 돌려준다", async () => {
    const { root, service } = await project({});
    const escaped = path.join(root, "..", `escaped-${process.pid}.txt`);
    const { fetchImpl, bodies } = stubOpenAi([
      toolCall("write_file", { path: `../escaped-${process.pid}.txt`, content: "탈출" }),
      { content: "쓰지 못했습니다", tool_calls: [] },
    ]);

    const result = await createOpenAiCodeEditorExecutor({
      projectPath: root,
      fileServiceFor: async () => service,
      apiKey: "sk-test",
      model: "gpt-4o",
      fetchImpl,
    }).execute("code_editor", { task: "밖에 써줘" });

    expect(result.ok).toBe(true); // 모델이 스스로 포기한 것이므로 실행 자체는 정상 종료
    await expect(readFile(escaped, "utf8")).rejects.toThrow();
    const toolReply = (bodies.at(-1)?.messages as Array<{ role: string; content: string }>)
      .findLast((message) => message.role === "tool");
    expect(toolReply?.content).toContain("프로젝트 폴더 밖");
  });

  it("HTTP 실패는 실행 실패로 보고한다", async () => {
    const { root, service } = await project({});
    const fetchImpl = (async () => ({
      ok: false,
      status: 401,
      json: async () => ({}),
      text: async () => "invalid api key",
    } as Response)) as unknown as typeof fetch;

    const result = await createOpenAiCodeEditorExecutor({
      projectPath: root,
      fileServiceFor: async () => service,
      apiKey: "sk-bad",
      model: "gpt-4o",
      fetchImpl,
    }).execute("code_editor", { task: "고쳐줘" });

    expect(result.ok).toBe(false);
    expect(result.detail).toContain("401");
  });

  it("프로젝트가 없는 워크스페이스에서는 편집을 시작하지 않는다", async () => {
    const { service } = await project({});
    const result = await createOpenAiCodeEditorExecutor({
      projectPath: "",
      fileServiceFor: async () => service,
      apiKey: "sk-test",
      model: "gpt-4o",
      fetchImpl: (async () => {
        throw new Error("호출되면 안 됨");
      }) as unknown as typeof fetch,
    }).execute("code_editor", { task: "고쳐줘" });

    expect(result.ok).toBe(false);
    expect(result.detail).toContain("연결된 프로젝트가 없습니다");
  });
});
