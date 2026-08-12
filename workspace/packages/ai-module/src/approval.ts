/**
 * ai-module A6 — 승인 판정 (기획서 3.3).
 *
 * "이 도구 호출에 사용자 승인이 필요한가"만 판단하는 순수 함수 모음이다.
 * 실제로 묻는 일(콜백/UI)과 실행 여부 결정은 client.ts가 한다 — 판정 로직을
 * 부수효과에서 떼어놔야 케이스별로 단위 검증이 된다.
 *
 * A2에서 모델이 "날씨 알려줘"에 curl | python3 파이프라인을 승인 없이 실행한
 * 사례가 이 파일이 존재하는 이유다.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

import type { ToolDefinition } from "@speaki-e/protocol";

/** 번들 환경에서는 파일 자산이 없을 수 있으므로 안전한 내장 기본값을 둔다. */
const DEFAULT_WHITELIST: Whitelist = {
  version: 1,
  firstTokenCommands: ["pwd", "ls", "cat", "echo", "which", "head", "tail", "wc", "date", "whoami"],
  twoTokenCommands: ["git status", "git log", "git diff", "git branch", "git show"],
};

/**
 * 셸 메타문자. 하나라도 있으면 화이트리스트와 무관하게 승인을 요구한다.
 *
 * 목적은 "ls; rm -rf ~"처럼 허용된 명령으로 시작해 다른 명령을 이어 붙이는
 * 경로를 전부 막는 것이다. 명령 연결(; & |), 리다이렉션(< >), 치환($ ` ( )),
 * 그룹/글롭({ } [ ] * ?), 히스토리·주석·이스케이프(! # \), 개행이 포함된다.
 *
 * 넉넉하게 잡는 쪽이 안전하다 — 오탐의 대가는 승인 창 한 번이고,
 * 누락의 대가는 승인 없이 실행되는 임의 명령이다.
 */
export const SHELL_METACHARACTERS = /[;&|<>$`()[\]{}*?!#\\\n\r]/;

/** whitelist.json을 읽어 들인 형태. */
export interface Whitelist {
  version: number;
  /** 첫 토큰이 완전 일치하면 통과. 뒤 인자는 자유(ls -la 등). */
  firstTokenCommands: readonly string[];
  /** 앞 두 토큰이 완전 일치해야 통과(git status 등). 첫 토큰만으로는 통과하지 않는다. */
  twoTokenCommands: readonly string[];
}

/** 화이트리스트가 없을 때의 값. 전부 승인을 요구하는, 가장 안전한 상태다. */
export const EMPTY_WHITELIST: Whitelist = {
  version: 0,
  firstTokenCommands: [],
  twoTokenCommands: [],
};

/**
 * data/whitelist.json을 읽는다.
 *
 * 실패해도 던지지 않고 빈 화이트리스트로 물러선다 — 파일이 깨졌을 때의 안전한
 * 기본값은 "전부 승인을 요구"이지 "프로세스 중단"이 아니다. 대신 왜 승인 창이
 * 늘었는지 알 수 있도록 stderr에 이유를 남긴다.
 * (prompts/system.md는 반대로 던진다. 없으면 행동 규칙 자체가 사라져 조용히
 *  위험해지기 때문이다.)
 */
export function loadWhitelist(): Whitelist {
  const candidates: string[] = [];
  const configuredRoot = process.env["SPEAKI_AI_MODULE_ROOT"];
  if (configuredRoot) candidates.push(path.resolve(configuredRoot, "data/whitelist.json"));
  try {
    if (import.meta.url) candidates.push(fileURLToPath(new URL("../data/whitelist.json", import.meta.url)));
  } catch {
    // 번들 환경에서는 아래 내장 화이트리스트를 사용한다.
  }

  for (const candidate of [...new Set(candidates)]) {
    try {
      return parseWhitelist(JSON.parse(readFileSync(candidate, "utf8")));
    } catch {
      // 다음 후보를 확인한다.
    }
  }
  return DEFAULT_WHITELIST;
}

/** JSON 값을 Whitelist로 좁힌다. 모르는 필드는 무시하고, 이상한 값은 버린다. */
export function parseWhitelist(raw: unknown): Whitelist {
  if (typeof raw !== "object" || raw === null) return EMPTY_WHITELIST;
  const record = raw as Record<string, unknown>;

  return {
    version: typeof record["version"] === "number" ? record["version"] : 0,
    firstTokenCommands: stringArray(record["first_token_commands"]),
    twoTokenCommands: stringArray(record["two_token_commands"]),
  };
}

/**
 * 이 도구 호출에 사용자 승인이 필요한가.
 *
 * @param def       protocol 레지스트리 정의. approval.kind가 1차 기준이다.
 * @param args      모델이 보낸 도구 입력. run_shell의 command 검사에만 쓰인다.
 * @param whitelist required_with_whitelist 판정에 쓰이는 허용 목록.
 */
export function needsApproval(
  def: ToolDefinition,
  args: unknown,
  whitelist: Whitelist,
): boolean {
  switch (def.approval.kind) {
    case "not_required":
      return false;
    // Claude Code(ACP)가 자체 승인 흐름을 가지고 있어 pet-app은 프롬프트를
    // 띄우지 않는다(protocol tools.ts 주석). 우리도 여기서 통과시킨다.
    case "acp_internal":
      return false;
    case "required":
      return true;
    case "required_with_whitelist":
      return !isWhitelistedCommand(readCommand(args), whitelist);
  }
}

/**
 * 화이트리스트 통과 여부. 통과 조건이 아주 좁다:
 * 메타문자가 없고, 토큰이 목록과 완전히 일치할 때만 true.
 */
export function isWhitelistedCommand(
  command: string | undefined,
  whitelist: Whitelist,
): boolean {
  // command를 못 읽었으면 판단할 근거가 없다 → 승인을 받는다.
  if (command === undefined) return false;

  // 1) 메타문자가 하나라도 있으면 무조건 승인. 접두 매칭 금지의 핵심.
  if (SHELL_METACHARACTERS.test(command)) return false;

  // 2) 메타문자가 없을 때만 토큰 완전 일치를 본다.
  const tokens = command.trim().split(/\s+/).filter((token) => token !== "");
  const [first, second] = tokens;
  if (first === undefined) return false;

  if (whitelist.firstTokenCommands.includes(first)) return true;
  if (second !== undefined && whitelist.twoTokenCommands.includes(`${first} ${second}`)) {
    return true;
  }
  return false;
}

/**
 * 승인 요청에 띄울 한 줄 요약.
 *
 * 사용자가 "무엇을 허용하는지"를 이 문장 하나로 판단하므로, 실행될 값
 * 자체(명령 원문, 좌표)를 보여준다. 도구 이름만 적으면 승인의 의미가 없다.
 */
export function describeApproval(def: ToolDefinition, args: unknown): string {
  switch (def.name) {
    case "run_shell":
      return `셸 명령 실행 승인 요청: ${readCommand(args) ?? "(명령 없음)"}`;
    case "run_applescript":
      return `AppleScript 실행 승인 요청: ${oneLine(readString(args, "script") ?? "(스크립트 없음)")}`;
    case "click_element":
      return `화면 클릭 승인 요청: ${describeFrame(args)}`;
    default:
      return `${def.name} 실행 승인 요청: ${oneLine(JSON.stringify(args) ?? "")}`;
  }
}

/** 클릭 대상 좌표. frame은 Quartz 전역 좌표(좌상단 원점)다. */
function describeFrame(args: unknown): string {
  const frame = readRecord(args)?.["frame"];
  const record = readRecord(frame);
  if (record === undefined) return "(좌표 없음)";

  const { x, y, width, height } = record;
  if (typeof x !== "number" || typeof y !== "number") return oneLine(JSON.stringify(frame) ?? "");
  const size =
    typeof width === "number" && typeof height === "number" ? ` (${width}x${height})` : "";
  return `x=${x}, y=${y}${size}`;
}

function readCommand(args: unknown): string | undefined {
  return readString(args, "command");
}

function readString(args: unknown, key: string): string | undefined {
  const value = readRecord(args)?.[key];
  return typeof value === "string" ? value : undefined;
}

function readRecord(value: unknown): Record<string, unknown> | undefined {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;
}

/** 여러 줄 스크립트가 승인 프롬프트를 밀어내지 않도록 한 줄로 줄인다. */
function oneLine(text: string): string {
  const flat = text.replace(/\s+/g, " ").trim();
  return flat.length > 120 ? `${flat.slice(0, 117)}...` : flat;
}

function stringArray(value: unknown): readonly string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is string => typeof item === "string");
}
