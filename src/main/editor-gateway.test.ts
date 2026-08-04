import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import WebSocket from "ws";
import { EditorGateway } from "./editor-gateway.js";
import { FileService } from "./file-service.js";
import { JsonlLogger } from "./logger.js";
import type { EditorMessage } from "../shared/editor-contract.js";
import { connectMockEditorGateway, type MockEditorGatewayClient } from "../mocks/mock-editor-gateway-client.js";

const gateways: EditorGateway[] = [];

async function setup(): Promise<{ gateway: EditorGateway; service: FileService; projectRoot: string }> {
  const staticRoot = await mkdtemp(path.join(os.tmpdir(), "workspace-editor-static-"));
  await mkdir(path.join(staticRoot, "assets"), { recursive: true });
  await writeFile(
    path.join(staticRoot, "index.html"),
    "<!doctype html><div id=\"root\"></div><script src=\"./assets/app.js\"></script>",
    "utf8",
  );
  await writeFile(path.join(staticRoot, "assets", "app.js"), "console.log('editor view')", "utf8");

  const projectRoot = await mkdtemp(path.join(os.tmpdir(), "workspace-editor-project-"));
  await writeFile(path.join(projectRoot, "main.ts"), "export const value = 1;\n", "utf8");
  const service = await FileService.create(projectRoot);

  const logs = await mkdtemp(path.join(os.tmpdir(), "workspace-editor-logs-"));
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
  return { gateway, service, projectRoot };
}

// 실제 클라이언트 로직은 mocks/mock-editor-gateway-client.ts로 뺐다(W0: 다른 저장소도 재사용
// 가능한 Mock EditorGateway WebSocket 클라이언트). 여기서는 이 테스트 파일의 기존 호출부
// 시그니처(connect(gateway, workspaceId, token) / requestOnce(connection, message))만 유지하는
// 얇은 래퍼다.
type ConnectedSocket = MockEditorGatewayClient;

function connect(gateway: EditorGateway, workspaceId: string, token: string): Promise<ConnectedSocket> {
  return connectMockEditorGateway(`ws://127.0.0.1:${gateway.port}/editor/${workspaceId}/ws?token=${token}`);
}

async function requestOnce(connection: ConnectedSocket, message: EditorMessage): Promise<EditorMessage> {
  return connection.request(message);
}

function tokenFromUrl(url: string): string {
  return new URL(url).searchParams.get("token")!;
}

afterEach(async () => {
  await Promise.all(gateways.splice(0).map((gateway) => gateway.stop()));
});

describe("EditorGateway", () => {
  it("정상 토큰으로 정적 번들과 asset을 서빙한다", async () => {
    const { gateway } = await setup();
    const token = tokenFromUrl(gateway.url("default"));
    const page = await fetch(gateway.url("default"));
    expect(page.status).toBe(200);
    expect(await page.text()).toContain("root");

    const asset = await fetch(`http://127.0.0.1:${gateway.port}/editor/default/assets/app.js?token=${token}`);
    expect(asset.status).toBe(200);
    expect(await asset.text()).toContain("editor view");
  });

  it("asset 요청은 token 없이도 서빙한다 (index.html의 상대 경로는 쿼리스트링을 안 옮긴다)", async () => {
    const { gateway } = await setup();
    const asset = await fetch(`http://127.0.0.1:${gateway.port}/editor/default/assets/app.js`);
    expect(asset.status).toBe(200);
    expect(await asset.text()).toContain("editor view");
  });

  it("진입 문서는 token 없이 거부한다", async () => {
    const { gateway } = await setup();
    const page = await fetch(`http://127.0.0.1:${gateway.port}/editor/default/`);
    expect(page.status).toBe(401);
  });

  it("트레일링 슬래시가 없으면 붙여서 리다이렉트한다", async () => {
    const { gateway } = await setup();
    const token = tokenFromUrl(gateway.url("default"));
    const response = await fetch(`http://127.0.0.1:${gateway.port}/editor/default?token=${token}`, { redirect: "manual" });
    expect(response.status).toBe(302);
    expect(response.headers.get("location")).toBe(`/editor/default/?token=${token}`);
  });

  it("잘못된 token/workspace ID/과대 본문 HTTP 요청을 거부한다", async () => {
    const { gateway } = await setup();
    const token = tokenFromUrl(gateway.url("default"));

    const badToken = await fetch(`http://127.0.0.1:${gateway.port}/editor/default/?token=wrong`);
    expect(badToken.status).toBe(401);

    const badWorkspace = await fetch(`http://127.0.0.1:${gateway.port}/editor/unknown/?token=${token}`);
    expect(badWorkspace.status).toBe(404);

    const tooLarge = await fetch(`http://127.0.0.1:${gateway.port}/editor/default/?token=${token}`, {
      method: "POST",
      body: "x".repeat(6 * 1024 * 1024),
    });
    expect(tooLarge.status).toBe(413);
  });

  it("허용되지 않은 Origin의 WebSocket 업그레이드를 거부한다", async () => {
    const { gateway } = await setup();
    const token = tokenFromUrl(gateway.url("default"));
    const socket = new WebSocket(`ws://127.0.0.1:${gateway.port}/editor/default/ws?token=${token}`, {
      headers: { origin: "http://evil.example" },
    });
    await new Promise<void>((resolve) => {
      socket.once("error", () => resolve());
      socket.once("close", () => resolve());
    });
    expect(socket.readyState).not.toBe(WebSocket.OPEN);
  });

  it("잘못된 token의 WebSocket 업그레이드를 거부한다", async () => {
    const { gateway } = await setup();
    const socket = new WebSocket(`ws://127.0.0.1:${gateway.port}/editor/default/ws?token=wrong`);
    await new Promise<void>((resolve) => {
      socket.once("error", () => resolve());
      socket.once("close", () => resolve());
    });
    expect(socket.readyState).not.toBe(WebSocket.OPEN);
  });

  it("WS requestId를 매칭해 파일 트리·읽기·저장 API를 처리한다", async () => {
    const { gateway } = await setup();
    const token = tokenFromUrl(gateway.url("default"));
    const connection = await connect(gateway, "default", token);

    const tree = await requestOnce(connection, { requestId: "r1", workspaceId: "default", type: "file:list-tree", payload: null });
    expect(tree.requestId).toBe("r1");
    expect((tree.payload as Array<{ name: string }>).some((entry) => entry.name === "main.ts")).toBe(true);

    const read = await requestOnce(connection, { requestId: "r2", workspaceId: "default", type: "file:read", payload: { path: "main.ts" } });
    const content = read.payload as { content: string; revision: string };
    expect(content.content).toContain("value = 1");

    const saved = await requestOnce(connection, {
      requestId: "r3",
      workspaceId: "default",
      type: "file:save",
      payload: { path: "main.ts", content: "export const value = 2;\n", expectedRevision: content.revision },
    });
    expect((saved.payload as { revision: string }).revision).not.toBe(content.revision);
    connection.socket.close();
  });

  it("알 수 없는 요청 type은 error로 응답한다", async () => {
    const { gateway } = await setup();
    const token = tokenFromUrl(gateway.url("default"));
    const connection = await connect(gateway, "default", token);
    const response = await requestOnce(connection, { requestId: "bad", workspaceId: "default", type: "nope", payload: null });
    expect(response.type).toBe("error");
    expect((response.payload as { code: string }).code).toBe("unknown_request");
    connection.socket.close();
  });

  it("파일 변경 이벤트를 연결된 소켓에 브로드캐스트한다", async () => {
    const { gateway, service, projectRoot } = await setup();
    const token = tokenFromUrl(gateway.url("default"));
    const connection = await connect(gateway, "default", token);
    await requestOnce(connection, { requestId: "list", workspaceId: "default", type: "file:list-tree", payload: null });
    await service.startWatching();
    // chokidar의 네이티브 watch 핸들이 startWatching() 반환 직후 아직 준비되지 않았을 수 있어
    // 곧바로 쓰기를 하면 이벤트를 놓친다 -- 실제 사용에서는 문제되지 않는 타이밍이라 FileService는
    // 별도 ready 대기를 하지 않는다(이주한 W1 소유 코드, 이 테스트에서만 여유를 둔다).
    await new Promise((resolve) => setTimeout(resolve, 250));

    await writeFile(path.join(projectRoot, "new.txt"), "hi", "utf8");
    let event = await connection.next();
    while (event.type !== "file:changed") event = await connection.next();
    expect((event.payload as { path: string }).path).toBe("new.txt");
    connection.socket.close();
    await service.close();
  });

  it("ACP 진행 상태(working paths)를 브로드캐스트한다", async () => {
    const { gateway } = await setup();
    const token = tokenFromUrl(gateway.url("default"));
    const connection = await connect(gateway, "default", token);
    gateway.broadcastWorkingPaths("default", ["main.ts"]);
    const update = await connection.next();
    expect(update.type).toBe("acp:working-paths");
    connection.socket.close();
  });

  it("재연결 시 state:restore로 저장된 탭/활성 탭 상태를 복원한다", async () => {
    const { gateway } = await setup();
    const token = tokenFromUrl(gateway.url("default"));
    const first = await connect(gateway, "default", token);
    await requestOnce(first, {
      requestId: "u1",
      workspaceId: "default",
      type: "state:update",
      payload: { openTabs: ["main.ts"], activePath: "main.ts" },
    });
    first.socket.close();
    await new Promise((resolve) => setTimeout(resolve, 50));

    const second = await connect(gateway, "default", token);
    const restored = await requestOnce(second, { requestId: "r", workspaceId: "default", type: "state:restore", payload: null });
    expect(restored.payload).toMatchObject({ openTabs: ["main.ts"], activePath: "main.ts" });
    second.socket.close();
  });

  it("Editor View 미연결 시 open_in_editor 요청을 저장했다가 다음 연결에서 전달한다", async () => {
    const { gateway } = await setup();
    gateway.requestOpenTab("default", "main.ts");
    const token = tokenFromUrl(gateway.url("default"));
    const connection = await connect(gateway, "default", token);
    const opened = await connection.next();
    expect(opened).toMatchObject({ type: "editor:open-tab", payload: { path: "main.ts" } });
    connection.socket.close();
  });

  it("형식이 깨진 JSON 메시지를 받아도 크래시 없이 error로 응답하고 연결을 유지한다", async () => {
    const { gateway } = await setup();
    const token = tokenFromUrl(gateway.url("default"));
    const connection = await connect(gateway, "default", token);

    connection.socket.send("{ this is not json");
    const response = await connection.next();
    expect(response.type).toBe("error");
    expect((response.payload as { code: string }).code).toBe("invalid_message");

    // 연결은 계속 살아 있어 이어서 정상 요청을 처리한다.
    const tree = await requestOnce(connection, { requestId: "after-bad-json", workspaceId: "default", type: "file:list-tree", payload: null });
    expect(tree.requestId).toBe("after-bad-json");
    connection.socket.close();
  });

  it("type 필드가 없는 메시지를 받아도 크래시 없이 error로 응답한다", async () => {
    const { gateway } = await setup();
    const token = tokenFromUrl(gateway.url("default"));
    const connection = await connect(gateway, "default", token);

    connection.socket.send(JSON.stringify({ requestId: "no-type", workspaceId: "default", payload: null }));
    const response = await connection.next();
    expect(response.type).toBe("error");
    expect((response.payload as { code: string }).code).toBe("invalid_message");
    connection.socket.close();
  });

  it("file:save에 필수 필드가 누락되면 크래시 없이 invalid_request로 응답한다", async () => {
    const { gateway } = await setup();
    const token = tokenFromUrl(gateway.url("default"));
    const connection = await connect(gateway, "default", token);

    // content/expectedRevision이 빠져 있다.
    const response = await requestOnce(connection, {
      requestId: "bad-save",
      workspaceId: "default",
      type: "file:save",
      payload: { path: "main.ts" },
    });
    expect(response.type).toBe("error");
    expect((response.payload as { code: string }).code).toBe("invalid_request");

    // 연결은 계속 살아 있어 이어서 정상 요청을 처리한다.
    const tree = await requestOnce(connection, { requestId: "after-bad-save", workspaceId: "default", type: "file:list-tree", payload: null });
    expect(tree.requestId).toBe("after-bad-save");
    connection.socket.close();
  });
});
