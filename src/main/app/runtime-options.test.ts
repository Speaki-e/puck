import { describe, expect, it } from "vitest";
import { parseRuntimeOptions } from "./runtime-options.js";

describe("parseRuntimeOptions", () => {
  it("parses Workspace flags without depending on process.argv", () => {
    expect(parseRuntimeOptions([
      "electron",
      ".",
      "--headless",
      "--project",
      "/tmp/project",
      "--bridge-socket",
      "/tmp/bridge.sock",
    ])).toEqual({
      headless: true,
      projectPath: "/tmp/project",
      bridgeSocket: "/tmp/bridge.sock",
    });
  });

  it("does not consume the next flag as a value", () => {
    expect(parseRuntimeOptions(["electron", ".", "--project", "--headless"]))
      .toEqual({ headless: true, projectPath: undefined, bridgeSocket: undefined });
  });
});
