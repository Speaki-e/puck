import { describe, expect, it } from "vitest";
import { JsonlParser } from "./jsonl-parser.js";

describe("JsonlParser", () => {
  it("분할·결합된 UTF-8 JSON Lines를 파싱한다", () => {
    const parser = new JsonlParser();
    const encoder = new TextEncoder();
    expect(parser.push(encoder.encode('{"type":"a","text":"안'))).toEqual([]);
    expect(parser.push(encoder.encode('녕"}\n{"type":"b"}\n'))).toEqual([
      { type: "a", text: "안녕" },
      { type: "b" },
    ]);
  });

  it("잘못된 JSON은 호출자가 처리할 수 있도록 예외를 낸다", () => {
    const parser = new JsonlParser();
    expect(() => parser.push(new TextEncoder().encode("{bad}\n"))).toThrow();
  });
});
