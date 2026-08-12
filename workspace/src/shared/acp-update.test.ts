import path from "node:path";
import { describe, expect, it } from "vitest";
import { workingPathsFromUpdate } from "./acp-update.js";

describe("workingPathsFromUpdate", () => {
  it("프로젝트 내부 ACP location만 상대 경로로 정규화한다", () => {
    const root = path.resolve("project");
    expect(workingPathsFromUpdate(root, { locations: [
      { path: path.join(root, "src", "App.tsx") },
      { path: path.join(root, "src", "App.tsx") },
      { path: path.resolve("outside.txt") },
    ] })).toEqual(["src/App.tsx"]);
  });
});
