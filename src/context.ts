/**
 * ai-module A5 — 컨텍스트 주입.
 *
 * Context는 protocol이 정의한다(agent-interface.ts). 여기서는 그 값을 모델이
 * 읽을 수 있는 한 덩어리 요약으로 바꿔 시스템 프롬프트에 붙이는 일만 한다.
 *
 * 기본 시스템 프롬프트 원문은 prompts/system.md에서 관리한다 — 프롬프트 튜닝이
 * 코드 변경 없이 이뤄져야 하기 때문이다(기획서 3.5, 담당: 정가은).
 */
import { readFileSync } from "node:fs";

import type { Context, WindowInfo } from "@speaki-e/protocol/src/index.js";

export type { Context, WindowInfo };

/** src/에서 실행하든 dist/에서 실행하든 저장소 루트의 prompts/를 가리킨다. */
const SYSTEM_PROMPT_PATH = new URL("../prompts/system.md", import.meta.url);

/** 요약이 길어져 본문을 밀어내지 않도록 목록형 필드는 앞에서 몇 개만 싣는다. */
const MAX_LIST_ITEMS = 5;

/**
 * 기본 시스템 프롬프트를 읽는다.
 *
 * 파일이 없으면 던진다 — 행동 규칙 없이 도구를 쥐여주면 모델이 코딩 작업을
 * code_editor 대신 run_shell로 처리하는 등 규칙 위반이 그대로 실행된다.
 */
export function loadBasePrompt(): string {
  try {
    return readFileSync(SYSTEM_PROMPT_PATH, "utf8").trim();
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    throw new Error(`prompts/system.md를 읽을 수 없습니다: ${detail}`);
  }
}

/**
 * 기본 프롬프트에 현재 상황과 세션 브리프를 덧붙인다.
 *
 * 붙일 게 없으면 기본 프롬프트를 그대로 돌려준다 — 빈 "[현재 상황]" 머리말은
 * 모델에게 "상황 정보가 있다"는 잘못된 신호를 준다.
 *
 * @param basePrompt   prompts/system.md 원문
 * @param context      호출부가 수집한 현재 상황. 비어 있어도 된다.
 * @param sessionBrief 작업 세션의 시드 컨텍스트 (open_task_session의 brief).
 *                     protocol이 "first system message"라고 규정하므로 대화
 *                     히스토리가 아니라 시스템 프롬프트 쪽에 싣는다.
 */
export function buildSystemPrompt(
  basePrompt: string,
  context: Context,
  sessionBrief?: string,
): string {
  const sections = [basePrompt, describeContext(context), describeBrief(sessionBrief)];
  return sections.filter((section) => section !== undefined && section !== "").join("\n\n");
}

/** Context를 한 줄 요약으로. 실을 값이 하나도 없으면 undefined. */
function describeContext(context: Context): string | undefined {
  const parts: string[] = [];

  if (context.frontmostApp) parts.push(`최전면 앱: ${context.frontmostApp}`);
  if (context.openWindows?.length) parts.push(`열린 창: ${describeWindows(context.openWindows)}`);
  if (context.editorOpenFiles?.length) {
    parts.push(`열린 파일: ${joinCapped(context.editorOpenFiles)}`);
  }
  if (context.recentActions?.length) parts.push(`최근 작업: ${joinCapped(context.recentActions)}`);
  if (context.projectPath) parts.push(`프로젝트 경로: ${context.projectPath}`);

  if (parts.length === 0) return undefined;

  const lines = [`[현재 상황] ${parts.join(" / ")}`];
  if (context.projectPath) {
    // 자동 주입의 목적 자체가 "모델이 매번 경로를 지정하지 않게 하는 것"이므로
    // 값만 주지 말고 어디에 쓸 값인지까지 못박는다.
    lines.push(`code_editor를 호출할 때 project_path는 ${context.projectPath} 를 사용하라.`);
  }
  return lines.join("\n");
}

/** 창 정보는 "앱 - 제목" 형태로 줄인다. frame 좌표는 모델에게 의미가 없다. */
function describeWindows(windows: readonly WindowInfo[]): string {
  return joinCapped(
    windows.map((win) => (win.title ? `${win.owner_name} - ${win.title}` : win.owner_name)),
  );
}

function joinCapped(items: readonly string[]): string {
  const shown = items.slice(0, MAX_LIST_ITEMS).join(", ");
  const rest = items.length - MAX_LIST_ITEMS;
  return rest > 0 ? `${shown} 외 ${rest}개` : shown;
}

function describeBrief(brief: string | undefined): string | undefined {
  if (!brief) return undefined;
  return `[작업 세션 브리프] 이 세션은 아래 작업을 위해 열렸다. 대화는 이 맥락에서 이어간다.\n${brief}`;
}
