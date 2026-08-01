export interface QueueTask<T> {
  requestId: string;
  workspaceId: string;
  signal?: AbortSignal;
  execute(signal: AbortSignal): Promise<T>;
}

interface PendingTask<T> {
  task: QueueTask<T>;
  controller: AbortController;
  resolve(value: T): void;
  reject(reason: unknown): void;
  started: boolean;
  abortCleanup?: () => void;
}

export class QueueCancelledError extends Error {
  constructor() {
    super("작업이 실행 전에 취소되었습니다.");
    this.name = "QueueCancelledError";
  }
}

export class CodeEditorQueue {
  private readonly queues = new Map<string, PendingTask<unknown>[]>();
  private readonly requests = new Map<string, PendingTask<unknown>>();

  enqueue<T>(task: QueueTask<T>): Promise<T> {
    if (this.requests.has(task.requestId)) return Promise.reject(new Error(`중복 requestId: ${task.requestId}`));
    if (task.signal?.aborted) return Promise.reject(new QueueCancelledError());
    return new Promise<T>((resolve, reject) => {
      const controller = new AbortController();
      const pending: PendingTask<T> = { task, controller, resolve, reject, started: false };
      if (task.signal) {
        const onAbort = () => this.cancel(task.requestId);
        task.signal.addEventListener("abort", onAbort, { once: true });
        pending.abortCleanup = () => task.signal?.removeEventListener("abort", onAbort);
      }
      const queue = this.queues.get(task.workspaceId) ?? [];
      queue.push(pending as PendingTask<unknown>);
      this.queues.set(task.workspaceId, queue);
      this.requests.set(task.requestId, pending as PendingTask<unknown>);
      if (queue.length === 1) void this.drain(task.workspaceId);
    });
  }

  cancel(requestId: string): boolean {
    const pending = this.requests.get(requestId);
    if (!pending) return false;
    pending.controller.abort();
    if (!pending.started) {
      const queue = this.queues.get(pending.task.workspaceId);
      const index = queue?.indexOf(pending) ?? -1;
      if (queue && index >= 0) queue.splice(index, 1);
      this.finish(pending);
      pending.reject(new QueueCancelledError());
      if (queue?.length === 0) this.queues.delete(pending.task.workspaceId);
    }
    return true;
  }

  cancelAll(): void {
    for (const requestId of [...this.requests.keys()]) this.cancel(requestId);
  }

  position(requestId: string): number | undefined {
    const pending = this.requests.get(requestId);
    if (!pending) return undefined;
    return this.queues.get(pending.task.workspaceId)?.indexOf(pending);
  }

  private async drain(workspaceId: string): Promise<void> {
    const queue = this.queues.get(workspaceId);
    const pending = queue?.[0];
    if (!queue || !pending) return;
    pending.started = true;
    try {
      const value = await pending.task.execute(pending.controller.signal);
      pending.resolve(value);
    } catch (error) {
      pending.reject(error);
    } finally {
      this.finish(pending);
      if (queue[0] === pending) queue.shift();
      if (queue.length === 0) this.queues.delete(workspaceId);
      else void this.drain(workspaceId);
    }
  }

  private finish(pending: PendingTask<unknown>): void {
    pending.abortCleanup?.();
    this.requests.delete(pending.task.requestId);
  }
}
