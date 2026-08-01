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
    const task = JSON.stringify(context.params.prompt);
    if (task.includes("CRASH")) {
      process.stderr.write("intentional mock ACP crash\n");
      process.exit(23);
      return new Promise(() => undefined);
    }
    if (task.includes("WAIT")) {
      await new Promise((resolve) => { session.release = resolve; });
      if (session.cancelled) return { stopReason: "cancelled" };
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
