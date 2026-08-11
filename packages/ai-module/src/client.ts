import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";

import Anthropic from "@anthropic-ai/sdk";
import type { JSONValue, ToolDefinition } from "@speaki-e/protocol";

import { describeApproval, loadWhitelist, needsApproval, type Whitelist } from "./approval.js";
import { buildSystemPrompt, loadBasePrompt } from "./context.js";
import { DEFAULT_SESSION_ID, SessionStore } from "./session-store.js";
import { getToolDef, toAnthropicTools, validateArgs } from "./tools.js";
import type {
  AiClient,
  Attachment,
  ClientOptions,
  Context,
  ExecutorMap,
  LocalToolErrorCode,
  RunCallbacks,
  ToolExecutionResult,
} from "./types.js";

/**
 * 스트리밍 요청이므로 넉넉하게 잡는다. max_tokens는 상한일 뿐
 * 실제 사용량이 아니며, 낮게 잡으면 응답이 중간에 잘린다.
 */
const DEFAULT_MAX_TOKENS = 64000;

/**
 * 도구 호출 루프의 최대 턴 수. 무한루프 방지용 안전장치다.
 * 한 턴 = API 호출 1회 + (필요 시) 도구 실행 1묶음.
 */
const MAX_TURNS = 10;

/**
 * Claude 스트리밍 클라이언트를 생성한다.
 *
 * API 키/모델/실행기를 전부 주입받는다 — 모듈 내부에 저장하지 않고, 도구를
 * 직접 실행하지도 않는다. 어떤 도구가 어느 실행기로 가는지는 protocol의
 * TOOL_REGISTRY가 정하고, 이 모듈은 그 라우팅만 수행한다.
 *
 * 세션 히스토리는 이 클라이언트 인스턴스가 들고 있다. 인스턴스를 새로 만들면
 * 이전 대화는 남지 않는다.
 */
export function createClient({ apiKey, model, executors }: ClientOptions): AiClient {
  const anthropic = new Anthropic({ apiKey });
  const tools = toAnthropicTools();
  const basePrompt = loadBasePrompt();
  const whitelist = loadWhitelist();
  const store = new SessionStore((sessionId, waiting) => {
    // stdout은 --seq의 JSON 전용이라 건드리지 않는다.
    process.stderr.write(`[queued session=${sessionId} waiting=${waiting}]\n`);
  });

  /** 한 턴의 실제 실행. 큐를 통과한 뒤에만 호출된다. */
  async function runTurn(
    command: string,
    sessionId: string,
    context: Context,
    callbacks: RunCallbacks,
    attachments?: Attachment[],
    signal?: AbortSignal,
  ): Promise<void> {
    // 큐에서 기다리는 동안 중단됐을 수 있다. API를 부르기 전에 걸러낸다.
    if (signal?.aborted) {
      callbacks.onDone(false, "aborted");
      return;
    }

    const session = store.getOrCreate(sessionId);

    // 이전 대화 위에 이번 입력을 얹는다. API는 상태를 갖지 않으므로
    // 히스토리 전체를 매 턴 다시 보낸다.
    const messages: Anthropic.MessageParam[] = [
      ...session.history,
      { role: "user", content: await buildUserContent(command, attachments) },
    ];
    const system = buildSystemPrompt(basePrompt, context, session.brief);

    try {
      for (let turn = 0; turn < MAX_TURNS; turn++) {
        const stream = anthropic.messages.stream(
          {
            model,
            max_tokens: DEFAULT_MAX_TOKENS,
            system,
            tools,
            messages,
          },
          // AbortSignal을 SDK에 그대로 전달 — 중간 중단이 실제 HTTP 요청까지 전파된다.
          // 루프의 모든 턴에 걸어야 도구 실행 후 다음 호출도 즉시 멈춘다.
          { signal },
        );

        // 텍스트 델타(증분)만 전달된다. 누적 스냅샷이 아니므로 그대로 흘려보내면 된다.
        stream.on("text", (delta) => callbacks.onTextChunk(delta));

        // 에러는 아래 finalMessage()의 rejection으로 받는다.
        // 리스너가 없을 때 발생할 수 있는 unhandled error 이벤트만 막아둔다.
        stream.on("error", () => {});

        const message = await stream.finalMessage();

        if (message.stop_reason !== "tool_use") {
          // end_turn만 정상 종료다. max_tokens(잘림)나 refusal을 성공으로
          // 보고하면 잘린 답변이 완성된 답변처럼 보인다.
          const ok = message.stop_reason === "end_turn";
          if (ok) {
            // 정상 종료한 턴만 히스토리에 남긴다. 항상 assistant 메시지로
            // 끝나므로 다음 턴의 user 메시지와 짝이 맞는다.
            store.commit(sessionId, [
              ...messages,
              { role: "assistant", content: message.content },
            ]);
          }
          callbacks.onDone(ok, message.stop_reason ?? undefined);
          return;
        }

        const toolUses = message.content.filter(
          (block): block is Anthropic.ToolUseBlock => block.type === "tool_use",
        );

        // assistant 메시지(도구 호출 포함)를 먼저 넣어야 tool_result가 짝을 찾는다.
        // content 전체를 넣는다 — text 블록만 뽑으면 tool_use 블록이 사라져 API가 거부한다.
        messages.push({ role: "assistant", content: message.content });

        // 여러 개면 전부 순차 실행하고, 모든 id에 대한 tool_result를 한 user
        // 메시지에 모아서 보낸다. 나눠 보내면 모델이 병렬 호출을 그만두게 된다.
        const results: Anthropic.ToolResultBlockParam[] = [];
        for (const block of toolUses) {
          results.push(await runOneTool(block, executors, whitelist, store, callbacks, signal));
        }
        messages.push({ role: "user", content: results });
      }

      // 턴 수를 다 쓴 대화는 tool_result로 끝나 있어 히스토리로 남기지 않는다.
      callbacks.onDone(false, "max_turns_exceeded");
    } catch (err) {
      // 어떤 실패도 밖으로 던지지 않는다 — 호출한 프로세스가 죽지 않아야 한다.
      // 중단·에러로 끝난 턴도 커밋하지 않는다: tool_use만 있고 tool_result가
      // 없는 히스토리를 남기면 다음 호출이 통째로 거부된다.
      callbacks.onDone(false, describeError(err));
    }
  }

  return {
    // protocol AgentRun 형태와 A0~A3 형태를 한 구현으로 받는다.
    // 두 번째 인자가 문자열이면 protocol 형태(sessionId), 아니면 예전 형태(callbacks).
    run(
      command: string,
      second: RunCallbacks | string,
      third?: Context | AbortSignal,
      fourth?: RunCallbacks,
      fifth?: Attachment[],
      sixth?: AbortSignal,
    ): Promise<void> {
      const legacy = typeof second !== "string";
      const sessionId = legacy ? DEFAULT_SESSION_ID : second;
      const context = legacy ? {} : ((third as Context | undefined) ?? {});
      const callbacks = legacy ? second : (fourth as RunCallbacks);
      const signal = legacy ? (third as AbortSignal | undefined) : sixth;

      return store.enqueue(sessionId, () =>
        runTurn(command, sessionId, context, callbacks, legacy ? undefined : fifth, signal),
      );
    },
  };
}

/** Workspace가 검증한 이미지 첨부를 Claude 멀티모달 user content로 변환한다. */
async function buildUserContent(
  command: string,
  attachments?: Attachment[],
): Promise<Anthropic.MessageParam["content"]> {
  if (!attachments?.length) return command;

  const blocks: Array<Record<string, unknown>> = [{ type: "text", text: command }];
  for (const attachment of attachments) {
    if (attachment.type !== "image" || !attachment.path) continue;
    const mediaType = imageMediaType(attachment.path);
    if (!mediaType) continue;
    try {
      const data = (await readFile(attachment.path)).toString("base64");
      blocks.push({
        type: "image",
        source: { type: "base64", media_type: mediaType, data },
      });
    } catch {
      blocks.push({ type: "text", text: `[첨부 이미지를 읽지 못했습니다: ${path.basename(attachment.path)}]` });
    }
  }
  return blocks as unknown as Anthropic.MessageParam["content"];
}

function imageMediaType(filePath: string): "image/jpeg" | "image/png" | "image/gif" | "image/webp" | undefined {
  switch (path.extname(filePath).toLowerCase()) {
    case ".jpg":
    case ".jpeg":
      return "image/jpeg";
    case ".png":
      return "image/png";
    case ".gif":
      return "image/gif";
    case ".webp":
      return "image/webp";
    default:
      return undefined;
  }
}

/**
 * tool_use 블록 하나를 레지스트리 기준으로 라우팅해 실행하고, 대응하는
 * tool_result 블록을 만든다.
 *
 * 이 함수는 절대 예외를 던지지 않는다. tool_use 블록이 여러 개일 때 하나가
 * 실패해서 그 id의 tool_result를 빠뜨리면, 다음 API 호출이
 * "tool_use ids were found without tool_result blocks"로 거부된다.
 * 그래서 실행기 예외와 콜백 예외를 모두 여기서 흡수한다.
 */
async function runOneTool(
  block: Anthropic.ToolUseBlock,
  executors: ExecutorMap,
  whitelist: Whitelist,
  store: SessionStore,
  callbacks: RunCallbacks,
  signal?: AbortSignal,
): Promise<Anthropic.ToolResultBlockParam> {
  const def = getToolDef(block.name);

  try {
    callbacks.onToolCallStart?.({
      id: block.id,
      name: block.name,
      input: block.input,
      ...(def ? { executor: def.executor } : {}),
    });
  } catch {
    // 로그 콜백이 실패해도 도구 실행과 tool_result 생성은 계속돼야 한다.
  }

  const result = await dispatch(def, block, executors, whitelist, store, callbacks, signal);

  // 결과는 문자열로만 돌려줄 수 있으므로 JSON으로 직렬화한다.
  const content = JSON.stringify(result);

  try {
    callbacks.onToolResult?.({
      id: block.id,
      name: block.name,
      ok: result.ok,
      content,
    });
  } catch {
    // 출력 콜백이 실패해도 tool_result는 반드시 만들어야 한다. 무시하고 진행.
  }

  return {
    type: "tool_result",
    tool_use_id: block.id,
    content,
    // 실패한 결과에만 붙인다. 모델이 재시도할지 다른 방법을 쓸지 판단하는 신호다.
    ...(result.ok ? {} : { is_error: true }),
  };
}

/**
 * 레지스트리 정의에 따라 실행기를 고르고 호출한다.
 *
 * 실패는 전부 { ok: false } 결과로 표현하고 예외를 던지지 않는다.
 */
async function dispatch(
  def: ToolDefinition | undefined,
  block: Anthropic.ToolUseBlock,
  executors: ExecutorMap,
  whitelist: Whitelist,
  store: SessionStore,
  callbacks: RunCallbacks,
  signal?: AbortSignal,
): Promise<ToolExecutionResult> {
  // 1) 레지스트리에 없는 이름 — 모델이 지어낸 도구이거나 레지스트리가 바뀐 경우.
  if (def === undefined) {
    return fail("unknown_tool", `${block.name}은(는) 등록된 도구가 아닙니다.`);
  }

  // 2) "ai-module"은 디스패치 대상이 아니라 인라인 처리 표식이다(기획서 3.7).
  //    소켓으로 내보내지 않고 이 루프가 직접 처리한다.
  if (def.executor === "ai-module") {
    if (def.name !== "open_task_session") {
      return fail("not_implemented_yet", `${def.name}은(는) 아직 구현되지 않았습니다.`);
    }
    const badField = validateArgs(def, block.input);
    if (badField !== undefined) {
      return fail("invalid_input", `${badField} 값이 없거나 형식이 올바르지 않습니다.`);
    }
    return openTaskSession(block.input as Record<string, string>, store, callbacks);
  }

  // TODO: def.timeoutSec — 실행기 호출에 타임아웃을 걸고 초과 시 timeout 반환.
  //   지금은 mock이 즉시 응답하므로 걸지 않는다.

  const executor = executors[def.executor];
  if (executor === undefined) {
    return fail("executor_not_available", `${def.executor} 실행기가 주입되지 않았습니다.`);
  }

  // 스키마를 strict로 걸지 않았으므로 모델 입력을 그대로 믿지 않는다.
  // 승인보다 먼저 본다 — 형식이 깨진 호출로 사용자를 깨울 이유가 없다.
  const badField = validateArgs(def, block.input);
  if (badField !== undefined) {
    return fail("invalid_input", `${badField} 값이 없거나 형식이 올바르지 않습니다.`);
  }

  // 승인 게이트(기획서 3.3). 거부되면 실행기를 호출하지 않는 것이 핵심이다 —
  // denied_by_user는 소켓을 지나지 않는 모델 전용 값이므로, 여기서 막지 못하면
  // 위험한 명령이 이미 pet-app으로 나간 뒤가 된다.
  if (needsApproval(def, block.input, whitelist)) {
    const approved = await requestApproval(describeApproval(def, block.input), callbacks, signal);
    if (!approved) {
      return fail("denied_by_user", `${def.name} 실행이 사용자에 의해 거부되었습니다.`);
    }
  }

  try {
    // block.input은 API가 파싱해 준 JSON이므로 JSONValue다.
    return await executor.execute(def.name, block.input as JSONValue, signal);
  } catch (err) {
    // 중단으로 인한 실패도 여기서 결과로 흡수한다. 그래야 이 턴의 모든 tool_use에
    // tool_result가 채워지고, 실제 종료는 다음 API 호출의 abort로 이어진다.
    return fail("execution_failed", describeError(err));
  }
}

/**
 * 사용자에게 승인을 묻고 답을 기다린다.
 *
 * 안전 기본값은 항상 거부다:
 * - 콜백을 붙이지 않은 호출부(승인 UI가 없는 환경)에서는 묻지 않고 거부한다.
 *   물어볼 수 없는데 실행하면 게이트가 없는 것과 같다.
 * - 대기 중에 abort되면 즉시 거부로 풀어 pending이 남지 않게 한다.
 * - 콜백이 예외를 던져도 거부로 처리한다.
 *
 * resolve가 여러 번 호출돼도 첫 번째만 반영한다 — UI가 중복 호출해도
 * 이 프라미스가 두 번 풀리지 않아야 한다.
 */
function requestApproval(
  summary: string,
  callbacks: RunCallbacks,
  signal?: AbortSignal,
): Promise<boolean> {
  const ask = callbacks.onApprovalRequired;
  if (ask === undefined) return Promise.resolve(false);
  if (signal?.aborted) return Promise.resolve(false);

  return new Promise<boolean>((settle) => {
    let settled = false;
    const finish = (approved: boolean): void => {
      if (settled) return;
      settled = true;
      signal?.removeEventListener("abort", onAbort);
      settle(approved);
    };
    const onAbort = (): void => finish(false);

    signal?.addEventListener("abort", onAbort, { once: true });

    try {
      ask(summary, finish);
    } catch {
      finish(false);
    }
  });
}

/**
 * open_task_session 인라인 처리 (기획서 3.7).
 *
 * 새 sessionId를 발급하고 brief를 시드로 심은 뒤 onSessionCreated로 알린다.
 * 소켓 디스패치를 타지 않는 유일한 도구다.
 *
 * 이번 run의 나머지 대화는 원래 세션에 남는다. 새 세션은 brief만 들고 시작하고,
 * 다음 명령부터 그쪽에 쌓인다 — 한 턴을 중간에서 두 히스토리로 쪼개면 원래 쪽에
 * tool_result 없는 tool_use가 남아 다음 호출이 거부되기 때문이다.
 */
function openTaskSession(
  args: Record<string, string>,
  store: SessionStore,
  callbacks: RunCallbacks,
): ToolExecutionResult {
  const { title, brief } = args;
  const sessionId = `task-${Date.now().toString(36)}-${randomUUID().slice(0, 8)}`;

  store.seed(sessionId, brief as string, title as string);

  try {
    callbacks.onSessionCreated?.(sessionId, title as string);
  } catch {
    // 통지 실패로 세션 생성 자체를 되돌리지는 않는다. 세션은 이미 만들어졌다.
  }

  // protocol의 responseNote는 data: null이지만, 모델이 "어느 세션에서
  // 이어가는지" 답변에 쓸 수 있도록 새 id를 실어 보낸다(보고 대상).
  return { ok: true, data: { session_id: sessionId }, detail: `새 작업 세션: ${title}` };
}

/** 실패 결과. error 코드는 모델이 재시도 여부를 판단하는 신호이므로 detail과 분리한다. */
function fail(error: LocalToolErrorCode, detail: string): ToolExecutionResult {
  // ToolExecutionResult.error는 protocol의 ToolResultErrorCode로 좁혀져 있지만,
  // invalid_input/not_implemented_yet/executor_not_available은 디스패치 이전에
  // ai-module 안에서만 발생해 소켓을 건너지 않는다. LocalToolErrorCode 참조.
  return { ok: false, error, detail } as ToolExecutionResult;
}

/** 에러를 한 줄 요약 문자열로 변환한다. */
function describeError(err: unknown): string {
  // APIUserAbortError는 APIError의 하위 클래스이므로 먼저 검사해야 한다.
  if (err instanceof Anthropic.APIUserAbortError) return "aborted";
  if (err instanceof Anthropic.AuthenticationError) return `auth error (401): ${err.message}`;
  if (err instanceof Anthropic.PermissionDeniedError) return `permission denied (403): ${err.message}`;
  if (err instanceof Anthropic.NotFoundError) return `not found (404): ${err.message}`;
  if (err instanceof Anthropic.RateLimitError) return `rate limited (429): ${err.message}`;
  if (err instanceof Anthropic.APIConnectionError) return `connection error: ${err.message}`;
  if (err instanceof Anthropic.APIError) return `api error (${err.status ?? "?"}): ${err.message}`;
  if (err instanceof Error) return err.message;
  return String(err);
}
