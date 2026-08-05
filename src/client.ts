import Anthropic from "@anthropic-ai/sdk";

import { TOOLS, executeTool, type ToolExecutionResult } from "./tools.js";
import type { AiClient, RunCallbacks } from "./types.js";

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
 * API 키와 모델명은 모듈 내부에 저장하지 않고 호출부에서 주입받는다.
 *
 * @param apiKey Anthropic API 키 (CLI에서는 ANTHROPIC_API_KEY 환경변수)
 * @param model  모델 ID (예: "claude-sonnet-4-6")
 */
export function createClient(apiKey: string, model: string): AiClient {
  const anthropic = new Anthropic({ apiKey });

  return {
    async run(command, callbacks, signal) {
      // API는 상태를 갖지 않으므로 대화 전체를 매 턴 다시 보낸다.
      const messages: Anthropic.MessageParam[] = [
        { role: "user", content: command },
      ];

      try {
        for (let turn = 0; turn < MAX_TURNS; turn++) {
          const stream = anthropic.messages.stream(
            {
              model,
              max_tokens: DEFAULT_MAX_TOKENS,
              tools: TOOLS,
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
          messages.push({
            role: "user",
            content: toolUses.map((block) => runOneTool(block, callbacks)),
          });
        }

        callbacks.onDone(false, "max_turns_exceeded");
      } catch (err) {
        // 어떤 실패도 밖으로 던지지 않는다 — 호출한 프로세스가 죽지 않아야 한다.
        callbacks.onDone(false, describeError(err));
      }
    },
  };
}

/**
 * tool_use 블록 하나를 실행하고 대응하는 tool_result 블록을 만든다.
 *
 * 이 함수는 절대 예외를 던지지 않는다. tool_use 블록이 여러 개일 때 하나가
 * 실패해서 그 id의 tool_result를 빠뜨리면, 다음 API 호출이
 * "tool_use ids were found without tool_result blocks"로 거부된다.
 * 그래서 실행기 예외와 콜백 예외를 모두 여기서 흡수한다.
 */
function runOneTool(
  block: Anthropic.ToolUseBlock,
  callbacks: RunCallbacks,
): Anthropic.ToolResultBlockParam {
  let result: ToolExecutionResult;
  try {
    callbacks.onToolCallStart?.({
      id: block.id,
      name: block.name,
      input: block.input,
    });
    result = executeTool(block.name, block.input);
  } catch (err) {
    result = { ok: false, error: describeError(err) };
  }

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
