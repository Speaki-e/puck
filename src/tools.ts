/**
 * ai-module A1 — mock 도구 정의 + mock 실행기.
 *
 * TODO(A2): 아래 도구 정의는 임시로 하드코딩한 것이다.
 *   A2에서 protocol 패키지 import로 교체 예정 —
 *   교체 시 TOOLS 배열만 갈아끼우면 되도록 executeTool()의 디스패치는
 *   도구 이름(문자열) 기준으로만 분기하게 유지한다.
 *
 * 이 단계의 실행기는 아무것도 실제로 실행하지 않는다. run_shell도 가짜 결과만
 * 돌려준다 — 승인 게이트는 A6에서 붙인다.
 */
import type Anthropic from "@anthropic-ai/sdk";

/** 도구 실행 결과. 성공/실패가 판별 가능한 유니온이어야 tool_result의 is_error를 결정할 수 있다. */
export type ToolExecutionResult =
  | { ok: true; detail: string }
  | { ok: false; error: string };

/**
 * Anthropic API의 tools 파라미터로 그대로 전달되는 도구 정의.
 *
 * description은 모델이 "언제" 이 도구를 부를지 판단하는 유일한 근거다.
 * 무엇을 하는지뿐 아니라 호출 조건까지 적어야 잡담에 도구를 끌어다 쓰지 않는다.
 */
export const TOOLS: Anthropic.Tool[] = [
  {
    name: "launch_app",
    description:
      "지정한 앱을 사용자의 컴퓨터에서 실행한다. 사용자가 특정 앱을 켜 달라고 요청했을 때 호출한다.",
    input_schema: {
      type: "object",
      properties: {
        app_name: {
          type: "string",
          description: "실행할 앱 이름 (예: Safari, 메모)",
        },
      },
      required: ["app_name"],
    },
  },
  {
    name: "get_weather",
    description:
      "지정한 도시의 현재 날씨를 조회한다. 사용자가 날씨나 기온을 물었을 때 호출한다.",
    input_schema: {
      type: "object",
      properties: {
        city: {
          type: "string",
          description: "날씨를 조회할 도시 이름 (예: 서울, 부산)",
        },
      },
      required: ["city"],
    },
  },
  {
    name: "run_shell",
    description:
      "셸 명령을 실행한다. 파일 조작이나 시스템 작업처럼 명령줄로만 처리할 수 있는 요청에 호출한다.",
    input_schema: {
      type: "object",
      properties: {
        command: {
          type: "string",
          description: "실행할 셸 명령 전체",
        },
      },
      required: ["command"],
    },
  },
];

/**
 * mock 실행기. 실제로는 아무것도 실행하지 않고 가짜 결과를 반환한다.
 *
 * 예외를 던지지 않는다 — 모든 실패는 { ok: false } 결과로 표현된다.
 * 호출부가 모든 tool_use id에 대해 반드시 tool_result를 만들어야 하기 때문이다.
 *
 * @param name 모델이 호출한 도구 이름
 * @param args 파싱된 도구 입력. 모델이 보내는 값이므로 스키마를 신뢰하지 않고 검사한다.
 */
export function executeTool(name: string, args: unknown): ToolExecutionResult {
  switch (name) {
    case "launch_app": {
      const appName = readString(args, "app_name");
      if (appName === undefined) return invalidInput("app_name");
      return { ok: true, detail: `${appName} 실행됨 (mock)` };
    }
    case "get_weather": {
      const city = readString(args, "city");
      if (city === undefined) return invalidInput("city");
      return { ok: true, detail: `${city}는 맑음, 24도 (mock)` };
    }
    case "run_shell": {
      const command = readString(args, "command");
      if (command === undefined) return invalidInput("command");
      return { ok: true, detail: `명령 실행됨 (mock): ${command}` };
    }
    default:
      return { ok: false, error: "unknown_tool" };
  }
}

/**
 * args에서 문자열 필드를 안전하게 꺼낸다.
 *
 * strict: true를 걸지 않았으므로 모델이 필수 필드를 빠뜨릴 수 있다.
 * 그 경우 "undefined는 맑음" 같은 결과를 만들지 않고 실패로 처리한다.
 */
function readString(args: unknown, key: string): string | undefined {
  if (typeof args !== "object" || args === null) return undefined;
  const value = (args as Record<string, unknown>)[key];
  if (typeof value !== "string" || value.trim() === "") return undefined;
  return value;
}

/** 필수 입력이 비었을 때의 실패 결과. 어떤 필드가 문제였는지 모델에게 알려 재시도할 수 있게 한다. */
function invalidInput(field: string): ToolExecutionResult {
  return { ok: false, error: `invalid_input: ${field}` };
}
