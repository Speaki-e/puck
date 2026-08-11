/**
 * ai-module A6 — CLI 승인 UI.
 *
 * 기본값은 거부다. 엔터만 치거나(빈 입력), 입력이 끊기거나(파이프 EOF, Ctrl+D),
 * run이 중단되면 전부 거부로 처리한다 — 승인은 명시적으로 y를 눌렀을 때만.
 */
import * as readline from "node:readline";

export interface AskOptions {
  /** REPL처럼 이미 열려 있는 readline. 없으면 이 함수가 임시로 하나 만든다. */
  rl?: readline.Interface;
  /** 프롬프트를 쓸 스트림. */
  out: NodeJS.WritableStream;
  /** 진행 중인 run의 중단 신호. abort되면 질문을 접고 거부한다. */
  signal?: AbortSignal;
}

/**
 * 승인 여부를 물어보고 resolve로 답한다.
 *
 * client.ts의 requestApproval이 resolve 중복 호출을 흡수하므로, 여기서도
 * 여러 경로(응답/중단/EOF)에서 안전하게 부를 수 있다.
 */
export function askApproval(
  summary: string,
  resolve: (approved: boolean) => void,
  { rl, out, signal }: AskOptions,
): void {
  // 단발 모드에는 열려 있는 readline이 없다. 그 경우만 만들고, 답을 받으면 닫는다.
  const owned = rl === undefined;
  const reader =
    rl ?? readline.createInterface({ input: process.stdin, output: out as NodeJS.WritableStream });

  let settled = false;
  const finish = (approved: boolean): void => {
    if (settled) return;
    settled = true;
    signal?.removeEventListener("abort", onAbort);
    reader.off("close", onClose);
    if (owned) reader.close();
    resolve(approved);
  };
  const onAbort = (): void => finish(false);
  const onClose = (): void => finish(false);

  signal?.addEventListener("abort", onAbort, { once: true });
  reader.once("close", onClose);

  // 앞의 텍스트 스트림이 개행 없이 끝나므로 줄을 띄우고 시작한다.
  out.write(`\n⚠️  승인 필요: ${summary}\n`);

  try {
    reader.question("허용하시겠습니까? [y/N]: ", (answer) => finish(isYes(answer)));
  } catch {
    // 이미 닫힌 readline 등 — 물어볼 수 없으면 거부.
    finish(false);
  }
}

/** y / yes만 승인. 그 외(엔터 포함)는 전부 거부. */
function isYes(answer: string): boolean {
  const normalized = answer.trim().toLowerCase();
  return normalized === "y" || normalized === "yes";
}
