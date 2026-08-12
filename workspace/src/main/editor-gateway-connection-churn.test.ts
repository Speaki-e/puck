import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { EditorGateway } from "./editor-gateway.js";
import { FileService } from "./file-service.js";
import { JsonlLogger } from "./logger.js";
import { connectMockEditorGateway } from "../mocks/mock-editor-gateway-client.js";

const gateways: EditorGateway[] = [];

async function setup(): Promise<{ gateway: EditorGateway; token: string }> {
  const staticRoot = await mkdtemp(path.join(os.tmpdir(), "workspace-editor-churn-static-"));
  await writeFile(path.join(staticRoot, "index.html"), "<!doctype html><div id=\"root\"></div>", "utf8");

  const projectRoot = await mkdtemp(path.join(os.tmpdir(), "workspace-editor-churn-project-"));
  await mkdir(projectRoot, { recursive: true });
  const service = await FileService.create(projectRoot);

  const logs = await mkdtemp(path.join(os.tmpdir(), "workspace-editor-churn-logs-"));
  const gateway = new EditorGateway({
    staticRoot,
    logger: new JsonlLogger(logs),
    isKnownWorkspace: (id) => id === "default",
    fileServiceFor: async (id) => {
      if (id !== "default") throw new Error("unknown workspace");
      return service;
    },
  });
  gateways.push(gateway);
  await gateway.start();
  const token = new URL(gateway.url("default")).searchParams.get("token")!;
  return { gateway, token };
}

async function waitUntilConnectionCount(
  gateway: EditorGateway,
  workspaceId: string,
  target: number,
  timeoutMs = 5_000,
): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (gateway.connectionCount(workspaceId) !== target) {
    if (Date.now() > deadline) {
      throw new Error(`connectionCount가 ${timeoutMs}ms 안에 ${target}이 되지 않음 (현재 ${gateway.connectionCount(workspaceId)})`);
    }
    await new Promise((resolve) => setImmediate(resolve));
  }
}

async function connectAndDisconnect(gateway: EditorGateway, token: string): Promise<void> {
  const connection = await connectMockEditorGateway(`ws://127.0.0.1:${gateway.port}/editor/default/ws?token=${token}`);
  await new Promise<void>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("소켓 close 이벤트 대기 시간 초과")), 5_000);
    connection.socket.once("close", () => {
      clearTimeout(timer);
      resolve();
    });
    connection.close();
  });
  // 클라이언트가 close 이벤트를 받았다고 해서 서버 쪽 "close" 핸들러(editor-gateway.ts의 forget())가
  // 반드시 같은 틱에 이미 끝났다는 보장은 없다 -- state.connections에서 실제로 빠질 때까지 짧게 폴링한다.
  await waitUntilConnectionCount(gateway, "default", 0);
}

afterEach(async () => {
  await Promise.all(gateways.splice(0).map((gateway) => gateway.stop()));
});

/**
 * 공통 "필수 장애 시험" 항목 "장시간 실행·반복 재연결·메모리 누수 시험". EditorGateway WebSocket을
 * 짧은 간격으로 수백 회 연결·해제해도 서버 쪽에 연결 목록이 누적되지 않는지, heap 사용량이
 * 반복 횟수에 비례해 계속 커지지만 않는지 확인한다. pending-approval-store/run-registry/
 * session-registry는 EditorGateway의 WS 연결·해제와 코드상 연동돼 있지 않아(그냥 워크스페이스별
 * connections Set만 건드림) 이 시험 범위에 포함하지 않는다.
 */
describe("EditorGateway WebSocket 반복 연결/해제", () => {
  it("300회 연결·해제 후에도 서버에 남는 연결이 없고 heap이 반복 횟수에 비례해 계속 자라지 않는다", async () => {
    const { gateway, token } = await setup();
    const ITERATIONS = 300;
    const heapSamplesMb: number[] = [];

    expect(gateway.connectionCount("default")).toBe(0);

    for (let i = 0; i < ITERATIONS; i += 1) {
      await connectAndDisconnect(gateway, token);
      // 매 반복마다 정확히 0으로 돌아와야 한다 -- 중간에라도 누적되면 여기서 바로 잡힌다.
      expect(gateway.connectionCount("default")).toBe(0);
      if (i % 50 === 0) {
        (globalThis as { gc?: () => void }).gc?.();
        heapSamplesMb.push(process.memoryUsage().heapUsed / (1024 * 1024));
      }
    }

    expect(gateway.connectionCount("default")).toBe(0);

    // 정밀 프로파일링 도구 없이 대략적인 추이만 본다 -- GC 타이밍에 따라 흔들릴 수 있어 널널한
    // 임계값(반복 사이 heap이 20MB 넘게 계속 불어나면 뭔가 잘못됐다고 본다)으로만 스모크 체크한다.
    const first = heapSamplesMb[0]!;
    const last = heapSamplesMb[heapSamplesMb.length - 1]!;
    expect(last - first).toBeLessThan(20);

    // 반복 뒤에도 새 연결이 정상 동작하는지(내부 상태가 깨지지 않았는지) 확인.
    const fresh = await connectMockEditorGateway(`ws://127.0.0.1:${gateway.port}/editor/default/ws?token=${token}`);
    expect(gateway.connectionCount("default")).toBe(1);
    fresh.close();
  }, 60_000);
});
