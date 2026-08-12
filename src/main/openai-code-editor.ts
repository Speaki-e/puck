import { writeFile as writeFileRaw, mkdir } from "node:fs/promises";
import path from "node:path";

import type { JSONValue, ToolExecutionResult, ToolExecutor } from "@speaki-e/protocol";

import { isPathInside } from "../shared/path-containment.js";
import type { FileService } from "./file-service.js";

/**
 * code_editor를 ACP(Claude Code) 대신 OpenAI 툴 루프로 실행하는 실행기.
 *
 * 왜: 팀이 가진 키가 OpenAI 하나뿐이다(pet-app의 F15 두뇌도 같은 이유로 OpenAI다).
 * 기본 경로인 ACP는 Claude Code 인증을, ai-module은 Anthropic API 키를 요구하므로
 * 키가 하나뿐인 환경에서는 편집만 돌지 않는 상태가 된다. 이 실행기는 같은
 * ToolExecutor 계약을 그대로 구현하므로 code_editor를 부르는 쪽(DirectCodeEditorRuntime,
 * ai-module)은 무엇이 편집했는지 알 필요가 없다.
 *
 * 파일 접근은 전부 FileService를 지나간다 -- 2MB 상한, 바이너리 거부, 저장 전 revision
 * 확인, 제외 디렉터리 목록이 이미 거기 있고, 여기서 fs를 직접 만지면 그 규칙을 조용히
 * 우회하게 된다. 새 파일 생성만 FileService에 없어서 직접 쓰되, 경로 격리는
 * isPathInside로 같은 기준을 강제한다.
 *
 * ponytail: 도구 3개(목록/읽기/전체 쓰기)와 턴 상한이 전부다. 부분 편집(diff/patch),
 * 셸 실행, 멀티파일 리팩터링 계획 같은 건 없다 -- ACP가 있는 환경에서는 그쪽이 훨씬
 * 낫고, 이건 "키가 OpenAI뿐일 때도 편집이 되긴 한다"를 위한 최소 구현이다.
 */

const MAX_TURNS = 12;
const ENDPOINT = "https://api.openai.com/v1/chat/completions";

export interface OpenAiCodeEditorDeps {
  projectPath: string;
  fileServiceFor(): Promise<FileService>;
  apiKey: string;
  model: string;
  /** 테스트에서 실제 네트워크 대신 끼워 넣는다. */
  fetchImpl?: typeof fetch;
}

interface ChatMessage {
  role: "system" | "user" | "assistant" | "tool";
  content: string | null;
  tool_calls?: Array<{ id: string; type: "function"; function: { name: string; arguments: string } }>;
  tool_call_id?: string;
}

const TOOLS = [
  {
    type: "function" as const,
    function: {
      name: "list_files",
      description: "프로젝트의 파일 목록을 반환한다. 편집 전에 먼저 호출해 실제 경로를 확인할 것.",
      parameters: { type: "object", properties: {}, required: [] },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "read_file",
      description: "파일 내용을 읽는다. 쓰기 전에 반드시 먼저 읽어야 한다.",
      parameters: {
        type: "object",
        properties: { path: { type: "string", description: "프로젝트 루트 기준 상대 경로" } },
        required: ["path"],
      },
    },
  },
  {
    type: "function" as const,
    function: {
      name: "write_file",
      description:
        "파일 전체를 주어진 내용으로 덮어쓴다(없으면 새로 만든다). 부분 편집은 없으므로 content에는 " +
        "생략 없는 파일 전체를 담아야 한다 -- '...' 같은 축약을 쓰면 그대로 저장되어 파일이 망가진다.",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "프로젝트 루트 기준 상대 경로" },
          content: { type: "string", description: "파일 전체 내용" },
        },
        required: ["path", "content"],
      },
    },
  },
];

const SYSTEM_PROMPT = [
  "너는 사용자의 프로젝트 파일을 직접 편집하는 코딩 에이전트다.",
  "규칙:",
  "- 먼저 list_files/read_file로 실제 내용을 확인하고, 추측으로 쓰지 않는다.",
  "- write_file은 파일 전체를 덮어쓴다. 읽은 내용을 바탕으로 완전한 파일을 만들어 보낼 것.",
  "- 요청받은 것만 바꾼다. 요청에 없는 리팩터링·포매팅·주석 정리를 끼워 넣지 않는다.",
  "- 편집이 끝나면 무엇을 어떻게 바꿨는지 한두 문장으로 한국어로 요약한다.",
  "- 요청을 수행할 수 없으면 파일을 건드리지 말고 이유를 설명한다.",
].join("\n");

export function createOpenAiCodeEditorExecutor(deps: OpenAiCodeEditorDeps): ToolExecutor {
  return {
    async execute(tool, args, signal): Promise<ToolExecutionResult> {
      if (tool !== "code_editor") {
        return { ok: false, error: "unknown_tool", detail: `openAiCodeEditor는 ${tool}을 지원하지 않습니다` };
      }
      const task = typeof (args as Record<string, unknown> | undefined)?.task === "string"
        ? String((args as Record<string, string>).task)
        : "";
      if (!task) return { ok: false, error: "execution_failed", detail: "task가 필요합니다" };
      if (!deps.projectPath) {
        return { ok: false, error: "execution_failed", detail: "이 워크스페이스에는 연결된 프로젝트가 없습니다" };
      }
      return await runLoop(deps, task, signal);
    },
  };
}

async function runLoop(deps: OpenAiCodeEditorDeps, task: string, signal?: AbortSignal): Promise<ToolExecutionResult> {
  const fetchImpl = deps.fetchImpl ?? fetch;
  const messages: ChatMessage[] = [
    { role: "system", content: SYSTEM_PROMPT },
    { role: "user", content: task },
  ];
  const changedFiles = new Set<string>();
  // read_file이 준 revision. saveFile은 이 값으로 "읽은 뒤 디스크가 바뀌지 않았음"을
  // 확인하므로, 모델이 읽지 않고 쓰려 하면 그 지점에서 막힌다.
  const revisions = new Map<string, string>();

  for (let turn = 0; turn < MAX_TURNS; turn += 1) {
    if (signal?.aborted) return { ok: false, error: "cancelled", detail: "사용자가 중지했습니다" };

    const response = await fetchImpl(ENDPOINT, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${deps.apiKey}` },
      body: JSON.stringify({ model: deps.model, messages, tools: TOOLS }),
      signal,
    });
    if (!response.ok) {
      const body = await response.text().catch(() => "");
      return { ok: false, error: "execution_failed", detail: `OpenAI ${response.status}: ${body.slice(0, 500)}` };
    }
    const payload = await response.json() as { choices?: Array<{ message?: ChatMessage }> };
    const message = payload.choices?.[0]?.message;
    if (!message) return { ok: false, error: "execution_failed", detail: "OpenAI 응답을 해석하지 못했습니다" };

    messages.push(message);
    const calls = message.tool_calls ?? [];
    if (calls.length === 0) {
      const summary = message.content?.trim() ?? "";
      return {
        ok: true,
        data: {
          summary: summary || "편집을 마쳤습니다",
          changedFiles: [...changedFiles],
        } as unknown as JSONValue,
      };
    }

    for (const call of calls) {
      const result = await runTool(deps, call.function.name, call.function.arguments, changedFiles, revisions);
      messages.push({ role: "tool", tool_call_id: call.id, content: result });
    }
  }

  return {
    ok: false,
    error: "execution_failed",
    detail: `도구를 ${MAX_TURNS}번 호출하고도 끝나지 않아 중단했습니다`,
  };
}

async function runTool(
  deps: OpenAiCodeEditorDeps,
  name: string,
  rawArguments: string,
  changedFiles: Set<string>,
  revisions: Map<string, string>,
): Promise<string> {
  let args: Record<string, unknown> = {};
  try {
    args = rawArguments ? JSON.parse(rawArguments) as Record<string, unknown> : {};
  } catch {
    return "error: 도구 인자를 JSON으로 해석하지 못했습니다";
  }

  try {
    const service = await deps.fileServiceFor();
    switch (name) {
      case "list_files": {
        const tree = await service.listTree();
        return JSON.stringify(tree).slice(0, 20_000);
      }
      case "read_file": {
        const requestPath = String(args.path ?? "");
        if (!requestPath) return "error: path가 필요합니다";
        const file = await service.readFile(requestPath);
        revisions.set(file.path, file.revision);
        return file.content ?? "";
      }
      case "write_file": {
        const requestPath = String(args.path ?? "");
        const content = typeof args.content === "string" ? args.content : undefined;
        if (!requestPath || content === undefined) return "error: path와 content가 필요합니다";
        const written = await write(deps, service, requestPath, content, revisions);
        changedFiles.add(written);
        return `saved ${written}`;
      }
      default:
        return `error: 알 수 없는 도구 ${name}`;
    }
  } catch (error) {
    // 모델이 읽어서 스스로 고쳐야 하는 정보다 -- 루프를 끊지 않고 그대로 돌려준다
    // (경로 오타, 2MB 초과, 바이너리, 읽기 전 쓰기 시도 전부 여기로 온다).
    return `error: ${error instanceof Error ? error.message : String(error)}`;
  }
}

async function write(
  deps: OpenAiCodeEditorDeps,
  service: FileService,
  requestPath: string,
  content: string,
  revisions: Map<string, string>,
): Promise<string> {
  const expectedRevision = revisions.get(normalize(requestPath));
  if (expectedRevision !== undefined) {
    const saved = await service.saveFile({ path: requestPath, content, expectedRevision });
    revisions.set(saved.path, saved.revision);
    return saved.path;
  }

  // 새 파일. FileService.saveFile은 존재하는 파일만 다루므로(resolveExisting) 여기서
  // 직접 쓰되, 프로젝트 루트 밖은 거부한다 -- 이 검사가 없으면 모델이 보낸 "../"
  // 한 줄로 워크스페이스 밖에 파일이 생긴다.
  const target = path.resolve(deps.projectPath, requestPath);
  if (!isPathInside(deps.projectPath, target)) {
    throw new Error("프로젝트 폴더 밖에는 쓸 수 없습니다");
  }
  await mkdir(path.dirname(target), { recursive: true });
  await writeFileRaw(target, content, "utf8");
  return normalize(path.relative(deps.projectPath, target));
}

function normalize(requestPath: string): string {
  return requestPath.split(path.sep).join("/").replace(/^\.\//, "");
}
