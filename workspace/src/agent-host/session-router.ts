import type { SessionRouterPort } from "../shared/ports.js";

/**
 * 동일 (workspaceId, sessionId)의 사용자 입력은 순차 실행하고, 다른 세션은 병렬로 흘려보낸다
 * (plan/03_workspace.md W3, 04_ai-module.md 3.4). ai-module 자체도 세션별 히스토리 큐를 갖지만,
 * Workspace 쪽에서 같은 세션의 두 번째 task()를 첫 번째가 끝나기 전에 시작하지 않도록 여기서도
 * 직렬화해 "두 레이어가 동시에 같은 세션을 돌리는" 중복 실행을 원천 차단한다.
 */
export class SessionRouter implements SessionRouterPort {
  private readonly chains = new Map<string, Promise<void>>();
  private readonly queueDepth = new Map<string, number>();

  route(workspaceId: string, sessionId: string, task: () => Promise<void>): Promise<void> {
    const key = this.key(workspaceId, sessionId);
    const previous = this.chains.get(key) ?? Promise.resolve();
    this.queueDepth.set(key, (this.queueDepth.get(key) ?? 0) + 1);
    const settle = () => {
      const depth = (this.queueDepth.get(key) ?? 1) - 1;
      if (depth <= 0) this.queueDepth.delete(key);
      else this.queueDepth.set(key, depth);
    };
    const next = previous.catch(() => undefined).then(() => task());
    const tracked = next.finally(settle);
    this.chains.set(key, tracked.catch(() => undefined));
    return next;
  }

  /** 대기 중(자기 자신 포함) 작업 수 -- 호출자가 "이전 작업 진행 중" 표시를 하기 위한 진단용. */
  queueLength(workspaceId: string, sessionId: string): number {
    return this.queueDepth.get(this.key(workspaceId, sessionId)) ?? 0;
  }

  private key(workspaceId: string, sessionId: string): string {
    return `${workspaceId}::${sessionId}`;
  }
}
