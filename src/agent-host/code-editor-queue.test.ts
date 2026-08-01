import { describe, expect, it, vi } from "vitest";
import { CodeEditorQueue, QueueCancelledError } from "./code-editor-queue.js";

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
}

describe("CodeEditorQueue", () => {
  it("같은 워크스페이스 작업은 순차 실행한다", async () => {
    const queue = new CodeEditorQueue();
    const gate = deferred<string>();
    const first = vi.fn(() => gate.promise);
    const second = vi.fn(async () => "second");
    const p1 = queue.enqueue({ requestId: "r1", workspaceId: "w1", execute: first });
    const p2 = queue.enqueue({ requestId: "r2", workspaceId: "w1", execute: second });
    await Promise.resolve();
    expect(first).toHaveBeenCalledOnce();
    expect(second).not.toHaveBeenCalled();
    expect(queue.position("r2")).toBe(1);
    gate.resolve("first");
    await expect(p1).resolves.toBe("first");
    await expect(p2).resolves.toBe("second");
  });

  it("다른 워크스페이스 작업은 병렬 실행한다", async () => {
    const queue = new CodeEditorQueue();
    const first = vi.fn(async () => "a");
    const second = vi.fn(async () => "b");
    await Promise.all([
      queue.enqueue({ requestId: "r1", workspaceId: "w1", execute: first }),
      queue.enqueue({ requestId: "r2", workspaceId: "w2", execute: second }),
    ]);
    expect(first).toHaveBeenCalledOnce();
    expect(second).toHaveBeenCalledOnce();
  });

  it("대기 중 취소 작업은 실행하지 않는다", async () => {
    const queue = new CodeEditorQueue();
    const gate = deferred<string>();
    const waiting = vi.fn(async () => "unexpected");
    const first = queue.enqueue({ requestId: "r1", workspaceId: "w1", execute: () => gate.promise });
    const second = queue.enqueue({ requestId: "r2", workspaceId: "w1", execute: waiting });
    expect(queue.cancel("r2")).toBe(true);
    await expect(second).rejects.toBeInstanceOf(QueueCancelledError);
    expect(waiting).not.toHaveBeenCalled();
    gate.resolve("done");
    await first;
  });
});
