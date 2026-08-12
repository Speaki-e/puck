// 대규모 프로젝트 파일 트리 성능 벤치마크(공통 W1, TODO.md "대규모 프로젝트 파일 트리 성능 및
// 제외 패턴 정책"). vitest 회귀 테스트(src/main/file-service-large-tree.test.ts)는 CI 러너 편차를
// 고려해 느슨한 상한만 지키지만, 이 스크립트는 실제 규모(기본 수만 개 파일)에서 DEFAULT_IGNORES
// 적용 여부에 따른 listTree() 체감 시간을 재서 docs/file-tree-performance.md에 적을 실측치를 낸다.
// 실행: node scripts/benchmark-file-tree.mjs [파일수]
import { mkdir, mkdtemp, rm, writeFile, readdir, lstat, realpath } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

const DEFAULT_IGNORES = new Set([
  ".git", "node_modules", "dist", "dist-main", "release",
  ".next", "build", "target", ".venv", "venv", "__pycache__",
  ".pytest_cache", ".cache", "coverage", ".turbo", "Pods", ".build", "DerivedData",
]);

const targetSourceFiles = Number(process.argv[2] ?? 20_000);
const filesPerDir = 100;
const sourceDirs = Math.ceil(targetSourceFiles / filesPerDir);
// node_modules는 흔히 소스 코드보다 훨씬 크다 -- 3배 규모로 만들어 "제외 안 하면 얼마나 손해인지" 보여준다.
const nodeModulesDirs = sourceDirs * 3;

async function buildFixture(root) {
  for (let d = 0; d < sourceDirs; d += 1) {
    const dir = path.join(root, "src", `module-${d}`);
    await mkdir(dir, { recursive: true });
    await Promise.all(
      Array.from({ length: filesPerDir }, (_, i) => writeFile(path.join(dir, `file-${i}.ts`), "export {};\n", "utf8")),
    );
  }
  const nodeModules = path.join(root, "node_modules");
  for (let d = 0; d < nodeModulesDirs; d += 1) {
    const dir = path.join(nodeModules, `dep-${d}`);
    await mkdir(dir, { recursive: true });
    await Promise.all(
      Array.from({ length: filesPerDir }, (_, i) => writeFile(path.join(dir, `file-${i}.js`), "module.exports={};\n", "utf8")),
    );
  }
}

// file-service.ts의 readDirectory()와 동일한 순서/필터링 로직(심볼릭 링크 realpath 확인 포함)을
// 그대로 재현한다 -- FileService 클래스를 직접 import하지 않는 건 이 스크립트가 TS 빌드 산출물에
// 의존하지 않고 항상 바로 실행되게 하기 위함이다.
async function walk(root, directory, applyIgnores) {
  let fileCount = 0;
  const entries = await readdir(directory, { withFileTypes: true });
  for (const entry of entries) {
    if (applyIgnores && DEFAULT_IGNORES.has(entry.name)) continue;
    const candidate = path.join(directory, entry.name);
    const info = await lstat(candidate);
    if (info.isSymbolicLink()) {
      try {
        await realpath(candidate);
      } catch {
        continue;
      }
    } else if (info.isDirectory()) {
      fileCount += await walk(root, candidate, applyIgnores);
    } else if (info.isFile()) {
      fileCount += 1;
    }
  }
  return fileCount;
}

async function time(label, fn) {
  const startedAt = performance.now();
  const result = await fn();
  const elapsedMs = performance.now() - startedAt;
  console.log(`${label}: ${elapsedMs.toFixed(1)}ms (${result}개 파일)`);
  return elapsedMs;
}

const root = await mkdtemp(path.join(os.tmpdir(), "workspace-filetree-bench-"));
try {
  console.log(`fixture 생성 중: 소스 ${sourceDirs * filesPerDir}개, node_modules ${nodeModulesDirs * filesPerDir}개...`);
  await buildFixture(root);

  const withIgnores = await time("DEFAULT_IGNORES 적용 (listTree 실제 동작)", () => walk(root, root, true));
  const withoutIgnores = await time("DEFAULT_IGNORES 미적용 (node_modules까지 전부 순회)", () => walk(root, root, false));

  console.log(`\n제외 패턴으로 ${(withoutIgnores / withIgnores).toFixed(1)}배 빠름`);
} finally {
  await rm(root, { recursive: true, force: true });
}
