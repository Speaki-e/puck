/**
 * ai-module A5 — 컨텍스트 주입.
 *
 * Context는 protocol이 정의한다. 기본 프롬프트는 prompts/system.md를 우선 읽되,
 * Electron/esbuild 단일 번들처럼 패키지 자산 경로를 잃는 환경에서도 행동 규칙이
 * 사라지지 않도록 동일한 안전 프롬프트를 코드 폴백으로 보관한다.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

import type { Context, WindowInfo } from "@speaki-e/protocol/dist/index.js";

export type { Context, WindowInfo };

const MAX_LIST_ITEMS = 5;

const FALLBACK_SYSTEM_PROMPT = `너는 사용자의 데스크톱에서 함께 일하는 에이전트다. 아래 규칙을 지켜라.

## 행동 규칙

1. 코딩 작업은 반드시 \`code_editor\` 도구로 위임한다. 직접 파일을 수정하지 않는다.
   파일 내용을 확인할 때는 \`read_file\`을 열람 전용으로만 사용한다.
2. \`click_element\`는 일반 UI 요소에만 쓴다. 시스템 권한을 묻는 다이얼로그에는 동작하지 않으므로,
   그 경우 \`point_at\`으로 위치를 가리키고 사용자가 직접 누르도록 안내한다.
3. 응답은 간결하게, 수행 결과 중심으로 쓴다.
4. 일상 대화 중 코딩이나 작업성 요청이 명확해지면 그 자리에서 작업 도구를 바로 쓰지 말고,
   먼저 \`open_task_session\`으로 새 작업 세션을 연 뒤 그 세션에서 진행한다.`;

/**
 * 기본 시스템 프롬프트를 읽는다.
 *
 * - SPEAKI_AI_MODULE_ROOT가 있으면 그 경로를 최우선으로 사용한다.
 * - ESM 패키지로 직접 실행하면 모듈 위치 기준 prompts/system.md를 사용한다.
 * - 패키지가 단일 번들로 포함돼 파일 자산이 없으면 안전 규칙의 내장 사본을 사용한다.
 */
export function loadBasePrompt(): string {
  for (const candidate of assetCandidates("prompts/system.md")) {
    try {
      return readFileSync(candidate, "utf8").trim();
    } catch {
      // 다음 후보를 확인한다.
    }
  }
  return FALLBACK_SYSTEM_PROMPT;
}

/** 기본 프롬프트에 현재 상황과 세션 브리프를 덧붙인다. */
export function buildSystemPrompt(
  basePrompt: string,
  context: Context,
  sessionBrief?: string,
): string {
  const sections = [basePrompt, describeContext(context), describeBrief(sessionBrief)];
  return sections.filter((section) => section !== undefined && section !== "").join("\n\n");
}

function assetCandidates(relativePath: string): string[] {
  const candidates: string[] = [];
  const configuredRoot = process.env["SPEAKI_AI_MODULE_ROOT"];
  if (configuredRoot) candidates.push(path.resolve(configuredRoot, relativePath));

  // ESM 패키지로 실행될 때는 실제 패키지 자산을 읽는다. esbuild가 CJS 단일 번들로
  // 묶는 환경에서는 import.meta.url이 비어 있을 수 있으므로 그때는 안전 폴백을 쓴다.
  try {
    if (import.meta.url) {
      candidates.push(fileURLToPath(new URL(`../${relativePath}`, import.meta.url)));
    }
  } catch {
    // 번들 환경: 내장 프롬프트로 폴백.
  }
  return [...new Set(candidates)];
}

function describeContext(context: Context): string | undefined {
  const parts: string[] = [];

  if (context.frontmostApp) parts.push(`최전면 앱: ${context.frontmostApp}`);
  if (context.openWindows?.length) parts.push(`열린 창: ${describeWindows(context.openWindows)}`);
  if (context.editorOpenFiles?.length) parts.push(`열린 파일: ${joinCapped(context.editorOpenFiles)}`);
  if (context.recentActions?.length) parts.push(`최근 작업: ${joinCapped(context.recentActions)}`);
  if (context.projectPath) parts.push(`프로젝트 경로: ${context.projectPath}`);

  if (parts.length === 0) return undefined;

  const lines = [`[현재 상황] ${parts.join(" / ")}`];
  if (context.projectPath) {
    lines.push(`code_editor를 호출할 때 project_path는 ${context.projectPath} 를 사용하라.`);
  }
  return lines.join("\n");
}

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
