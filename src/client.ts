import Anthropic from "@anthropic-ai/sdk";

import type { AiClient, RunCallbacks } from "./types.js";

/**
 * 스트리밍 요청이므로 넉넉하게 잡는다. max_tokens는 상한일 뿐
 * 실제 사용량이 아니며, 낮게 잡으면 응답이 중간에 잘린다.
 */
const DEFAULT_MAX_TOKENS = 64000;

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
      try {
        const stream = anthropic.messages.stream(
          {
            model,
            max_tokens: DEFAULT_MAX_TOKENS,
            messages: [{ role: "user", content: command }],
          },
          // AbortSignal을 SDK에 그대로 전달 — 중간 중단이 실제 HTTP 요청까지 전파된다.
          { signal },
        );

        // 텍스트 델타(증분)만 전달된다. 누적 스냅샷이 아니므로 그대로 흘려보내면 된다.
        stream.on("text", (delta) => callbacks.onTextChunk(delta));

        // 에러는 아래 finalMessage()의 rejection으로 받는다.
        // 리스너가 없을 때 발생할 수 있는 unhandled error 이벤트만 막아둔다.
        stream.on("error", () => {});

        const message = await stream.finalMessage();
        callbacks.onDone(true, message.stop_reason ?? undefined);
      } catch (err) {
        // 어떤 실패도 밖으로 던지지 않는다 — 호출한 프로세스가 죽지 않아야 한다.
        callbacks.onDone(false, describeError(err));
      }
    },
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
