/**
 * 모드 3 — 시퀀스 출력. `npm run cli --seq "명령"`
 *
 * A4 회귀 스크립트가 파이프로 읽어갈 출력이므로 stdout 규약이 엄격하다:
 * **stdout에는 JSON 한 줄만** 나간다. 사람이 읽는 로그는 전부 stderr.
 *
 * 실행이 실패하거나 중단돼도 JSON은 반드시 출력하고 종료 코드는 0을 유지한다.
 * 종료 코드로 실패를 알리면 파이프 상대가 출력을 읽기 전에 끊어버린다 —
 * "무엇이 왜 실패했는지"는 JSON의 ok/stopReason으로 전달한다.
 */
import type { AiClient } from "../types.js";
import { formatToolCall, formatToolResult } from "./log.js";

/** 호출된 도구 하나. A4 회귀 비교의 최소 단위(도구명 + 인자)다. */
export interface SeqEntry {
  tool: string;
  /** 모델이 보낸 도구 입력 그대로. 검증 실패로 실행되지 않은 호출도 그대로 실린다. */
  args: unknown;
}

/** open_task_session으로 새로 열린 세션. 발생하지 않으면 필드 자체가 없다. */
export interface SeqCreatedSession {
  id: string;
  title: string;
}

/** --seq가 stdout에 출력하는 JSON 한 줄의 스키마. */
export interface SeqOutput {
  command: string;
  /** 이 명령을 실행한 세션 id. --session=<id>로 지정, 기본 "default". */
  session: string;
  /** 실제 호출된 순서대로. 도구 호출이 없으면 빈 배열. */
  sequence: SeqEntry[];
  /** 루프가 정상 종료(end_turn)했는지. 도구 실행 개별 실패는 여기 반영되지 않는다. */
  ok: boolean;
  /** 성공 시 stop_reason, 실패 시 실패 요약 문자열. */
  stopReason: string;
  /** open_task_session이 발생했을 때만 존재한다. */
  createdSession?: SeqCreatedSession;
}

export async function runSeq(
  client: AiClient,
  command: string,
  sessionId: string,
): Promise<number> {
  const controller = new AbortController();
  const onSigint = () => controller.abort();
  process.on("SIGINT", onSigint);

  const sequence: SeqEntry[] = [];
  let createdSession: SeqCreatedSession | undefined;
  let ok = false;
  let stopReason = "unknown";

  await client.run(
    command,
    sessionId,
    {},
    {
      // 텍스트는 버린다 — stdout은 JSON 전용이고, 시퀀스 검증에 본문은 필요 없다.
      onTextChunk() {},
      onToolCallStart(call) {
        sequence.push({ tool: call.name, args: call.input });
        process.stderr.write(`${formatToolCall(call)}\n`);
      },
      onToolResult(result) {
        process.stderr.write(`${formatToolResult(result)}\n`);
      },
      onSessionCreated(id, title) {
        // 한 run에서 여러 번 열릴 수 있지만 마지막 것만 싣는다 —
        // 케이스 표가 검증하는 건 "작업 세션으로 분기했는가"다.
        createdSession = { id, title };
        process.stderr.write(`[session_created] ${id} (${title})\n`);
      },
      onDone(doneOk, summary) {
        ok = doneOk;
        // stop_reason이 null인 응답도 있으므로 문자열 자리를 비우지 않는다.
        stopReason = summary ?? "unknown";
      },
    },
    undefined,
    controller.signal,
  );

  const output: SeqOutput = {
    command,
    session: sessionId,
    sequence,
    ok,
    stopReason,
    ...(createdSession ? { createdSession } : {}),
  };
  process.stdout.write(`${JSON.stringify(output)}\n`);

  process.off("SIGINT", onSigint);
  return 0;
}
