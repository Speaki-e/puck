import { describe, expect, it } from "vitest";
import { SessionRouter } from "./session-router.js";

function deferred<T = void>(): { promise: Promise<T>; resolve: (value: T) => void } {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((res) => { resolve = res; });
  return { promise, resolve };
}

describe("SessionRouter", () => {
  it("동일 세션의 입력은 순차 실행한다", async () => {
    const router = new SessionRouter();
    const order: number[] = [];
    const first = deferred();
    const runFirst = router.route("w1", "s1", async () => {
      order.push(1);
      await first.promise;
      order.push(2);
    });
    const runSecond = router.route("w1", "s1", async () => {
      order.push(3);
    });
    await new Promise((resolve) => setTimeout(resolve, 20));
    expect(order).toEqual([1]);
    first.resolve();
    await Promise.all([runFirst, runSecond]);
    expect(order).toEqual([1, 2, 3]);
  });

  it("서로 다른 세션은 병렬 실행한다", async () => {
    const router = new SessionRouter();
    const gate = deferred();
    const order: string[] = [];
    const runA = router.route("w1", "a", async () => {
      order.push("a-start");
      await gate.promise;
      order.push("a-end");
    });
    const runB = router.route("w1", "b", async () => {
      order.push("b-start");
      order.push("b-end");
    });
    await runB;
    expect(order).toEqual(["a-start", "b-start", "b-end"]);
    gate.resolve();
    await runA;
    expect(order).toEqual(["a-start", "b-start", "b-end", "a-end"]);
  });

  it("다른 워크스페이스의 같은 session_id는 서로 막지 않는다", async () => {
    const router = new SessionRouter();
    const gate = deferred();
    const order: string[] = [];
    const runW1 = router.route("w1", "default", async () => {
      order.push("w1-start");
      await gate.promise;
      order.push("w1-end");
    });
    const runW2 = router.route("w2", "default", async () => {
      order.push("w2-start");
    });
    await runW2;
    expect(order).toContain("w2-start");
    expect(order).not.toContain("w1-end");
    gate.resolve();
    await runW1;
  });

  it("먼저 들어온 작업이 실패해도 다음 작업은 실행된다", async () => {
    const router = new SessionRouter();
    const order: string[] = [];
    const first = router.route("w1", "s1", async () => {
      order.push("first");
      throw new Error("boom");
    });
    const second = router.route("w1", "s1", async () => {
      order.push("second");
    });
    await expect(first).rejects.toThrow("boom");
    await second;
    expect(order).toEqual(["first", "second"]);
  });

  it("queueLength는 대기 중인 작업 수를 보고한다", async () => {
    const router = new SessionRouter();
    const gate = deferred();
    expect(router.queueLength("w1", "s1")).toBe(0);
    const run1 = router.route("w1", "s1", () => gate.promise as Promise<void>);
    const run2 = router.route("w1", "s1", async () => undefined);
    expect(router.queueLength("w1", "s1")).toBe(2);
    gate.resolve();
    await Promise.all([run1, run2]);
    expect(router.queueLength("w1", "s1")).toBe(0);
  });
});
