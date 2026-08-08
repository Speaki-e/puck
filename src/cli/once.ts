/**
 * 모드 1 — 단발 실행. `npm run cli "명령"`
 *
 * A2까지의 동작을 그대로 유지한다: 텍스트 스트리밍 + 도구 로그를 stdout에
 * 내보내고, 실패로 끝나면 종료 코드 1.
 *
 * 한 번만 실행하므로 히스토리가 쌓일 일이 없다. 세션은 default 고정.
 */
import { DEFAULT_SESSION_ID } from "../session-store.js";
import type { AiClient } from "../types.js";
import { createLogCallbacks } from "./log.js";

export async function runOnce(client: AiClient, command: string): Promise<number> {
  // Ctrl+C로 스트리밍 중간 중단 (AbortSignal 경로 확인용)
  const controller = new AbortController();
  const onSigint = () => controller.abort();
  process.on("SIGINT", onSigint);

  const log = createLogCallbacks({ out: process.stdout, streamText: true, printDone: true });
  let exitCode = 0;

  await client.run(
    command,
    DEFAULT_SESSION_ID,
    {},
    {
      ...log,
      onDone(ok, summary) {
        log.onDone(ok, summary);
        if (!ok) exitCode = 1;
      },
    },
    undefined,
    controller.signal,
  );

  process.off("SIGINT", onSigint);
  return exitCode;
}
