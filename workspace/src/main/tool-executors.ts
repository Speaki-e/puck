import { randomUUID } from "node:crypto";
import { TOOL_REGISTRY, type JSONValue, type ToolExecutionResult, type ToolExecutor, type ToolResultErrorCode } from "@speaki-e/protocol";
import type { CodeEditorResult } from "../agent-host/acp-adapter.js";
import { DEFAULT_EDITABLE_SIZE_LIMIT, type FileService } from "./file-service.js";
import { FileServiceError } from "../shared/file-contract.js";
import type { CodingAgentKind } from "../shared/acp-command.js";
import type { AgentHostController } from "./agent-host-controller.js";
import type { EditorGateway } from "./editor-gateway.js";

const CODE_EDITOR_TIMEOUT_MS = (TOOL_REGISTRY.find((entry) => entry.name === "code_editor")?.timeoutSec ?? 600) * 1_000;

export interface EditorLocalDeps {
  workspaceId: string;
  sessionId: string;
  /** 세션이 속한 워크스페이스의 실제 프로젝트 경로 -- 모델이 args로 보낸 project_path는 절대 쓰지 않는다. */
  projectPath: string;
  agentHost: Pick<AgentHostController, "request">;
  editorGateway: Pick<EditorGateway, "requestOpenTab">;
  /** 설정(W7)의 codingAgent 스냅샷 -- 비어 있으면 AcpAdapter가 "claude"로 기본 처리한다. */
  codingAgent?: CodingAgentKind;
  fileServiceFor(workspaceId: string): Promise<FileService>;
  /**
   * code_editor 요청을 Agent Host에 보내기 직전에 그 requestId를 알려준다. Agent Host의
   * code_editor_update 이벤트는 requestId만 들고 오므로(에이전트 이벤트 정규화, W3), 호출자가
   * 이 훅으로 requestId -> workspaceId/sessionId 매핑을 유지해야 진행상황을 올바른 세션에 전달할 수 있다.
   * 반환한 함수는 요청이 끝났을 때(성공/실패/취소 무관) 정리용으로 호출된다.
   */
  trackCodeEditorRequest?(requestId: string): () => void;
}

function stringArg(args: JSONValue, key: string): string | undefined {
  const value = (args as Record<string, JSONValue> | null)?.[key];
  return typeof value === "string" ? value : undefined;
}

/**
 * protocol의 ToolErrorCode(events.ts)에는 파일 전용 실패 코드가 없어(file_not_found 등)
 * execution_failed로 뭉뚱그리고 실제 사유는 detail에 싣는다.
 * TODO(protocol PR 필요): open_in_editor/read_file용 전용 에러 코드가 추가되면 이 매핑을 걷어낸다.
 */
function fileServiceErrorResult(error: FileServiceError): ToolExecutionResult {
  return { ok: false, error: "execution_failed", detail: `${error.code}: ${error.message}` };
}

function mapCodeEditorResult(result: CodeEditorResult): ToolExecutionResult {
  if (result.ok) return { ok: true, data: result as unknown as JSONValue };
  // CodeEditorResult.error는 acp-adapter.ts 자체 어휘(acp_error 등)라서 wire의 ToolResultErrorCode로
  // 그대로 옮길 수 없다 -- cancelled만 보존하고 나머지는 execution_failed로 정규화한다.
  const error: ToolResultErrorCode = result.error === "cancelled" ? "cancelled" : "execution_failed";
  const detail = [result.summary, result.detail].filter(Boolean).join("\n").slice(0, 4_000) || undefined;
  return { ok: false, error, detail };
}

async function codeEditorTool(deps: EditorLocalDeps, args: JSONValue, signal?: AbortSignal): Promise<ToolExecutionResult> {
  const task = stringArg(args, "task");
  if (!task) return { ok: false, error: "execution_failed", detail: "task가 필요합니다" };
  const requestId = randomUUID();
  const untrack = deps.trackCodeEditorRequest?.(requestId);
  const pending = deps.agentHost.request("runCodeEditor", {
    requestId,
    workspaceId: deps.workspaceId,
    sessionId: deps.sessionId,
    task,
    // 보안 핵심(W6 완료 기준): args.project_path는 절대 신뢰하지 않고 세션 workspace의 실제 경로로 강제한다.
    projectPath: deps.projectPath,
    agentKind: deps.codingAgent,
  }, CODE_EDITOR_TIMEOUT_MS);
  const onAbort = () => {
    void deps.agentHost.request("cancelCodeEditor", { requestId }, 5_000).catch(() => undefined);
  };
  signal?.addEventListener("abort", onAbort, { once: true });
  try {
    const result = await pending;
    return mapCodeEditorResult(result as unknown as CodeEditorResult);
  } finally {
    signal?.removeEventListener("abort", onAbort);
    untrack?.();
  }
}

async function openInEditorTool(deps: EditorLocalDeps, args: JSONValue): Promise<ToolExecutionResult> {
  const filePath = stringArg(args, "path");
  if (!filePath) return { ok: false, error: "execution_failed", detail: "path가 필요합니다" };
  const service = await deps.fileServiceFor(deps.workspaceId);
  try {
    await service.readFile(filePath);
  } catch (error) {
    if (error instanceof FileServiceError) return fileServiceErrorResult(error);
    throw error;
  }
  deps.editorGateway.requestOpenTab(deps.workspaceId, filePath);
  return { ok: true };
}

async function readFileTool(deps: EditorLocalDeps, args: JSONValue): Promise<ToolExecutionResult> {
  const filePath = stringArg(args, "path");
  if (!filePath) return { ok: false, error: "execution_failed", detail: "path가 필요합니다" };
  const service = await deps.fileServiceFor(deps.workspaceId);
  try {
    const file = await service.readFile(filePath);
    if (file.size > DEFAULT_EDITABLE_SIZE_LIMIT) {
      return { ok: false, error: "execution_failed", detail: `file_too_large: ${file.size} bytes` };
    }
    return { ok: true, data: { path: file.path, content: file.content } as unknown as JSONValue };
  } catch (error) {
    if (error instanceof FileServiceError) return fileServiceErrorResult(error);
    throw error;
  }
}

/**
 * editorLocal: code_editor/open_in_editor/read_file을 처리하는 in-process 실행기(plan 4.3, TODO W6).
 * 세션 하나(= 실행 하나)마다 새로 만들어 projectPath를 클로저로 고정한다 -- ToolExecutor.execute
 * 시그니처에는 세션 컨텍스트가 없으므로, 그 신뢰 경계를 여기 팩토리 호출 시점에 강제해야 한다.
 */
export function createEditorLocalExecutor(deps: EditorLocalDeps): ToolExecutor {
  return {
    execute(tool, args, signal) {
      switch (tool) {
        case "code_editor":
          return codeEditorTool(deps, args, signal);
        case "open_in_editor":
          return openInEditorTool(deps, args);
        case "read_file":
          return readFileTool(deps, args);
        default:
          return Promise.resolve({ ok: false, error: "unknown_tool", detail: `editorLocal은 ${tool}을 지원하지 않습니다` });
      }
    },
  };
}
