/**
 * ai-module A5 — 세션별 대화 히스토리 + 직렬 큐 (메모리 내).
 *
 * 세션 하나 = 독립된 대화 하나. 히스토리가 세션 사이로 새면 일상 세션에 작업
 * 로그가 섞이고, 반대로 작업 세션이 잡담을 기억한다(기획서 3.4/3.7).
 *
 * 로컬 파일 저장은 후순위라 하지 않는다 — 프로세스가 죽으면 히스토리도 사라진다.
 */
import type Anthropic from "@anthropic-ai/sdk";

/** 항상 존재한다고 가정하는 기본 세션. 일상 대화가 여기 쌓인다. */
export const DEFAULT_SESSION_ID = "default";

export interface Session {
  id: string;
  /**
   * 지금까지의 대화. 항상 assistant 메시지로 끝난다 —
   * 중간에 끊긴 턴은 커밋하지 않기 때문이다(SessionStore.commit 참고).
   */
  history: Anthropic.MessageParam[];
  /** open_task_session으로 열린 세션의 제목. 기본 세션은 undefined. */
  title?: string;
  /** open_task_session의 brief. 매 턴 시스템 프롬프트에 실린다. */
  brief?: string;
}

/** 큐잉이 발생했을 때 알림. 진행 중인 run이 있어 대기로 밀린 경우에만 호출된다. */
export type QueuedListener = (sessionId: string, waiting: number) => void;

interface SessionEntry extends Session {
  /** 직렬 실행 체인의 꼬리. 이 프라미스가 끝나야 다음 run이 시작된다. */
  tail: Promise<void>;
  /** 대기 중이거나 실행 중인 run 수. 1보다 크면 뒤의 run은 기다리고 있다. */
  depth: number;
}

export class SessionStore {
  private readonly sessions = new Map<string, SessionEntry>();

  /** 큐잉 알림 수신자. CLI가 [queued session=...] 로그를 찍는 데 쓴다. */
  constructor(private readonly onQueued?: QueuedListener) {
    // "default" 세션은 항상 존재한다고 가정한다(A5 요구사항).
    this.getOrCreate(DEFAULT_SESSION_ID);
  }

  /** 세션을 조회하거나 없으면 만든다. */
  getOrCreate(sessionId: string): Session {
    return this.entry(sessionId);
  }

  has(sessionId: string): boolean {
    return this.sessions.has(sessionId);
  }

  /** 세션 id 목록. 생성 순서를 유지한다(Map의 삽입 순서). */
  list(): Session[] {
    return [...this.sessions.values()];
  }

  /**
   * 새 작업 세션을 만들고 brief를 시드로 심는다.
   *
   * brief는 히스토리의 첫 user 메시지가 아니라 세션 속성으로 저장한다.
   * 히스토리 맨 앞에 짝 없는 user 메시지를 두면 다음 턴에 user 메시지가
   * 연달아 붙어 대화가 어긋난다 — protocol도 brief를 "first system message"로
   * 규정하므로 시스템 프롬프트 쪽에 싣는 게 맞다(context.ts 참고).
   */
  seed(sessionId: string, brief: string, title?: string): Session {
    const session = this.entry(sessionId);
    session.brief = brief;
    if (title !== undefined) session.title = title;
    return session;
  }

  /**
   * 한 턴이 정상적으로 끝났을 때 그 턴 전체를 히스토리에 반영한다.
   *
   * 중단·에러로 끝난 턴은 커밋하지 않는다. tool_use 블록만 있고 대응하는
   * tool_result가 없는 히스토리를 남기면 다음 API 호출이 통째로 거부된다.
   */
  commit(sessionId: string, messages: Anthropic.MessageParam[]): void {
    this.entry(sessionId).history = messages;
  }

  /**
   * 같은 세션의 run을 직렬로 실행한다. 다른 세션끼리는 서로 막지 않는다.
   *
   * 진행 중인 run을 취소하지 않는다 — 뒤에 온 요청이 앞의 요청을 죽이면
   * 사용자가 방금 시킨 작업이 소리 없이 사라진다(기획서 3.4).
   */
  enqueue<T>(sessionId: string, task: () => Promise<T>): Promise<T> {
    const session = this.entry(sessionId);

    if (session.depth > 0) this.notifyQueued(sessionId, session.depth);
    session.depth += 1;

    // 앞 run이 실패해도 체인을 끊지 않는다(성공/실패 양쪽에 task를 건다).
    const run = session.tail.then(task, task);
    const settled = run.then(
      () => {},
      () => {},
    );
    session.tail = settled;
    void settled.then(() => {
      session.depth -= 1;
    });

    return run;
  }

  private entry(sessionId: string): SessionEntry {
    const existing = this.sessions.get(sessionId);
    if (existing !== undefined) return existing;

    const created: SessionEntry = {
      id: sessionId,
      history: [],
      tail: Promise.resolve(),
      depth: 0,
    };
    this.sessions.set(sessionId, created);
    return created;
  }

  private notifyQueued(sessionId: string, waiting: number): void {
    try {
      this.onQueued?.(sessionId, waiting);
    } catch {
      // 로그 콜백 실패로 큐잉 자체가 깨지면 안 된다.
    }
  }
}
