import { randomBytes, timingSafeEqual } from "node:crypto";
import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { Duplex } from "node:stream";
import { readFile as readFileAsync, stat } from "node:fs/promises";
import path from "node:path";
import { WebSocketServer, type RawData, type WebSocket } from "ws";
import type { JSONValue } from "@speaki-e/protocol";
import type { EditorMessage, EditorViewState } from "../shared/editor-contract.js";
import { FileServiceError, type SaveFileRequest } from "../shared/file-contract.js";
import type { FileService } from "./file-service.js";
import { JsonlLogger } from "./logger.js";

export type { EditorViewState } from "../shared/editor-contract.js";

interface WorkspaceGatewayState {
  view: EditorViewState;
  pendingOpenPath?: string;
  connections: Set<WebSocket>;
}

export interface EditorGatewayOptions {
  /** Editor View 정적 빌드 산출물 루트 (vite build의 dist/). */
  staticRoot: string;
  logger: JsonlLogger;
  /** 127.0.0.1 고정 바인딩이 기본값 -- plan 03_workspace.md 4.7 (외부 네트워크 미노출). */
  host?: string;
  maxBodyBytes?: number;
  isKnownWorkspace(workspaceId: string): boolean;
  fileServiceFor(workspaceId: string): Promise<FileService>;
}

class EditorGatewayRequestError extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "EditorGatewayRequestError";
  }
}

const DEFAULT_MAX_BODY_BYTES = 4 * 1024 * 1024;

const MIME_TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".map": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".ico": "image/x-icon",
  ".woff2": "font/woff2",
  ".woff": "font/woff",
  ".ttf": "font/ttf",
};

function contentType(filePath: string): string {
  return MIME_TYPES[path.extname(filePath).toLowerCase()] ?? "application/octet-stream";
}

/**
 * Workspace 프로세스당 단일 EditorGateway. Editor View 번들을 서빙하고, 파일 트리·읽기·저장,
 * 파일 변경/ACP 진행상황 브로드캐스트를 WebSocket 하나로 처리한다(plan/03_workspace.md 4.7).
 * PetBridge(bridge.sock)와는 완전히 분리된 채널이다.
 */
export class EditorGateway {
  private readonly token = randomBytes(24).toString("hex");
  private readonly workspaces = new Map<string, WorkspaceGatewayState>();
  private readonly fileChangeSubscribed = new Set<string>();
  private server?: Server;
  private wss?: WebSocketServer;
  private boundPort = 0;

  constructor(private readonly options: EditorGatewayOptions) {}

  get port(): number {
    return this.boundPort;
  }

  /** pet-app/폴백 창이 로드할 URL. 토큰이 쿼리스트링에 포함된다(WKWebView는 커스텀 헤더를 못 붙이므로). */
  url(workspaceId: string): string {
    return `http://127.0.0.1:${this.boundPort}/editor/${encodeURIComponent(workspaceId)}/?token=${this.token}`;
  }

  async start(): Promise<void> {
    if (this.server) return;
    const server = createServer((req, res) => {
      void this.handleHttp(req, res).catch((error) => {
        void this.options.logger.write("error", "editor_gateway_http_error", {
          message: error instanceof Error ? error.message : String(error),
        });
        if (!res.headersSent) res.writeHead(500).end();
      });
    });
    const wss = new WebSocketServer({ noServer: true, maxPayload: this.options.maxBodyBytes ?? DEFAULT_MAX_BODY_BYTES });
    server.on("upgrade", (req, socket, head) => this.handleUpgrade(req, socket, head, wss));
    await new Promise<void>((resolve, reject) => {
      server.once("error", reject);
      server.listen(0, this.options.host ?? "127.0.0.1", () => resolve());
    });
    const address = server.address();
    this.boundPort = typeof address === "object" && address ? address.port : 0;
    this.server = server;
    this.wss = wss;
    await this.options.logger.write("info", "editor_gateway_started", { port: this.boundPort });
  }

  async stop(): Promise<void> {
    for (const state of this.workspaces.values()) {
      for (const socket of state.connections) socket.close(1001, "server_shutdown");
      state.connections.clear();
    }
    const wss = this.wss;
    this.wss = undefined;
    if (wss) await new Promise<void>((resolve) => wss.close(() => resolve()));
    const server = this.server;
    this.server = undefined;
    if (server) {
      server.closeAllConnections();
      await new Promise<void>((resolve) => server.close(() => resolve()));
    }
  }

  /**
   * open_in_editor 도구용 진입점(W6). Editor View가 연결돼 있으면 즉시 탭 열기를 push하고,
   * 연결이 없으면 다음 연결 때 전달하도록 보관한다.
   */
  requestOpenTab(workspaceId: string, filePath: string): void {
    const state = this.stateFor(workspaceId);
    if (state.connections.size > 0) {
      this.broadcastRaw(state, { workspaceId, type: "editor:open-tab", payload: { path: filePath } });
    } else {
      state.pendingOpenPath = filePath;
    }
  }

  broadcastFileChange(workspaceId: string, event: { event: string; path: string }): void {
    const state = this.workspaces.get(workspaceId);
    if (!state) return;
    this.broadcastRaw(state, { workspaceId, type: "file:changed", payload: event as unknown as JSONValue });
  }

  broadcastAcpUpdate(workspaceId: string, payload: JSONValue): void {
    const state = this.workspaces.get(workspaceId);
    if (!state) return;
    this.broadcastRaw(state, { workspaceId, type: "acp:update", payload });
  }

  broadcastWorkingPaths(workspaceId: string, paths: string[]): void {
    const state = this.stateFor(workspaceId);
    state.view = { ...state.view, workingPaths: paths };
    this.broadcastRaw(state, { workspaceId, type: "acp:working-paths", payload: paths });
  }

  private stateFor(workspaceId: string): WorkspaceGatewayState {
    let state = this.workspaces.get(workspaceId);
    if (!state) {
      state = { view: { openTabs: [], workingPaths: [] }, connections: new Set() };
      this.workspaces.set(workspaceId, state);
    }
    return state;
  }

  private broadcastRaw(state: WorkspaceGatewayState, message: EditorMessage): void {
    const data = JSON.stringify(message);
    for (const socket of state.connections) {
      if (socket.readyState === socket.OPEN) socket.send(data);
    }
  }

  private verifyToken(candidate: string | null): boolean {
    if (!candidate) return false;
    const a = Buffer.from(candidate);
    const b = Buffer.from(this.token);
    return a.length === b.length && timingSafeEqual(a, b);
  }

  /** Origin이 없는 요청(최상위 탐색, WKWebView 최초 로드)은 허용하고, 있으면 게이트웨이 자기 자신과 일치해야 한다. */
  private verifyOrigin(origin: string | undefined): boolean {
    if (!origin) return true;
    return origin === `http://127.0.0.1:${this.boundPort}`;
  }

  private parseEditorPath(pathname: string): { workspaceId: string; rest: string } | undefined {
    const match = /^\/editor\/([^/]+)((?:\/.*)?)$/.exec(pathname);
    if (!match) return undefined;
    return { workspaceId: decodeURIComponent(match[1]!), rest: match[2]! };
  }

  private isInsideStaticRoot(candidate: string): boolean {
    const relative = path.relative(this.options.staticRoot, candidate);
    return relative !== "" && !relative.startsWith(`..${path.sep}`) && relative !== ".." && !path.isAbsolute(relative);
  }

  private async handleHttp(req: IncomingMessage, res: ServerResponse): Promise<void> {
    const url = new URL(req.url ?? "/", `http://127.0.0.1:${this.boundPort}`);
    const contentLength = Number(req.headers["content-length"] ?? 0);
    const maxBytes = this.options.maxBodyBytes ?? DEFAULT_MAX_BODY_BYTES;
    if (Number.isFinite(contentLength) && contentLength > maxBytes) {
      res.writeHead(413).end("payload too large");
      return;
    }
    if (!this.verifyOrigin(req.headers.origin)) {
      res.writeHead(403).end("origin not allowed");
      return;
    }
    const parsed = this.parseEditorPath(url.pathname);
    if (!parsed) {
      res.writeHead(404).end();
      return;
    }
    const { workspaceId, rest } = parsed;
    if (!this.options.isKnownWorkspace(workspaceId)) {
      res.writeHead(404).end("unknown workspace");
      return;
    }
    if (!this.verifyToken(url.searchParams.get("token"))) {
      res.writeHead(401).end("invalid token");
      return;
    }
    if (rest === "") {
      res.writeHead(302, { Location: `${url.pathname}/${url.search}` });
      res.end();
      return;
    }
    if (rest === "/") {
      await this.serveFile(res, path.join(this.options.staticRoot, "index.html"));
      return;
    }
    const target = path.resolve(this.options.staticRoot, rest.slice(1));
    if (!this.isInsideStaticRoot(target)) {
      res.writeHead(403).end();
      return;
    }
    await this.serveFile(res, target);
  }

  private async serveFile(res: ServerResponse, filePath: string): Promise<void> {
    try {
      const info = await stat(filePath);
      if (!info.isFile()) {
        res.writeHead(404).end();
        return;
      }
      const body = await readFileAsync(filePath);
      res.writeHead(200, {
        "Content-Type": contentType(filePath),
        "Content-Length": body.byteLength,
        "Cache-Control": "no-store",
      });
      res.end(body);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") {
        res.writeHead(404).end();
        return;
      }
      throw error;
    }
  }

  private handleUpgrade(req: IncomingMessage, socket: Duplex, head: Buffer, wss: WebSocketServer): void {
    const reject = (code: number, message: string) => {
      socket.write(`HTTP/1.1 ${code} ${message}\r\nConnection: close\r\n\r\n`);
      socket.destroy();
    };
    const url = new URL(req.url ?? "/", `http://127.0.0.1:${this.boundPort}`);
    const parsed = this.parseEditorPath(url.pathname);
    if (!parsed || parsed.rest !== "/ws") return reject(404, "Not Found");
    if (!this.options.isKnownWorkspace(parsed.workspaceId)) return reject(404, "Not Found");
    if (!this.verifyOrigin(req.headers.origin)) return reject(403, "Forbidden");
    if (!this.verifyToken(url.searchParams.get("token"))) return reject(401, "Unauthorized");
    wss.handleUpgrade(req, socket, head, (ws) => this.handleConnection(ws, parsed.workspaceId));
  }

  private handleConnection(ws: WebSocket, workspaceId: string): void {
    const state = this.stateFor(workspaceId);
    state.connections.add(ws);
    void this.options.logger.write("info", "editor_gateway_ws_connected", { workspaceId });
    if (state.pendingOpenPath) {
      const filePath = state.pendingOpenPath;
      state.pendingOpenPath = undefined;
      ws.send(JSON.stringify({ workspaceId, type: "editor:open-tab", payload: { path: filePath } } satisfies EditorMessage));
    }
    ws.on("message", (data) => {
      void this.handleMessage(ws, workspaceId, state, data).catch((error) => {
        void this.options.logger.write("warn", "editor_gateway_ws_error", {
          workspaceId,
          message: error instanceof Error ? error.message : String(error),
        });
      });
    });
    const forget = () => {
      state.connections.delete(ws);
      void this.options.logger.write("info", "editor_gateway_ws_disconnected", { workspaceId });
    };
    ws.on("close", forget);
    ws.on("error", forget);
  }

  private async handleMessage(ws: WebSocket, workspaceId: string, state: WorkspaceGatewayState, data: RawData): Promise<void> {
    let message: EditorMessage;
    try {
      message = JSON.parse(data.toString()) as EditorMessage;
    } catch {
      ws.send(JSON.stringify({ workspaceId, type: "error", payload: { code: "invalid_message", message: "잘못된 JSON입니다" } }));
      return;
    }
    if (!message || typeof message.type !== "string") {
      ws.send(JSON.stringify({ workspaceId, type: "error", payload: { code: "invalid_message", message: "type이 필요합니다" } }));
      return;
    }
    try {
      const payload = await this.dispatch(workspaceId, state, message);
      ws.send(JSON.stringify({ requestId: message.requestId, workspaceId, type: message.type, payload } satisfies EditorMessage));
    } catch (error) {
      const described = this.describeError(error);
      ws.send(JSON.stringify({
        requestId: message.requestId,
        workspaceId,
        type: "error",
        payload: { code: described.code, message: described.detail, requestType: message.type },
      } satisfies EditorMessage));
    }
  }

  private describeError(error: unknown): { code: string; detail: string } {
    if (error instanceof FileServiceError) return { code: error.code, detail: error.message };
    if (error instanceof EditorGatewayRequestError) return { code: error.code, detail: error.message };
    return { code: "internal_error", detail: error instanceof Error ? error.message : String(error) };
  }

  private stringField(payload: JSONValue, key: string): string {
    const value = (payload as Record<string, JSONValue> | null)?.[key];
    if (typeof value !== "string") throw new EditorGatewayRequestError("invalid_request", `${key} 필드가 필요합니다`);
    return value;
  }

  private subscribeFileChanges(workspaceId: string, service: FileService): void {
    if (this.fileChangeSubscribed.has(workspaceId)) return;
    this.fileChangeSubscribed.add(workspaceId);
    service.on("change", (event: { event: string; path: string }) => this.broadcastFileChange(workspaceId, event));
  }

  private async dispatch(workspaceId: string, state: WorkspaceGatewayState, message: EditorMessage): Promise<JSONValue> {
    switch (message.type) {
      case "file:list-tree": {
        const service = await this.options.fileServiceFor(workspaceId);
        this.subscribeFileChanges(workspaceId, service);
        return (await service.listTree()) as unknown as JSONValue;
      }
      case "file:read": {
        const service = await this.options.fileServiceFor(workspaceId);
        return (await service.readFile(this.stringField(message.payload, "path"))) as unknown as JSONValue;
      }
      case "file:preview-image": {
        const service = await this.options.fileServiceFor(workspaceId);
        return (await service.readImagePreview(this.stringField(message.payload, "path"))) as unknown as JSONValue;
      }
      case "file:save": {
        const request = message.payload as unknown as Partial<SaveFileRequest>;
        if (typeof request.path !== "string" || typeof request.content !== "string" || typeof request.expectedRevision !== "string") {
          throw new EditorGatewayRequestError("invalid_request", "path/content/expectedRevision이 필요합니다");
        }
        const service = await this.options.fileServiceFor(workspaceId);
        return (await service.saveFile(request as SaveFileRequest)) as unknown as JSONValue;
      }
      case "state:restore":
        return { ...state.view } as unknown as JSONValue;
      case "state:update": {
        const next = message.payload as unknown as Partial<EditorViewState> | null;
        state.view = {
          openTabs: Array.isArray(next?.openTabs) ? next.openTabs.filter((entry): entry is string => typeof entry === "string") : state.view.openTabs,
          activePath: typeof next?.activePath === "string" ? next.activePath : undefined,
          workingPaths: state.view.workingPaths,
        };
        return { ok: true } as unknown as JSONValue;
      }
      default:
        throw new EditorGatewayRequestError("unknown_request", `알 수 없는 요청입니다: ${message.type}`);
    }
  }
}
