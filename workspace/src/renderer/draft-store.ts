export const DRAFT_TTL_MS = 7 * 24 * 60 * 60 * 1_000;
export const DRAFT_KEY_PREFIX = "workspace:drafts:";

export interface StoredDrafts {
  projectPath: string;
  expiresAt: number;
  activePath?: string;
  tabs: Array<{ path: string; content: string; revision: string }>;
}

export function draftKey(projectPath: string): string {
  return `${DRAFT_KEY_PREFIX}${projectPath}`;
}

export function readDraft(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

export function removeDraft(key: string): void {
  try {
    localStorage.removeItem(key);
  } catch {
    // Draft recovery is best-effort and must never break the editor.
  }
}

/**
 * 지금까지 만료 정리는 같은 프로젝트를 다시 열 때만 일어났다(App.tsx의 draft 복원 effect) -- 한 번
 * 열고 다시는 열지 않은 프로젝트의 draft는 7일이 지나도 아무도 지우지 않고 localStorage에 영원히
 * 남는다. 앱 시작 시 한 번, 프로젝트와 무관하게 모든 workspace:drafts:* 키를 훑어 만료/손상된
 * 항목을 정리한다(W7 완료 기준 "복구 데이터 만료 정책" 점검에서 발견한 빠진 부분).
 */
export function sweepExpiredDrafts(now = Date.now()): void {
  let keys: string[];
  try {
    keys = Object.keys(localStorage).filter((key) => key.startsWith(DRAFT_KEY_PREFIX));
  } catch {
    return;
  }
  for (const key of keys) {
    const raw = readDraft(key);
    if (!raw) continue;
    try {
      const stored = JSON.parse(raw) as Partial<StoredDrafts>;
      if (typeof stored.expiresAt !== "number" || stored.expiresAt < now) removeDraft(key);
    } catch {
      removeDraft(key);
    }
  }
}
