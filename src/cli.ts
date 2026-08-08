/**
 * 테스트용 진입점.
 *
 *   npx tsx src/cli.ts "질문 내용"
 *
 * 인자가 없으면 기본 명령을 사용한다.
 */
import { createClient } from "./client.js";
import { mockPetApp, mockWorkspace } from "./mock-executors.js";
import type { RunCallbacks } from "./types.js";

const DEFAULT_COMMAND = "안녕, 자기소개 해줘";
const DEFAULT_MODEL = "claude-sonnet-4-6";

async function main(): Promise<void> {
  const apiKey = process.env["ANTHROPIC_API_KEY"];
  if (!apiKey) {
    console.error("ANTHROPIC_API_KEY 환경변수가 설정되어 있지 않습니다.");
    process.exitCode = 1;
    return;
  }

  const model = process.env["ANTHROPIC_MODEL"] ?? DEFAULT_MODEL;
  const command = process.argv.slice(2).join(" ").trim() || DEFAULT_COMMAND;

  // Ctrl+C로 스트리밍 중간 중단 (AbortSignal 경로 확인용)
  const controller = new AbortController();
  const onSigint = () => controller.abort();
  process.on("SIGINT", onSigint);

  const callbacks: RunCallbacks = {
    onTextChunk(text) {
      // 버퍼링 없이 즉시 출력해야 글자가 실시간으로 흘러나온다.
      process.stdout.write(text);
    },
    onToolCallStart({ name, input, executor }) {
      // 앞의 텍스트 스트림이 개행 없이 끝나므로 \n으로 줄을 띄운다.
      console.log(`\n[tool_call] ${name} ${JSON.stringify(input)}`);
      // 레지스트리에 없는 도구는 executor가 undefined다 — 그 경우 라우팅 자체가 없다.
      if (executor) console.log(`[dispatch] ${name} → ${executor}`);
    },
    onToolResult({ content }) {
      // content는 이미 실행 결과 객체의 JSON 문자열이다 — 다시 감싸면 이중 인코딩된다.
      console.log(`[tool_result] ${content}`);
    },
    onDone(ok, summary) {
      process.stdout.write(`\n[done ok=${ok}${summary ? ` ${summary}` : ""}]\n`);
      if (!ok) process.exitCode = 1;
    },
  };

  // 실제 실행기(pet-app 소켓 프록시 / workspace 인프로세스 실행기) 자리에
  // mock을 주입한다. 디스패치 경로는 실제와 동일하다.
  const client = createClient({
    apiKey,
    model,
    executors: { "pet-app": mockPetApp, workspace: mockWorkspace },
  });
  await client.run(command, callbacks, controller.signal);

  process.off("SIGINT", onSigint);
}

main();
