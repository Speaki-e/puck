/**
 * Workspace v2에서 권장하지만 @speaki-e/protocol v0.5.0에는 아직 없는 메시지다.
 * protocol PR과 태그가 나오기 전에는 wire로 전송하지 않는다.
 */
export interface StateSnapshotRequest {
  type: "state_snapshot_request";
}

export interface ExtendedRunCancel {
  type: "run_cancel";
  workspace_id: string;
  session_id: string;
  run_id: string;
}

export const PROTOCOL_EXTENSIONS_ENABLED = false;
