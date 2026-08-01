import { describe, expect, it } from "vitest";
import { editorReducer, isDirty, type EditorState } from "./editor-state";

const file = { path: "src/main.ts", content: "one", revision: "r1", readOnly: false, size: 3 };

describe("editorReducer", () => {
  it("편집과 저장 상태를 분리한다", () => {
    let state: EditorState = { tabs: [] };
    state = editorReducer(state, { type: "open", file });
    state = editorReducer(state, { type: "edit", path: file.path, content: "two" });
    expect(isDirty(state.tabs[0]!)).toBe(true);
    state = editorReducer(state, { type: "saved", path: file.path, revision: "r2", size: 3 });
    expect(isDirty(state.tabs[0]!)).toBe(false);
  });

  it("외부 변경 충돌을 표시하고 명시적으로 해제한다", () => {
    let state: EditorState = { tabs: [] };
    state = editorReducer(state, { type: "open", file });
    state = editorReducer(state, { type: "diskChanged", path: file.path });
    expect(state.tabs[0]?.diskChanged).toBe(true);
    state = editorReducer(state, { type: "keepMine", path: file.path });
    expect(state.tabs[0]?.diskChanged).toBe(false);
  });
});
