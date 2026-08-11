/**
 * ai-module A3 — CLI 공통 출력 포맷.
 *
 * 단발/REPL 모드는 사람이 읽는 로그를 stdout에, --seq 모드는 같은 로그를
 * stderr에 흘린다. stdout 규약(--seq는 JSON 한 줄만)이 모드마다 다르므로
 * 출력 스트림을 인자로 받고, 포맷 자체는 한 곳에서만 정의한다.
 */
import type { RunCallbacks, ToolCallInfo, ToolResultInfo } from "../types.js";

export interface LogOptions {
  /** 로그를 흘려보낼 스트림. --seq에서는 stderr. */
  out: NodeJS.WritableStream;
  /** 모델 텍스트 청크를 그대로 출력할지. --seq에서는 false. */
  streamText: boolean;
  /** 종료 줄([done ...])을 출력할지. --seq에서는 JSON이 그 역할을 한다. */
  printDone: boolean;
}

/** 도구 호출 시작 로그. 이름 → 실행기 라우팅까지 두 줄로 보여준다. */
export function formatToolCall({ name, input, executor }: ToolCallInfo): string {
  const call = `[tool_call] ${name} ${JSON.stringify(input)}`;
  // 레지스트리에 없는 도구는 executor가 undefined다 — 그 경우 라우팅 자체가 없다.
  return executor ? `${call}\n[dispatch] ${name} → ${executor}` : call;
}

/** content는 이미 실행 결과 객체의 JSON 문자열이다 — 다시 감싸면 이중 인코딩된다. */
export function formatToolResult({ content }: ToolResultInfo): string {
  return `[tool_result] ${content}`;
}

export function formatDone(ok: boolean, summary?: string): string {
  return `[done ok=${ok}${summary ? ` ${summary}` : ""}]`;
}

/**
 * 사람이 읽는 로그용 콜백 묶음을 만든다.
 *
 * onDone에서 종료 코드를 건드리지 않는다 — 종료 코드 정책은 모드마다 다르므로
 * (단발은 실패 시 1, REPL/--seq는 0) 호출부가 결정한다.
 */
export function createLogCallbacks({ out, streamText, printDone }: LogOptions): RunCallbacks {
  return {
    onTextChunk(text) {
      // 버퍼링 없이 즉시 출력해야 글자가 실시간으로 흘러나온다.
      if (streamText) out.write(text);
    },
    onToolCallStart(call) {
      // 앞의 텍스트 스트림이 개행 없이 끝나므로 \n으로 줄을 띄운다.
      out.write(`${streamText ? "\n" : ""}${formatToolCall(call)}\n`);
    },
    onToolResult(result) {
      out.write(`${formatToolResult(result)}\n`);
    },
    onDone(ok, summary) {
      if (printDone) out.write(`\n${formatDone(ok, summary)}\n`);
    },
  };
}
