/**
 * ai-module A0 — 콜백 인터페이스 정의.
 *
 * 이 시그니처는 이후 단계(도구 호출, 대화 히스토리, 승인 게이트)에서 확장될 예정이므로
 * 필드를 제거하거나 이름을 바꾸지 말고 추가만 할 것.
 */
import type {
  Attachment,
  Context,
  ToolExecutor,
  ToolExecutorKind,
  ToolResultErrorCode,
} from "@speaki-e/protocol/src/index.js";

// ToolExecutor는 protocol이 이미 정의하고 있다(agent-interface.ts). 자체 정의하지 않고
// 그대로 재수출한다 — 호출부가 protocol 경로를 몰라도 되게 하기 위한 편의 재수출일 뿐,
// 이 파일이 원본이 아니다.
export type {
  Attachment,
  Context,
  ToolExecutor,
  ToolExecutionResult,
} from "@speaki-e/protocol/src/index.js";

/**
 * 실제로 디스패치되는 실행기 종류. "ai-module"은 open_task_session 하나를 위한
 * 표식이고 ai-module의 루프가 인라인 처리하므로 주입 대상이 아니다.
 */
export type DispatchableExecutorKind = Exclude<ToolExecutorKind, "ai-module">;

/**
 * 실행기 주입 맵. 값이 optional인 이유는 CLI처럼 일부만 붙이는 호출부가 있고,
 * 그 경우 런타임에서 executor_not_available로 되돌려줘야 하기 때문이다.
 */
export type ExecutorMap = Partial<Record<DispatchableExecutorKind, ToolExecutor>>;

/**
 * 모델에게 돌려주는 tool_result의 error 코드.
 *
 * protocol의 ToolResultErrorCode(소켓 코드 + denied_by_user)를 기본으로 쓰되,
 * 디스패치 이전에 ai-module 안에서만 발생하는 세 가지를 추가한다. 이 셋은
 * 소켓을 건너지 않으므로 protocol의 wire 코드 집합을 넓히지 않는다.
 * TODO: protocol에 정식 코드로 올릴지 논의 필요 (아래 세 값 참조).
 */
export type LocalToolErrorCode =
  | ToolResultErrorCode
  | "invalid_input"
  | "not_implemented_yet"
  | "executor_not_available";

/** createClient() 옵션. API 키/모델/실행기를 전부 호출부에서 주입받는다. */
export interface ClientOptions {
  /** Anthropic API 키. 모듈 내부에 저장하지 않는다. */
  apiKey: string;
  /** 모델 ID (예: "claude-sonnet-4-6"). */
  model: string;
  /** executor kind별 실행기. 실제 구현(소켓 프록시)이든 mock이든 무관하다. */
  executors: ExecutorMap;
}

/** 모델이 도구를 호출하기 시작했을 때 전달되는 정보. (A1에서 사용) */
export interface ToolCallInfo {
  /** Claude가 부여한 tool_use 블록 id. tool_result와 짝을 맞추는 데 사용. */
  id: string;
  /** 호출된 도구 이름. */
  name: string;
  /** 파싱된 도구 입력. 스키마는 도구마다 다르므로 unknown. */
  input: unknown;
  /** 레지스트리상의 실행기 종류. 레지스트리에 없는 도구면 undefined. (A2에서 추가) */
  executor?: ToolExecutorKind;
}

/** 도구 실행 결과. (A1에서 사용) */
export interface ToolResultInfo {
  /** 대응하는 ToolCallInfo.id. */
  id: string;
  /** 실행된 도구 이름. 여러 도구가 한 턴에 호출될 때 결과를 짝지어 보기 위한 것. */
  name: string;
  /** 도구 실행 성공 여부. false면 tool_result에 is_error 플래그가 붙는다. */
  ok: boolean;
  /** 모델에게 돌려줄 결과 텍스트. A1에서는 실행 결과 객체의 JSON.stringify 결과. */
  content: string;
}

/** run() 실행 중 발생하는 이벤트를 받는 콜백 묶음. */
export interface RunCallbacks {
  /** 텍스트 청크를 수신할 때마다 호출. 누적이 아니라 델타(증분)가 전달된다. */
  onTextChunk(text: string): void;

  /**
   * 실행이 끝났을 때 정확히 한 번 호출.
   * @param ok      정상 종료 여부. 에러/중단 시 false.
   * @param summary 성공 시 stop_reason(예: "end_turn"), 실패 시 에러 메시지.
   */
  onDone(ok: boolean, summary?: string): void;

  /** 모델이 도구를 호출했을 때, 실행 직전에 호출. (A1부터 호출됨) */
  onToolCallStart?(call: ToolCallInfo): void;

  /** 도구 실행이 끝났을 때, 결과를 모델에 돌려주기 직전에 호출. (A1부터 호출됨) */
  onToolResult?(result: ToolResultInfo): void;

  /**
   * 위험한 도구를 실행하기 직전에 호출. (A6부터, 기획서 3.3)
   * 시그니처는 protocol AgentCallbacks.onApprovalRequired와 같다.
   *
   * resolve(true)면 실행하고, resolve(false)면 실행기를 호출하지 않은 채
   * tool_result(error=denied_by_user)를 모델에 돌려준다.
   *
   * 이 콜백을 붙이지 않으면 승인이 필요한 도구는 전부 거부된다 —
   * 물어볼 방법이 없는데 실행하면 게이트가 없는 것과 같다.
   *
   * @param summary 사용자가 무엇을 허용하는지 판단할 한 줄 요약(실행될 명령 원문 포함).
   */
  onApprovalRequired?(summary: string, resolve: (approved: boolean) => void): void;

  /**
   * 모델이 스스로 open_task_session을 호출해 새 작업 세션이 열렸을 때 호출.
   * (A5부터, 기획서 3.7) 시그니처는 protocol AgentCallbacks.onSessionCreated와 같다.
   *
   * 호출자(workspace)는 이걸 session_create(origin=agent) 소켓 이벤트로 바꿔
   * pet-app 사이드바에 새 세션을 띄운다. CLI는 현재 세션을 그쪽으로 전환한다.
   */
  onSessionCreated?(sessionId: string, title: string): void;
}

/** createClient()가 반환하는 클라이언트. (A2 기준: 도구 실행은 주입된 실행기가 담당) */
export interface AiClient {
  /**
   * A0~A3 호환 형태. sessionId는 "default", context는 {}로 취급된다.
   *
   * 예외를 던지지 않는다 — 모든 실패는 onDone(false, message)로 보고된다.
   * @param signal 중간 중단용. abort 시 onDone(false, "aborted")로 종료.
   */
  run(command: string, callbacks: RunCallbacks, signal?: AbortSignal): Promise<void>;

  /**
   * protocol AgentRun과 같은 인자 순서
   * (command, sessionId, context, callbacks, attachments?, signal?).
   *
   * 같은 sessionId로 실행 중에 다시 호출하면 그 세션 안에서만 직렬 큐잉된다 —
   * 앞의 run이 끝난 뒤 순서대로 처리되고, 다른 sessionId의 run은 막지 않는다.
   *
   * @param attachments Workspace가 검증한 이미지 첨부. Claude 멀티모달 입력으로 전달한다.
   */
  run(
    command: string,
    sessionId: string,
    context: Context,
    callbacks: RunCallbacks,
    attachments?: Attachment[],
    signal?: AbortSignal,
  ): Promise<void>;
}
