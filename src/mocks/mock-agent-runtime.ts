import type { AgentRuntime } from "../shared/ports.js";

export class MockAgentRuntime implements AgentRuntime {
  async run(command: Parameters<AgentRuntime["run"]>[0], _sessionId: string, _context: Parameters<AgentRuntime["run"]>[2], callbacks: Parameters<AgentRuntime["run"]>[3]): Promise<void> {
    callbacks.onTextChunk(`Mock 실행: ${command}`);
    callbacks.onDone(true, "Mock 작업 완료");
  }
}
