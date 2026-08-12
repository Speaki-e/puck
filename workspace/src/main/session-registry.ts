import { randomUUID } from "node:crypto";
import type { SessionOrigin } from "@speaki-e/protocol";

export interface SessionRecord {
  id: string;
  workspaceId: string;
  title: string;
  origin: SessionOrigin;
  createdAt: number;
}

/**
 * 세션 메타데이터(제목·소속 워크스페이스·생성 주체)를 보관하는 최소 레지스트리다.
 * 실제로는 ai-module이 세션 히스토리 레지스트리(04_ai-module.md 3.4)를 소유해야 하지만
 * ai-module이 아직 없어(TODO.md 참고) 임시로 Workspace가 들고 있다. ai-module이 준비되면
 * 이 클래스는 그쪽 레지스트리를 감싸는 얇은 어댑터로 바뀔 것이다. 영속화하지 않는다 --
 * 프로세스 생명주기 동안만 유지된다(워크스페이스 메타데이터와 달리 세션은 아직 재시작 후
 * 복원 대상이 아니다, W4 공통 항목의 state_snapshot이 나온 뒤에 다시 볼 문제).
 */
export class SessionRegistry {
  private readonly sessions = new Map<string, SessionRecord>();

  /** session_create_request(origin=user) 또는 open_task_session(origin=agent) 둘 다 여기로 들어온다. */
  record(workspaceId: string, title: string, origin: SessionOrigin, id: string = randomUUID()): SessionRecord {
    const record: SessionRecord = { id, workspaceId, title: title.trim() || "새 세션", origin, createdAt: Date.now() };
    this.sessions.set(id, record);
    return record;
  }

  get(id: string): SessionRecord | undefined {
    return this.sessions.get(id);
  }

  listForWorkspace(workspaceId: string): SessionRecord[] {
    return [...this.sessions.values()].filter((session) => session.workspaceId === workspaceId);
  }
}
