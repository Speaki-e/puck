/**
 * 모드 2 — 대화형 REPL. 인자 없이 `npm run cli`.
 *
 * A5 전까지는 대화 히스토리가 없으므로 각 입력은 서로 독립된 run이다.
 * (같은 세션의 연속 대화처럼 보이지만 모델은 이전 턴을 기억하지 못한다.)
 *
 * Node 내장 readline만 사용한다 — 외부 패키지 금지.
 */
import * as readline from "node:readline";

import { allTools } from "../tools.js";
import type { AiClient } from "../types.js";
import { createLogCallbacks } from "./log.js";

const PROMPT = "ai-module> ";

/** 스트림 주입은 테스트용이다. 실제 실행에서는 기본값(process.stdin/stdout)을 쓴다. */
export interface ReplIo {
  input?: NodeJS.ReadableStream;
  output?: NodeJS.WritableStream;
  terminal?: boolean;
}

export async function runRepl(client: AiClient, io: ReplIo = {}): Promise<number> {
  const input = io.input ?? process.stdin;
  const output = io.output ?? process.stdout;
  const rl = readline.createInterface({
    input,
    output,
    prompt: PROMPT,
    // 파이프로 입력을 넣으면 TTY가 아니다. 그 경우 terminal:false로 두어야
    // 에코가 중복되지 않는다.
    terminal: io.terminal ?? (output as NodeJS.WriteStream).isTTY === true,
  });

  const log = createLogCallbacks({ out: output, streamText: true, printDone: true });

  // 진행 중인 run이 있을 때만 값이 있다. Ctrl+C가 "run 중단"인지 "REPL 종료"인지
  // 가르는 유일한 기준이다.
  let running: AbortController | undefined;

  // 파이프 입력은 줄을 다 흘려보낸 직후 EOF로 닫힌다 — 그 뒤에 prompt()를
  // 부르면 ERR_USE_AFTER_CLOSE다. 닫힌 뒤에도 버퍼에 남은 줄은 계속 처리한다.
  let closed = false;
  rl.on("close", () => {
    closed = true;
  });
  const prompt = (): void => {
    if (!closed) rl.prompt();
  };

  const interrupt = (): void => {
    if (running !== undefined) {
      // 진행 중인 run만 중단하고 REPL은 살려둔다. 중단 결과는 onDone이 찍는다.
      running.abort();
      return;
    }
    rl.close();
  };

  // raw 모드 TTY에서는 ^C가 OS 시그널이 되지 않고 readline의 SIGINT 이벤트로만
  // 온다. 반대로 파이프 입력에서는 프로세스 시그널로 온다. 둘 다 붙여야 어느
  // 실행 형태에서든 같은 동작이 된다.
  rl.on("SIGINT", interrupt);
  process.on("SIGINT", interrupt);

  output.write(`ai-module CLI (REPL). /help 로 명령 목록, /exit 로 종료.\n`);
  prompt();

  for await (const line of rl) {
    const entry = line.trim();

    if (entry === "") {
      prompt();
      continue;
    }

    if (entry.startsWith("/")) {
      if (handleSpecial(entry, output) === "exit") {
        rl.close();
        break;
      }
      prompt();
      continue;
    }

    running = new AbortController();
    // run 중에 입력된 줄은 readline이 큐에 쌓아 두었다가 다음 반복에서 처리한다.
    await client.run(entry, log, running.signal);
    running = undefined;

    prompt();
  }

  process.off("SIGINT", interrupt);
  output.write("\n");
  return 0;
}

/** 특수 명령 처리. 종료해야 하면 "exit"를 반환한다. */
function handleSpecial(entry: string, out: NodeJS.WritableStream): "exit" | "continue" {
  // 인자는 아직 받지 않는다 — 첫 토큰만 본다.
  const [command] = entry.split(/\s+/);

  switch (command) {
    case "/exit":
      return "exit";
    case "/tools":
      out.write(`${renderToolTable()}\n`);
      return "continue";
    case "/help":
      out.write(`${renderHelp()}\n`);
      return "continue";
    default:
      out.write(`알 수 없는 명령: ${command} (/help 참고)\n`);
      return "continue";
  }
}

/**
 * protocol 레지스트리를 표로 출력한다. API를 호출하지 않는 로컬 조회다 —
 * "모델이 무엇을 볼 수 있는가"가 아니라 "레지스트리에 무엇이 있는가"를 본다.
 */
function renderToolTable(): string {
  const rows = allTools().map((def) => ({
    name: def.name,
    executor: def.executor,
    approval: def.approval.kind,
    timeout: `${def.timeoutSec}s`,
  }));

  const header = { name: "NAME", executor: "EXECUTOR", approval: "APPROVAL", timeout: "TIMEOUT" };
  const width = (key: keyof typeof header): number =>
    Math.max(header[key].length, ...rows.map((row) => row[key].length));

  const line = (row: typeof header): string =>
    [
      row.name.padEnd(width("name")),
      row.executor.padEnd(width("executor")),
      row.approval.padEnd(width("approval")),
      // 마지막 열은 오른쪽 공백을 남기지 않는다.
      row.timeout,
    ].join("  ");

  return [
    line(header),
    "-".repeat(width("name") + width("executor") + width("approval") + width("timeout") + 6),
    ...rows.map(line),
    `총 ${rows.length}개 (protocol TOOL_REGISTRY)`,
  ].join("\n");
}

function renderHelp(): string {
  return [
    "/tools  protocol 도구 레지스트리를 표로 출력 (API 호출 없음)",
    "/help   이 도움말",
    "/exit   종료 (프롬프트에서 Ctrl+C도 동일)",
    "",
    "그 외 입력은 모델에 명령으로 전달된다. 실행 중 Ctrl+C는 그 run만 중단한다.",
  ].join("\n");
}
