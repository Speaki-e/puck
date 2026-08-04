import { beforeEach, describe, expect, it } from "vitest";
import { DRAFT_TTL_MS, draftKey, sweepExpiredDrafts, type StoredDrafts } from "./draft-store";

/**
 * vitest.config.ts는 environment: "node"라 DOM/localStorage가 없다 -- App.tsx가 브라우저에서
 * 쓰는 것과 같은 최소 인터페이스(getItem/setItem/removeItem/키 열거)만 흉내 낸 스텁으로 충분하다.
 */
class MemoryStorage {
  private readonly store = new Map<string, string>();

  getItem(key: string): string | null {
    return this.store.has(key) ? this.store.get(key)! : null;
  }

  setItem(key: string, value: string): void {
    this.store.set(key, value);
  }

  removeItem(key: string): void {
    this.store.delete(key);
  }

  keys(): string[] {
    return [...this.store.keys()];
  }
}

function draft(overrides: Partial<StoredDrafts> = {}): StoredDrafts {
  return {
    projectPath: "/proj",
    expiresAt: Date.now() + DRAFT_TTL_MS,
    tabs: [{ path: "a.ts", content: "x", revision: "r1" }],
    ...overrides,
  };
}

describe("sweepExpiredDrafts", () => {
  let storage: MemoryStorage;

  beforeEach(() => {
    storage = new MemoryStorage();
    // localStorage 키 열거(Object.keys(localStorage))는 브라우저에서 인덱스 프로퍼티로 동작한다 --
    // 스텁에서는 Proxy로 흉내 내 실제 App.tsx 코드 경로(Object.keys)와 동일하게 검증한다.
    const proxied = new Proxy(storage, {
      ownKeys: (target) => target.keys(),
      getOwnPropertyDescriptor: () => ({ enumerable: true, configurable: true }),
    });
    Object.defineProperty(globalThis, "localStorage", { value: proxied, configurable: true });
  });

  it("만료된 draft는 지우고, 아직 유효한 draft는 남긴다", () => {
    storage.setItem(draftKey("/expired"), JSON.stringify(draft({ projectPath: "/expired", expiresAt: Date.now() - 1_000 })));
    storage.setItem(draftKey("/fresh"), JSON.stringify(draft({ projectPath: "/fresh" })));

    sweepExpiredDrafts();

    expect(storage.getItem(draftKey("/expired"))).toBeNull();
    expect(storage.getItem(draftKey("/fresh"))).not.toBeNull();
  });

  it("손상된(JSON이 아니거나 expiresAt이 없는) draft도 정리한다", () => {
    storage.setItem(draftKey("/broken-json"), "{not json");
    storage.setItem(draftKey("/no-expiry"), JSON.stringify({ projectPath: "/no-expiry", tabs: [] }));

    sweepExpiredDrafts();

    expect(storage.getItem(draftKey("/broken-json"))).toBeNull();
    expect(storage.getItem(draftKey("/no-expiry"))).toBeNull();
  });

  it("workspace:drafts: 접두어가 아닌 키는 건드리지 않는다", () => {
    storage.setItem("some:other:key", "value");
    sweepExpiredDrafts();
    expect(storage.getItem("some:other:key")).toBe("value");
  });

  it("한 번 열고 다시 열지 않은 프로젝트의 draft도(현재 활성 프로젝트와 무관하게) 정리한다", () => {
    // 이 케이스가 기존 lazy 정리(같은 프로젝트를 다시 열 때만 청소)의 사각지대였다 --
    // sweepExpiredDrafts는 activeProjectPath 인자를 받지 않고 전체를 훑어야 한다.
    storage.setItem(draftKey("/never-reopened"), JSON.stringify(draft({ projectPath: "/never-reopened", expiresAt: Date.now() - 1 })));
    sweepExpiredDrafts();
    expect(storage.getItem(draftKey("/never-reopened"))).toBeNull();
  });
});
