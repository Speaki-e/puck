import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { FileService } from "./file-service.js";

/**
 * 대규모 프로젝트 파일 트리 성능 및 제외 패턴 정책(공통 W1). 두 가지를 확인한다:
 * 1. DEFAULT_IGNORES가 실제로 흔한 대형 빌드/의존성/캐시 디렉터리를 걸러내는지(이 디렉터리들은
 *    파일 수가 수만~수십만 개까지 갈 수 있어, 걸러내지 못하면 listTree()가 그 안까지 다 훑는다).
 * 2. 걸러진 뒤 남은 파일이 수천 개 규모일 때 listTree()가 감당할 수 있는 시간 안에 끝나는지.
 * CI 러너 성능 편차를 고려해 임계값은 넉넉하게 잡는다(정확한 수치는
 * docs/file-tree-performance.md의 로컬 벤치마크 스크립트 결과를 참고) -- 여기서는 "터무니없이
 * 느려지지 않았는지"만 회귀 방지용으로 지킨다.
 */
describe("FileService 대규모 트리", () => {
  it("DEFAULT_IGNORES에 포함된 대형 디렉터리는 listTree/watch 양쪽에서 제외된다", async () => {
    const root = await mkdtemp(path.join(os.tmpdir(), "workspace-file-ignores-"));
    const ignoredDirs = [
      "node_modules", ".git", "dist", "dist-main", "release",
      ".next", "build", "target", ".venv", "venv", "__pycache__",
      ".pytest_cache", ".cache", "coverage", ".turbo", "Pods", ".build", "DerivedData",
    ];
    for (const dir of ignoredDirs) {
      await mkdir(path.join(root, dir), { recursive: true });
      await writeFile(path.join(root, dir, "should-not-appear.txt"), "x", "utf8");
    }
    await mkdir(path.join(root, "src"));
    await writeFile(path.join(root, "src", "main.ts"), "export const value = 1;\n", "utf8");

    const service = await FileService.create(root);
    const tree = await service.listTree();

    const names = tree.map((entry) => entry.name);
    for (const dir of ignoredDirs) expect(names).not.toContain(dir);
    expect(names).toContain("src");

    function flatten(entries: typeof tree): string[] {
      return entries.flatMap((entry) => [entry.path, ...(entry.children ? flatten(entry.children) : [])]);
    }
    const allPaths = flatten(tree);
    expect(allPaths.some((p) => p.includes("should-not-appear.txt"))).toBe(false);
    expect(allPaths).toContain("src/main.ts");
  });

  it("제외 후 남은 파일이 수백 개 규모여도 listTree가 합리적인 시간 안에 끝난다", async () => {
    const root = await mkdtemp(path.join(os.tmpdir(), "workspace-file-perf-"));
    // vitest는 테스트 파일별로 워커를 병렬 실행한다 -- 여기서 수천 개 파일을 만들면 `pnpm test`
    // 전체 실행 시 다른 파일(특히 실제 자식 프로세스를 띄우는 ACP 관련 테스트)과 자원 경합이 커져
    // CI/로컬 모두에서 이 테스트 자체가 아니라 다른 테스트를 타임아웃시키는 부작용이 있었다.
    // 실제 대규모 수치는 scripts/benchmark-file-tree.mjs로 별도로 재고, 여기서는 회귀 방지용으로
    // 가벼운 규모만 확인한다.
    const dirCount = 15;
    const filesPerDir = 15; // 총 225개 파일 + node_modules 안의 파일(전부 제외 대상)
    for (let d = 0; d < dirCount; d += 1) {
      const dir = path.join(root, `pkg-${d}`);
      await mkdir(dir, { recursive: true });
      await Promise.all(
        Array.from({ length: filesPerDir }, (_, i) => writeFile(path.join(dir, `file-${i}.ts`), "export {};\n", "utf8")),
      );
    }
    // node_modules 안에도 대량 파일을 심어 "제외가 안 됐다면 여기까지 다 훑느라 훨씬 느려진다"를
    // 실질적으로 검증한다.
    const nodeModules = path.join(root, "node_modules");
    for (let d = 0; d < dirCount; d += 1) {
      const dir = path.join(nodeModules, `dep-${d}`);
      await mkdir(dir, { recursive: true });
      await Promise.all(
        Array.from({ length: filesPerDir }, (_, i) => writeFile(path.join(dir, `file-${i}.js`), "module.exports = {};\n", "utf8")),
      );
    }

    const service = await FileService.create(root);
    const startedAt = Date.now();
    const tree = await service.listTree();
    const elapsedMs = Date.now() - startedAt;

    expect(tree.some((entry) => entry.name === "node_modules")).toBe(false);
    // 넉넉한 상한(CI 러너 편차 및 vitest 병렬 워커 간 자원 경합 고려) -- 로컬 개발 환경에서
    // 단독 실행하면 훨씬 빠르게 끝난다.
    expect(elapsedMs).toBeLessThan(15_000);
  }, 30_000);
});
