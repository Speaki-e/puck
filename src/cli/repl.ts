/**
 * 모드 2 — 대화형 REPL. 인자 없이 `npm run cli`.
 *
 * A5부터 세션별 히스토리가 붙는다: 같은 세션에서 이어 말하면 앞의 대화를
 * 기억하고, /session으로 세션을 바꾸면 그쪽 히스토리로 갈아탄다.
 *
 * Node 내장 readline만 사용한다 — 외부 패키지 금지.
 */
import * as readline from "node:readline";

import { DEFAULT_SESSION_ID } from "../session-store.js";
import { allTools } from "../tools.js";
import type { AiClient, Context } from "../types.js";
import { askApproval } from "./approve.js";
import { createLogCallbacks } from "./log.js";

/** 스트림 주입은 테스트용이다. 실제 실행에서는 기본값(process.stdin/stdout)을 쓴다. */
export interface ReplIo {
  input?: NodeJS.ReadableStream;
  output?: NodeJS.WritableStream;
  terminal?: boolean;
}

/** /ctx로 설정할 수 있는 필드. WindowInfo 배열인 openWindows는 key=value로 표현할 수 없어 제외. */
const CTX_STRING_KEYS = ["frontmostApp", "projectPath"] as const;
const CTX_LIST_KEYS = ["editorOpenFiles", "recentActions"] as const;

export async function runRepl(client: AiClient, io: ReplIo = {}): Promise<number> {
  const input = io.input ?? process.stdin;
  const output = io.output ?? process.stdout;
  const rl = readline.createInterface({
    input,
    output,
    // 파이프로 입력을 넣으면 TTY가 아니다. 그 경우 terminal:false로 두어야
    // 에코가 중복되지 않는다.
    terminal: io.terminal ?? (output as NodeJS.WriteStream).isTTY === true,
  });

  // REPL이 들고 있는 상태. 세션은 /session이나 onSessionCreated로 바뀐다.
  let sessionId = DEFAULT_SESSION_ID;
  let context: Context = {};

  const setPrompt = (): void => rl.setPrompt(`ai-module[${sessionId}]> `);
  setPrompt();

  // 진행 중인 run이 있을 때만 값이 있다. Ctrl+C가 "run 중단"인지 "REPL 종료"인지
  // 가르는 기준이자, 승인 대기를 함께 풀어주는 신호다.
  let running: AbortController | undefined;

  const log = createLogCallbacks({ out: output, streamText: true, printDone: true });
  const callbacks = {
    ...log,
    onApprovalRequired(summary: string, resolve: (approved: boolean) => void) {
      // 이미 열려 있는 REPL readline을 재사용한다. question은 그 줄을 가로채므로
      // 답변이 다음 명령으로 흘러들어가지 않는다.
      askApproval(summary, resolve, { rl, out: output, signal: running?.signal });
    },
    onSessionCreated(created: string, title: string) {
      // pet-app 사이드바가 새 세션으로 전환되는 동작을 CLI에서 흉내 낸다.
      output.write(`\n[새 세션 생성: ${created} (${title})] — 이후 명령은 이 세션에서 진행됩니다.\n`);
      sessionId = created;
      setPrompt();
    },
  };

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
      const result = handleSpecial(entry, output, { sessionId, context });
      if (result.exit) {
        rl.close();
        break;
      }
      if (result.sessionId !== undefined && result.sessionId !== sessionId) {
        sessionId = result.sessionId;
        setPrompt();
      }
      if (result.context !== undefined) context = result.context;
      prompt();
      continue;
    }

    running = new AbortController();
    // run 중에 입력된 줄은 readline이 큐에 쌓아 두었다가 다음 반복에서 처리한다.
    await client.run(entry, sessionId, context, callbacks, undefined, running.signal);
    running = undefined;

    prompt();
  }

  process.off("SIGINT", interrupt);
  output.write("\n");
  return 0;
}

interface ReplState {
  sessionId: string;
  context: Context;
}

interface SpecialResult {
  exit?: boolean;
  /** 세션 전환이 일어났으면 새 id. */
  sessionId?: string;
  /** 컨텍스트가 바뀌었으면 새 값. */
  context?: Context;
}

/** 특수 명령 처리. */
function handleSpecial(entry: string, out: NodeJS.WritableStream, state: ReplState): SpecialResult {
  const [command, ...args] = entry.split(/\s+/);

  switch (command) {
    case "/exit":
      return { exit: true };
    case "/tools":
      out.write(`${renderToolTable()}\n`);
      return {};
    case "/session":
      return handleSession(args, out, state);
    case "/ctx":
      return handleCtx(args, out, state);
    case "/help":
      out.write(`${renderHelp()}\n`);
      return {};
    default:
      out.write(`알 수 없는 명령: ${command} (/help 참고)\n`);
      return {};
  }
}

/**
 * /session          현재 세션과 목록 표시
 * /session <id>     세션 전환 (없으면 그 이름으로 새로 만들어진다)
 *
 * 세션 목록은 클라이언트가 들고 있으므로 CLI는 자기가 거쳐 간 세션만 안다.
 * 목록을 정확히 보여주려면 클라이언트가 세션 목록을 노출해야 한다(A7 통합 시).
 */
function handleSession(
  args: string[],
  out: NodeJS.WritableStream,
  state: ReplState,
): SpecialResult {
  const target = args[0];
  if (target === undefined) {
    out.write(`현재 세션: ${state.sessionId}\n`);
    out.write("세션 전환: /session <id> (없는 id를 주면 그 이름으로 새 대화가 시작된다)\n");
    return {};
  }
  out.write(`세션 전환: ${state.sessionId} → ${target}\n`);
  return { sessionId: target };
}

/**
 * /ctx                                       현재 컨텍스트 표시
 * /ctx frontmostApp=Safari projectPath=/tmp  값 설정 (기존 값에 덮어쓰기)
 * /ctx clear                                 초기화
 *
 * 목록형(editorOpenFiles, recentActions)은 쉼표로 구분한다.
 * openWindows는 WindowInfo 객체 배열이라 key=value로 표현할 수 없어 지원하지 않는다.
 */
function handleCtx(args: string[], out: NodeJS.WritableStream, state: ReplState): SpecialResult {
  if (args.length === 0) {
    out.write(`${renderContext(state.context)}\n`);
    return {};
  }
  if (args[0] === "clear") {
    out.write("컨텍스트를 비웠습니다.\n");
    return { context: {} };
  }

  const next: Context = { ...state.context };
  for (const arg of args) {
    const index = arg.indexOf("=");
    if (index <= 0) {
      out.write(`형식이 아닙니다(key=value): ${arg}\n`);
      continue;
    }
    const key = arg.slice(0, index);
    const value = arg.slice(index + 1);

    if (isStringKey(key)) {
      next[key] = value;
    } else if (isListKey(key)) {
      next[key] = value.split(",").map((item) => item.trim()).filter((item) => item !== "");
    } else {
      out.write(`설정할 수 없는 키: ${key} (가능: ${settableKeys()})\n`);
      continue;
    }
    out.write(`${key} = ${value}\n`);
  }
  return { context: next };
}

function isStringKey(key: string): key is (typeof CTX_STRING_KEYS)[number] {
  return (CTX_STRING_KEYS as readonly string[]).includes(key);
}

function isListKey(key: string): key is (typeof CTX_LIST_KEYS)[number] {
  return (CTX_LIST_KEYS as readonly string[]).includes(key);
}

function settableKeys(): string {
  return [...CTX_STRING_KEYS, ...CTX_LIST_KEYS].join(", ");
}

function renderContext(context: Context): string {
  const entries = Object.entries(context).filter(([, value]) =>
    Array.isArray(value) ? value.length > 0 : value !== undefined,
  );
  if (entries.length === 0) return "컨텍스트 없음 (/ctx key=value 로 설정)";
  return entries
    .map(([key, value]) => `${key} = ${Array.isArray(value) ? value.join(", ") : String(value)}`)
    .join("\n");
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
    "/tools          protocol 도구 레지스트리를 표로 출력 (API 호출 없음)",
    "/session        현재 세션 표시",
    "/session <id>   세션 전환 (없는 id면 새 대화가 시작된다)",
    "/ctx            현재 컨텍스트 표시",
    "/ctx k=v ...    컨텍스트 설정 (frontmostApp, projectPath, editorOpenFiles, recentActions)",
    "/ctx clear      컨텍스트 초기화",
    "/help           이 도움말",
    "/exit           종료 (프롬프트에서 Ctrl+C도 동일)",
    "",
    "그 외 입력은 모델에 명령으로 전달된다. 실행 중 Ctrl+C는 그 run만 중단한다.",
    "같은 세션에서는 이전 대화를 기억한다. 세션이 다르면 히스토리도 완전히 분리된다.",
  ].join("\n");
}
