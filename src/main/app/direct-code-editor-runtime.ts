import { randomUUID } from "node:crypto";

import type { AgentCallbacks, Attachment, Context, ToolExecutor } from "@speaki-e/protocol";

import type { AgentRuntime } from "../../shared/ports.js";

/**
 * user_input 하나를 code_editor 한 번으로 곧장 실행하는 AgentRuntime.
 *
 * 왜 필요한가: pet-app의 에이전트(F15, 현재 OpenAI)가 "이건 코딩 작업이다"라고
 * 판단하고 지시문까지 작성해서 code_editor 위임으로 넘겨준다. 그 뒤에서 ai-module
 * (Anthropic 전용)이 같은 판단을 한 번 더 하는 것은 중복인 데다, Anthropic API 키를
 * 요구해서 키가 OpenAI뿐인 환경에서는 편집 자체가 불가능해진다. 실제 편집을 수행하는
 * ACP(Claude Code)는 ANTHROPIC_API_KEY가 없으면 자기 로그인 인증을 쓰므로
 * (acp-adapter.ts) 가운데 층만 걷어내면 키 없이도 편집이 돌아간다.
 *
 * 계약은 그대로다: AgentRuntime 포트를 그대로 구현하고, 이벤트도 ai-module 경로와
 * 같은 콜백으로만 낸다. 소켓 메시지도 도구 레지스트리도 건드리지 않는다.
 *
 * ponytail: 도구가 code_editor 하나로 고정이라 일상 대화나 pet-app 도구 호출은
 * 처리하지 못한다 -- 이 런타임은 "pet-app 두뇌가 이미 코딩 작업으로 분류해서 보낸
 * 요청"만 받는다는 전제로 켜는 플래그(--direct-code-editor)다. 두뇌를 workspace로
 * 옮기기로 결정되면 이 파일이 아니라 플래그가 사라진다.
 */
export class DirectCodeEditorRuntime implements AgentRuntime {
  constructor(private readonly editorLocalFor: (sessionId: string) => ToolExecutor) {}

  async run(
    command: string,
    sessionId: string,
    _context: Context,
    callbacks: AgentCallbacks,
    _attachments?: Attachment[],
    signal?: AbortSignal,
  ): Promise<void> {
    const id = randomUUID();
    // project_path는 넘기지 않는다: editorLocal이 세션 workspace의 실제 경로로
    // 강제하고 인자로 온 값은 무시한다(tool-executors.ts의 보안 기준).
    callbacks.onToolCallStart(id, "code_editor", { task: command });

    const result = await this.editorLocalFor(sessionId).execute("code_editor", { task: command }, signal);
    callbacks.onToolResult(id, result.ok, result.data, result.error, result.detail);
    callbacks.onDone(result.ok, summaryOf(result.ok, result.data, result.detail));
  }
}

/**
 * agent_done의 summary는 사용자와 pet-app 두뇌가 함께 읽는 유일한 결과 문자열이라,
 * 실패했을 때 빈 문자열로 두면 "왜 안 됐는지"가 어디에도 남지 않는다.
 */
function summaryOf(ok: boolean, data: unknown, detail?: string): string {
  if (!ok) return detail ?? "코드 편집에 실패했습니다";
  const summary = (data as { summary?: unknown } | undefined)?.summary;
  return typeof summary === "string" && summary.length > 0 ? summary : "코드 편집을 마쳤습니다";
}
