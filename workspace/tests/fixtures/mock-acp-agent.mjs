import { writeFile } from "node:fs/promises";
import { Readable, Writable } from "node:stream";
import * as acp from "@agentclientprotocol/sdk";

const sessions = new Map();
const stream = acp.ndJsonStream(Writable.toWeb(process.stdout), Readable.toWeb(process.stdin));

acp.agent({ name: "workspace-mock-agent" })
  .onRequest(acp.methods.agent.initialize, () => ({
    protocolVersion: acp.PROTOCOL_VERSION,
    agentCapabilities: { loadSession: false },
  }))
  .onRequest(acp.methods.agent.session.new, (context) => {
    const sessionId = crypto.randomUUID();
    sessions.set(sessionId, { cwd: context.params.cwd, cancelled: false });
    return { sessionId };
  })
  .onRequest(acp.methods.agent.session.prompt, async (context) => {
    const session = sessions.get(context.params.sessionId);
    if (!session) throw new Error("unknown session");
    // context.params.prompt는 클라이언트가 session.prompt(문자열)로 보낸 걸 SDK가
    // [{type:"text", text: 문자열}]로 감싼 것 -- 원문 그대로 꺼내 쓴다(JSON.stringify는
    // 경로에 백슬래시가 섞이면 이스케이프되어 ESCAPE: 뒤의 경로를 그대로 못 씀).
    const promptText = context.params.prompt.map((block) => (block.type === "text" ? block.text : "")).join("");
    if (promptText.includes("CRASH")) {
      process.stderr.write("intentional mock ACP crash\n");
      process.exit(23);
      return new Promise(() => undefined);
    }
    if (promptText.includes("WAIT")) {
      await new Promise((resolve) => { session.release = resolve; });
      if (session.cancelled) return { stopReason: "cancelled" };
    }
    // 워크스페이스 경계 밖 접근 시뮬레이션(공통 W5 "ACP가 사용할 수 있는 경로가 WorkspaceRegistry
    // 경로와 일치하는지 통합 검증"): 진짜 ACP가 오작동하거나 악의적으로 session.cwd 밖 절대경로에
    // 쓰려고 하면 어떻게 되는지 확인하기 위한 훅. AcpAdapter는 spawn에 cwd만 지정할 뿐 OS 수준
    // 샌드박싱은 하지 않으므로, 이 파일 쓰기 자체는 실제로 성공한다 -- changedFiles 집계가
    // projectPath 밖 경로를 걸러내는지가 실제 검증 대상이다.
    if (promptText.startsWith("ESCAPE:")) {
      const target = promptText.slice("ESCAPE:".length);
      await writeFile(target, "escaped write from mock acp\n", "utf8");
      await context.client.notify(acp.methods.client.session.update, {
        sessionId: context.params.sessionId,
        update: {
          sessionUpdate: "agent_message_chunk",
          content: { type: "text", text: "Mock ACP 경계 이탈 시도 완료" },
        },
      });
      return { stopReason: session.cancelled ? "cancelled" : "end_turn" };
    }
    await writeFile(`${session.cwd}/mock-change.txt`, "changed by mock acp\n", "utf8");
    await context.client.notify(acp.methods.client.session.update, {
      sessionId: context.params.sessionId,
      update: {
        sessionUpdate: "agent_message_chunk",
        content: { type: "text", text: "Mock ACP 작업 완료" },
      },
    });
    return { stopReason: session.cancelled ? "cancelled" : "end_turn" };
  })
  .onNotification(acp.methods.agent.session.cancel, (context) => {
    const session = sessions.get(context.params.sessionId);
    if (session) {
      session.cancelled = true;
      session.release?.();
    }
  })
  .connect(stream);
