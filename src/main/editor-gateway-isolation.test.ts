import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { EditorGateway } from "./editor-gateway.js";
import { FileService } from "./file-service.js";
import { JsonlLogger } from "./logger.js";
import { connectMockEditorGateway, type MockEditorGatewayClient } from "../mocks/mock-editor-gateway-client.js";

/**
 * 서로 다른 두 워크스페이스를 같은 EditorGateway(HTTP 서버 하나, Workspace 프로세스당 단일 인스턴스,
 * W2 완료 기준)에서 동시에 열었을 때, 한쪽 워크스페이스의 WebSocket 이벤트/상태가 다른 쪽으로
 * 새지 않는지 검증한다(공통 W2 계약 시험). EditorGateway는 workspaceId별로 별도의
 * WorkspaceGatewayState(connections/view)를 Map에 들고 있으므로 격리되는 게 맞지만, 회귀를 막기
 * 위해 실제 소켓 두 개로 왕복 확인한다.
 */

const gateways: EditorGateway[] = [];

async function setupTwoWorkspaces(): Promise<{
  gateway: EditorGateway;
  serviceA: FileService;
  serviceB: FileService;
  rootA: string;
  rootB: string;
}> {
  const staticRoot = await mkdtemp(path.join(os.tmpdir(), "workspace-editor-iso-static-"));
  await mkdir(path.join(staticRoot, "assets"), { recursive: true });
  await writeFile(path.join(staticRoot, "index.html"), "<!doctype html><div id=\"root\"></div>", "utf8");

  const rootA = await mkdtemp(path.join(os.tmpdir(), "workspace-editor-iso-a-"));
  await writeFile(path.join(rootA, "a.ts"), "export const a = 1;\n", "utf8");
  const serviceA = await FileService.create(rootA);

  const rootB = await mkdtemp(path.join(os.tmpdir(), "workspace-editor-iso-b-"));
  await writeFile(path.join(rootB, "b.ts"), "export const b = 2;\n", "utf8");
  const serviceB = await FileService.create(rootB);

  const logs = await mkdtemp(path.join(os.tmpdir(), "workspace-editor-iso-logs-"));
  const gateway = new EditorGateway({
    staticRoot,
    logger: new JsonlLogger(logs),
    isKnownWorkspace: (id) => id === "workspace-a" || id === "workspace-b",
    fileServiceFor: async (id) => {
      if (id === "workspace-a") return serviceA;
      if (id === "workspace-b") return serviceB;
      throw new Error(`unknown workspace: ${id}`);
    },
  });
  gateways.push(gateway);
  await gateway.start();
  return { gateway, serviceA, serviceB, rootA, rootB };
}

function connect(gateway: EditorGateway, workspaceId: string): Promise<MockEditorGatewayClient> {
  const token = new URL(gateway.url(workspaceId)).searchParams.get("token")!;
  return connectMockEditorGateway(`ws://127.0.0.1:${gateway.port}/editor/${workspaceId}/ws?token=${token}`);
}

async function expectNoMessage(connection: MockEditorGatewayClient, timeoutMs = 300): Promise<void> {
  await expect(connection.next(timeoutMs)).rejects.toThrow(/timeout/);
}

afterEach(async () => {
  await Promise.all(gateways.splice(0).map((gateway) => gateway.stop()));
});

describe("EditorGateway 워크스페이스 간 격리", () => {
  it("파일 변경 브로드캐스트는 같은 워크스페이스 소켓에만 전달된다", async () => {
    const { gateway, rootA } = await setupTwoWorkspaces();
    const connA = await connect(gateway, "workspace-a");
    const connB = await connect(gateway, "workspace-b");

    gateway.broadcastFileChange("workspace-a", { event: "change", path: "a.ts" });
    const received = await connA.next();
    expect(received).toMatchObject({ workspaceId: "workspace-a", type: "file:changed", payload: { path: "a.ts" } });
    await expectNoMessage(connB);

    connA.socket.close();
    connB.socket.close();
    void rootA;
  });

  it("ACP 진행 상태(update/working-paths) 브로드캐스트는 다른 워크스페이스로 새지 않는다", async () => {
    const { gateway } = await setupTwoWorkspaces();
    const connA = await connect(gateway, "workspace-a");
    const connB = await connect(gateway, "workspace-b");

    gateway.broadcastAcpUpdate("workspace-a", { note: "a만 받아야 함" });
    const update = await connA.next();
    expect(update).toMatchObject({ workspaceId: "workspace-a", type: "acp:update" });
    await expectNoMessage(connB);

    gateway.broadcastWorkingPaths("workspace-b", ["b.ts"]);
    const workingPaths = await connB.next();
    expect(workingPaths).toMatchObject({ workspaceId: "workspace-b", type: "acp:working-paths", payload: ["b.ts"] });
    await expectNoMessage(connA);

    connA.socket.close();
    connB.socket.close();
  });

  it("state:update/state:restore 상태는 워크스페이스별로 분리된다", async () => {
    const { gateway } = await setupTwoWorkspaces();
    const connA = await connect(gateway, "workspace-a");
    const connB = await connect(gateway, "workspace-b");

    await connA.request({
      requestId: "u1",
      workspaceId: "workspace-a",
      type: "state:update",
      payload: { openTabs: ["a.ts"], activePath: "a.ts" },
    });

    const restoredB = await connB.request({ requestId: "r1", workspaceId: "workspace-b", type: "state:restore", payload: null });
    // workspace-b는 한 번도 state:update를 보낸 적이 없으므로 workspace-a의 탭이 섞여 들어오면 안 된다.
    expect(restoredB.payload).toMatchObject({ openTabs: [] });

    const restoredA = await connA.request({ requestId: "r2", workspaceId: "workspace-a", type: "state:restore", payload: null });
    expect(restoredA.payload).toMatchObject({ openTabs: ["a.ts"], activePath: "a.ts" });

    connA.socket.close();
    connB.socket.close();
  });

  it("open_in_editor로 예약된 대기 탭은 해당 워크스페이스의 다음 연결에만 전달된다", async () => {
    const { gateway } = await setupTwoWorkspaces();
    gateway.requestOpenTab("workspace-a", "a.ts");

    const connB = await connect(gateway, "workspace-b");
    await expectNoMessage(connB);

    const connA = await connect(gateway, "workspace-a");
    const opened = await connA.next();
    expect(opened).toMatchObject({ workspaceId: "workspace-a", type: "editor:open-tab", payload: { path: "a.ts" } });

    connA.socket.close();
    connB.socket.close();
  });

  it("서로 다른 워크스페이스는 각자의 FileService(프로젝트 루트)로만 파일을 읽는다", async () => {
    const { gateway } = await setupTwoWorkspaces();
    const connA = await connect(gateway, "workspace-a");
    const connB = await connect(gateway, "workspace-b");

    const readA = await connA.request({ requestId: "f1", workspaceId: "workspace-a", type: "file:read", payload: { path: "a.ts" } });
    expect((readA.payload as { content: string }).content).toContain("a = 1");

    const readBMissing = await connB.request({ requestId: "f2", workspaceId: "workspace-b", type: "file:read", payload: { path: "a.ts" } });
    expect(readBMissing.type).toBe("error");

    connA.socket.close();
    connB.socket.close();
  });
});
