import type { EditorMessage, EditorTransport } from "../shared/editor-contract";

interface PendingRequest {
  resolve(value: unknown): void;
  reject(error: Error): void;
}

/** URL의 /editor/:workspaceId/... 에서 workspaceId를 뽑아낸다. EditorGateway가 만든 URL과 짝을 이룬다. */
export function parseGatewayWorkspaceId(pathname: string): string {
  const segments = pathname.split("/").filter(Boolean);
  return decodeURIComponent(segments[1] ?? "default");
}

/**
 * pet-app의 WKWebView(또는 contextBridge가 없는 어떤 호스트)에서 EditorGateway와 통신하기 위한
 * EditorTransport 구현체다(plan/03_workspace.md 4.1: "pet-app에 로드될 때는 로컬 서버의
 * WebSocket으로 메인과 통신"). requestId로 요청/응답을 매칭하고, 나머지(요청 없이 오는 push)는
 * subscribe 리스너들에게 그대로 흘려보낸다. 연결이 끊기면 재연결하고 끊긴 동안의 요청은 큐잉한다.
 */
export function createGatewayTransport(workspaceId: string, token: string): EditorTransport {
  const listeners = new Set<(message: EditorMessage) => void>();
  const pending = new Map<string, PendingRequest>();
  const outbox: string[] = [];
  let socket: WebSocket | undefined;

  function wsUrl(): string {
    const scheme = location.protocol === "https:" ? "wss:" : "ws:";
    return `${scheme}//${location.host}/editor/${encodeURIComponent(workspaceId)}/ws?token=${encodeURIComponent(token)}`;
  }

  function flushOutbox(ws: WebSocket): void {
    while (outbox.length) ws.send(outbox.shift()!);
  }

  function handleMessage(raw: string): void {
    let message: EditorMessage;
    try {
      message = JSON.parse(raw) as EditorMessage;
    } catch {
      return;
    }
    if (message.requestId && pending.has(message.requestId)) {
      const request = pending.get(message.requestId)!;
      pending.delete(message.requestId);
      if (message.type === "error") {
        const detail = (message.payload as { message?: string } | null)?.message ?? "요청이 실패했습니다";
        request.reject(new Error(detail));
      } else {
        request.resolve(message.payload);
      }
      return;
    }
    for (const listener of listeners) listener(message);
  }

  function connect(): void {
    const ws = new WebSocket(wsUrl());
    socket = ws;
    ws.addEventListener("open", () => flushOutbox(ws));
    ws.addEventListener("message", (event) => handleMessage(String(event.data)));
    ws.addEventListener("close", () => {
      if (socket === ws) socket = undefined;
      window.setTimeout(connect, 1_000);
    });
    ws.addEventListener("error", () => ws.close());
  }
  connect();

  function send(message: EditorMessage): void {
    const raw = JSON.stringify(message);
    if (socket?.readyState === WebSocket.OPEN) socket.send(raw);
    else outbox.push(raw);
  }

  return {
    request<T = unknown>(message: EditorMessage): Promise<T> {
      const requestId = message.requestId ?? crypto.randomUUID();
      return new Promise<T>((resolve, reject) => {
        pending.set(requestId, { resolve: resolve as (value: unknown) => void, reject });
        send({ ...message, requestId });
      });
    },
    subscribe(listener: (message: EditorMessage) => void): () => void {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
  };
}
