/**
 * ai-module A2 — CLI 테스트용 mock 실행기.
 *
 * 아무것도 실제로 실행하지 않는다. 디스패치 라우팅(도구 → executor kind →
 * 실행기)이 제대로 도는지 확인하기 위한 것이므로, 실행기 자리에 무엇이
 * 오든 클라이언트 쪽 코드가 달라지지 않는다는 것만 보이면 된다.
 *
 * 실제 구현은 pet-app 소켓 프록시(petAppProxy)와 workspace 인프로세스
 * 실행기(editorLocal)가 각각 맡는다.
 */
import type { JSONValue } from "@speaki-e/protocol/src/index.js";

import type { ToolExecutionResult, ToolExecutor } from "./types.js";

/** pet-app 담당 도구(launch_app, run_shell, point_at 등)의 mock 실행기. */
export const mockPetApp: ToolExecutor = {
  async execute(tool, args) {
    return mockResult(tool, args);
  },
};

/** workspace 담당 도구(code_editor, open_in_editor, read_file)의 mock 실행기. */
export const mockWorkspace: ToolExecutor = {
  async execute(tool, args) {
    return mockResult(tool, args);
  },
};

/**
 * 가짜 결과를 만든다.
 *
 * 기본값은 data: null이지만, 모델이 결과를 인용해야 답변이 성립하는 도구는
 * 레지스트리의 responseNote 형식에 맞춘 가짜 데이터를 준다 — 그래야 "pid
 * 12345로 실행됐어" 같은 최종 답변까지 경로가 이어지는지 확인할 수 있다.
 */
function mockResult(tool: string, args: JSONValue): ToolExecutionResult {
  const detail = `(mock) ${tool}: ${JSON.stringify(args)}`;

  switch (tool) {
    // responseNote: { pid: number }
    case "launch_app":
      return { ok: true, data: { pid: 12345 }, detail };
    // responseNote: { stdout: string, stderr: string, exit_code: number }
    case "run_shell":
      return { ok: true, data: { stdout: "(mock output)", stderr: "", exit_code: 0 }, detail };
    default:
      return { ok: true, data: null, detail };
  }
}
