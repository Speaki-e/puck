/**
 * ai-module A3/A5 — CLI 테스트 진입점.
 *
 *   npm run cli "명령"                        단발 실행 (텍스트 스트리밍 + 도구 로그)
 *   npm run cli                               대화형 REPL (세션/컨텍스트 지원)
 *   npm run cli --seq "명령"                  시퀀스 JSON 한 줄만 stdout에 출력
 *   npm run cli --seq --session=t1 "명령"     세션을 지정해서 시퀀스 출력
 *   npm run cli --seq --approve=all "명령"    승인 요청을 전부 허용 (기본: none)
 *
 * 종료 코드: 단발 모드만 실행 실패 시 1. REPL/--seq는 0(설정 오류 제외).
 * 자세한 규약은 README "6. CLI 사용법" 참고.
 */
import { createClient } from "./client.js";
import { mockPetApp, mockWorkspace } from "./mock-executors.js";
import { DEFAULT_SESSION_ID } from "./session-store.js";
import { runOnce } from "./cli/once.js";
import { runRepl } from "./cli/repl.js";
import { runSeq, type ApprovePolicy } from "./cli/seq.js";

const DEFAULT_MODEL = "claude-sonnet-4-6";

type Mode = "once" | "repl" | "seq";

interface ParsedArgs {
  mode: Mode;
  command: string;
  sessionId: string;
  approve: ApprovePolicy;
}

async function main(): Promise<void> {
  const apiKey = process.env["ANTHROPIC_API_KEY"];
  if (!apiKey) {
    console.error("ANTHROPIC_API_KEY 환경변수가 설정되어 있지 않습니다.");
    process.exitCode = 1;
    return;
  }

  const { mode, command, sessionId, approve } = parseArgs(process.argv.slice(2));

  if (mode === "seq" && command === "") {
    // --seq는 검증할 명령이 있어야 의미가 있다. 빈 JSON을 흘려보내면
    // 회귀 스크립트가 통과한 것으로 오해한다.
    console.error('사용법: npm run cli --seq [--session=<id>] [--approve=all|none] "명령"');
    process.exitCode = 1;
    return;
  }

  const model = process.env["ANTHROPIC_MODEL"] ?? DEFAULT_MODEL;

  // 실제 실행기(pet-app 소켓 프록시 / workspace 인프로세스 실행기) 자리에
  // mock을 주입한다. 디스패치 경로는 실제와 동일하다.
  const client = createClient({
    apiKey,
    model,
    baseURL: process.env["ANTHROPIC_BASE_URL"],
    executors: { "pet-app": mockPetApp, workspace: mockWorkspace },
  });

  switch (mode) {
    case "seq":
      process.exitCode = await runSeq(client, command, sessionId, approve);
      return;
    case "repl":
      process.exitCode = await runRepl(client);
      return;
    case "once":
      process.exitCode = await runOnce(client, command);
      return;
  }
}

/**
 * 인자를 모드와 명령으로 가른다.
 *
 * `npm run cli --seq "명령"`에서 npm은 `--seq`를 자신의 config 플래그로
 * 삼켜 스크립트까지 전달하지 않고 npm_config_seq=true만 남긴다(--session도
 * 마찬가지로 npm_config_session에 실린다). 그래서 두 경로를 모두 본다 —
 * 직접 실행(`npx tsx src/cli.ts --seq "명령"`)과 npm 경유 실행이 같게
 * 동작해야 한다.
 */
function parseArgs(argv: string[]): ParsedArgs {
  const seq = argv.includes("--seq") || process.env["npm_config_seq"] === "true";

  const sessionId =
    optionValue(argv, "--session") ?? process.env["npm_config_session"] ?? DEFAULT_SESSION_ID;

  // 오타(--approve=yes 등)는 조용히 all로 넘어가면 안 된다 — all일 때만 all.
  const approveRaw = optionValue(argv, "--approve") ?? process.env["npm_config_approve"];
  const approve: ApprovePolicy = approveRaw === "all" ? "all" : "none";

  const command = argv
    .filter((arg) => arg !== "--seq" && !isOption(arg, "--session") && !isOption(arg, "--approve"))
    .join(" ")
    .trim();

  if (seq) return { mode: "seq", command, sessionId, approve };
  // 명령 없이 실행하면 REPL. (A2까지는 기본 명령을 대신 실행했다.)
  return { mode: command === "" ? "repl" : "once", command, sessionId, approve };
}

/** `--name=value` 형태에서 값만 꺼낸다. 없거나 비어 있으면 undefined. */
function optionValue(argv: string[], name: string): string | undefined {
  const found = argv.find((arg) => isOption(arg, name));
  const value = found?.slice(`${name}=`.length);
  return value === undefined || value === "" ? undefined : value;
}

function isOption(arg: string, name: string): boolean {
  return arg.startsWith(`${name}=`);
}

main().catch((err: unknown) => {
  // createClient는 prompts/system.md를 못 읽으면 던진다. 스택 대신 한 줄로 보고한다.
  console.error(err instanceof Error ? err.message : String(err));
  process.exitCode = 1;
});
