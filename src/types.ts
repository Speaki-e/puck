/**
 * ai-module A0 — 콜백 인터페이스 정의.
 *
 * 이 시그니처는 이후 단계(도구 호출, 대화 히스토리, 승인 게이트)에서 확장될 예정이므로
 * 필드를 제거하거나 이름을 바꾸지 말고 추가만 할 것.
 */

/** 모델이 도구를 호출하기 시작했을 때 전달되는 정보. (A1에서 사용) */
export interface ToolCallInfo {
  /** Claude가 부여한 tool_use 블록 id. tool_result와 짝을 맞추는 데 사용. */
  id: string;
  /** 호출된 도구 이름. */
  name: string;
  /** 파싱된 도구 입력. 스키마는 도구마다 다르므로 unknown. */
  input: unknown;
}

/** 도구 실행 결과. (A1에서 사용) */
export interface ToolResultInfo {
  /** 대응하는 ToolCallInfo.id. */
  id: string;
  /** 도구 실행 성공 여부. */
  ok: boolean;
  /** 모델에게 돌려줄 결과 텍스트. */
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

  /** A0에서는 호출되지 않음 — 타입만 선언. */
  onToolCallStart?(call: ToolCallInfo): void;

  /** A0에서는 호출되지 않음 — 타입만 선언. */
  onToolResult?(result: ToolResultInfo): void;
}

/** createClient()가 반환하는 클라이언트. */
export interface AiClient {
  /**
   * 명령 문자열을 Claude에 보내고 응답을 콜백으로 스트리밍한다.
   * 예외를 던지지 않는다 — 모든 실패는 onDone(false, message)로 보고된다.
   *
   * @param signal 중간 중단용. abort 시 onDone(false, "aborted")로 종료.
   */
  run(command: string, callbacks: RunCallbacks, signal?: AbortSignal): Promise<void>;
}
