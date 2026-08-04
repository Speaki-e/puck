import type { ToolExecutor } from "@speaki-e/protocol";
import type { AgentRuntime } from "../shared/ports.js";

export interface MockAgentRuntimeOptions {
  petAppProxy?: ToolExecutor;
  editorLocal?: ToolExecutor;
}

/**
 * 실제 ai-module 태그가 아직 없는 동안(W0) AgentCallbacks 전 구간과 두 ToolExecutor를 실제
 * 인터페이스대로 왕복시키기 위한 목(mock)이다 -- SessionRouter/RunRegistry/승인 브리지를
 * ai-module 없이도 통합 테스트할 수 있게 한다. 스크립트 문법:
 *   "tool:pet-app:<tool> [<json args>]" -- petAppProxy.execute 왕복
 *   "tool:workspace:<tool> [<json args>]" -- editorLocal.execute 왕복
 *   "approve:<summary>" -- onApprovalRequired 왕복
 *   "open_task_session:<title>" -- onSessionCreated 왕복
 *   그 외 -- onTextChunk 후 onDone(true)
 */
export class MockAgentRuntime implements AgentRuntime {
  constructor(private readonly options: MockAgentRuntimeOptions = {}) {}

  async run(
    command: Parameters<AgentRuntime["run"]>[0],
    _sessionId: string,
    _context: Parameters<AgentRuntime["run"]>[2],
    callbacks: Parameters<AgentRuntime["run"]>[3],
    _attachments?: Parameters<AgentRuntime["run"]>[4],
    signal?: AbortSignal,
  ): Promise<void> {
    callbacks.onTextChunk(`Mock 실행: ${command}`);

    const approvalMatch = /^approve:(.+)$/.exec(command);
    if (approvalMatch) {
      const approved = await new Promise<boolean>((resolve) => callbacks.onApprovalRequired(approvalMatch[1]!, resolve));
      callbacks.onDone(approved, approved ? "승인됨" : "거부됨");
      return;
    }

    const sessionMatch = /^open_task_session:(.+)$/.exec(command);
    if (sessionMatch) {
      callbacks.onSessionCreated(`mock-session-${sessionMatch[1]}`, sessionMatch[1]!);
      callbacks.onDone(true, "새 세션을 열었습니다");
      return;
    }

    const toolMatch = /^tool:(pet-app|workspace):(\S+)(?:\s+(.*))?$/.exec(command);
    if (toolMatch) {
      const [, executorKind, tool, rawArgs] = toolMatch;
      const executor = executorKind === "pet-app" ? this.options.petAppProxy : this.options.editorLocal;
      const id = "mock-tool-1";
      const args = rawArgs ? JSON.parse(rawArgs) : {};
      callbacks.onToolCallStart(id, tool!, args);
      if (!executor) {
        callbacks.onToolResult(id, false, undefined, "execution_failed", "executor가 주입되지 않았습니다");
        callbacks.onDone(false, "실행기 없음");
        return;
      }
      const result = await executor.execute(tool!, args, signal);
      callbacks.onToolResult(id, result.ok, result.data, result.error, result.detail);
      callbacks.onDone(result.ok, result.ok ? "Mock 작업 완료" : "Mock 작업 실패");
      return;
    }

    callbacks.onDone(true, "Mock 작업 완료");
  }
}
