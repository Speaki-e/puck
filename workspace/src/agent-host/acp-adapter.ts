import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { readdir, stat } from "node:fs/promises";
import path from "node:path";
import { Readable, Writable } from "node:stream";
import chokidar, { type FSWatcher } from "chokidar";
import * as acp from "@agentclientprotocol/sdk";
import { resolveAgentCommand, type CodingAgentKind } from "../shared/acp-command.js";

export interface CodeEditorResult {
  ok: boolean;
  summary: string;
  changedFiles: string[];
  tests?: Array<{ command: string; ok: boolean; output?: string }>;
  error?: string;
  detail?: string;
}

export interface AcpRunInput {
  requestId: string;
  workspaceId: string;
  task: string;
  projectPath: string;
  signal: AbortSignal;
}

export type AcpUpdateHandler = (update: acp.SessionUpdate) => void;
export type PermissionResolver = (
  request: acp.RequestPermissionRequest,
) => Promise<acp.RequestPermissionResponse>;

export interface AcpAdapterOptions {
  command?: string;
  args?: string[];
  env?: NodeJS.ProcessEnv;
  agentKind?: CodingAgentKind;
  onUpdate?: AcpUpdateHandler;
  resolvePermission?: PermissionResolver;
  spawnProcess?: (command: string, args: string[], options: Parameters<typeof spawn>[2]) => ChildProcessWithoutNullStreams;
}

function agentCommand(kind: CodingAgentKind): { command: string; args: string[] } {
  const appPath = process.env.WORKSPACE_APP_PATH ?? process.cwd();
  return resolveAgentCommand(kind, appPath);
}

function permissionDenied(): acp.RequestPermissionResponse {
  return { outcome: { outcome: "cancelled" } };
}

function textFromUpdate(update: acp.SessionUpdate): string {
  if (update.sessionUpdate !== "agent_message_chunk") return "";
  return update.content.type === "text" ? update.content.text : "";
}

function relativeProjectPath(projectPath: string, changedPath: string): string | undefined {
  const relative = path.relative(projectPath, changedPath);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) return undefined;
  return relative.split(path.sep).join("/");
}

async function projectSnapshot(root: string): Promise<Map<string, string>> {
  const snapshot = new Map<string, string>();
  const visit = async (directory: string): Promise<void> => {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      if (entry.name === ".git" || entry.name === "node_modules") continue;
      const absolute = path.join(directory, entry.name);
      if (entry.isDirectory()) await visit(absolute);
      else if (entry.isFile()) {
        const info = await stat(absolute);
        snapshot.set(path.relative(root, absolute).split(path.sep).join("/"), `${info.size}:${info.mtimeMs}`);
      }
    }
  };
  await visit(root);
  return snapshot;
}

async function addSnapshotChanges(root: string, before: Map<string, string>, changed: Set<string>): Promise<void> {
  const after = await projectSnapshot(root);
  for (const [file, fingerprint] of after) {
    if (before.get(file) !== fingerprint) changed.add(file);
  }
  for (const file of before.keys()) {
    if (!after.has(file)) changed.add(file);
  }
}

export class AcpAdapter {
  constructor(private readonly options: AcpAdapterOptions = {}) {}

  async run(input: AcpRunInput): Promise<CodeEditorResult> {
    if (input.signal.aborted) return { ok: false, summary: "중단됨", changedFiles: [], error: "cancelled" };

    const changedFiles = new Set<string>();
    let watcher: FSWatcher | undefined;
    let child: ChildProcessWithoutNullStreams | undefined;
    let stderrTail = "";
    let forceKillTimer: NodeJS.Timeout | undefined;
    const before = await projectSnapshot(input.projectPath);

    try {
      watcher = chokidar.watch(input.projectPath, {
        ignoreInitial: true,
        ignored: [/(^|[/\\])\.git([/\\]|$)/, /(^|[/\\])node_modules([/\\]|$)/],
      });
      watcher.on("all", (_event, changedPath) => {
        const relative = relativeProjectPath(input.projectPath, path.resolve(changedPath));
        if (relative) changedFiles.add(relative);
      });
      await new Promise<void>((resolve, reject) => watcher!.once("ready", resolve).once("error", reject));

      const agentKind = this.options.agentKind ?? "claude";
      const defaults = agentCommand(agentKind);
      const command = this.options.command ?? defaults.command;
      const args = this.options.args ?? defaults.args;
      const spawnProcess = this.options.spawnProcess ?? ((cmd, childArgs, options) => spawn(cmd, childArgs, options) as ChildProcessWithoutNullStreams);
      // Deliberately minimal env: only forward what the spawned agent process
      // needs (PATH/NODE_ENV/ELECTRON_RUN_AS_NODE plus the API key the
      // selected agent reads), never the full parent env.
      const agentEnv: NodeJS.ProcessEnv = {};
      if (agentKind === "codex") {
        if (process.env.CODEX_API_KEY) agentEnv.CODEX_API_KEY = process.env.CODEX_API_KEY;
        if (process.env.OPENAI_API_KEY) agentEnv.OPENAI_API_KEY = process.env.OPENAI_API_KEY;
      } else {
        if (process.env.ANTHROPIC_API_KEY) agentEnv.ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY;
      }
      child = spawnProcess(command, args, {
        cwd: input.projectPath,
        stdio: ["pipe", "pipe", "pipe"],
        windowsHide: true,
        env: {
          PATH: process.env.PATH,
          NODE_ENV: process.env.NODE_ENV ?? "production",
          ELECTRON_RUN_AS_NODE: "1",
          ...agentEnv,
          ...this.options.env,
        },
      });
      child.stderr.on("data", (chunk: Buffer) => {
        stderrTail = `${stderrTail}${chunk.toString("utf8")}`.slice(-8_192);
      });

      const childFailure = new Promise<never>((_resolve, reject) => {
        child!.once("error", reject);
        child!.once("exit", (code, signal) => reject(new Error(`ACP 프로세스 종료: code=${code ?? "null"}, signal=${signal ?? "none"}`)));
      });
      const stream = acp.ndJsonStream(
        Writable.toWeb(child.stdin) as WritableStream<Uint8Array>,
        Readable.toWeb(child.stdout) as ReadableStream<Uint8Array>,
      );
      const resolvePermission = this.options.resolvePermission ?? (async () => permissionDenied());
      let summary = "";

      const execution = acp.client({ name: "Speaki-e Workspace" })
        .onRequest(acp.methods.client.session.requestPermission, (context) => resolvePermission(context.params))
        .connectWith(stream, async (context) => {
          await context.request(acp.methods.agent.initialize, {
            protocolVersion: acp.PROTOCOL_VERSION,
            clientCapabilities: {},
          });
          return context.buildSession(input.projectPath).withSession(async (session) => {
            const cancel = () => {
              void context.notify(acp.methods.agent.session.cancel, { sessionId: session.sessionId });
              forceKillTimer = setTimeout(() => child?.kill(), 2_000);
            };
            const listenForAbort = !input.signal.aborted;
            if (listenForAbort) input.signal.addEventListener("abort", cancel, { once: true });
            else cancel();
            try {
              void session.prompt(input.task).catch(() => undefined);
              for (;;) {
                const message = await session.nextUpdate();
                if (message.kind === "stop") {
                  return { stopReason: message.stopReason, summary };
                }
                summary += textFromUpdate(message.update);
                this.options.onUpdate?.(message.update);
              }
            } finally {
              if (listenForAbort) input.signal.removeEventListener("abort", cancel);
            }
          });
        });

      const completed = await Promise.race([execution, childFailure]);
      await addSnapshotChanges(input.projectPath, before, changedFiles);
      if (input.signal.aborted) {
        return { ok: false, summary: "중단됨", changedFiles: [...changedFiles].sort(), error: "cancelled" };
      }
      return {
        ok: true,
        summary: completed.summary.trim() || `ACP 작업 완료 (${completed.stopReason})`,
        changedFiles: [...changedFiles].sort(),
      };
    } catch (error) {
      await addSnapshotChanges(input.projectPath, before, changedFiles).catch(() => undefined);
      return {
        ok: false,
        summary: input.signal.aborted ? "중단됨" : "ACP 작업에 실패했습니다.",
        changedFiles: [...changedFiles].sort(),
        error: input.signal.aborted ? "cancelled" : "acp_error",
        detail: [error instanceof Error ? error.message : String(error), stderrTail.trim()].filter(Boolean).join("\n").slice(-10_000),
      };
    } finally {
      if (forceKillTimer) clearTimeout(forceKillTimer);
      if (child && !child.killed) child.kill();
      await watcher?.close();
    }
  }
}
