import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { AcpAdapter } from "./acp-adapter.js";
import { FileService } from "../main/file-service.js";
import { FileServiceError } from "../shared/file-contract.js";

const FIXTURE = path.resolve("tests/fixtures/mock-acp-agent.mjs");
const FILE_NAME = "mock-change.txt";
const ACP_CONTENT = "changed by mock acp\n";

function newAdapter(): AcpAdapter {
  return new AcpAdapter({ command: process.execPath, args: [FIXTURE] });
}

async function waitForChange(service: FileService, timeoutMs = 5_000): Promise<{ path: string }> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("파일 변경 이벤트를 기다리다 시간 초과")), timeoutMs);
    service.once("change", (event) => {
      clearTimeout(timer);
      resolve(event as { path: string });
    });
  });
}

/**
 * 공통 W1 "ACP와 사용자가 같은 파일을 동시에 수정하는 실제 통합 시험". Mock ACP(자식 프로세스, 실제
 * ACP처럼 FileService를 거치지 않고 파일을 직접 쓴다)와 FileService.saveFile(revision 검사 + 임시
 * 파일 후 rename하는 원자적 저장, W1에서 이미 완료)이 같은 파일을 두고 부딪히는 시나리오를 실제로
 * 재현한다. 새 잠금 메커니즘은 만들지 않고 기존 revision 검사·원자적 저장·chokidar 변경 감지만으로
 * 파일이 깨지지 않는지 확인한다.
 */
describe("ACP와 사용자 저장이 같은 파일을 동시에 건드려도 손상되지 않는다", () => {
  it("사용자가 먼저 저장에 성공한 뒤 ACP가 덮어쓰면, 디스크는 ACP 내용 그대로이고 외부 변경 이벤트가 사용자 쪽에 전달된다", async () => {
    const root = await mkdtemp(path.join(os.tmpdir(), "concurrent-user-first-"));
    await writeFile(path.join(root, FILE_NAME), "initial\n", "utf8");
    const service = await FileService.create(root);
    await service.startWatching();
    // chokidar 네이티브 watch 핸들이 startWatching() 직후 아직 준비되지 않을 수 있다
    // (editor-gateway.test.ts의 동일한 타이밍 여유와 같은 이유).
    await new Promise((resolve) => setTimeout(resolve, 250));

    try {
      const initial = await service.readFile(FILE_NAME);
      const saved = await service.saveFile({ path: FILE_NAME, content: "user edit\n", expectedRevision: initial.revision });
      expect(saved.revision).not.toBe(initial.revision);
      await expect(readFile(path.join(root, FILE_NAME), "utf8")).resolves.toBe("user edit\n");

      const changed = waitForChange(service);
      const result = await newAdapter().run({
        requestId: "concurrent-user-first",
        workspaceId: "w1",
        task: "평범한 작업",
        projectPath: root,
        signal: new AbortController().signal,
      });
      expect(result.ok).toBe(true);

      // 디스크 내용은 ACP가 마지막에 쓴 그대로여야 한다 -- 부분 쓰기나 사용자 내용과 뒤섞인 흔적이 없어야 한다.
      await expect(readFile(path.join(root, FILE_NAME), "utf8")).resolves.toBe(ACP_CONTENT);

      // FileService의 chokidar watcher가 이 변경을 감지해야 EditorGateway가 file:changed로
      // 사용자에게 "디스크가 너 몰래 바뀌었다"를 알릴 수 있다(editor-gateway.ts가 이 change 이벤트를
      // 그대로 브로드캐스트한다, W2에서 이미 검증된 배선). 여기서는 이벤트 자체가 실제로 발생하는지만 본다.
      const event = await changed;
      expect(event.path).toBe(FILE_NAME);
    } finally {
      await service.close();
    }
  }, 15_000);

  it("ACP가 먼저 쓴 뒤 사용자가 오래된 revision으로 저장을 시도하면 file_conflict로 막히고 ACP의 내용이 보존된다", async () => {
    const root = await mkdtemp(path.join(os.tmpdir(), "concurrent-acp-first-"));
    await writeFile(path.join(root, FILE_NAME), "initial\n", "utf8");
    const service = await FileService.create(root);

    try {
      const initial = await service.readFile(FILE_NAME);

      const result = await newAdapter().run({
        requestId: "concurrent-acp-first",
        workspaceId: "w1",
        task: "평범한 작업",
        projectPath: root,
        signal: new AbortController().signal,
      });
      expect(result.ok).toBe(true);

      // 사용자는 여전히 ACP가 바꾸기 전의 낡은 revision을 들고 있다 -- saveFile은 이걸 잡아내야 한다.
      await expect(
        service.saveFile({ path: FILE_NAME, content: "user edit based on stale revision\n", expectedRevision: initial.revision }),
      ).rejects.toMatchObject({ code: "file_conflict" });

      // 실패한 저장 시도가 디스크를 건드리지 않았는지(ACP 내용이 그대로인지, 부분 쓰기가 없는지) 확인.
      await expect(readFile(path.join(root, FILE_NAME), "utf8")).resolves.toBe(ACP_CONTENT);
    } finally {
      await service.close();
    }
  }, 15_000);

  it("두 쓰기가 실제로 거의 동시에 겹쳐도(Promise.all) 디스크 내용은 항상 완전한 값 중 하나이고 중간에 깨진 상태로 관측되지 않는다", async () => {
    const root = await mkdtemp(path.join(os.tmpdir(), "concurrent-race-"));
    await writeFile(path.join(root, FILE_NAME), "initial\n", "utf8");
    const service = await FileService.create(root);
    const userContent = "user edit racing acp\n";
    const knownValues = new Set(["initial\n", userContent, ACP_CONTENT]);

    let stopPolling = false;
    const observed = new Set<string>();
    const poll = (async () => {
      while (!stopPolling) {
        try {
          observed.add(await readFile(path.join(root, FILE_NAME), "utf8"));
        } catch {
          // 파일이 rename 도중 아주 짧게 안 보일 수 있다 -- 무시하고 계속 폴링한다.
        }
        await new Promise((resolve) => setImmediate(resolve));
      }
    })();

    try {
      const initial = await service.readFile(FILE_NAME);
      const [acpResult, saveOutcome] = await Promise.all([
        newAdapter().run({
          requestId: "concurrent-race",
          workspaceId: "w1",
          task: "평범한 작업",
          projectPath: root,
          signal: new AbortController().signal,
        }),
        service
          .saveFile({ path: FILE_NAME, content: userContent, expectedRevision: initial.revision })
          .then((value) => ({ ok: true as const, value }))
          .catch((error: unknown) => ({ ok: false as const, error })),
      ]);
      stopPolling = true;
      await poll;

      expect(acpResult.ok).toBe(true);
      // 사용자 저장이 성공했든 file_conflict로 막혔든, 둘 다 유효한 결과다 -- 중요한 건 어느 쪽이든
      // 디스크가 깨지지 않는다는 것.
      if (!saveOutcome.ok) {
        expect(saveOutcome.error).toBeInstanceOf(FileServiceError);
        expect((saveOutcome.error as FileServiceError).code).toBe("file_conflict");
      }

      // 최종(정착된) 상태는 항상 완전한 값 중 하나여야 한다 -- 절대 빈 문자열이나 뒤섞인 내용이면 안 된다.
      const final = await readFile(path.join(root, FILE_NAME), "utf8");
      expect(knownValues.has(final)).toBe(true);

      // 폴링 동안 관측된 스냅샷도 전부 완전한 값이거나, ACP 쪽이 직접 truncate+write하는 순간의
      // 빈 문자열(FileService의 원자적 저장을 거치지 않는 외부 프로세스 특유의 현상, 우리 쪽 결함이
      // 아님)이어야 한다 -- 절대 두 값이 섞인 부분 문자열이면 안 된다("user"와 "acp"가 섞인 내용 등).
      for (const snapshot of observed) {
        const isKnownComplete = knownValues.has(snapshot);
        const isAcpTruncationWindow = snapshot === "";
        expect(isKnownComplete || isAcpTruncationWindow).toBe(true);
      }
    } finally {
      stopPolling = true;
      await poll;
      await service.close();
    }
  }, 15_000);
});
