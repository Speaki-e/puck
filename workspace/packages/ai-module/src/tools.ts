/**
 * ai-module A2 — protocol 도구 레지스트리 → Anthropic API 도구 정의 변환.
 *
 * 도구 목록은 이제 protocol의 TOOL_REGISTRY가 유일한 출처다. 이 파일은
 * 레지스트리를 Anthropic의 tools 파라미터 형식으로 옮기기만 하고, 도구를
 * 추가/삭제/수정하지 않는다 — 도구가 늘거나 스펙이 바뀌면 protocol만 고친다.
 */
import type Anthropic from "@anthropic-ai/sdk";
import { TOOL_REGISTRY, type ToolDefinition, type ToolParam } from "@speaki-e/protocol";

/** 이름 → 정의 조회용 인덱스. 레지스트리는 상수이므로 모듈 로드 시 한 번만 만든다. */
const BY_NAME: ReadonlyMap<string, ToolDefinition> = new Map(
  TOOL_REGISTRY.map((def) => [def.name, def]),
);

/**
 * TOOL_REGISTRY를 Anthropic API의 tools 파라미터 형식으로 변환한다.
 *
 * description은 모델이 "언제" 이 도구를 부를지 판단하는 유일한 근거이므로
 * 레지스트리 값을 그대로 넘긴다 — 여기서 임의로 다듬지 않는다.
 * executor/approval/timeoutSec는 API로 보내지 않는다. 모델이 알아야 할 정보가
 * 아니라 우리 쪽 디스패치/승인 라우팅용 메타데이터다.
 */
export function toAnthropicTools(): Anthropic.Tool[] {
  return TOOL_REGISTRY.map((def) => ({
    name: def.name,
    description: def.description,
    input_schema: {
      type: "object" as const,
      properties: Object.fromEntries(
        def.params.map((param) => [
          param.name,
          { type: param.type, description: param.description },
        ]),
      ),
      // 필수 파라미터가 없으면 required 키 자체를 넣지 않는다 (빈 배열은 무의미).
      ...requiredNames(def.params),
    },
  }));
}

/** 모델이 호출한 이름에 대응하는 레지스트리 정의. 없으면 undefined (= unknown_tool). */
export function getToolDef(name: string): ToolDefinition | undefined {
  return BY_NAME.get(name);
}

/**
 * 레지스트리 전체를 레지스트리 순서 그대로 반환한다. (CLI /tools 출력용)
 * protocol import 경로를 이 파일 하나로 묶어두기 위한 통로다.
 */
export function allTools(): readonly ToolDefinition[] {
  return TOOL_REGISTRY;
}

/**
 * 모델이 보낸 입력이 레지스트리 스펙에 맞는지 검사한다.
 *
 * strict 스키마를 걸지 않았으므로 모델은 필수 필드를 빠뜨리거나 타입이 다른
 * 값을 보낼 수 있다. 그대로 실행기로 넘기면 "undefined 앱 실행" 같은 결과가
 * 나오므로 여기서 걸러 invalid_input으로 되돌려준다.
 *
 * 참고: launch_app의 app_name/bundle_id처럼 "둘 중 하나는 필수" 규칙은
 * ToolParam으로 표현되지 않는다(둘 다 required:false). 그런 교차 조건은
 * 실행기 쪽 책임으로 남긴다.
 *
 * @returns 문제가 된 필드 이름. 이상이 없으면 undefined.
 */
export function validateArgs(def: ToolDefinition, args: unknown): string | undefined {
  // 파라미터가 없는 도구는 모델이 {}를 보내든 아무것도 안 보내든 통과시킨다.
  if (def.params.length === 0) return undefined;

  const record = args !== null && typeof args === "object" ? (args as Record<string, unknown>) : undefined;
  if (record === undefined) return def.params.find((p) => p.required)?.name;

  for (const param of def.params) {
    const value = record[param.name];
    if (value === undefined || value === null) {
      if (param.required) return param.name;
      continue;
    }
    if (!matchesType(value, param.type)) return param.name;
    // 빈 문자열은 값을 안 준 것과 같다 — 필수 파라미터라면 실패로 본다.
    if (param.required && param.type === "string" && (value as string).trim() === "") {
      return param.name;
    }
  }
  return undefined;
}

/** ToolParam.type(JSON 값 종류)과 실제 값이 맞는지 확인한다. */
function matchesType(value: unknown, type: ToolParam["type"]): boolean {
  switch (type) {
    case "string":
      return typeof value === "string";
    case "number":
      return typeof value === "number" && Number.isFinite(value);
    case "boolean":
      return typeof value === "boolean";
    case "object":
      return typeof value === "object" && !Array.isArray(value);
  }
}

function requiredNames(params: readonly ToolParam[]): { required?: string[] } {
  const names = params.filter((param) => param.required).map((param) => param.name);
  return names.length > 0 ? { required: names } : {};
}
