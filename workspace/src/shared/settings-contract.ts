import type { CodingAgentKind } from "./acp-command.js";

/** main(JsonlLogger)과 renderer(설정 화면) 양쪽이 쓰므로 shared에 둔다. */
export type LogLevel = "debug" | "info" | "warn" | "error";

export interface WorkspaceSettings {
  /** read_file/에디터 편집 가능 크기 상한(바이트). */
  fileSizeLimitBytes: number;
  logLevel: LogLevel;
  /** code_editor를 실행할 코딩 에이전트(ACP). 기본값 "claude" -- 설정하지 않으면 기존 동작과 동일하다. */
  codingAgent: CodingAgentKind;
}

export interface RecentProject {
  id: string;
  name: string;
  projectPath: string;
  updatedAt: number;
}

/** 설정 화면(W7)이 한 번에 받는 스냅샷. API 키는 존재 여부만 싣고 값은 절대 포함하지 않는다. */
export interface SettingsSnapshot extends WorkspaceSettings {
  hasApiKey: boolean;
  recentProjects: RecentProject[];
  windowSize?: { width: number; height: number };
}
