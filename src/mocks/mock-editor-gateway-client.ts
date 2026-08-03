import WebSocket from "ws";
import type { EditorMessage } from "../shared/editor-contract.js";

export interface MockEditorGatewayClient {
  socket: WebSocket;
  /** 큐잉된(또는 다음에 도착할) 메시지 하나를 받는다 -- 서버가 push하는 메시지도 이걸로 받는다. */
  next(timeoutMs?: number): Promise<EditorMessage>;
  /** 보내고 다음 메시지(보통 같은 requestId의 응답)를 기다린다. */
  request(message: EditorMessage): Promise<EditorMessage>;
  close(): void;
}

/** EditorGateway.url()이 주는 HTTP 진입 URL을 WebSocket 엔드포인트 URL로 바꾼다. */
export function toEditorGatewayWsUrl(httpEntryUrl: string): string {
  const url = new URL(httpEntryUrl);
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  url.pathname = `${url.pathname.replace(/\/$/, "")}/ws`;
  return url.toString();
}

/**
 * 다른 저장소(pet-app 등)가 EditorGateway를 상대로 통합 테스트를 짤 때 재사용할 수 있는
 * 최소 WebSocket 클라이언트다(W0 완료 기준: Mock EditorGateway HTTP/WebSocket 클라이언트).
 * open 이벤트와 서버가 연결 직후 곧바로 push하는 메시지(예: open_in_editor의 pending tab) 사이의
 * 경합을 피하려고 소켓 생성 즉시 큐잉을 시작한다 -- 메시지 리스너를 나중에 붙이면 그 사이에 온
 * 메시지를 놓친다.
 */
export function connectMockEditorGateway(wsUrl: string): Promise<MockEditorGatewayClient> {
  const socket = new WebSocket(wsUrl);
  const queue: EditorMessage[] = [];
  const waiters: Array<(message: EditorMessage) => void> = [];

  socket.on("message", (data) => {
    const message = JSON.parse(data.toString()) as EditorMessage;
    const waiter = waiters.shift();
    if (waiter) waiter(message);
    else queue.push(message);
  });

  const next = (timeoutMs = 2_000): Promise<EditorMessage> => {
    const queued = queue.shift();
    if (queued) return Promise.resolve(queued);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error("timeout waiting for EditorGateway message")), timeoutMs);
      waiters.push((message) => {
        clearTimeout(timer);
        resolve(message);
      });
    });
  };

  return new Promise((resolve, reject) => {
    socket.once("open", () => resolve({
      socket,
      next,
      request: (message) => {
        socket.send(JSON.stringify(message));
        return next();
      },
      close: () => socket.close(),
    }));
    socket.once("error", reject);
  });
}
