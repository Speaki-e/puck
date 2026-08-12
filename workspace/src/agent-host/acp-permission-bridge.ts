import type * as acp from "@agentclientprotocol/sdk";
import type { JSONValue } from "@speaki-e/protocol";
import type { PermissionResolver } from "./acp-adapter.js";
import type { ApprovalPort } from "../shared/ports.js";

function summarize(toolCall: acp.ToolCallUpdate): string {
  return toolCall.title?.trim() || toolCall.kind || "Claude Code 권한 요청";
}

/**
 * "항상 허용"은 1차 범위 밖으로 고정돼 있다(plan/03_workspace.md 4.5) -- *_once 옵션만 고르고,
 * 그것도 없을 때만 *_always로 물러선다. 옵션이 아예 없으면 cancelled로 취급한다.
 */
function chooseOptionId(options: readonly acp.PermissionOption[], approved: boolean): acp.PermissionOptionId | undefined {
  const onceKind = approved ? "allow_once" : "reject_once";
  const alwaysKind = approved ? "allow_always" : "reject_always";
  return options.find((option) => option.kind === onceKind)?.optionId
    ?? options.find((option) => option.kind === alwaysKind)?.optionId
    ?? options[0]?.optionId;
}

export interface AcpPermissionBridgeContext {
  runId: string;
  workspaceId: string;
  sessionId: string;
}

/**
 * ACP의 request_permission을 ApprovalPort(PendingApprovalStore)에 연결한다(W5, plan 4.5).
 * ai-module의 onApprovalRequired와 다른 별도 IPC 경로지만, 허용/거부 이지선다로 축약해
 * 같은 approval_id 발급 경로에 태운다.
 */
export function createAcpPermissionResolver(approvals: ApprovalPort, context: AcpPermissionBridgeContext): PermissionResolver {
  return async (request) => {
    const approved = await approvals.requestApproval({
      runId: context.runId,
      workspaceId: context.workspaceId,
      sessionId: context.sessionId,
      source: "acp",
      summary: summarize(request.toolCall),
      options: request.options as unknown as JSONValue,
    });
    const optionId = chooseOptionId(request.options, approved);
    if (!optionId) return { outcome: { outcome: "cancelled" } };
    return { outcome: { outcome: "selected", optionId } };
  };
}
