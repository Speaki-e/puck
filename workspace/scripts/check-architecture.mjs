import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const ROOT = path.resolve("src");
const SOURCE_EXTENSIONS = new Set([".ts", ".tsx", ".cts"]);
const IMPORT_PATTERNS = [
  /(?:from\s+|import\s*\()(["'])(\.[^"']+)\1/g,
  /(?:^|[;\n])\s*import\s+(["'])(\.[^"']+)\1/gm,
];

async function collectFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const target = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await collectFiles(target));
    else if (SOURCE_EXTENSIONS.has(path.extname(entry.name)) && !entry.name.includes(".test.")) files.push(target);
  }
  return files;
}

function normalizeImport(source, specifier, knownFiles) {
  const unresolved = path.resolve(path.dirname(source), specifier);
  const withoutJs = path.extname(unresolved) === ".js" ? unresolved.slice(0, -3) : unresolved;
  const candidates = [
    unresolved,
    withoutJs,
    `${withoutJs}.ts`,
    `${withoutJs}.tsx`,
    `${withoutJs}.cts`,
    path.join(withoutJs, "index.ts"),
    path.join(withoutJs, "index.tsx"),
  ];
  return candidates.find((candidate) => knownFiles.has(candidate));
}

function layer(file) {
  return path.relative(ROOT, file).split(path.sep)[0];
}

function relative(file) {
  return path.relative(process.cwd(), file).split(path.sep).join("/");
}

function findCycles(graph) {
  const visited = new Set();
  const active = new Set();
  const stack = [];
  const cycles = [];

  function visit(node) {
    if (active.has(node)) {
      const start = stack.indexOf(node);
      cycles.push([...stack.slice(start), node]);
      return;
    }
    if (visited.has(node)) return;
    visited.add(node);
    active.add(node);
    stack.push(node);
    for (const dependency of graph.get(node) ?? []) visit(dependency);
    stack.pop();
    active.delete(node);
  }

  for (const node of graph.keys()) visit(node);
  return cycles;
}

const files = await collectFiles(ROOT);
const knownFiles = new Set(files);
const graph = new Map(files.map((file) => [file, []]));
const violations = [];

for (const file of files) {
  const source = await readFile(file, "utf8");
  const dependencies = new Set();
  for (const pattern of IMPORT_PATTERNS) {
    for (const match of source.matchAll(pattern)) {
      const dependency = normalizeImport(file, match[2], knownFiles);
      if (dependency) dependencies.add(dependency);
    }
  }

  for (const dependency of dependencies) {
    graph.get(file).push(dependency);

    const from = layer(file);
    const to = layer(dependency);
    const forbidden = (
      (from === "shared" && to !== "shared")
      || (from === "renderer" && ["main", "agent-host", "mocks"].includes(to))
      || (from === "agent-host" && ["main", "renderer"].includes(to))
      || (from === "mocks" && ["main", "renderer", "agent-host"].includes(to))
      || (from === "main" && to === "renderer")
      || (from === "main" && to === "mocks")
    );
    if (forbidden) violations.push(`${relative(file)} must not import ${relative(dependency)}`);

    if (from === "agent-host" && to === "mocks" && relative(file) !== "src/agent-host/agent-runner.ts") {
      violations.push(`${relative(file)} imports mocks outside the temporary ai-module boundary`);
    }
  }
}

for (const cycle of findCycles(graph)) {
  violations.push(`import cycle: ${cycle.map(relative).join(" -> ")}`);
}

const sizeLimits = new Map([
  [path.join(ROOT, "main", "index.ts"), 40],
  [path.join(ROOT, "renderer", "App.tsx"), 400],
]);
for (const [file, limit] of sizeLimits) {
  const lines = (await readFile(file, "utf8")).split(/\r?\n/).length;
  if (lines > limit) violations.push(`${relative(file)} has ${lines} lines (limit: ${limit})`);
}

if (violations.length) {
  console.error("Architecture check failed:\n");
  for (const violation of violations) console.error(`- ${violation}`);
  process.exitCode = 1;
} else {
  const edges = [...graph.values()].reduce((total, dependencies) => total + dependencies.length, 0);
  console.log(`Architecture check passed (${files.length} modules, ${edges} internal imports, no cycles).`);
}
