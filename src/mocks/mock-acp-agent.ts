import { EventEmitter } from "node:events";

export class MockAcpAgent extends EventEmitter {
  async prompt(task: string): Promise<{ summary: string; changedFiles: string[] }> {
    this.emit("update", { type: "agent_message", text: `Mock ACP: ${task}` });
    return { summary: "Mock ACP 작업 완료", changedFiles: [] };
  }
}
